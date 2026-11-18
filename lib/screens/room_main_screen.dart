import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../services/room_sync_service.dart';
import '../widgets/interactive_floor_map.dart';
import '../widgets/room_detail_sheet.dart';
import '../widgets/diagnostics_dialog.dart';
import '../widgets/esp_devices_dialog.dart';
import '../services/app_update_service.dart';
import 'add_edit_room_screen.dart';
import 'tv_dashboard_screen.dart';
import '../theme/app_theme.dart';
import '../services/occupant_nick.dart';

class RoomMainScreen extends StatefulWidget {
  const RoomMainScreen({super.key});

  @override
  State<RoomMainScreen> createState() => _RoomMainScreenState();
}

class _RoomMainScreenState extends State<RoomMainScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _selectedFloor = 'Piętro';

  /// Twoja nazwa — podpisuje sale, które zajmujesz. Zmieniana przyciskiem w nagłówku.
  String _myNick = '';
  int _currentViewIndex = 0; // 0 = Mapa, 1 = Lista
  String _statusFilter = 'Wszystkie'; // 'Wszystkie', 'Wolne', 'Zajęte'
  bool _isReorderMode = false;
  bool _isEditMode = false;

  List<Room> _rooms = [];
  List<Map<String, dynamic>> _pairingDevices = [];
  bool _isLoading = true;

  final List<String> _floors = ['Piętro', 'Parter', 'Garaż podziemny'];

  // WebSocket subscription — receives room.updated events immediately from ESP/server
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  void _openTvDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TvDashboardScreen()),
    );
  }

  static const String _prefSelectedFloor = 'room_main_selected_floor';
  static const String _prefCurrentViewIndex = 'room_main_current_view_index';
  static const String _prefStatusFilter = 'room_main_status_filter';

  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFloor = prefs.getString(_prefSelectedFloor);
      final savedViewIndex = prefs.getInt(_prefCurrentViewIndex);
      final savedStatusFilter = prefs.getString(_prefStatusFilter);

      if (mounted) {
        setState(() {
          if (savedFloor != null && (_floors.contains(savedFloor) || savedFloor == 'Wszystkie')) {
            _selectedFloor = savedFloor;
          }
          if (savedViewIndex != null && (savedViewIndex == 0 || savedViewIndex == 1)) {
            _currentViewIndex = savedViewIndex;
          }
          if (savedStatusFilter != null && ['Wszystkie', 'Wolne', 'Zajęte'].contains(savedStatusFilter)) {
            _statusFilter = savedStatusFilter;
          }
        });
        _loadRooms();
      }
    } catch (e) {
      debugPrint('[RoomMainScreen] Error loading saved state: $e');
    }
  }

  Future<void> _saveCurrentState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSelectedFloor, _selectedFloor);
      await prefs.setInt(_prefCurrentViewIndex, _currentViewIndex);
      await prefs.setString(_prefStatusFilter, _statusFilter);
    } catch (e) {
      debugPrint('[RoomMainScreen] Error saving state: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedState();
    _loadRooms();
    OccupantNick.load().then((nick) {
      if (mounted) setState(() => _myNick = nick);
    });

    // WebSocket: instant updates when ESP changes room status
    final sync = RoomSyncService.instance;
    sync.startWebSocket();
    _wsSubscription = sync.roomUpdatedStream.listen((_) {
      // A room was updated (by ESP or any client) — reload immediately
      _loadRooms(showLoading: false);
    });

    // Polling fallback (slower, catches anything WebSocket might miss)
    sync.startPolling(
      onTick: () => _loadRooms(showLoading: false),
      interval: const Duration(seconds: 8),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.instance.checkForUpdate(context, autoPrompt: true);
    });
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    RoomSyncService.instance.stopWebSocket();
    RoomSyncService.instance.stopPolling();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }
    final rooms = await RoomDatabaseHelper.instance.getRooms(
      floor: _currentViewIndex == 0 ? _selectedFloor : (_selectedFloor == 'Wszystkie' ? null : _selectedFloor),
      searchQuery: _searchController.text,
      onlyAvailable: _statusFilter == 'Wolne' ? true : null,
      onlyOccupied: _statusFilter == 'Zajęte' ? true : null,
    );

    List<Map<String, dynamic>> pairings = [];
    try {
      pairings = await RoomSyncService.instance.getPairingDevices();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _rooms = rooms;
        _pairingDevices = pairings;
        if (showLoading) _isLoading = false;
      });
    }
  }

  Future<void> _toggleBreak(Room room) async {
    final sync = RoomSyncService.instance;
    if (room.lockStatus && !sync.isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zmiana statusu tej sali jest zablokowana.'), backgroundColor: AppColors.danger),
        );
      }
      return;
    }
    if (sync.isLoggedIn && sync.isOperator && sync.operatorRoomId != room.number) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Brak uprawnień: Jesteś operatorem sali ${sync.operatorRoomId}. Nie możesz modyfikować sali ${room.number}.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }
    final success = await RoomDatabaseHelper.instance.setBreakStatus(
      room.id ?? 0,
      room.number,
      !room.isBreak,
    );
    await _loadRooms(showLoading: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? (room.isBreak ? 'Przerwa zakończona.' : 'Sala ${room.number} w przerwie (bez timera).')
              : 'Nie udało się zmienić przerwy sali ${room.number}.'),
          backgroundColor: success ? AppColors.success : AppColors.danger,
        ),
      );
    }
  }

  Future<void> _toggleAvailability(Room room) async {
    final sync = RoomSyncService.instance;
    if (room.lockStatus && !sync.isAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zmiana statusu tej sali jest zablokowana.'), backgroundColor: AppColors.danger),
        );
      }
      return;
    }
    if (sync.isLoggedIn && sync.isOperator && sync.operatorRoomId != room.number) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Brak uprawnień: Jesteś operatorem sali ${sync.operatorRoomId}. Nie możesz modyfikować sali ${room.number}.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    // Zajmowana sala dostaje Twoją nazwę (albo nazwę konta, jeśli jej nie ustawiłeś).
    String? occupantName;
    if (room.isAvailable) {
      if (_myNick.isNotEmpty) {
        occupantName = _myNick;
      } else if (sync.isLoggedIn && sync.userDisplayName.trim().isNotEmpty) {
        occupantName = sync.userDisplayName.trim();
      }
    }

    final newStatus = !room.isAvailable;
    final success = await RoomDatabaseHelper.instance.toggleAvailability(
      room.id ?? 0,
      room.isAvailable,
      roomNumber: room.number,
      occupantName: occupantName,
    );
    await _loadRooms(showLoading: false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  newStatus ? Icons.check_circle : Icons.event_busy,
                  color: newStatus ? AppColors.success : AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    newStatus
                        ? 'Sala ${room.number} jest wolna'
                        : (occupantName != null
                            ? 'Sala ${room.number} zajęta przez $occupantName'
                            : 'Sala ${room.number} zajęta'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF141414),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sync.lastErrorMessage.isNotEmpty ? sync.lastErrorMessage : 'Nie udało się zmienić statusu sali.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// Ustawianie / zmiana Twojej nazwy. Sale, które zajmujesz pod starą
  /// nazwą, od razu dostają nową.
  Future<void> _editMyNick() async {
    final controller = TextEditingController(text: _myNick);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Twoja nazwa',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Będzie widoczna przy salach, które zajmujesz.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Nick lub imię'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anuluj', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    if (result == null || result == _myNick) return;

    final oldNick = _myNick;
    await OccupantNick.save(result);
    if (!mounted) return;
    setState(() => _myNick = result);

    // Sale zajęte pod starą nazwą dostają nową
    if (oldNick.isNotEmpty) {
      final mine = _rooms.where((r) => r.occupantName == oldNick).toList();
      for (final r in mine) {
        await RoomSyncService.instance.changeRoomOccupant(r.number, result.isEmpty ? null : result);
      }
      if (mine.isNotEmpty) await _loadRooms(showLoading: false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isEmpty ? 'Usunięto Twoją nazwę' : 'Twoja nazwa: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildMyNickButton() {
    final hasNick = _myNick.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: InkWell(
        onTap: _editMyNick,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
            border: Border.all(color: AppColors.glassStroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasNick ? Icons.person_rounded : Icons.person_add_alt_1_rounded,
                size: 15,
                color: hasNick ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  hasNick ? _myNick : 'Ustaw nazwę',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasNick ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setAllFloorAvailability(bool isAvailable) async {
    await RoomDatabaseHelper.instance.setAllAvailabilityForFloor(
      floor: _selectedFloor,
      isAvailable: isAvailable,
    );
    await _loadRooms();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAvailable
                ? 'Wszystkie sale na kondygnacji "$_selectedFloor" oznaczone jako WOLNE'
                : 'Wszystkie sale na kondygnacji "$_selectedFloor" oznaczone jako ZAJĘTE',
          ),
          backgroundColor: isAvailable ? Colors.green : AppColors.danger,
        ),
      );
    }
  }

  Future<void> _resetDefaultRooms() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Przywróć domyślne sale', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Czy chcesz przywrócić pierwotną listę sal z planu Politechniki Rzeszowskiej (Noc Nauki)?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Przywróć', style: TextStyle(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await RoomDatabaseHelper.instance.resetToDefaults();
      await _loadRooms();
    }
  }

  Future<void> _navigateToAddRoom() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => AddEditRoomScreen(defaultFloor: _selectedFloor),
      ),
    );
    if (result == true) {
      _loadRooms();
    }
  }

  Future<void> _navigateToEditRoom(Room room) async {
    if (room.lockInfo && !RoomSyncService.instance.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Edycja informacji tej sali jest zablokowana.'), backgroundColor: AppColors.danger),
      );
      return;
    }
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => AddEditRoomScreen(room: room),
      ),
    );
    if (result == true) {
      _loadRooms();
    }
  }

  Future<void> _deleteRoom(Room room) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Usuń salę', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz usunąć "${room.displayName}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Usuń', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && room.id != null) {
      await RoomDatabaseHelper.instance.deleteRoom(room.id!);
      _loadRooms();
    }
  }

  Future<void> _showSyncSettingsDialog() async {
    final serverController = TextEditingController(text: RoomSyncService.instance.serverUrl);
    bool isDetectingLan = false;
    bool hasAutoChecked = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          if (!hasAutoChecked && (!kIsWeb || Uri.base.scheme != 'https') && RoomSyncService.instance.detectedLanUrl == null) {
            hasAutoChecked = true;
            Future.microtask(() async {
              setDialogState(() => isDetectingLan = true);
              await RoomSyncService.instance.discoverLocalServerUrl();
              if (dialogCtx.mounted) {
                setDialogState(() => isDetectingLan = false);
              }
            });
          }

          final currentState = RoomSyncService.instance.connectionState;
          Color badgeColor;
          String badgeText;
          switch (currentState) {
            case SyncConnectionState.connected:
              badgeColor = AppColors.success;
              badgeText = 'Połączono (Synchronizacja Live)';
              break;
            case SyncConnectionState.connecting:
              badgeColor = AppColors.warning;
              badgeText = 'Sprawdzanie połączenia...';
              break;
            case SyncConnectionState.offline:
              badgeColor = AppColors.danger;
              badgeText = 'Offline (Baza lokalna)';
              break;
            case SyncConnectionState.error:
              badgeColor = AppColors.warning;
              badgeText = 'Błąd połączenia';
              break;
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            title: const Row(
              children: [
                Icon(Icons.cloud_sync, color: AppColors.primary),
                SizedBox(width: 10),
                Text(
                  'Synchronizacja & Web',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            badgeText,
                            style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Adres serwera synchronizacji:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      if (isDetectingLan)
                        const Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                            ),
                            SizedBox(width: 6),
                            Text('Wykrywanie...', style: TextStyle(color: AppColors.cyan, fontSize: 11)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: serverController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF000000),
                      hintText: 'https://sale.pwojtaszek.codes',
                      hintStyle: const TextStyle(color: Colors.white30),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.wifi_find, color: AppColors.cyan, size: 20),
                        tooltip: 'Pobierz adres serwera z sieci Wi-Fi (Auto)',
                        onPressed: isDetectingLan
                            ? null
                            : () async {
                                setDialogState(() => isDetectingLan = true);
                                final detected = await RoomSyncService.instance.discoverLocalServerUrl();
                                if (!dialogCtx.mounted) return;
                                setDialogState(() {
                                  isDetectingLan = false;
                                  if (detected != null && detected.isNotEmpty) {
                                    serverController.text = detected;
                                  }
                                });
                                if (detected != null && detected.isNotEmpty) {
                                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                    SnackBar(
                                      content: Text('Pobrano adres serwera lokalnego: $detected'),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: const Color(0xFF000000),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.cloud, size: 14, color: AppColors.primary),
                        backgroundColor: const Color(0xFF2A2A2A),
                        label: const Text('sale.pwojtaszek.codes', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                        onPressed: () {
                          serverController.text = 'https://sale.pwojtaszek.codes';
                        },
                      ),
                      if (!kIsWeb || Uri.base.scheme != 'https')
                        ActionChip(
                          avatar: isDetectingLan
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
                              )
                            : const Icon(Icons.wifi, size: 14, color: AppColors.cyan),
                        backgroundColor: const Color(0xFF141414),
                        side: const BorderSide(color: AppColors.cyan, width: 0.8),
                        label: Text(
                          isDetectingLan
                              ? 'Wykrywanie w sieci...'
                              : (RoomSyncService.instance.detectedLanUrl != null
                                  ? 'Lokalnie (${RoomSyncService.instance.detectedLanUrl!.replaceFirst("http://", "")})'
                                  : 'Lokalnie Wi-Fi (Pobierz auto)'),
                          style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: isDetectingLan
                            ? null
                            : () async {
                                setDialogState(() => isDetectingLan = true);
                                final detected = await RoomSyncService.instance.discoverLocalServerUrl();
                                if (!dialogCtx.mounted) return;
                                setDialogState(() {
                                  isDetectingLan = false;
                                  if (detected != null && detected.isNotEmpty) {
                                    serverController.text = detected;
                                  }
                                });
                                if (detected != null && detected.isNotEmpty) {
                                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                    SnackBar(
                                      content: Text('Pobrano adres serwera w sieci Wi-Fi: $detected'),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: const Color(0xFF000000),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Nie udało się automatycznie wykryć serwera. Upewnij się, że komputer z serwerem i telefon są w tej samej sieci Wi-Fi.'),
                                      duration: Duration(seconds: 3),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.language, color: AppColors.textSecondary, size: 16),
                            SizedBox(width: 6),
                            Text('Aplikacja w przeglądarce Web:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        SizedBox(height: 6),
                        SelectableText(
                          'https://sale.pwojtaszek.codes',
                          style: TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Każda zmiana na telefonie lub w przeglądarce natychmiast synchronizuje się ze wszystkimi urządzeniami.',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  setDialogState(() {
                    badgeText = 'Sprawdzanie...';
                    badgeColor = AppColors.warning;
                  });
                  await RoomSyncService.instance.setServerUrl(serverController.text);
                  await _loadRooms();
                  setDialogState(() {});
                },
                child: const Text('Testuj & Zapisz', style: TextStyle(color: AppColors.primary)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Wymuś synchronizację'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                ),
                onPressed: () async {
                  await RoomSyncService.instance.setServerUrl(serverController.text);
                  await _loadRooms();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _downloadApk() async {
    const apkUrl = 'https://sale.pwojtaszek.codes/DostepnoscSal.apk';
    try {
      final uri = Uri.parse(kIsWeb ? '/DostepnoscSal.apk' : apkUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(Uri.parse(apkUrl), mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Error launching APK download: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.download_done, color: AppColors.success, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rozpoczęto pobieranie pliku DostepnoscSal.apk! Po pobraniu otwórz plik, aby zainstalować aplikację.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF141414),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _showAuthDialog({String? preselectedRoom}) async {
    final sync = RoomSyncService.instance;
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoading = false;
    String errorMsg = '';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isLoggedIn = sync.isLoggedIn;
          final role = sync.userRole;
          final assignedRoom = sync.operatorRoomId;

          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: Row(
              children: [
                Icon(
                  isLoggedIn ? Icons.verified_user : Icons.lock_person,
                  color: isLoggedIn ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Text(
                  isLoggedIn ? 'Konto operatora / admina' : 'Logowanie do systemu sal',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: isLoggedIn
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF000000),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Zalogowany:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                    const SizedBox(width: 8),
                                    Text(
                                      sync.userDisplayName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text('Rola:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: role == 'admin' ? AppColors.cyan.withValues(alpha: 0.2) : AppColors.warning.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        role.toUpperCase(),
                                        style: TextStyle(
                                          color: role == 'admin' ? AppColors.cyan : AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text('Uprawnienie:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        role == 'admin'
                                            ? 'Wszystkie sale i urządzenia'
                                            : 'Tylko sala $assignedRoom',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.danger.withValues(alpha: 0.2),
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                              ),
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Wyloguj się'),
                              onPressed: () async {
                                await sync.logout();
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                setState(() {});
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Wylogowano pomyślnie.'),
                                      backgroundColor: Color(0xFF141414),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zaloguj się, aby zarządzać statusem sal i czasem sesji:',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: usernameController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF000000),
                              hintText: 'Login (np. operator_104 lub admin)',
                              hintStyle: const TextStyle(color: Colors.white30),
                              prefixIcon: const Icon(Icons.person, color: Colors.white54, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: passwordController,
                            obscureText: true,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF000000),
                              hintText: 'Hasło',
                              hintStyle: const TextStyle(color: Colors.white30),
                              prefixIcon: const Icon(Icons.lock, color: Colors.white54, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                          ),
                          if (errorMsg.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              errorMsg,
                              style: const TextStyle(color: AppColors.danger, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 16),
                          const Text(
                            'Szybkie profile testowe (1 kliknięcie):',
                            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                avatar: const Icon(Icons.admin_panel_settings, size: 14, color: AppColors.cyan),
                                backgroundColor: const Color(0xFF000000),
                                side: const BorderSide(color: AppColors.cyan, width: 0.8),
                                label: const Text('Admin', style: TextStyle(color: AppColors.cyan, fontSize: 11)),
                                onPressed: () {
                                  usernameController.text = 'admin';
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.badge, size: 14, color: AppColors.primary),
                                backgroundColor: const Color(0xFF000000),
                                side: const BorderSide(color: AppColors.primary, width: 0.8),
                                label: const Text('Sala 104', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                                onPressed: () {
                                  usernameController.text = 'operator_104';
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.badge, size: 14, color: AppColors.primary),
                                backgroundColor: const Color(0xFF000000),
                                side: const BorderSide(color: AppColors.primary, width: 0.8),
                                label: const Text('AULA', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                                onPressed: () {
                                  usernameController.text = 'operator_aula';
                                },
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.badge, size: 14, color: AppColors.primary),
                                backgroundColor: const Color(0xFF000000),
                                side: const BorderSide(color: AppColors.primary, width: 0.8),
                                label: const Text('Garaż', style: TextStyle(color: AppColors.primary, fontSize: 11)),
                                onPressed: () {
                                  usernameController.text = 'operator_garaz';
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () async {
                                      setDialogState(() {
                                        isLoading = true;
                                        errorMsg = '';
                                      });
                                      final ok = await sync.login(
                                        usernameController.text.trim(),
                                        passwordController.text.trim(),
                                      );
                                      if (!ctx.mounted) return;
                                      setDialogState(() => isLoading = false);
                                      if (ok) {
                                        Navigator.of(ctx).pop();
                                        setState(() {});
                                        await _loadRooms();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Zalogowano pomyślnie jako ${sync.userDisplayName} (${sync.userRole})'),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      } else {
                                        setDialogState(() {
                                          errorMsg = sync.lastErrorMessage.isNotEmpty
                                              ? sync.lastErrorMessage
                                              : 'Niepoprawny login lub hasło.';
                                        });
                                      }
                                    },
                              child: isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                                    )
                                  : const Text('Zaloguj się', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Zamknij', style: TextStyle(color: Colors.white60)),
              ),
            ],
          );
        },
      ),
    );
  }

  int get _freeCount => _rooms.where((r) => r.isAvailable).length;
  int get _occupiedCount => _rooms.where((r) => !r.isAvailable).length;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dostępność sal',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
            const Text(
              'Politechnika Rzeszowska, wersja 1.3.10',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          _buildMyNickButton(),
          const SizedBox(width: 4),
          // Auth Role Indicator & Login Button
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: RoomSyncService.instance.authNotifier,
            builder: (context, user, _) {
              final isLoggedIn = RoomSyncService.instance.isLoggedIn;
              final isAdmin = RoomSyncService.instance.isAdmin;
              final isOperator = RoomSyncService.instance.isOperator;
              final opRoom = RoomSyncService.instance.operatorRoomId;

              Color chipColor = const Color(0xFF000000);
              Color textColor = Colors.white70;
              IconData icon = Icons.person_outline;
              String label = 'Gość';

              if (isAdmin) {
                chipColor = AppColors.cyan.withValues(alpha: 0.2);
                textColor = AppColors.cyan;
                icon = Icons.admin_panel_settings;
                label = 'Admin';
              } else if (isOperator) {
                chipColor = AppColors.warning.withValues(alpha: 0.2);
                textColor = AppColors.warning;
                icon = Icons.badge_outlined;
                label = 'Op. $opRoom';
              } else if (isLoggedIn) {
                chipColor = Colors.blue.withValues(alpha: 0.2);
                textColor = AppColors.primary;
                icon = Icons.account_circle_outlined;
                label = 'Konto';
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showAuthDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: textColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: textColor),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Tryb TV (Wszystkie piętra na jednym ekranie)',
            icon: const Icon(Icons.tv_rounded, color: AppColors.cyan),
            onPressed: _openTvDashboard,
          ),
          ValueListenableBuilder<SyncConnectionState>(
            valueListenable: RoomSyncService.instance.connectionNotifier,
            builder: (context, state, _) {
              Color dotColor;
              String tooltip;
              switch (state) {
                case SyncConnectionState.connected:
                  dotColor = AppColors.success;
                  tooltip = 'Synchronizacja aktywna (Online)';
                  break;
                case SyncConnectionState.connecting:
                  dotColor = AppColors.warning;
                  tooltip = 'Łączenie z serwerem...';
                  break;
                case SyncConnectionState.offline:
                case SyncConnectionState.error:
                  dotColor = AppColors.danger;
                  tooltip = 'Tryb lokalny (Offline)';
                  break;
              }
              return IconButton(
                tooltip: tooltip,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.cloud_sync, color: Colors.white70),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.6),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: _showSyncSettingsDialog,
              );
            },
          ),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                icon: const Icon(Icons.download, size: 16),
                label: const Text(
                  'Pobierz APK',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: _downloadApk,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF2A2A2A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            onSelected: (val) {
              if (val == 'tv_dashboard') {
                _openTvDashboard();
              } else if (val == 'esp_devices') {
                EspDevicesDialog.show(context);
              } else if (val == 'check_updates') {
                AppUpdateService.instance.checkForUpdate(context, showUpToDate: true);
              } else if (val == 'download') {
                _downloadApk();
              } else if (val == 'diagnostics') {
                DiagnosticsDialog.show(context);
              } else if (val == 'free_all') {
                _setAllFloorAvailability(true);
              } else if (val == 'occupy_all') {
                _setAllFloorAvailability(false);
              } else if (val == 'reset') {
                _resetDefaultRooms();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'tv_dashboard',
                child: Row(
                  children: [
                    Icon(Icons.tv_rounded, color: AppColors.cyan, size: 18),
                    SizedBox(width: 10),
                    Text('Tryb TV / Kiosk (Wszystkie piętra)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'esp_devices',
                child: Row(
                  children: [
                    Icon(Icons.memory, color: AppColors.cyan, size: 18),
                    SizedBox(width: 10),
                    Text('Sterowniki ESP (ESP8266 & ESP32)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'check_updates',
                child: Row(
                  children: [
                    Icon(Icons.system_update_rounded, color: AppColors.warning, size: 18),
                    SizedBox(width: 10),
                    Text('Sprawdź aktualizacje', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              if (kIsWeb)
                const PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.android, color: AppColors.success, size: 18),
                      SizedBox(width: 10),
                      Text('Pobierz aplikację na Androida (.apk)', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'diagnostics',
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, color: AppColors.textSecondary, size: 18),
                    SizedBox(width: 10),
                    Text('Diagnostyka serwisowa', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'free_all',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                    SizedBox(width: 10),
                    Text('Zwolnij wszystkie na tym piętrze', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'occupy_all',
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, color: AppColors.danger, size: 18),
                    SizedBox(width: 10),
                    Text('Zajmij wszystkie na tym piętrze', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restore, color: AppColors.warning, size: 18),
                    SizedBox(width: 10),
                    Text('Przywróć domyślne sale PRz', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls: Mode Switcher (Mapa vs Lista) & Floor Chips
            _buildTopControls(),

            if (_pairingDevices.isNotEmpty)
              GestureDetector(
                onTap: () => EspDevicesDialog.show(context),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.warning.withValues(alpha: 0.35),
                        AppColors.warning.withValues(alpha: 0.2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.warning, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sensors, color: AppColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Wykryto sterownik ESP8266 (${_pairingDevices.first['deviceId'] ?? 'Wemos'}) w trybie parowania! Kliknij, aby przypisać salę.',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_ios, color: AppColors.warning, size: 14),
                    ],
                  ),
                ),
              ),

            // Stats Banner
            _buildStatsBanner(),

            // View Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _currentViewIndex == 0
                      ? _buildMapView()
                      : _buildListView(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddRoom,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text(
          'Dodaj salę',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.transparent,
      child: Column(
        children: [
          // Switch between Map and List View
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.map_outlined, size: 18),
                      label: Text('Plan budynku (Mapa)', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.list_alt_rounded, size: 18),
                      label: Text('Lista sal', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {_currentViewIndex},
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primary.withValues(alpha: 0.22);
                      }
                      return AppColors.glass;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return AppColors.primary;
                      }
                      return AppColors.textSecondary;
                    }),
                    side: const WidgetStatePropertyAll(
                      BorderSide(color: AppColors.glassStroke),
                    ),
                  ),
                  onSelectionChanged: (set) {
                    setState(() {
                      _currentViewIndex = set.first;
                    });
                    _saveCurrentState();
                    _loadRooms();
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Floor Selector & Actions Bar (plenty of room in browser/desktop)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildFloorChip('Wszystkie'),
                      ..._floors.map((fl) => _buildFloorChip(fl)),
                    ],
                  ),
                ),
              ),
              if (_currentViewIndex == 0) ...[
                const SizedBox(width: 8),
                _buildLayoutEditButton(),
              ],
              const SizedBox(width: 8),
              _buildTvModeButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutEditButton() {
    if (_isEditMode) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Przywróć domyślny układ sal',
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
            onPressed: () => _confirmResetPositions(_selectedFloor == 'Wszystkie' ? 'Piętro' : _selectedFloor),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Zakończ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusPill)),
            ),
            onPressed: () {
              setState(() => _isEditMode = false);
            },
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      icon: const Icon(Icons.edit_location_alt_rounded, size: 16, color: AppColors.primary),
      label: const Text(
        'Układ sal na planie',
        style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.glassStroke, width: 1),
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusPill)),
      ),
      onPressed: () async {
        final sync = RoomSyncService.instance;
        if (sync.isLoggedIn && sync.isAdmin) {
          setState(() => _isEditMode = true);
          return;
        }
        // Układ sal jest wspólny dla wszystkich, więc zmienia go administrator
        final login = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Zmiana układu sal',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            content: const Text(
              'Układ sal widzą wszyscy, dlatego przestawiać sale może administrator. '
              'Zaloguj się jako admin, a tryb przestawiania włączy się od razu.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Anuluj', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Zaloguj się'),
              ),
            ],
          ),
        );
        if (login != true || !mounted) return;
        await _showAuthDialog();
        if (mounted && sync.isLoggedIn && sync.isAdmin) {
          setState(() => _isEditMode = true);
        }
      },
    );
  }

  void _showLayoutSaveError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nie zapisano zmiany sali. Sprawdź połączenie z serwerem i czy jesteś zalogowany jako admin.'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  Widget _buildTvModeButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.tv_rounded, size: 16, color: AppColors.cyan),
      label: const Text(
        'Tryb TV',
        style: TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.cyan.withValues(alpha: 0.12),
        elevation: 0,
        side: const BorderSide(color: AppColors.glassStroke, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusPill)),
      ),
      onPressed: _openTvDashboard,
    );
  }

  Widget _buildFloorChip(String floorName) {
    final isSelected = _selectedFloor == floorName;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(floorName),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.glass,
        labelStyle: TextStyle(
          color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.glassStroke),
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedFloor = floorName);
            _saveCurrentState();
            _loadRooms();
          }
        },
      ),
    );
  }

  /// Polska odmiana liczebnika: 1 sala, 2–4 sale, 5+ sal (z wyjątkiem 12–14).
  String _plural(int n, String one, String few, String many) {
    if (n == 1) return one;
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  Widget _buildStatsBanner() {
    final total = _rooms.length;
    final free = _freeCount;
    final occupied = _occupiedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$free',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_plural(free, 'wolna sala', 'wolne sale', 'wolnych sal')} z $total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
              Text(
                '$occupied ${_plural(occupied, 'zajęta', 'zajęte', 'zajętych')}',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Pasek obłożenia: zielone = wolne, czerwone = zajęte
          ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (free > 0)
                    Expanded(
                      flex: free,
                      child: Container(color: AppColors.success),
                    ),
                  if (occupied > 0)
                    Expanded(
                      flex: occupied,
                      child: Container(color: AppColors.danger),
                    ),
                  if (total == 0)
                    Expanded(child: Container(color: AppColors.glassHi)),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildMapView() {
    final isAllFloors = _selectedFloor == 'Wszystkie';

    return Column(
      children: [
        // Map Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 12, color: AppColors.success),
                    SizedBox(width: 4),
                    Text('Dostępna (Wolna)', style: TextStyle(color: AppColors.success, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cancel, size: 12, color: AppColors.danger),
                    SizedBox(width: 4),
                    Text('Niedostępna (Zajęta)', style: TextStyle(color: AppColors.danger, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Interactive Map
        Expanded(
          child: isAllFloors
              ? _buildAllFloorsMapView()
              : _buildSingleFloorMapView(_selectedFloor),
        ),
      ],
    );
  }

  Widget _buildAllFloorsMapView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;

        if (isWide) {
          // Side-by-side for desktop browser / TV / wide monitors
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildFloorCard('Parter', 'POZIOM 0 (PARTER)', AppColors.cyan),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildFloorCard('Piętro', 'POZIOM +1 (I PIĘTRO)', AppColors.primary, controlsBottomOffset: 80),
                ),
              ],
            ),
          );
        } else {
          // Stacked scrollable for narrow/mobile screens
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            child: Column(
              children: [
                _buildFloorCard('Parter', 'POZIOM 0 (PARTER)', AppColors.cyan, fixedHeight: 560),
                const SizedBox(height: 16),
                _buildFloorCard('Piętro', 'POZIOM +1 (I PIĘTRO)', AppColors.primary, fixedHeight: 560, controlsBottomOffset: 80),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildFloorCard(String floor, String title, Color accentColor, {double? fixedHeight, double controlsBottomOffset = 12}) {
    final floorRooms = _rooms.where((r) => r.floor == floor || (floor == 'Parter' && r.floor == 'Garaż podziemny')).toList();
    final free = floorRooms.where((r) => r.isAvailable).length;

    final cardContent = Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.glassHi,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.8),
              ),
              const Spacer(),
              Text(
                'Wolne: $free / ${floorRooms.length}',
                style: TextStyle(color: free > 0 ? AppColors.success : AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: InteractiveFloorMap(
            floor: floor,
            rooms: _rooms,
            isEditMode: _isEditMode,
            showEditToolbar: false,
            controlsBottomOffset: controlsBottomOffset,
            onRoomTap: (room) {
              showRoomDetailSheet(
                context: context,
                room: room,
                onToggleAvailability: _toggleAvailability,
                onToggleBreak: _toggleBreak,
                onLocksChanged: () => _loadRooms(showLoading: false),
                onEdit: () => _navigateToEditRoom(room),
                onDelete: () => _deleteRoom(room),
                onLimitChanged: (updatedRoom, newLimit) async {
                  await _loadRooms(showLoading: false);
                },
              );
            },
            onRoomQuickToggle: (room) => _toggleAvailability(room),
            onRoomPositionChanged: (room, newX, newY) async {
              final saved = await RoomDatabaseHelper.instance.updateRoomPosition(room, newX, newY);
              if (!saved) _showLayoutSaveError();
              return saved;
            },
            onRoomLayoutChanged: (room, scale, angle) async {
              final saved = await RoomDatabaseHelper.instance.updateRoomLayout(room, scale, angle);
              if (!saved) _showLayoutSaveError();
              return saved;
            },
            onResetPositions: (fl) async {
              await RoomDatabaseHelper.instance.resetRoomPositions(floor: fl);
              await _loadRooms();
            },
          ),
        ),
      ],
    );

    if (fixedHeight != null) {
      return Container(
        height: fixedHeight,
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(color: AppColors.glassStroke),
        ),
        clipBehavior: Clip.antiAlias,
        child: cardContent,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: AppColors.glassStroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: cardContent,
    );
  }

  Widget _buildSingleFloorMapView(String floor) {
    return InteractiveFloorMap(
      floor: floor,
      rooms: _rooms,
      isEditMode: _isEditMode,
      showEditToolbar: false,
      controlsBottomOffset: 80,
      onRoomTap: (room) {
        showRoomDetailSheet(
          context: context,
          room: room,
          onToggleAvailability: _toggleAvailability,
          onToggleBreak: _toggleBreak,
          onLocksChanged: () => _loadRooms(showLoading: false),
          onEdit: () => _navigateToEditRoom(room),
          onDelete: () => _deleteRoom(room),
          onLimitChanged: (updatedRoom, newLimit) async {
            await _loadRooms(showLoading: false);
          },
        );
      },
      onRoomQuickToggle: (room) => _toggleAvailability(room),
      onRoomPositionChanged: (room, newX, newY) async {
        final saved = await RoomDatabaseHelper.instance.updateRoomPosition(room, newX, newY);
        if (!saved) _showLayoutSaveError();
        return saved;
      },
      onRoomLayoutChanged: (room, scale, angle) async {
        final saved = await RoomDatabaseHelper.instance.updateRoomLayout(room, scale, angle);
        if (!saved) _showLayoutSaveError();
        return saved;
      },
      onResetPositions: (fl) async {
        await RoomDatabaseHelper.instance.resetRoomPositions(floor: fl);
        await _loadRooms();
      },
    );
  }

  Future<void> _confirmResetPositions(String floor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Przywróć domyślny układ', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz przywrócić pierwotne położenie wszystkich sal na kondygnacji "$floor"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Przywróć', style: TextStyle(color: AppColors.onPrimary)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await RoomDatabaseHelper.instance.resetRoomPositions(floor: floor);
      await _loadRooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Przywrócono domyślne położenie sal dla "$floor"'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  Widget _buildListView() {
    return Column(
      children: [
        // Search & Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(AppColors.radiusControl),
              border: Border.all(color: AppColors.glassStroke),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => _loadRooms(),
              decoration: InputDecoration(
                hintText: 'Szukaj po numerze, nazwie lub temacie...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white60),
                        onPressed: () {
                          _searchController.clear();
                          _loadRooms();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // Quick Status Filter (Wszystkie, Wolne, Zajęte) + Reorder Toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildStatusFilterChip('Wszystkie'),
              const SizedBox(width: 8),
              _buildStatusFilterChip('Wolne'),
              const SizedBox(width: 8),
              _buildStatusFilterChip('Zajęte'),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() => _isReorderMode = !_isReorderMode);
                },
                borderRadius: BorderRadius.circular(AppColors.radiusPill),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isReorderMode
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.glass,
                    borderRadius: BorderRadius.circular(AppColors.radiusPill),
                    border: Border.all(
                      color: _isReorderMode ? AppColors.primary : AppColors.glassStroke,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isReorderMode ? Icons.check : Icons.swap_vert_rounded,
                        size: 16,
                        color: _isReorderMode ? AppColors.primary : Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isReorderMode ? 'Zapisz' : 'Kolejność',
                        style: TextStyle(
                          color: _isReorderMode ? AppColors.primary : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Rooms List
        Expanded(
          child: _rooms.isEmpty
              ? const Center(
                  child: Text(
                    'Brak sal spełniających kryteria',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : _isReorderMode
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: _rooms.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) async {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final item = _rooms.removeAt(oldIndex);
                          _rooms.insert(newIndex, item);
                        });
                        final roomIds = _rooms.where((r) => r.id != null).map((r) => r.id!).toList();
                        await RoomDatabaseHelper.instance.updateRoomSortOrder(roomIds);
                      },
                      itemBuilder: (context, index) {
                        final room = _rooms[index];
                        return Container(
                          key: ValueKey(room.id ?? index),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: _buildRoomCard(room, isReordering: true),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: _rooms.length,
                      itemBuilder: (context, index) {
                        final room = _rooms[index];
                        return _buildRoomCard(room);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStatusFilterChip(String label) {
    final isSelected = _statusFilter == label;
    Color activeColor = AppColors.primary;
    if (label == 'Wolne') activeColor = AppColors.success;
    if (label == 'Zajęte') activeColor = AppColors.danger;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: activeColor.withValues(alpha: 0.16),
      backgroundColor: AppColors.glass,
      labelStyle: TextStyle(
        color: isSelected ? activeColor : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11,
      ),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        side: BorderSide(color: isSelected ? activeColor : AppColors.glassStroke),
      ),
      onSelected: (_) {
        setState(() => _statusFilter = label);
        _saveCurrentState();
        _loadRooms();
      },
    );
  }

  Widget _buildRoomCard(Room room, {bool isReordering = false}) {
    final isAvailable = room.isAvailable;
    final statusColor = room.isBreak ? AppColors.warning : (isAvailable ? AppColors.success : AppColors.danger);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppColors.glassDecoration(
        borderColor: isReordering ? AppColors.primary : null,
      ),
      child: InkWell(
        onTap: isReordering ? null : () => _toggleAvailability(room),
        onLongPress: isReordering
            ? null
            : () {
                showRoomDetailSheet(
                  context: context,
                  room: room,
                  onToggleAvailability: _toggleAvailability,
                onToggleBreak: _toggleBreak,
                onLocksChanged: () => _loadRooms(showLoading: false),
                  onEdit: () => _navigateToEditRoom(room),
                  onDelete: () => _deleteRoom(room),
                  onLimitChanged: (updatedRoom, newLimit) async {
                    await _loadRooms(showLoading: false);
                  },
                );
              },
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              // Pasek statusu (zielony = wolna, czerwony = zajęta)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Numer sali jak na tabliczce
              SizedBox(
                width: 50,
                child: Text(
                  room.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Room Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 2,
                      children: [
                        if (room.occupantName != null) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_rounded, size: 13, color: AppColors.textPrimary),
                              const SizedBox(width: 3),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(
                                  room.occupantName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          room.floor,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          room.category,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        if (room.defaultAlertLimitSeconds != null && room.defaultAlertLimitSeconds! > 0) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () {
                              showRoomDetailSheet(
                                context: context,
                                room: room,
                                onToggleAvailability: _toggleAvailability,
                onToggleBreak: _toggleBreak,
                onLocksChanged: () => _loadRooms(showLoading: false),
                                onEdit: () => _navigateToEditRoom(room),
                                onDelete: () => _deleteRoom(room),
                                onLimitChanged: (updatedRoom, newLimit) async {
                                  await _loadRooms(showLoading: false);
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined, size: 12, color: AppColors.warning),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${room.defaultAlertLimitSeconds! ~/ 60}m',
                                    style: const TextStyle(
                                      color: AppColors.warning,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (!room.isAvailable && room.durationFormatted.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                room.isAlertDue ? Icons.warning_amber_rounded : Icons.access_time_rounded,
                                size: 12,
                                color: room.isAlertDue ? AppColors.warning : AppColors.danger,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                room.durationFormatted,
                                style: TextStyle(
                                  color: room.isAlertDue ? AppColors.warning : AppColors.danger,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    if (room.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        room.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // 1-TAP AVAILABILITY TOGGLE BUTTON or DRAG HANDLE
              if (isReordering)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.drag_indicator_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                )
              else
                InkWell(
                  onTap: () => _toggleAvailability(room),
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppColors.radiusPill),
                      border: Border.all(color: statusColor.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      room.isBreak ? 'Przerwa' : (isAvailable ? 'Wolna' : 'Zajęta'),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
