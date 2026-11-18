import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'room_sync_service.dart';
import 'room_database_helper.dart';

class DiagnosticsService {
  static final DiagnosticsService instance = DiagnosticsService._init();
  DiagnosticsService._init();

  Future<Map<String, dynamic>> gatherDiagnosticReport({
    double? screenWidth,
    double? screenHeight,
    double? pixelRatio,
  }) async {
    final clientData = await _getClientDiagnostics(
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      pixelRatio: pixelRatio,
    );
    final serverData = await _getServerDiagnostics();

    return {
      'report_generated_at': DateTime.now().toIso8601String(),
      'client': clientData,
      'server': serverData,
    };
  }

  Future<Map<String, dynamic>> _getClientDiagnostics({
    double? screenWidth,
    double? screenHeight,
    double? pixelRatio,
  }) async {
    final sw = Stopwatch()..start();
    bool pingSuccess = false;
    int pingLatencyMs = -1;

    try {
      final pingUrl = RoomSyncService.instance.buildUri('/api/v1/health');
      final res = await http.get(pingUrl).timeout(const Duration(seconds: 3));
      sw.stop();
      if (res.statusCode == 200) {
        pingSuccess = true;
        pingLatencyMs = sw.elapsedMilliseconds;
      }
    } catch (_) {
      sw.stop();
    }

    // Local DB count
    int localRoomsCount = 0;
    try {
      final rooms = await RoomDatabaseHelper.instance.getRooms();
      localRoomsCount = rooms.length;
    } catch (_) {}

    return {
      'app_name': 'Dostępność Sal - Politechnika Rzeszowska',
      'package_name': 'com.example.roomavailability',
      'app_version': '1.3.7+12',
      'platform': kIsWeb ? 'Web Browser' : Platform.operatingSystem,
      'os_version': kIsWeb ? 'HTML5 / WebAssembly' : Platform.operatingSystemVersion,
      'is_web': kIsWeb,
      'display': {
        'width': screenWidth != null ? screenWidth.toInt() : 'unknown',
        'height': screenHeight != null ? screenHeight.toInt() : 'unknown',
        'pixel_ratio': pixelRatio != null ? pixelRatio.toStringAsFixed(2) : 'unknown',
      },
      'sync_status': {
        'connection_state': RoomSyncService.instance.connectionState.name,
        'server_url': RoomSyncService.instance.serverUrl.isEmpty ? 'https://sale.pwojtaszek.codes' : RoomSyncService.instance.serverUrl,
        'last_sync': RoomSyncService.instance.lastSyncTime?.toIso8601String() ?? 'Nigdy',
        'ping_success': pingSuccess,
        'ping_latency_ms': pingLatencyMs,
      },
      'local_database': {
        'engine': kIsWeb ? 'In-Memory Web Cache' : 'SQLite (Mobile sqflite)',
        'records_count': localRoomsCount,
      },
    };
  }

  Future<Map<String, dynamic>> _getServerDiagnostics() async {
    try {
      final serverUrl = RoomSyncService.instance.buildUri('/api/service-info');
      final res = await http.get(serverUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        return json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } else {
        return {'status': 'error', 'code': res.statusCode};
      }
    } catch (e) {
      return {'status': 'unreachable', 'error': e.toString()};
    }
  }
}
