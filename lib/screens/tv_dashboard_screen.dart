import 'dart:async';
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../widgets/interactive_floor_map.dart';
import '../theme/app_theme.dart';
import '../services/room_sync_service.dart';
import '../services/occupant_nick.dart';

class TvDashboardScreen extends StatefulWidget {
  const TvDashboardScreen({super.key});

  @override
  State<TvDashboardScreen> createState() => _TvDashboardScreenState();
}

class _TvDashboardScreenState extends State<TvDashboardScreen> {
  List<Room> _rooms = [];
  bool _isLoading = true;
  Timer? _clockTimer;
  Timer? _refreshTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadRooms();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
    // Auto-refresh rooms every 3 seconds for live TV display
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadRooms(silent: true);
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRooms({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final rooms = await RoomDatabaseHelper.instance.getRooms();
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleAvailability(Room room) async {
    if (room.id == null) return;
    final sync = RoomSyncService.instance;
    String? occupantName;
    if (room.isAvailable) {
      final nick = await OccupantNick.load();
      occupantName = nick.isNotEmpty ? nick : (sync.isLoggedIn ? sync.userDisplayName : null);
    }
    await RoomDatabaseHelper.instance.toggleAvailability(
      room.id!,
      room.isAvailable,
      roomNumber: room.number,
      occupantName: occupantName,
    );
    await _loadRooms(silent: true);
  }

  int get _freeCount => _rooms.where((r) => r.isAvailable).length;
  int get _occupiedCount => _rooms.where((r) => !r.isAvailable).length;

  String _formatTwoDigits(int n) => n.toString().padLeft(2, '0');

  String _formattedTime() {
    return '${_formatTwoDigits(_now.hour)}:${_formatTwoDigits(_now.minute)}:${_formatTwoDigits(_now.second)}';
  }

  String _formattedDate() {
    const days = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela'];
    const months = [
      'stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca',
      'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'
    ];
    final dayName = days[_now.weekday - 1];
    final monthName = months[_now.month - 1];
    return '$dayName, ${_now.day} $monthName ${_now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: SafeArea(
        child: Column(
          children: [
            _buildTvHeader(),
            Expanded(
              child: _isLoading && _rooms.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _buildMainContent(),
            ),
            _buildBottomRoomTicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildTvHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          // Left: University Logo & Title (skraca się, gdy brakuje miejsca)
          Expanded(
            child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.school, color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              const Flexible(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'POLITECHNIKA RZESZOWSKA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'Tablica informacyjna, dostępność sal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              ),
            ],
          ),
          ),

          const SizedBox(width: 16),

          // Center: Live Availability Counter (zmniejsza się zamiast wychodzić poza ekran)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.success),
                ),
                const SizedBox(width: 8),
                Text(
                  'WOLNE: $_freeCount',
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.danger),
                ),
                const SizedBox(width: 8),
                Text(
                  'ZAJĘTE: $_occupiedCount',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi, color: AppColors.cyan, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
            ),
          ),

          const SizedBox(width: 16),

          // Right: Real-time Clock & Controls
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formattedTime(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    _formattedDate(),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              IconButton(
                tooltip: 'Zamknij widok TV',
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 850;

        if (isWide) {
          // Side-by-side layout for TV / Wide monitors
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ground Floor (Parter)
                Expanded(
                  child: _buildFloorPanel(
                    floorName: 'Parter',
                    floorTitle: 'PARTER (POZIOM 0)',
                    accentColor: AppColors.cyan,
                  ),
                ),
                const SizedBox(width: 16),
                // First Floor (Piętro)
                Expanded(
                  child: _buildFloorPanel(
                    floorName: 'Piętro',
                    floorTitle: 'I PIĘTRO (POZIOM +1)',
                    accentColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          );
        } else {
          // Stacked scrollable layout for smaller screens
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildFloorPanel(
                  floorName: 'Parter',
                  floorTitle: 'PARTER (POZIOM 0)',
                  accentColor: AppColors.cyan,
                ),
                const SizedBox(height: 16),
                _buildFloorPanel(
                  floorName: 'Piętro',
                  floorTitle: 'I PIĘTRO (POZIOM +1)',
                  accentColor: AppColors.primary,
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildFloorPanel({
    required String floorName,
    required String floorTitle,
    required Color accentColor,
  }) {
    final floorRooms = _rooms.where((r) => r.floor == floorName || (floorName == 'Parter' && r.floor == 'Garaż podziemny')).toList();
    final free = floorRooms.where((r) => r.isAvailable).length;
    final total = floorRooms.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Floor Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: accentColor.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
                ),
                const SizedBox(width: 8),
                Text(
                  floorTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Wolne: $free / $total',
                    style: TextStyle(
                      color: free > 0 ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Map Display
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: InteractiveFloorMap(
                floor: floorName,
                rooms: _rooms,
                isEditMode: false,
                showEditToolbar: false,
                enableViewer: true,
                onRoomTap: (room) => _toggleAvailability(room),
                onRoomQuickToggle: (room) => _toggleAvailability(room),
                onRoomPositionChanged: (room, newX, newY) =>
                    RoomDatabaseHelper.instance.updateRoomPosition(room, newX, newY),
                onResetPositions: (floor) async {
                  await RoomDatabaseHelper.instance.resetRoomPositions(floor: floor);
                  await _loadRooms(silent: true);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRoomTicker() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF000000),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _rooms.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final r = _rooms[idx];
          final isAvail = r.isAvailable;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _toggleAvailability(r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isAvail
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isAvail
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isAvail ? AppColors.success : AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      r.number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      r.name,
                      style: TextStyle(
                        color: isAvail ? AppColors.success : (r.isAlertDue ? AppColors.warning : AppColors.danger),
                        fontSize: 11,
                      ),
                    ),
                    if (r.occupantName != null) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.person_rounded, size: 12, color: Colors.white70),
                      const SizedBox(width: 2),
                      Text(
                        r.occupantName!,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                    if (!isAvail && r.durationFormatted.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: r.isAlertDue ? AppColors.warning : Colors.white12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r.durationFormatted,
                          style: TextStyle(
                            color: r.isAlertDue ? Colors.black : Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
