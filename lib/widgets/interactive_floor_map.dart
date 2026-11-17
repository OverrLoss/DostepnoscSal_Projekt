import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../theme/app_theme.dart';

class InteractiveFloorMap extends StatefulWidget {
  final String floor;
  final List<Room> rooms;
  final Function(Room room) onRoomTap;
  final Function(Room room) onRoomQuickToggle;
  /// Zwraca true, gdy nowe położenie zostało zapisane (inaczej sala wraca na miejsce).
  final Future<bool> Function(Room room, double newX, double newY) onRoomPositionChanged;
  final Function(String floor) onResetPositions;

  /// Zapis rozmiaru (skala, 1.0 = domyślna) i obrotu (stopnie) sali.
  /// Gdy null — pasek zmiany rozmiaru i obrotu się nie pokazuje.
  final Future<bool> Function(Room room, double scale, double angle)? onRoomLayoutChanged;
  final bool? isEditMode;
  final VoidCallback? onToggleEditMode;
  final bool showEditToolbar;
  final bool enableViewer;
  final double controlsBottomOffset;

  const InteractiveFloorMap({
    super.key,
    required this.floor,
    required this.rooms,
    required this.onRoomTap,
    required this.onRoomQuickToggle,
    required this.onRoomPositionChanged,
    required this.onResetPositions,
    this.onRoomLayoutChanged,
    this.isEditMode,
    this.onToggleEditMode,
    this.showEditToolbar = false,
    this.enableViewer = true,
    this.controlsBottomOffset = 12,
  });

  @override
  State<InteractiveFloorMap> createState() => _InteractiveFloorMapState();
}

class _InteractiveFloorMapState extends State<InteractiveFloorMap> {
  bool _internalEditMode = false;
  bool get _isEditMode => widget.isEditMode ?? _internalEditMode;
  // Klucz = numer sali (AULA, HOL i Garaż nie mają liczbowego id)
  final Map<String, Offset> _draggedPositions = {};
  String? _activeDraggingKey;

  String _roomKey(Room room) => room.number.trim().toUpperCase();

  // Zaznaczona sala w trybie edycji + niezapisane jeszcze zmiany rozmiaru/obrotu
  String? _selectedKey;
  final Map<String, double> _scaleOverrides = {};
  final Map<String, double> _angleOverrides = {};
  final Map<String, double> _baseAngleDeg = {};

  static const double _minScale = 0.5;
  static const double _maxScale = 2.5;

  Room? _selectedRoom() {
    final key = _selectedKey;
    if (key == null) return null;
    for (final r in widget.rooms) {
      if (_roomKey(r) == key) return r;
    }
    return null;
  }

  double _currentScale(Room room) =>
      _scaleOverrides[_roomKey(room)] ?? room.layoutScale ?? 1.0;

  double _currentAngleDeg(Room room) {
    final key = _roomKey(room);
    return _angleOverrides[key] ?? room.layoutAngle ?? (_baseAngleDeg[key] ?? 0.0);
  }

  double _normalizeAngle(double a) {
    var v = a % 360.0;
    if (v > 180) v -= 360;
    if (v < -180) v += 360;
    return v;
  }

  Future<void> _applyLayout(Room room, {double? scale, double? angle}) async {
    final save = widget.onRoomLayoutChanged;
    if (save == null) return;
    final key = _roomKey(room);
    final prevScale = _scaleOverrides[key];
    final prevAngle = _angleOverrides[key];
    setState(() {
      if (scale != null) _scaleOverrides[key] = scale.clamp(_minScale, _maxScale);
      if (angle != null) _angleOverrides[key] = _normalizeAngle(angle);
    });
    final saved = await save(room, _currentScale(room), _currentAngleDeg(room));
    if (!saved && mounted) {
      // Nie zapisano — przywróć poprzedni wygląd sali
      setState(() {
        if (prevScale == null) {
          _scaleOverrides.remove(key);
        } else {
          _scaleOverrides[key] = prevScale;
        }
        if (prevAngle == null) {
          _angleOverrides.remove(key);
        } else {
          _angleOverrides[key] = prevAngle;
        }
      });
    }
  }

  Widget _buildLayoutToolbar(Room room) {
    final scale = _currentScale(room);
    final angle = _currentAngleDeg(room);
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon, size: 18, color: onTap == null ? Colors.white24 : Colors.white),
          tooltip: tip,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          onPressed: onTap,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sala ${room.number}',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(
            '${(scale * 100).round()}% · ${angle.round()}°',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 6),
          btn(Icons.rotate_left_rounded, 'Obróć w lewo (15°)', () => _applyLayout(room, angle: angle - 15)),
          btn(Icons.rotate_right_rounded, 'Obróć w prawo (15°)', () => _applyLayout(room, angle: angle + 15)),
          btn(Icons.remove_rounded, 'Mniejsza',
              scale <= _minScale ? null : () => _applyLayout(room, scale: ((scale - 0.1) * 10).round() / 10)),
          btn(Icons.add_rounded, 'Większa',
              scale >= _maxScale ? null : () => _applyLayout(room, scale: ((scale + 0.1) * 10).round() / 10)),
          btn(Icons.restart_alt_rounded, 'Domyślny rozmiar i obrót',
              () => _applyLayout(room, scale: 1.0, angle: _baseAngleDeg[_roomKey(room)] ?? 0.0)),
          btn(Icons.close_rounded, 'Odznacz salę', () => setState(() => _selectedKey = null)),
        ],
      ),
    );
  }
  final TransformationController _transformController = TransformationController();
  double _activeFitScale = 1.0;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final matrix = _transformController.value.clone();
    matrix.scaleByDouble(1.25, 1.25, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformController.value.clone();
    matrix.scaleByDouble(0.8, 0.8, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  // Canvas bounds
  static const double _canvasWidth = 360.0;
  static const double _canvasHeight = 520.0;

  Room? _findRoom(String number) {
    try {
      final target = number.trim().toUpperCase();
      return widget.rooms.firstWhere(
        (r) {
          final rNum = r.number.trim().toUpperCase();
          if (rNum != target) return false;
          if (r.floor == widget.floor) return true;
          // Garage can be displayed on Parter as requested
          if (widget.floor == 'Parter' && (target == 'GARAŻ' || target == 'GARAZ')) return true;
          return false;
        },
      );
    } catch (_) {
      return null;
    }
  }

  List<Room> _getExtraRooms() {
    final knownNumbers = [
      '104', 'AULA', '112', '113', '115', '116', '117', '118', '120', '122',
      '9', '12', '14', 'HOL', 'GARAŻ', 'GARAZ'
    ];
    return widget.rooms.where((r) {
      if (r.floor != widget.floor && !(widget.floor == 'Parter' && (r.floor == 'Garaż podziemny' || r.number.trim().toUpperCase() == 'GARAŻ'))) {
        return false;
      }
      return !knownNumbers.contains(r.number.trim().toUpperCase());
    }).toList();
  }

  Offset _getRoomOffset(Room room, Offset defaultOffset) {
    final key = _roomKey(room);
    if (_draggedPositions.containsKey(key)) {
      return _draggedPositions[key]!;
    }
    if (room.posX != null && room.posY != null) {
      return Offset(room.posX!, room.posY!);
    }
    return defaultOffset;
  }

  void _onPanStart(Room room, Offset currentPos) {
    final key = _roomKey(room);
    setState(() {
      _activeDraggingKey = key;
      _draggedPositions[key] = currentPos;
    });
  }

  void _onPanUpdate(Room room, DragUpdateDetails details, double width, double height) {
    final key = _roomKey(room);
    final current = _draggedPositions[key] ?? Offset(room.posX ?? 0, room.posY ?? 0);
    // Uwzględnij dopasowanie planu do okna ORAZ przybliżenie (zoom),
    // żeby sala szła dokładnie za kursorem / palcem.
    final fit = _activeFitScale <= 0 ? 1.0 : _activeFitScale;
    final zoom = _transformController.value.getMaxScaleOnAxis();
    final adjScale = fit * (zoom <= 0 ? 1.0 : zoom);
    final nextX = (current.dx + details.delta.dx / adjScale).clamp(10.0, _canvasWidth - width - 10.0);
    final nextY = (current.dy + details.delta.dy / adjScale).clamp(35.0, _canvasHeight - height - 10.0);

    setState(() {
      _draggedPositions[key] = Offset(nextX, nextY);
    });
  }

  Future<void> _onPanEnd(Room room, double width, double height) async {
    final key = _roomKey(room);
    final finalPos = _draggedPositions[key];
    setState(() {
      _activeDraggingKey = null;
    });
    if (finalPos == null) return;
    final saved = await widget.onRoomPositionChanged(room, finalPos.dx, finalPos.dy);
    if (!saved && mounted) {
      // Nie zapisano — sala wraca na swoje zapisane miejsce
      setState(() => _draggedPositions.remove(key));
    }
  }

  Future<void> _confirmResetPositions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Przywróć domyślny układ', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz przywrócić pierwotne położenie wszystkich sal na kondygnacji "${widget.floor}"?',
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
            child: const Text('Przywróć', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _draggedPositions.clear();
      });
      widget.onResetPositions(widget.floor);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Przywrócono domyślne położenie sal dla "${widget.floor}"'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extraRooms = _getExtraRooms();

        final hasFiniteW = constraints.maxWidth.isFinite && constraints.maxWidth > 0;
        final hasFiniteH = constraints.maxHeight.isFinite && constraints.maxHeight > 0;

        final availW = hasFiniteW ? constraints.maxWidth : _canvasWidth;
        final availH = hasFiniteH ? constraints.maxHeight : _canvasHeight;

        // Auto-scale calculation so the 360x520 canvas automatically scales to fit viewport
        final paddingH = 16.0;
        final paddingV = _isEditMode ? 48.0 : 16.0;
        final scaleX = (availW - paddingH) / _canvasWidth;
        final scaleY = (availH - paddingV) / _canvasHeight;
        final calculatedScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.25, 1.4);
        _activeFitScale = calculatedScale;

        Widget mapContent = SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Optional standalone toolbar
                  if (widget.showEditToolbar)
                    Container(
                      width: 360,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isEditMode
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isEditMode ? AppColors.primary : Colors.white12,
                          width: _isEditMode ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isEditMode ? Icons.open_with : Icons.edit_location_alt_rounded,
                            color: _isEditMode ? AppColors.primary : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isEditMode ? 'TRYB PRZESTAWIANIA' : 'Układ sal na planie',
                                  style: TextStyle(
                                    color: _isEditMode ? AppColors.primary : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _isEditMode
                                      ? 'Przeciągaj sale palcem/myszką'
                                      : 'Włącz, aby dowolnie przesuwać sale',
                                  style: TextStyle(
                                    color: _isEditMode ? Colors.white70 : Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_isEditMode) ...[
                            IconButton(
                              tooltip: 'Przywróć domyślne pozycje',
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                              onPressed: _confirmResetPositions,
                            ),
                            const SizedBox(width: 4),
                          ],
                          ElevatedButton(
                            onPressed: () {
                              if (widget.onToggleEditMode != null) {
                                widget.onToggleEditMode!();
                              } else {
                                setState(() {
                                  _internalEditMode = !_internalEditMode;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isEditMode ? AppColors.primary : const Color(0xFF2A2A2A),
                              foregroundColor: _isEditMode ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                              elevation: 0,
                            ),
                            child: Text(
                              _isEditMode ? 'Zakończ' : 'Przestaw',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isEditMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_with, color: AppColors.primary, size: 14),
                          SizedBox(width: 8),
                          Text(
                            'Przeciągnij salę, aby ją przesunąć. Zmiany zapisują się od razu.',
                            style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                  // Main Architectural Floor Plan (Auto-scaled to fit screen)
                  SizedBox(
                    width: _canvasWidth * calculatedScale,
                    height: _canvasHeight * calculatedScale,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Container(
                        width: _canvasWidth,
                        height: _canvasHeight,
                        decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isEditMode
                              ? AppColors.primary.withValues(alpha: 0.6)
                              : Colors.white12,
                          width: _isEditMode ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _isEditMode
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : Colors.black38,
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            // Building background path painter
                            CustomPaint(
                              size: const Size(_canvasWidth, _canvasHeight),
                              painter: _BuildingOutlinePainter(floor: widget.floor),
                            ),

                            // Floor Title Watermark
                            Positioned(
                              left: 20,
                              top: 20,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        widget.floor.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isEditMode
                                        ? '✥ Przeciągnij salę, aby zmienić jej położenie'
                                        : 'Dotknij: zmiana stanu • Przytrzymaj: szczegóły',
                                    style: TextStyle(
                                      color: _isEditMode ? AppColors.primary : AppColors.primary.withValues(alpha: 0.8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Rooms positioning based on floor
                            if (widget.floor == 'Piętro') ..._buildPietroRooms(),
                            if (widget.floor == 'Parter') ..._buildParterRooms(),
                            if (widget.floor == 'Garaż podziemny') ..._buildGarazRooms(),

                            // Extra custom user rooms placed on the floor plan
                            ..._buildExtraRoomsOnMap(extraRooms),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Extra custom user rooms chips list (quick overview)
                if (extraRooms.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: 360,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.meeting_room_outlined, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'DODATKOWE SALE (${widget.floor})'.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: extraRooms.map((r) {
                            return _buildExtraRoomChip(r);
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

      if (!widget.enableViewer) {
        return mapContent;
      }

      return Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.25,
            maxScale: 3.5,
            panEnabled: !_isEditMode,
            scaleEnabled: !_isEditMode,
            boundaryMargin: const EdgeInsets.all(50),
            child: mapContent,
          ),
          // Pasek obrotu i rozmiaru zaznaczonej sali (tryb edycji)
          if (_isEditMode && widget.onRoomLayoutChanged != null && _selectedRoom() != null)
            Positioned(
              left: 12,
              bottom: widget.controlsBottomOffset,
              child: _buildLayoutToolbar(_selectedRoom()!),
            )
          else if (_isEditMode && widget.onRoomLayoutChanged != null)
            Positioned(
              left: 12,
              bottom: widget.controlsBottomOffset,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF000000).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Kliknij salę, aby ją obrócić lub zmienić rozmiar',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          // Floating Zoom & Fit Controls
          Positioned(
            right: 12,
            bottom: widget.controlsBottomOffset,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF000000).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24, width: 0.8),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18, color: Colors.white70),
                    tooltip: 'Oddal widok',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _zoomOut,
                  ),
                  IconButton(
                    icon: const Icon(Icons.fit_screen_rounded, size: 18, color: AppColors.cyan),
                    tooltip: 'Dopasuj do ekranu',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _resetZoom,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18, color: Colors.white70),
                    tooltip: 'Przybliż widok',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: _zoomIn,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      },
    );
  }

  List<Widget> _buildPietroRooms() {
    return [
      // 104 on Left Wing
      _buildPositionedRoomBlock(
        number: '104',
        defaultLeft: 45,
        defaultTop: 200,
        width: 80,
        height: 48,
        titleOverride: '104',
        defaultAngle: -0.72,
      ),

      // Central Junction: AULA
      _buildPositionedRoomBlock(
        number: 'AULA',
        defaultLeft: 125,
        defaultTop: 430,
        width: 95,
        height: 55,
        titleOverride: 'AULA',
        isBig: true,
      ),

      // Vertical Wing Rooms
      _buildPositionedRoomBlock(number: '112', defaultLeft: 195, defaultTop: 388, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '113', defaultLeft: 195, defaultTop: 350, width: 75, height: 32),

      // WC Indicator
      Positioned(
        left: 160,
        top: 318,
        child: Container(
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: const Text('WC', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ),

      _buildPositionedRoomBlock(number: '115', defaultLeft: 195, defaultTop: 280, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '116', defaultLeft: 195, defaultTop: 242, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '117', defaultLeft: 195, defaultTop: 204, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '118', defaultLeft: 195, defaultTop: 166, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '120', defaultLeft: 195, defaultTop: 128, width: 75, height: 32),
      _buildPositionedRoomBlock(number: '122', defaultLeft: 195, defaultTop: 88, width: 75, height: 34),
    ];
  }

  List<Widget> _buildParterRooms() {
    return [
      // Wejście along left wing
      Positioned(
        left: 55,
        top: 260,
        child: Transform.rotate(
          angle: -0.72,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('WEJŚCIE', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 14),
              ],
            ),
          ),
        ),
      ),

      // Central Junction: HOL
      _buildPositionedRoomBlock(
        number: 'HOL',
        defaultLeft: 125,
        defaultTop: 430,
        width: 95,
        height: 55,
        titleOverride: 'HOL',
        isBig: true,
      ),

      // Vertical Wing Entrance
      Positioned(
        left: 280,
        top: 360,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back_rounded, color: AppColors.primary, size: 12),
              SizedBox(width: 4),
              Text('wejście', style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),

      // Vertical Wing Rooms
      _buildPositionedRoomBlock(number: '9', defaultLeft: 195, defaultTop: 355, width: 75, height: 38),

      // WC Indicator
      Positioned(
        left: 160,
        top: 310,
        child: Container(
          width: 32,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          alignment: Alignment.center,
          child: const Text('WC', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ),

      _buildPositionedRoomBlock(number: '12', defaultLeft: 195, defaultTop: 250, width: 75, height: 38),
      _buildPositionedRoomBlock(number: '14', defaultLeft: 195, defaultTop: 195, width: 75, height: 42),

      // Garaż (Pojazdy zabytkowe) placed in the central area of Parter
      _buildPositionedRoomBlock(
        number: 'Garaż',
        defaultLeft: 65,
        defaultTop: 325,
        width: 90,
        height: 60,
        titleOverride: 'GARAŻ\n(Pojazdy)',
        isBig: true,
      ),
    ];
  }

  List<Widget> _buildGarazRooms() {
    final garazRoom = _findRoom('Garaż') ?? _findRoom('GARAŻ');
    if (garazRoom == null) return [];

    // Karta garażu zawsze na środku obrysu garażu. Zapisana pozycja tej sali
    // dotyczy kafelka na planie parteru, więc tu jej nie używamy (wcześniej karta
    // wychodziła poza obrys i ucinała napisy).
    const offset = Offset(50, 140);
    const isDragging = false;

    return [
      Positioned(
        left: offset.dx,
        top: offset.dy,
        child: GestureDetector(
          onPanStart: null,
          onPanUpdate: null,
          onPanEnd: null,
          child: InkWell(
            onTap: () {
              if (!_isEditMode) widget.onRoomQuickToggle(garazRoom);
            },
            onLongPress: () {
              if (!_isEditMode) widget.onRoomTap(garazRoom);
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 260,
              height: 240,
              decoration: BoxDecoration(
                color: (garazRoom.isAvailable)
                    ? AppColors.success.withValues(alpha: 0.12)
                    : AppColors.danger.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDragging
                      ? AppColors.primary
                      : ((garazRoom.isAvailable) ? AppColors.success : AppColors.danger),
                  width: isDragging ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isEditMode) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_with, color: Colors.black, size: 14),
                          SizedBox(width: 4),
                          Text('Przeciągnij', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Icon(
                    Icons.directions_car_rounded,
                    size: 44,
                    color: (garazRoom.isAvailable) ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Garaż podziemny',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    garazRoom.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: ((garazRoom.isAvailable)
                              ? AppColors.success
                              : (garazRoom.isAlertDue ? AppColors.warning : AppColors.danger))
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (garazRoom.isAvailable)
                              ? Icons.check_circle
                              : (garazRoom.isAlertDue ? Icons.warning_amber_rounded : Icons.cancel),
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          (garazRoom.isAvailable)
                              ? 'Wolny'
                              : (garazRoom.isAlertDue
                                  ? 'Przekroczono czas (${garazRoom.durationFormatted})'
                                  : 'Zajęty (${garazRoom.durationFormatted})'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!garazRoom.isAvailable && garazRoom.occupantName != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded, size: 14, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          garazRoom.occupantName!,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _isEditMode ? 'Przeciągaj, aby zmienić pozycję' : 'Dotknij, aby zmienić dostępność',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildExtraRoomsOnMap(List<Room> extraRooms) {
    final widgets = <Widget>[];
    for (int i = 0; i < extraRooms.length; i++) {
      final room = extraRooms[i];
      // Default starting spot for custom extra rooms
      final defaultLeft = 35.0 + (i % 2) * 85.0;
      final defaultTop = 75.0 + (i ~/ 2) * 50.0;
      widgets.add(
        _buildPositionedRoomBlock(
          number: room.number,
          defaultLeft: defaultLeft,
          defaultTop: defaultTop,
          width: 80,
          height: 38,
          roomOverride: room,
        ),
      );
    }
    return widgets;
  }

  Widget _buildPositionedRoomBlock({
    required String number,
    required double defaultLeft,
    required double defaultTop,
    required double width,
    required double height,
    String? titleOverride,
    bool isBig = false,
    double? defaultAngle,
    Room? roomOverride,
  }) {
    final room = roomOverride ?? _findRoom(number);
    if (room == null) return const SizedBox.shrink();

    final defaultPos = Offset(defaultLeft, defaultTop);
    final pos = _getRoomOffset(room, defaultPos);
    final isCustomPosition = (room.posX != null && room.posY != null) ||
        _draggedPositions.containsKey(_roomKey(room));
    final key = _roomKey(room);
    final isDragging = _activeDraggingKey == key;
    final isSelected = _isEditMode && _selectedKey == key;

    // Domyślny kąt z projektu planu (tylko dla sal w domyślnym miejscu)
    final baseAngleDeg = (isCustomPosition || defaultAngle == null) ? 0.0 : defaultAngle * 180 / math.pi;
    _baseAngleDeg[key] = baseAngleDeg;

    // Rozmiar i obrót: zmiana w trakcie edycji > zapis z serwera > domyślne
    final scale = _currentScale(room);
    final angleDeg = _angleOverrides[key] ?? room.layoutAngle ?? baseAngleDeg;
    final angle = angleDeg == 0 ? null : angleDeg * math.pi / 180;
    final w = width * scale;
    final h = height * scale;

    Widget roomWidget = _buildRoomContent(
      room: room,
      width: w,
      height: h,
      label: titleOverride ?? number,
      isBig: isBig,
      isDragging: isDragging || isSelected,
    );

    if (angle != null) {
      roomWidget = Transform.rotate(
        angle: angle,
        child: roomWidget,
      );
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanStart: _isEditMode
            ? (_) {
                setState(() => _selectedKey = key);
                _onPanStart(room, pos);
              }
            : null,
        onPanUpdate: _isEditMode ? (details) => _onPanUpdate(room, details, w, h) : null,
        onPanEnd: _isEditMode ? (_) => _onPanEnd(room, w, h) : null,
        child: InkWell(
          onTap: () {
            if (_isEditMode) {
              // W trybie edycji kliknięcie zaznacza salę (pasek obrotu i rozmiaru)
              setState(() => _selectedKey = key);
            } else {
              widget.onRoomQuickToggle(room);
            }
          },
          onLongPress: () {
            if (!_isEditMode) widget.onRoomTap(room);
          },
          borderRadius: BorderRadius.circular(isBig ? 4 : 3),
          child: roomWidget,
        ),
      ),
    );
  }

  Widget _buildRoomContent({
    required Room room,
    required double width,
    required double height,
    required String label,
    required bool isBig,
    required bool isDragging,
  }) {
    final isAvailable = room.isAvailable;
    final isAlert = room.isAlertDue;
    final color = isDragging
        ? AppColors.primary
        : (isAlert
            ? AppColors.warning
            : (isAvailable ? AppColors.success : AppColors.danger));
    final bgColor = isDragging
        ? AppColors.primary.withValues(alpha: 0.2)
        : (isAlert
            ? AppColors.danger.withValues(alpha: 0.3)
            : (isAvailable
                ? AppColors.success.withValues(alpha: 0.14)
                : AppColors.danger.withValues(alpha: 0.16)));

    final duration = room.durationFormatted;

    return AnimatedContainer(
      duration: isDragging ? Duration.zero : const Duration(milliseconds: 200),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(isBig ? 4 : 3),
        border: Border.all(
          color: color,
          width: isDragging ? 2.0 : (isAlert ? 1.6 : 1.0),
        ),
        boxShadow: isDragging
            ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10)]
            : null,
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isEditMode) ...[
                    Icon(
                      Icons.open_with,
                      size: isBig ? 14 : 11,
                      color: isDragging ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isBig ? 13 : 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isAvailable && (duration.isNotEmpty || room.occupantName != null)) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isAlert) ...[
                      const Icon(Icons.warning_amber_rounded, size: 10, color: AppColors.warning),
                      const SizedBox(width: 2),
                    ],
                    if (room.occupantName != null) ...[
                      Flexible(
                        child: Text(
                          room.occupantName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (duration.isNotEmpty)
                    Text(
                      duration,
                      style: TextStyle(
                        color: isAlert ? AppColors.warning : Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (isAlert)
            Positioned(
              top: 2,
              right: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger,
                ),
                child: const Icon(Icons.priority_high, size: 8, color: Colors.white),
              ),
            )
          else if (isDragging)
            Positioned(
              top: 2,
              right: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExtraRoomChip(Room room) {
    final isAvailable = room.isAvailable;
    final color = isAvailable ? AppColors.success : AppColors.danger;

    return InkWell(
      onTap: () {
        if (!_isEditMode) widget.onRoomQuickToggle(room);
      },
      onLongPress: () {
        if (!_isEditMode) widget.onRoomTap(room);
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              room.number,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(width: 6),
            Text(
              room.name,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            if (room.occupantName != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.person_rounded, size: 12, color: Colors.white70),
              const SizedBox(width: 2),
              Text(
                room.occupantName!,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BuildingOutlinePainter extends CustomPainter {
  final String floor;

  _BuildingOutlinePainter({required this.floor});

  @override
  void paint(Canvas canvas, Size size) {
    // Siatka punktów jak na rysunku technicznym
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.06);
    for (double x = 10; x < size.width; x += 20) {
      for (double y = 10; y < size.height; y += 20) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), dotPaint);
      }
    }

    final corridorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 36
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter;

    final wallPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.miter;

    if (floor == 'Piętro' || floor == 'Parter') {
      final corridorPath = Path();
      // Start of left diagonal wing
      corridorPath.moveTo(40, 160);
      // Down to central junction
      corridorPath.lineTo(172, 455);
      // Up through vertical wing
      corridorPath.lineTo(172, 70);

      canvas.drawPath(corridorPath, corridorPaint);

      // Outer building walls
      final outerWall = Path();
      // Top of diagonal wing
      outerWall.moveTo(25, 145);
      outerWall.lineTo(55, 120);
      outerWall.lineTo(195, 415);
      outerWall.lineTo(195, 60);
      outerWall.lineTo(275, 60);
      outerWall.lineTo(275, 480);
      outerWall.lineTo(170, 500);
      outerWall.lineTo(110, 480);
      outerWall.lineTo(15, 180);
      outerWall.close();

      canvas.drawPath(outerWall, wallPaint);
    } else {
      // Underground garage grid outline
      canvas.drawRect(Rect.fromLTWH(30, 110, 300, 300), wallPaint);

      final gridPaint = Paint()
        ..color = Colors.white10
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (double y = 140; y < 400; y += 40) {
        canvas.drawLine(Offset(30, y), Offset(330, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BuildingOutlinePainter oldDelegate) {
    return oldDelegate.floor != floor;
  }
}
