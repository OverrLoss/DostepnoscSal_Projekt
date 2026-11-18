import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/room_model.dart';
import 'discovery/network_discovery.dart';

enum SyncConnectionState {
  connected,
  connecting,
  offline,
  error,
}

class RoomSyncService {
  static final RoomSyncService instance = RoomSyncService._init();
  RoomSyncService._init();

  static const String _defaultRemoteUrl = 'https://sale.pwojtaszek.codes';
  static const String _prefKeyServerUrl = 'room_sync_server_url';
  static const String _prefKeyToken = 'room_sync_auth_token';
  static const String _prefKeyUser = 'room_sync_auth_user';

  static String get _initialServerUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && origin != 'null') {
        return origin;
      }
    }
    return _defaultRemoteUrl;
  }

  String _serverUrl = _initialServerUrl;
  SyncConnectionState _connectionState = SyncConnectionState.connecting;
  DateTime? _lastSyncTime;
  String _lastErrorMessage = '';
  Timer? _pollingTimer;

  String? _authToken;
  Map<String, dynamic>? _currentUser;

  final ValueNotifier<SyncConnectionState> connectionNotifier =
      ValueNotifier<SyncConnectionState>(SyncConnectionState.connecting);

  final ValueNotifier<Map<String, dynamic>?> authNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);

  String? _detectedLanUrl;

  // --- WebSocket live updates ---
  WebSocketChannel? _wsChannel;
  Timer? _wsReconnectTimer;
  int _wsFailures = 0;
  bool _wsEnabled = false;
  final StreamController<Map<String, dynamic>> _roomUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<DateTime> _clockTickController =
      StreamController<DateTime>.broadcast();

  /// Stream of room.updated events from server WebSocket.
  /// Listeners will be notified immediately when ESP or any client changes room status.
  Stream<Map<String, dynamic>> get roomUpdatedStream => _roomUpdateController.stream;

  /// Server-driven clock ticks — browsers throttle local timers in hidden tabs.
  Stream<DateTime> get clockTickStream => _clockTickController.stream;

  String get serverUrl => _serverUrl;
  String? get detectedLanUrl => _detectedLanUrl;
  SyncConnectionState get connectionState => _connectionState;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get lastErrorMessage => _lastErrorMessage;

  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _authToken != null && _authToken!.isNotEmpty;
  String get userRole => _currentUser?['role']?.toString() ?? 'guest';
  bool get isAdmin => userRole == 'admin';
  bool get isOperator => userRole == 'operator';
  String? get operatorRoomId => _currentUser?['room_id']?.toString();
  String get userDisplayName =>
      _currentUser?['display_name']?.toString() ??
      _currentUser?['username']?.toString() ??
      'Gość';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_prefKeyServerUrl);
      if (kIsWeb) {
        final currentOrigin = Uri.base.origin;
        if (savedUrl == null ||
            savedUrl.trim().isEmpty ||
            savedUrl.contains('192.168.') ||
            savedUrl.contains('localhost') ||
            savedUrl.contains('127.0.0.1') ||
            (Uri.base.scheme == 'https' && savedUrl.startsWith('http://'))) {
          _serverUrl = (currentOrigin.isNotEmpty && currentOrigin != 'null')
              ? currentOrigin
              : _defaultRemoteUrl;
          try {
            await prefs.setString(_prefKeyServerUrl, _serverUrl);
          } catch (_) {}
        } else {
          _serverUrl = savedUrl.trim();
        }
      } else {
        if (savedUrl != null &&
            savedUrl.trim().isNotEmpty &&
            savedUrl.trim() != 'http://' &&
            savedUrl.trim() != 'https://') {
          _serverUrl = savedUrl.trim();
        } else {
          _serverUrl = _defaultRemoteUrl;
        }
      }

      final savedToken = prefs.getString(_prefKeyToken);
      final savedUserJson = prefs.getString(_prefKeyUser);
      if (savedToken != null && savedToken.isNotEmpty) {
        _authToken = savedToken;
        if (savedUserJson != null) {
          try {
            final decoded = json.decode(savedUserJson);
            _currentUser = decoded is Map<String, dynamic>
                ? decoded
                : Map<String, dynamic>.from(decoded as Map);
            authNotifier.value = _currentUser;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[SyncService] Error reading prefs: $e');
    }
    await checkConnection();
    if (isLoggedIn) {
      refreshCurrentUser().ignore();
    }
  }

  Future<void> setServerUrl(String newUrl) async {
    String sanitized = newUrl.trim();
    if (kIsWeb && Uri.base.scheme == 'https') {
      if (sanitized.isEmpty ||
          sanitized.contains('192.168.') ||
          sanitized.contains('localhost') ||
          sanitized.contains('127.0.0.1') ||
          sanitized.startsWith('http://')) {
        sanitized = Uri.base.origin.isNotEmpty && Uri.base.origin != 'null'
            ? Uri.base.origin
            : _defaultRemoteUrl;
      }
    }
    _serverUrl = sanitized;
    if (_serverUrl.endsWith('/')) {
      _serverUrl = _serverUrl.substring(0, _serverUrl.length - 1);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyServerUrl, _serverUrl);
    } catch (e) {
      debugPrint('[SyncService] Error saving url: $e');
    }
    await checkConnection();
  }

  Uri buildUri(String path, [Map<String, String>? queryParams]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    String effectiveBase = _serverUrl.trim();
    if (kIsWeb) {
      final currentOrigin = Uri.base.origin;
      if (effectiveBase.isEmpty ||
          effectiveBase == 'http://' ||
          effectiveBase == 'https://' ||
          effectiveBase.contains('192.168.') ||
          effectiveBase.contains('localhost') ||
          effectiveBase.contains('127.0.0.1') ||
          (Uri.base.scheme == 'https' && effectiveBase.startsWith('http://'))) {
        effectiveBase = (currentOrigin.isNotEmpty && currentOrigin != 'null')
            ? currentOrigin
            : _defaultRemoteUrl;
      }
    } else {
      if (effectiveBase.isEmpty || effectiveBase == 'http://' || effectiveBase == 'https://') {
        effectiveBase = _defaultRemoteUrl;
      }
    }
    if (effectiveBase.endsWith('/')) {
      effectiveBase = effectiveBase.substring(0, effectiveBase.length - 1);
    }
    final fullUrl = '$effectiveBase$cleanPath';
    final parsed = Uri.parse(fullUrl);
    if (queryParams != null && queryParams.isNotEmpty) {
      return parsed.replace(queryParameters: queryParams);
    }
    return parsed;
  }

  Uri _buildUri(String path, [Map<String, String>? queryParams]) => buildUri(path, queryParams);

  Map<String, String> _headers([Map<String, String>? additional]) {
    final map = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      map['Authorization'] = 'Bearer $_authToken';
    }
    if (additional != null) {
      map.addAll(additional);
    }
    return map;
  }

  void _updateStatus(SyncConnectionState state) {
    _connectionState = state;
    connectionNotifier.value = state;
  }

  // --- HEALTH & DISCOVERY ---

  Future<bool> checkConnection() async {
    try {
      _updateStatus(SyncConnectionState.connecting);
      final uri = _buildUri('/api/v1/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        _updateStatus(SyncConnectionState.connected);
        _lastErrorMessage = '';
        try {
          final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          if (data['lanUrl'] != null) {
            _detectedLanUrl = data['lanUrl'] as String;
          }
        } catch (_) {}
        return true;
      } else {
        _updateStatus(SyncConnectionState.error);
        _lastErrorMessage = 'Serwer odpowiedział kodem: ${res.statusCode}';
        return false;
      }
    } catch (e) {
      _updateStatus(SyncConnectionState.offline);
      _lastErrorMessage = e.toString();
      return false;
    }
  }

  Future<String?> discoverLocalServerUrl() async {
    try {
      final udpLan = await discoverLanServerUdp();
      if (udpLan != null && udpLan.isNotEmpty) {
        _detectedLanUrl = udpLan;
        return udpLan;
      }
    } catch (_) {}

    if (!kIsWeb) {
      for (final candidate in ['http://127.0.0.1:8081', 'http://localhost:8081']) {
        try {
          final uri = Uri.parse('$candidate/api/v1/health');
          final res = await http.get(uri).timeout(const Duration(seconds: 1));
          if (res.statusCode == 200) {
            _detectedLanUrl = candidate;
            return candidate;
          }
        } catch (_) {}
      }
    }
    return _detectedLanUrl;
  }

  // --- AUTHENTICATION ---

  Future<bool> login(String username, String password) async {
    try {
      final uri = buildUri('/api/v1/auth/login');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        final map = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);

        _authToken = (map['access_token'] ?? map['token']) as String?;
        if (map['user'] != null) {
          _currentUser = map['user'] is Map<String, dynamic>
              ? map['user'] as Map<String, dynamic>
              : Map<String, dynamic>.from(map['user'] as Map);
        }

        final prefs = await SharedPreferences.getInstance();
        if (_authToken != null) {
          await prefs.setString(_prefKeyToken, _authToken!);
        }
        if (_currentUser != null) {
          await prefs.setString(_prefKeyUser, json.encode(_currentUser));
        }

        authNotifier.value = _currentUser;
        _updateStatus(SyncConnectionState.connected);
        return true;
      } else {
        final err = json.decode(utf8.decode(res.bodyBytes));
        _lastErrorMessage = err['error']?['message'] ?? 'Błąd logowania (${res.statusCode})';
        return false;
      }
    } catch (e) {
      _lastErrorMessage = 'Nie można połączyć z serwerem logowania: $e';
      return false;
    }
  }

  Future<void> logout() async {
    if (_authToken != null) {
      try {
        final uri = buildUri('/api/v1/auth/logout');
        await http.post(uri, headers: _headers()).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _authToken = null;
    _currentUser = null;
    authNotifier.value = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyToken);
      await prefs.remove(_prefKeyUser);
    } catch (_) {}
  }

  Future<void> refreshCurrentUser() async {
    if (_authToken == null) return;
    try {
      final uri = buildUri('/api/v1/auth/me');
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        _currentUser = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        authNotifier.value = _currentUser;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyUser, json.encode(_currentUser));
      } else if (res.statusCode == 401) {
        await logout();
      }
    } catch (_) {}
  }

  // --- ROOMS (PUBLIC API V1) ---

  Future<List<Room>?> fetchRemoteRooms({
    String? floor,
    String? searchQuery,
    bool? onlyAvailable,
    bool? onlyOccupied,
  }) async {
    try {
      final params = <String, String>{};
      if (floor != null && floor.isNotEmpty && floor != 'Wszystkie') {
        params['floor'] = floor;
      }

      final uri = buildUri('/api/v1/public/rooms', params.isNotEmpty ? params : null);
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        final List<dynamic> list;
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['rooms'] is List) {
          list = decoded['rooms'] as List<dynamic>;
        } else {
          list = [];
        }

        var rooms = list.map((item) {
          final map = item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item as Map);
          return Room.fromMap(map);
        }).toList();

        _updateStatus(SyncConnectionState.connected);
        _lastSyncTime = DateTime.now();
        _lastErrorMessage = '';

        if (onlyAvailable == true) {
          rooms = rooms.where((r) => r.isAvailable).toList();
        } else if (onlyOccupied == true) {
          rooms = rooms.where((r) => !r.isAvailable).toList();
        }

        if (searchQuery != null && searchQuery.trim().isNotEmpty) {
          final q = searchQuery.trim().toLowerCase();
          rooms = rooms.where((r) =>
              r.number.toLowerCase().contains(q) ||
              r.name.toLowerCase().contains(q) ||
              r.description.toLowerCase().contains(q) ||
              r.category.toLowerCase().contains(q)).toList();
        }

        return rooms;
      } else {
        _updateStatus(SyncConnectionState.error);
        _lastErrorMessage = 'Błąd serwera (${res.statusCode})';
        return null;
      }
    } catch (e) {
      debugPrint('[SyncService] fetchRemoteRooms error: $e');
      _updateStatus(SyncConnectionState.offline);
      _lastErrorMessage = e.toString();
      return null;
    }
  }

  Future<Room?> fetchRemoteRoom(String roomId) async {
    try {
      final uri = buildUri('/api/v1/public/rooms/$roomId');
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final decoded = json.decode(utf8.decode(res.bodyBytes));
        if (decoded is Map) {
          final map = decoded is Map<String, dynamic>
              ? decoded
              : Map<String, dynamic>.from(decoded);
          final roomData = map['room'] is Map
              ? (map['room'] is Map<String, dynamic>
                  ? map['room'] as Map<String, dynamic>
                  : Map<String, dynamic>.from(map['room'] as Map))
              : map;
          return Room.fromMap(roomData);
        }
      }
    } catch (_) {}
    return null;
  }

  // --- ROOM STATUS MUTATION ---

  Future<bool> changeRoomStatus(String roomId, String targetStatus, {String? occupantName, bool isBreak = false}) async {
    try {
      final uri = _buildUri('/api/v1/rooms/$roomId/status');
      final res = await http
          .patch(
            uri,
            headers: _headers(),
            body: json.encode({
              'status': targetStatus,
              'is_break': isBreak,
              if (targetStatus == 'occupied' && occupantName != null && occupantName.trim().isNotEmpty)
                'occupant_name': occupantName.trim(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        _lastSyncTime = DateTime.now();
        return true;
      } else {
        final err = json.decode(utf8.decode(res.bodyBytes));
        _lastErrorMessage = err['error']?['message'] ?? 'Błąd zmiany statusu (${res.statusCode})';
        return false;
      }
    } catch (e) {
      _lastErrorMessage = 'Błąd połączenia: $e';
      return false;
    }
  }

  /// Zmienia nazwę osoby przy zajętej sali (po zmianie własnej nazwy).
  Future<bool> changeRoomOccupant(String roomId, String? occupantName) async {
    try {
      final uri = _buildUri('/api/v1/rooms/$roomId/occupant');
      final res = await http
          .patch(
            uri,
            headers: _headers(),
            body: json.encode({'occupant_name': occupantName}),
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleRemoteAvailability(String roomNumber, bool currentAvailable, {String? occupantName}) async {
    final nextStatus = currentAvailable ? 'occupied' : 'free';
    return await changeRoomStatus(roomNumber, nextStatus, occupantName: occupantName);
  }

  /// Blokady opcji sali (tylko admin). Zwraca zaktualizowaną salę lub null.
  Future<Room?> setRoomLocks(String roomId, {
    bool? lockStatus,
    bool? lockInfo,
    bool? lockLayout,
  }) async {
    try {
      final uri = _buildUri('/api/v1/admin/rooms/$roomId/locks');
      final res = await http.patch(
        uri,
        headers: _headers(),
        body: json.encode({
          'lock_status': lockStatus ?? false,
          'lock_info': lockInfo ?? false,
          'lock_layout': lockLayout ?? false,
        }),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return Room.fromMap({
          'number': roomId,
          'id': roomId,
          'lock_status': data['lock_status'],
          'lock_info': data['lock_info'],
          'lock_layout': data['lock_layout'],
        });
      }
      _lastErrorMessage = 'Błąd zmiany blokad (${res.statusCode})';
    } catch (e) {
      _lastErrorMessage = 'Błąd połączenia: $e';
    }
    return null;
  }

  Future<bool> setRoomAlertLimit(String roomId, int limitSeconds) async {
    try {
      final uri = _buildUri('/api/v1/rooms/$roomId/alert-limit');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({
              'alert_limit_seconds': limitSeconds,
              'limit_seconds': limitSeconds,
            }),
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- ADMIN ROOM ACTIONS ---

  Future<Room?> updateRoomPosition(String roomId, double posX, double posY) async {
    if (!isLoggedIn) return null;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/$roomId/position');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({'posX': posX, 'posY': posY}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['room'] != null) {
          return Room.fromMap(data['room'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('[SyncService] updateRoomPosition error: $e');
    }
    return null;
  }

  Future<Room?> updateRoomLayout(String roomId, double scale, double angle) async {
    if (!isLoggedIn) return null;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/$roomId/layout');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({'scale': scale, 'angle': angle}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['room'] != null) {
          return Room.fromMap(Map<String, dynamic>.from(data['room'] as Map));
        }
      }
    } catch (e) {
      debugPrint('[SyncService] updateRoomLayout error: $e');
    }
    return null;
  }

  Future<List<Room>?> resetPositions({String? floor}) async {
    if (!isLoggedIn) return null;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/reset-positions');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({'floor': floor}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['rooms'] != null) {
          final List<dynamic> list = data['rooms'];
          return list.map((item) => Room.fromMap(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<Room>?> updateRoomSortOrder(List<String> roomIds) async {
    if (!isLoggedIn) return null;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/reorder');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({'roomIds': roomIds}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['rooms'] != null) {
          final List<dynamic> list = data['rooms'];
          return list.map((item) => Room.fromMap(item as Map<String, dynamic>)).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Room?> createRemoteRoom(Room room) async {
    if (!isAdmin) return null;
    try {
      final uri = _buildUri('/api/v1/admin/rooms');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode(room.toJson()),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return room;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteRemoteRoom(String roomId) async {
    if (!isAdmin) return false;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/$roomId');
      final res = await http.delete(uri, headers: _headers()).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // --- HARDWARE CONTROLLERS (ESP8266) ---

  Future<List<Map<String, dynamic>>> getDevices() async {
    if (!isAdmin) return [];
    try {
      final uri = _buildUri('/api/v1/admin/devices');
      final res = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = json.decode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[SyncService] getDevices error: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> registerDevice(String name, String roomId) async {
    if (!isAdmin) return null;
    try {
      final uri = _buildUri('/api/v1/admin/devices');
      final res = await http
          .post(
            uri,
            headers: _headers(),
            body: json.encode({'name': name, 'room_id': roomId}),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 201 || res.statusCode == 200) {
        return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> updateDevice(
    String deviceId, {
    String? name,
    String? roomId,
    bool? isActive,
  }) async {
    if (!isAdmin) return null;
    try {
      final uri = _buildUri('/api/v1/admin/devices/$deviceId');
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (roomId != null) body['room_id'] = roomId;
      if (isActive != null) body['is_active'] = isActive;

      final res = await http
          .patch(
            uri,
            headers: _headers(),
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> deleteDevice(String deviceId) async {
    if (!isAdmin) return false;
    try {
      final uri = _buildUri('/api/v1/admin/devices/$deviceId');
      final res = await http.delete(uri, headers: _headers()).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // Compatibility helpers
  Future<List<Map<String, dynamic>>> getPairingDevices() async {
    final devices = await getDevices();
    return devices.where((d) => d['room_id'] == null || d['room_id'] == '').toList();
  }

  Future<bool> assignDeviceToRoom(String deviceId, {int? roomId, String? roomNumber}) async {
    final targetRoom = roomNumber ?? roomId?.toString() ?? '';
    // If device exists, update its room assignment
    final updated = await updateDevice(deviceId, roomId: targetRoom);
    if (updated != null) return true;
    final dev = await registerDevice(deviceId, targetRoom);
    return dev != null;
  }

  Future<bool> resetRemoteRooms() async {
    return true;
  }

  Future<Room?> updateRemoteRoom(Room room) async {
    if (!isAdmin) return room;
    try {
      final uri = _buildUri('/api/v1/admin/rooms/${room.number}');
      final res = await http
          .patch(
            uri,
            headers: _headers(),
            body: json.encode({
              'name': room.name,
              'floor': room.floor,
              'category': room.category,
              'description': room.description,
              'capacity': room.capacity,
              'svg_id': room.svgId ?? '',
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) return room;
    } catch (_) {}
    return null;
  }

  Future<bool> setRemoteFloorAvailability(String floor, bool isAvailable) async {
    return true;
  }

  // --- LIVE POLLING ---

  void startPolling({
    required VoidCallback onTick,
    Duration interval = const Duration(seconds: 3),
  }) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) {
      onTick();
    });
  }

  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  // --- WEBSOCKET LIVE UPDATES ---

  /// Start WebSocket connection to receive real-time room.updated events.
  /// Call once from your screen's initState. Automatically reconnects on disconnect.
  void startWebSocket() {
    _wsEnabled = true;
    _connectWebSocket();
  }

  /// Stop WebSocket and cancel reconnect timer.
  void stopWebSocket() {
    _wsEnabled = false;
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

  void _connectWebSocket() {
    if (!_wsEnabled) return;
    try {
      final base = _serverUrl.isNotEmpty ? _serverUrl : _defaultRemoteUrl;
      // Convert http(s) → ws(s)
      final wsBase = base
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      var wsUri = Uri.parse('$wsBase/api/v1/ws');
      // Dart nie zna domyślnych portów dla ws/wss (zwraca 0) — ustawiamy je jawnie.
      if (!wsUri.hasPort) {
        wsUri = wsUri.replace(port: wsUri.scheme == 'wss' ? 443 : 80);
      }
      debugPrint('[WS] Connecting to $wsUri');

      _wsChannel = WebSocketChannel.connect(wsUri);
      _wsChannel!.stream.listen(
        (raw) {
          _wsFailures = 0;
          try {
            final msg = json.decode(raw as String) as Map<String, dynamic>;
            final type = msg['type']?.toString() ?? '';
            if (type == 'room.updated') {
              final data = msg['data'];
              if (data is Map<String, dynamic>) {
                _roomUpdateController.add(data);
              }
            }
            if (type == 'clock.tick') {
              final data = msg['data'];
              if (data is Map<String, dynamic>) {
                final serverTime = DateTime.tryParse(data['time']?.toString() ?? '');
                if (serverTime != null) {
                  _clockTickController.add(serverTime.toLocal());
                }
              }
            }
            // Respond to server pings
            if (type == 'ping') {
              _wsChannel?.sink.add(json.encode({'type': 'pong'}));
            }
          } catch (_) {}
        },
        onDone: () {
          debugPrint('[WS] Connection closed — reconnecting');
          _scheduleWsReconnect();
        },
        onError: (e) {
          debugPrint('[WS] Error: $e — reconnecting');
          _scheduleWsReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[WS] Connect failed: $e — reconnecting');
      _scheduleWsReconnect();
    }
  }

  /// Ponowne łączenie z narastającą przerwą (3 s, 6 s, 12 s … maks. 60 s),
  /// żeby przy wyłączonym serwerze nie zasypywać go próbami co 3 sekundy.
  void _scheduleWsReconnect() {
    if (!_wsEnabled) return;
    _wsChannel = null;
    _wsReconnectTimer?.cancel();
    final shift = _wsFailures > 5 ? 5 : _wsFailures;
    var seconds = 3 * (1 << shift);
    if (seconds > 60) seconds = 60;
    _wsFailures++;
    _wsReconnectTimer = Timer(Duration(seconds: seconds), _connectWebSocket);
  }
}
