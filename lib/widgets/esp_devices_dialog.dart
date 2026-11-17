import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../services/room_sync_service.dart';
import '../theme/app_theme.dart';

class EspDevicesDialog extends StatefulWidget {
  const EspDevicesDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const EspDevicesDialog(),
    );
  }

  @override
  State<EspDevicesDialog> createState() => _EspDevicesDialogState();
}

class _EspDevicesDialogState extends State<EspDevicesDialog> {
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _pairingDevices = [];
  List<Room> _allRooms = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  String _filterType = 'all'; // 'all', 'esp32', 'esp8266'
  int _guideTabIndex = 0; // 0 = ESP32 CYD, 1 = ESP8266 Wemos

  // Selected room for pairing
  final Map<String, String> _selectedRoomForDevice = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 3 seconds while dialog is open to detect button presses & heartbeat
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _getDeviceType(Map<String, dynamic> dev) {
    final name = (dev['name'] as String? ?? '').toLowerCase();
    final id = (dev['id'] as String? ?? '').toLowerCase();
    if (name.contains('cyd') || name.contains('esp32') || id.contains('cyd') || id.contains('esp32')) {
      return 'esp32';
    }
    return 'esp8266';
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final devices = await RoomSyncService.instance.getDevices();
      final pairings = await RoomSyncService.instance.getPairingDevices();
      final rooms = await RoomDatabaseHelper.instance.getRooms();

      if (mounted) {
        setState(() {
          _devices = devices;
          _pairingDevices = pairings;
          _allRooms = rooms;
          _isLoading = false;

          // Default selection for pairing devices
          for (final p in _pairingDevices) {
            final devId = p['deviceId'] as String? ?? p['id'] as String?;
            if (devId != null && !_selectedRoomForDevice.containsKey(devId) && _allRooms.isNotEmpty) {
              _selectedRoomForDevice[devId] = _allRooms.first.number;
            }
          }
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _assignDevice(String deviceId, String roomNumber) async {
    final success = await RoomSyncService.instance.assignDeviceToRoom(deviceId, roomNumber: roomNumber);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '✅ Pomyślnie przypisano urządzenie do sali $roomNumber!' : '❌ Błąd przypisywania urządzenia.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.danger,
        ),
      );
      _loadData();
    }
  }

  Future<void> _deleteDevice(String deviceId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Usunąć sterownik?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz usunąć kontroler "$name"? Urządzenie straci autoryzację do serwera.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await RoomSyncService.instance.deleteDevice(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '🗑️ Usunięto sterownik.' : '❌ Błąd podczas usuwania sterownika.'),
            backgroundColor: ok ? AppColors.success : AppColors.danger,
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _showAddDeviceDialog() async {
    final nameController = TextEditingController(text: 'ESP32_CYD_Sala_');
    String selectedType = 'esp32'; // 'esp32' or 'esp8266'
    String selectedRoom = _allRooms.isNotEmpty ? _allRooms.first.number : '104';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            title: const Row(
              children: [
                Icon(Icons.add_circle_outline, color: AppColors.cyan),
                SizedBox(width: 10),
                Text('Zarejestruj sterownik ESP', style: TextStyle(color: Colors.white, fontSize: 17)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Typ sprzętu:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.smart_display, size: 16, color: AppColors.cyan),
                          label: const Text('ESP32 CYD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          selected: selectedType == 'esp32',
                          selectedColor: Colors.cyan.withValues(alpha: 0.3),
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                selectedType = 'esp32';
                                nameController.text = 'CYD_ESP32_Sala_$selectedRoom';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.developer_board, size: 16, color: AppColors.warning),
                          label: const Text('ESP8266 Wemos', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          selected: selectedType == 'esp8266',
                          selectedColor: Colors.orange.withValues(alpha: 0.3),
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                selectedType = 'esp8266';
                                nameController.text = 'ESP_Wemos_Sala_$selectedRoom';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Nazwa urządzenia:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF000000),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Przypisana sala:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedRoom,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF141414),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        items: _allRooms.map((r) {
                          return DropdownMenuItem<String>(
                            value: r.number,
                            child: Text('Sala ${r.number} - ${r.name} (${r.floor})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              selectedRoom = val;
                              if (selectedType == 'esp32') {
                                nameController.text = 'CYD_ESP32_Sala_$val';
                              } else {
                                nameController.text = 'ESP_Wemos_Sala_$val';
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Zarejestruj'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: () async {
                  final dev = await RoomSyncService.instance.registerDevice(
                    nameController.text.trim(),
                    selectedRoom,
                  );
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();

                  if (dev != null && dev['token'] != null) {
                    final rawToken = dev['token'] as String;
                    _showTokenDialog(nameController.text.trim(), selectedRoom, rawToken);
                  }
                  _loadData();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTokenDialog(String name, String room, String token) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Row(
          children: [
            Icon(Icons.key, color: AppColors.success),
            SizedBox(width: 10),
            Text('Token urządzenia', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Urządzenie "$name" dla sali $room zostało zarejestrowane pomyślnie!',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Wprowadź poniższy token w panelu konfiguracyjnym ESP (Token jest wyświetlany tylko raz):',
              style: TextStyle(color: AppColors.warning, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      token,
                      style: const TextStyle(
                        color: AppColors.success,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: AppColors.success, size: 20),
                    tooltip: 'Kopiuj token',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: token));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Skopiowano token do schowka!'),
                          backgroundColor: AppColors.success,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2A2A), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredDevices = _devices.where((d) {
      if (_filterType == 'all') return true;
      return _getDeviceType(d) == _filterType;
    }).toList();

    final esp32Count = _devices.where((d) => _getDeviceType(d) == 'esp32').length;
    final esp8266Count = _devices.where((d) => _getDeviceType(d) == 'esp8266').length;

    return Dialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(Icons.memory, color: AppColors.cyan, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sterowniki sal ESP (ESP8266 & ESP32)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Zarządzanie fizycznymi kontrolerami Wemos oraz panelami CYD',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.cyan, size: 22),
                  tooltip: 'Dodaj sterownik ESP',
                  onPressed: _showAddDeviceDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white70),
                  tooltip: 'Odśwież listę',
                  onPressed: () => _loadData(),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 20),

            // Filter Tabs: Wszystkie, ESP32 CYD, ESP8266 Wemos
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text('Wszystkie (${_devices.length})'),
                  selected: _filterType == 'all',
                  selectedColor: Colors.blueAccent.withValues(alpha: 0.3),
                  labelStyle: TextStyle(
                    color: _filterType == 'all' ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: _filterType == 'all' ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _filterType = 'all'),
                ),
                FilterChip(
                  avatar: const Icon(Icons.smart_display, size: 14, color: AppColors.cyan),
                  label: Text('ESP32 CYD ($esp32Count)'),
                  selected: _filterType == 'esp32',
                  selectedColor: AppColors.cyan.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                    color: _filterType == 'esp32' ? AppColors.cyan : Colors.white70,
                    fontSize: 11,
                    fontWeight: _filterType == 'esp32' ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _filterType = 'esp32'),
                ),
                FilterChip(
                  avatar: const Icon(Icons.developer_board, size: 14, color: AppColors.warning),
                  label: Text('ESP8266 Wemos ($esp8266Count)'),
                  selected: _filterType == 'esp8266',
                  selectedColor: AppColors.warning.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                    color: _filterType == 'esp8266' ? AppColors.warning : Colors.white70,
                    fontSize: 11,
                    fontWeight: _filterType == 'esp8266' ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _filterType = 'esp8266'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                  : ListView(
                      children: [
                        // Pairing Alert / Banner
                        if (_pairingDevices.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange.withValues(alpha: 0.25),
                                  Colors.amber.withValues(alpha: 0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.warning, width: 1.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.sensors, color: AppColors.warning, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Wykryto urządzenie w trybie parowania!',
                                      style: TextStyle(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Wciśnięto przyciski konfiguracji. Wybierz salę, aby przypisać kontroler:',
                                  style: TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                const SizedBox(height: 10),
                                ..._pairingDevices.map((dev) {
                                  final devId = dev['deviceId'] as String? ?? dev['id'] as String? ?? 'ESP_???';
                                  final currentSelection = _selectedRoomForDevice[devId] ?? (_allRooms.isNotEmpty ? _allRooms.first.number : '');

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF000000),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          devId,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                          ),
                                        ),
                                        const Spacer(),
                                        DropdownButton<String>(
                                          value: currentSelection,
                                          dropdownColor: const Color(0xFF141414),
                                          style: const TextStyle(color: Colors.white, fontSize: 12),
                                          underline: const SizedBox(),
                                          items: _allRooms.map((r) {
                                            return DropdownMenuItem<String>(
                                              value: r.number,
                                              child: Text('Sala ${r.number} (${r.name})'),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                _selectedRoomForDevice[devId] = val;
                                              });
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.warning,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                          icon: const Icon(Icons.link, size: 14),
                                          label: const Text('Przypisz'),
                                          onPressed: () => _assignDevice(devId, currentSelection),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Registered Devices List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Zarejestrowane kontrolery:',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Pozycji: ${filteredDevices.length}',
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (filteredDevices.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF000000),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.developer_board_off, color: Colors.white24, size: 36),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Brak zarejestrowanych sterowników w tym filtrze.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.add, size: 16, color: AppColors.cyan),
                                    label: const Text('Zarejestruj sterownik', style: TextStyle(color: AppColors.cyan, fontSize: 12)),
                                    onPressed: _showAddDeviceDialog,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...filteredDevices.map((dev) {
                            final devId = dev['id'] as String? ?? dev['deviceId'] as String? ?? 'ESP_???';
                            final devName = dev['name'] as String? ?? devId;
                            final roomNum = dev['room_id'] as String? ?? dev['roomNumber'] as String?;
                            final isActive = dev['is_active'] == 1 || dev['is_active'] == true;
                            final lastSeen = dev['last_seen_at'] as String?;
                            final type = _getDeviceType(dev);
                            final isEsp32 = type == 'esp32';

                            // Find room info if assigned
                            Room? assignedRoom;
                            if (roomNum != null && roomNum.isNotEmpty) {
                              try {
                                assignedRoom = _allRooms.firstWhere((r) => r.number == roomNum);
                              } catch (_) {}
                            }
                            final isAvail = assignedRoom?.isAvailable ?? true;
                            final hasRoom = roomNum != null && roomNum.isNotEmpty;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF000000),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: hasRoom
                                      ? (isAvail ? AppColors.success.withValues(alpha: 0.4) : AppColors.danger.withValues(alpha: 0.4))
                                      : Colors.white12,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Type icon
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isEsp32
                                          ? AppColors.cyan.withValues(alpha: 0.15)
                                          : AppColors.warning.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      isEsp32 ? Icons.smart_display : Icons.developer_board,
                                      color: isEsp32 ? AppColors.cyan : AppColors.warning,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              devName,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isEsp32
                                                    ? AppColors.cyan.withValues(alpha: 0.2)
                                                    : AppColors.warning.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                isEsp32 ? 'ESP32 CYD' : 'ESP8266 Wemos',
                                                style: TextStyle(
                                                  color: isEsp32 ? AppColors.cyan : AppColors.warning,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.success.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'Auto-OTA Aktywne',
                                                style: TextStyle(
                                                  color: AppColors.success,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (!isActive) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.danger.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'NIEAKTYWNY',
                                                  style: TextStyle(color: AppColors.danger, fontSize: 9, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          hasRoom
                                              ? 'Przypisano: Sala $roomNum (${assignedRoom?.name ?? "..."}) • Stan: ${isAvail ? "WOLNA" : "ZAJĘTA"}'
                                              : 'Brak przypisanej sali (Oczekuje na przypisanie)',
                                          style: TextStyle(
                                            color: hasRoom ? (isAvail ? AppColors.success : AppColors.danger) : Colors.white54,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (lastSeen != null && lastSeen.isNotEmpty)
                                          Text(
                                            'Ostatnia aktywność: ${lastSeen.replaceFirst("T", " ").substring(0, 19)} UTC',
                                            style: const TextStyle(color: Colors.white30, fontSize: 10),
                                          ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                                    color: const Color(0xFF2A2A2A),
                                    onSelected: (val) {
                                      if (val == '__delete__') {
                                        _deleteDevice(devId, devName);
                                      } else {
                                        _assignDevice(devId, val);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        enabled: false,
                                        child: Text('Zmień przypisaną salę:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                      ),
                                      ..._allRooms.map((r) => PopupMenuItem(
                                            value: r.number,
                                            child: Text('Sala ${r.number} (${r.name})', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          )),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: '__delete__',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: AppColors.danger, size: 16),
                                            SizedBox(width: 8),
                                            Text('Usuń kontroler', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 16),

                        // Hardware Guide Card with Tabs (ESP32 CYD & ESP8266)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ChoiceChip(
                                    avatar: const Icon(Icons.smart_display, size: 14, color: AppColors.cyan),
                                    label: const Text('Instrukcja ESP32 CYD', style: TextStyle(fontSize: 11)),
                                    selected: _guideTabIndex == 0,
                                    selectedColor: Colors.cyan.withValues(alpha: 0.25),
                                    onSelected: (s) => setState(() => _guideTabIndex = 0),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    avatar: const Icon(Icons.developer_board, size: 14, color: AppColors.warning),
                                    label: const Text('Instrukcja ESP8266 Wemos', style: TextStyle(fontSize: 11)),
                                    selected: _guideTabIndex == 1,
                                    selectedColor: Colors.orange.withValues(alpha: 0.25),
                                    onSelected: (s) => setState(() => _guideTabIndex = 1),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              if (_guideTabIndex == 0) ...[
                                const Text(
                                  '📱 ESP32 CYD (Cheap Yellow Display 2.8" TFT Touch):',
                                  style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '• Firmware: v1.3.7 z zegarem serwerowym, Auto-OTA i odświeżaniem minutowym (bez migotania ekranu)\n'
                                  '• Wyświetlacz: SPI TFT LCD 320x240 + Dotyk XPT2046 + Dioda RGB (RGB LED)\n'
                                  '• Pamięć: NVS + MicroSD (zapisywane sieci Wi-Fi i konfiguracja sal)\n'
                                  '• Zmiana statusu: 1 dotknięcie dużego przycisku ZAJMIJ / ZWOLNIJ\n'
                                  '• Wybór limitu: dotknięcie kafelka 15m / 30m / 45m / 60m\n'
                                  '• Domyślny token sprzętowy: "dev_token_sala104" (lub wygenerowany powyżej)',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.45),
                                ),
                              ] else ...[
                                const Text(
                                  '🔌 ESP8266 (Wemos D1 mini + Przyciski & Diody):',
                                  style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '• D1 (GPIO 5) -> Dioda LED Zielona (Wolna)\n'
                                  '• D2 (GPIO 4) -> Dioda LED Czerwona (Zajęta)\n'
                                  '• D5 (GPIO 14) -> Przycisk 1 (WOLNA)\n'
                                  '• D6 (GPIO 12) -> Przycisk 2 (ZAJĘTA)\n'
                                  '• Tryb parowania: Przytrzymaj oba przyciski (D5+D6) > 1.5s -> sieć "Wemos-Sala-Setup"',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.45),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
