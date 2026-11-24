import 'package:flutter/material.dart';

import 'floor0_plan.dart';
import 'floor1_plan.dart';
import 'interactive_floor_map.dart' show svgPolygonsFor;

/// Mini-plan do narysowania własnego kształtu sali przez klikanie w wierzchołki.
/// Kliknięcie przyciąga się do najbliższego węzła rzutu (krawędzi),
/// kliknięcie w pierwszy punkt zamyka kształt.
class RoomShapePicker extends StatefulWidget {
  final String floor;
  final String? initialPath;
  final ValueChanged<String> onChanged;

  const RoomShapePicker({
    super.key,
    required this.floor,
    required this.onChanged,
    this.initialPath,
  });

  @override
  State<RoomShapePicker> createState() => _RoomShapePickerState();
}

class _RoomShapePickerState extends State<RoomShapePicker> {
  static final RegExp _numRe = RegExp(r'-?\d+(?:\.\d+)?');
  static const double _snapRadius = 12.0;

  List<Offset> _points = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null && widget.initialPath!.isNotEmpty) {
      _points = _parse(widget.initialPath!);
    }
  }

  static List<Offset> _parse(String d) {
    final nums = _numRe.allMatches(d).map((m) => double.parse(m.group(0)!)).toList();
    final pts = <Offset>[];
    for (var i = 0; i + 1 < nums.length; i += 2) {
      pts.add(Offset(nums[i], nums[i + 1]));
    }
    return pts;
  }

  static String _format(List<Offset> pts) {
    if (pts.isEmpty) return '';
    final b = StringBuffer('M');
    for (final p in pts) {
      b.write('${p.dx.toStringAsFixed(1)} ${p.dy.toStringAsFixed(1)}L');
    }
    return '${b.toString().substring(0, b.length - 1)}Z';
  }

  Offset _toSvg(Offset canvas) => Offset(
        canvas.dx / floor1Scale + floor1ViewX,
        (canvas.dy - floor1OffsetY) / floor1Scale + floor1ViewY,
      );

  List<Offset> _nodes() {
    final pts = <Offset>[];
    for (final d in svgPolygonsFor(widget.floor).values) {
      pts.addAll(_parse(d));
    }
    pts.addAll(_parse(widget.floor == 'Piętro' ? floor1Outline : floor0Outline));
    return pts;
  }

  void _onTap(Offset local) {
    var p = _toSvg(local);
    var best = _snapRadius;
    for (final n in _nodes()) {
      final d = (n - p).distance;
      if (d < best) {
        best = d;
        p = n;
      }
    }
    setState(() {
      if (_points.length >= 3 && (p - _points.first).distance < _snapRadius) {
        return; // kliknięcie w pierwszy punkt domyka kształt
      }
      if (_points.isEmpty || (p - _points.last).distance > 2) {
        _points.add(p);
        widget.onChanged(_format(_points));
      }
    });
  }

  void _closeShape() {
    if (_points.length < 3) return;
    setState(() => widget.onChanged(_format(_points)));
  }

  void _undo() {
    setState(() {
      if (_points.isNotEmpty) _points.removeLast();
      widget.onChanged(_format(_points));
    });
  }

  void _clear() {
    setState(() {
      _points.clear();
      widget.onChanged('');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 360,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 520,
              child: GestureDetector(
                onTapDown: (d) => _onTap(d.localPosition),
                child: CustomPaint(
                  size: const Size(360, 520),
                  painter: _ShapePainter(floor: widget.floor, points: _points),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _undo,
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('Cofnij', style: TextStyle(fontSize: 11)),
            ),
            TextButton.icon(
              onPressed: _closeShape,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Zamknij', style: TextStyle(fontSize: 11)),
            ),
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Wyczyść', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        Text(
          'Punkty: ${_points.length}  •  kliknij pierwszy punkt, aby zamknąć kształt',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }
}

class _ShapePainter extends CustomPainter {
  final String floor;
  final List<Offset> points;

  _ShapePainter({required this.floor, required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = floor == 'Piętro' ? floor1Outline : floor0Outline;
    canvas.drawPath(floor1Path(outline), base..color = Colors.white38);
    for (final d in svgPolygonsFor(floor).values) {
      canvas.drawPath(floor1Path(d), base);
    }
    if (points.isEmpty) return;
    final path = Path();
    final first = floor1ToCanvas(points.first.dx, points.first.dy);
    path.moveTo(first.dx, first.dy);
    for (final p in points.skip(1)) {
      final c = floor1ToCanvas(p.dx, p.dy);
      path.lineTo(c.dx, c.dy);
    }
    if (points.length >= 3) path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF3B30).withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF3B30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final p in points) {
      final c = floor1ToCanvas(p.dx, p.dy);
      canvas.drawCircle(c, 5, Paint()..color = Colors.white);
      canvas.drawCircle(c, 3, Paint()..color = const Color(0xFFFF3B30));
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.floor != floor || old.points != points;
}
