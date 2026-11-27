import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../services/room_sync_service.dart';
import '../theme/app_theme.dart';

/// Panel administratora urządzenia zidentyfikowanego krótkim kodem.
/// Nie wymaga kamery ani nowych zależności — kod można wpisać lub wkleić.
class AdminDeviceDashboardScreen extends StatefulWidget {
  final String? initialCode;

  const AdminDeviceDashboardScreen({super.key, this.initialCode});

  @override
  State<AdminDeviceDashboardScreen> createState() => _AdminDeviceDashboardScreenState();
}

class _AdminDeviceDashboardScreenState extends State<AdminDeviceDashboardScreen> {
  final RoomSyncService _sync = RoomSyncService.instance;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _limitController = TextEditingController(text: '900');

  Map<String, dynamic>? _device;
  List<Map<String, dynamic>> _audit = [];
  List<Room> _rooms = [];
  bool _busy = false;
  String? _message;
  String? _newToken;
  String? _newPairCode;
  bool _lockStatus = false;
  bool _lockInfo = false;
  bool _lockLayout = false;
  String? _selectedRoomId;
  String? _selectedDeviceType;

  @override
  void initState() {
    super.initState();
    _codeController.text = widget.initialCode ?? '';
    _loadRooms();
    if ((widget.initialCode ?? '').isNotEmpty) {
      Future.microtask(() => _resolve());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await RoomDatabaseHelper.instance.getRooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {}
  }

  Future<void> _resolve() async {
    if (!_sync.isAdmin) {
      _show('Tylko administrator może zarządzać urządzeniami.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _newToken = null;
      _newPairCode = null;
    });
    final device = await _sync.resolveDevice(_codeController.text);
    if (!mounted) return;
    if (device == null) {
      setState(() {
        _busy = false;
        _device = null;
        _message = _sync.lastErrorMessage.isNotEmpty
            ? _sync.lastErrorMessage
            : 'Nie znaleziono urządzenia.';
      });
      return;
    }
    setState(() {
      _device = device;
      _selectedRoomId = device['room_id']?.toString();
      _selectedDeviceType = device['device_type']?.toString() ?? 'controller';
      _lockStatus = false;
      _lockInfo = false;
      _lockLayout = false;
      _busy = false;
    });
    await _refreshAudit();
    final roomId = device['room_id']?.toString();
    if (roomId != null && roomId.isNotEmpty) {
      final room = await _sync.fetchRemoteRoom(roomId);
      if (!mounted || room == null) return;
      setState(() {
        _lockStatus = room.lockStatus;
        _lockInfo = room.lockInfo;
        _lockLayout = room.lockLayout;
      });
    }
  }

  Future<void> _refreshAudit() async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final rows = await _sync.getDeviceAudit(id);
    if (mounted) setState(() => _audit = rows);
  }

  Future<void> _reloadDevice() async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final fresh = await _sync.getDevice(id);
    if (mounted && fresh != null) setState(() => _device = fresh);
  }

  void _show(String message) {
    if (!mounted) return;
    setState(() => _message = message);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeStatus(String status, {bool isBreak = false}) async {
    final roomId = _device?['room_id']?.toString();
    if (roomId == null || roomId.isEmpty) {
      _show('Urządzenie nie ma przypisanej sali.');
      return;
    }
    final ok = await _sync.changeRoomStatus(roomId, status, isBreak: isBreak);
    _show(ok ? 'Status sali zaktualizowany.' : (_sync.lastErrorMessage.isNotEmpty ? _sync.lastErrorMessage : 'Nie udało się zmienić statusu.'));
    if (ok) await _refreshAudit();
  }

  Future<void> _saveLimit() async {
    final roomId = _device?['room_id']?.toString();
    if (roomId == null || roomId.isEmpty) {
      _show('Urządzenie nie ma przypisanej sali.');
      return;
    }
    final seconds = int.tryParse(_limitController.text.trim());
    if (seconds == null || seconds < 60) {
      _show('Podaj limit w sekundach (min. 60).');
      return;
    }
    final ok = await _sync.setRoomAlertLimit(roomId, seconds);
    _show(ok ? 'Limit alertu zapisany.' : 'Nie udało się zapisać limitu.');
    if (ok) await _refreshAudit();
  }

  Future<void> _saveLocks() async {
    final roomId = _device?['room_id']?.toString();
    if (roomId == null || roomId.isEmpty) {
      _show('Urządzenie nie ma przypisanej sali.');
      return;
    }
    final room = await _sync.setRoomLocks(
      roomId,
      lockStatus: _lockStatus,
      lockInfo: _lockInfo,
      lockLayout: _lockLayout,
    );
    _show(room != null ? 'Blokady zapisane.' : 'Nie udało się zapisać blokad.');
    if (room != null) await _refreshAudit();
  }

  Future<void> _saveAssignment() async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final updated = await _sync.updateDevice(id, roomId: _selectedRoomId ?? '');
    if (updated != null) {
      _show('Przypisanie sali zapisane.');
      await _reloadDevice();
      await _refreshAudit();
    } else {
      _show('Nie udało się zapisać przypisania.');
    }
  }

  Future<void> _setActive(bool active) async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final updated = await _sync.updateDevice(id, isActive: active);
    if (updated != null) {
      _show(active ? 'Urządzenie aktywne.' : 'Urządzenie dezaktywowane.');
      await _reloadDevice();
      await _refreshAudit();
    } else {
      _show('Nie udało się zmienić stanu urządzenia.');
    }
  }

  Future<void> _setDeviceType(String? type) async {
    final id = _device?['id']?.toString();
    if (id == null || type == null) return;
    final updated = await _sync.updateDevice(id, deviceType: type);
    if (updated != null) {
      setState(() => _selectedDeviceType = type);
      _show('Typ urządzenia zapisany.');
      await _reloadDevice();
      await _refreshAudit();
    } else {
      _show('Nie udało się zapisać typu urządzenia.');
    }
  }

  Future<void> _rotateToken() async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final token = await _sync.rotateDeviceToken(id);
    if (token != null) {
      setState(() => _newToken = token);
      _show('Nowy token wygenerowany — zapisz go teraz, nie da się go odczytać ponownie.');
      await _refreshAudit();
    } else {
      _show('Nie udało się wygenerować tokenu.');
    }
  }

  Future<void> _rotatePairCode() async {
    final id = _device?['id']?.toString();
    if (id == null) return;
    final code = await _sync.rotateDevicePairCode(id);
    if (code != null) {
      setState(() {
        _newPairCode = code;
        _codeController.text = code;
      });
      _show('Nowy kod wygenerowany — zapisz go na wyświetlaczu.');
      await _reloadDevice();
      await _refreshAudit();
    } else {
      _show('Nie udało się wygenerować nowego kodu.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_sync.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Zarządzanie urządzeniem')),
        body: const Center(child: Text('Wymagane uprawnienia administratora.')),
      );
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Zarządzanie urządzeniem'),
        bottom: _device == null
            ? null
            : const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Status'),
                  Tab(text: 'Limity'),
                  Tab(text: 'Blokady'),
                  Tab(text: 'Przypisanie'),
                  Tab(text: 'Token i operator'),
                  Tab(text: 'Audyt'),
                ],
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCodeField(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_message!, style: const TextStyle(color: AppColors.warning)),
              ),
            Expanded(
              child: _device == null ? _buildIntro() : _buildTabs(),
            ),
          ],
        ),
      ),
    );
    return DefaultTabController(length: 6, child: scaffold);
  }

  Widget _buildCodeField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Kod urządzenia (6 znaków)',
                hintText: 'NP. K7M3Q2',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onSubmitted: (_) => _resolve(),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _resolve,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: const Text('Znajdź'),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 64, color: AppColors.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            const Text(
              'Wpisz 6-znakowy kod widoczny na wyświetlaczu lub w panelu sterownika.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kod identyfikuje urządzenie — zarządzanie nadal wymaga konta administratora.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final device = _device!;
    final room = device['room'] as Map<String, dynamic>?;
    return Column(
      children: [
        Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Icon(_iconForType(device['device_type']?.toString()), color: AppColors.cyan),
              title: Text(device['name']?.toString() ?? 'Urządzenie'),
              subtitle: Text(
                '${device['device_type'] ?? 'controller'} · ${room?['name'] ?? 'brak sali'} · kod ${device['pair_code_hint'] ?? '—'}'
                '${device['is_active'] == true ? '' : ' · NIEAKTYWNE'}',
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildStatusTab(room),
                _buildLimitsTab(),
                _buildLocksTab(),
                _buildAssignmentTab(device),
                _buildTokenTab(device),
                _buildAuditTab(),
              ],
            ),
          ),
      ],
    );
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'kiosk':
        return Icons.tv;
      case 'display':
        return Icons.display_settings;
      default:
        return Icons.memory;
    }
  }

  Widget _buildStatusTab(Map<String, dynamic>? room) {
    if (room == null) {
      return const Center(child: Text('Urządzenie nie ma przypisanej sali.'));
    }
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Status sali: ${room['name'] ?? room['id']}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _changeStatus('free'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Wolna'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => _changeStatus('occupied'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Zajęta'),
              ),
              OutlinedButton.icon(
                onPressed: () => _changeStatus('occupied', isBreak: true),
                icon: const Icon(Icons.free_breakfast),
                label: const Text('Przerwa'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('Aktywność urządzenia'),
          SwitchListTile(
            title: const Text('Urządzenie aktywne'),
            value: _device?['is_active'] == true,
            onChanged: _setActive,
          ),
        ],
      ),
    );
  }

  Widget _buildLimitsTab() {
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Limit czasu i alertu (sekundy)'),
          const SizedBox(height: 12),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _limitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limit (min. 60 s)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saveLimit,
            icon: const Icon(Icons.save),
            label: const Text('Zapisz limit'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocksTab() {
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Blokady sali'),
          SwitchListTile(
            title: const Text('Blokada zmiany statusu'),
            value: _lockStatus,
            onChanged: (v) => setState(() => _lockStatus = v),
          ),
          SwitchListTile(
            title: const Text('Blokada danych sali'),
            value: _lockInfo,
            onChanged: (v) => setState(() => _lockInfo = v),
          ),
          SwitchListTile(
            title: const Text('Blokada układu planu'),
            value: _lockLayout,
            onChanged: (v) => setState(() => _lockLayout = v),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saveLocks,
            icon: const Icon(Icons.save),
            label: const Text('Zapisz blokady'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentTab(Map<String, dynamic> device) {
    final roomIds = _rooms.map((r) => r.number).where((n) => n.isNotEmpty).toList();
    if (_selectedRoomId != null && !roomIds.contains(_selectedRoomId)) {
      roomIds.insert(0, _selectedRoomId!);
    }
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Przypisanie sali'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedRoomId,
            decoration: const InputDecoration(labelText: 'Sala', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('Brak sali')),
              ...roomIds.map((number) => DropdownMenuItem(value: number, child: Text(number))),
            ],
            onChanged: (value) => setState(() => _selectedRoomId = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saveAssignment,
            icon: const Icon(Icons.save),
            label: const Text('Zapisz przypisanie'),
          ),
          const SizedBox(height: 28),
          _sectionTitle('Typ urządzenia'),
          DropdownButtonFormField<String>(
            initialValue: _selectedDeviceType,
            decoration: const InputDecoration(labelText: 'Typ', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'controller', child: Text('Sterownik w sali')),
              DropdownMenuItem(value: 'kiosk', child: Text('TV / kiosk')),
              DropdownMenuItem(value: 'display', child: Text('Wyświetlacz')),
            ],
            onChanged: _setDeviceType,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenTab(Map<String, dynamic> device) {
    final operator = device['operator'] as Map<String, dynamic>?;
    return _scroll(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Dane operatora sali'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(operator?['display_name']?.toString() ?? operator?['username']?.toString() ?? 'Brak operatora'),
            subtitle: operator == null ? const Text('Ta sala nie ma przypisanego operatora.') : null,
          ),
          const Divider(height: 32),
          _sectionTitle('Kod identyfikacyjny'),
          SelectableText('Kod: ${device['pair_code_hint'] ?? '—'}', style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _rotatePairCode,
            icon: const Icon(Icons.refresh),
            label: const Text('Wygeneruj nowy kod'),
          ),
          if (_newPairCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText('Nowy kod: $_newPairCode', style: const TextStyle(color: AppColors.success, fontSize: 18)),
            ),
          const Divider(height: 32),
          _sectionTitle('Token API urządzenia'),
          const Text(
            'Token jest potrzebny ESP8266/ESP32 do komunikacji z serwerem.'
            ' Po wygenerowaniu zostaje wyświetlony tylko raz.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _rotateToken,
            icon: const Icon(Icons.key),
            label: const Text('Wygeneruj nowy token'),
          ),
          if (_newToken != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText('Token: $_newToken', style: const TextStyle(color: AppColors.warning, fontFamily: 'monospace')),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditTab() {
    if (_audit.isEmpty) {
      return const Center(child: Text('Brak zapisanych operacji dla tego urządzenia.'));
    }
    return ListView.builder(
      itemCount: _audit.length,
      itemBuilder: (context, index) {
        final entry = _audit[index];
        final details = entry['details'];
        return ListTile(
          leading: const Icon(Icons.history, size: 18),
          title: Text(entry['action']?.toString() ?? 'operacja'),
          subtitle: Text('${entry['created_at'] ?? ''} · ${entry['actor_type'] ?? ''} ${entry['actor_id'] ?? ''}'),
          trailing: details is Map && details.isNotEmpty
              ? Tooltip(message: details.toString(), child: const Icon(Icons.info_outline, size: 16))
              : null,
        );
      },
    );
  }

  Widget _scroll(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary));
  }
}
