import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const ink = Color(0xff11192c);
const panel = Color(0xff1d2942);
const wheat = Color(0xffffce79);
const paper = Color(0xfffff1d7);
const muted = Color(0xffb9c7dd);
const lime = Color(0xffd9ef88);
const lilac = Color(0xffc8b9ff);
const coral = Color(0xffffa68b);
const sky = Color(0xffa6e1fa);

TextStyle display(double size, {Color color = paper}) => TextStyle(
  fontFamily: 'Bricolage Grotesque',
  fontSize: size,
  color: color,
  fontVariations: const [FontVariation('wght', 760)],
  height: 1.02,
  letterSpacing: -0.028 * size,
);

class KernelStage extends StatefulWidget {
  const KernelStage({super.key, this.interactive = true});
  final bool interactive;

  @override
  State<KernelStage> createState() => _KernelStageState();
}

class _KernelStageState extends State<KernelStage> {
  final orientation = ValueNotifier((0.20, -0.46));

  @override
  void dispose() {
    orientation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drag = widget.interactive && !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      image: true,
      label: 'Illustration of a wheat kernel',
      child: GestureDetector(
        onPanUpdate: drag
            ? (details) {
                final (pitch, yaw) = orientation.value;
                orientation.value = (
                  (pitch + details.delta.dy * .013).clamp(-1.2, 1.2),
                  (yaw + details.delta.dx * .013) % (math.pi * 2),
                );
              }
            : null,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: KernelPainter(orientation),
            child: const SizedBox(width: double.infinity, height: 220),
          ),
        ),
      ),
    );
  }
}

typedef Point3 = ({double x, double y, double z});

class KernelPainter extends CustomPainter {
  KernelPainter(this.orientation) : super(repaint: orientation);
  final ValueNotifier<(double, double)> orientation;
  static const sides = 14;
  static const rings = 11;
  static final mesh = [
    for (var row = 0; row <= rings; row++)
      for (var col = 0; col < sides; col++)
        _vertex(row / rings, col * 2 * math.pi / sides),
  ];

  static Point3 _vertex(double t, double angle) {
    final radius = .06 + math.pow(math.sin(t * math.pi), .64) * (.54 + .18 * t);
    final crease = math.pow(math.max(0, math.sin(angle)), 34) * .22;
    return (
      x: math.cos(angle) * radius + .10 * math.sin(math.pi * t),
      y: (t - .5) * 2.55,
      z: (math.sin(angle) * .76 - crease) * radius,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .51, size.height * .50);
    final unit = math.min(size.width * .23, size.height * .335);
    final line = Paint()
      ..color = const Color(0xff6e6375)
      ..style = PaintingStyle.stroke;
    for (var i = 1; i <= 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: unit * (2.05 + .63 * i),
          height: unit * (1.05 + .40 * i),
        ),
        line..color = const Color(0xff706078).withValues(alpha: .24 + i * .07),
      );
    }
    final ticks = Paint()
      ..color = const Color(0xff827285)
      ..strokeWidth = 1;
    for (var i = 0; i < 36; i++) {
      final a = i * math.pi / 18;
      final direction = Offset(math.cos(a), math.sin(a) * .58);
      canvas.drawLine(
        center + direction * unit * 2.16,
        center + direction * unit * (i % 3 == 0 ? 2.27 : 2.21),
        ticks,
      );
    }
    for (final point in [
      const Offset(.10, .21),
      const Offset(.87, .26),
      const Offset(.19, .75),
      const Offset(.81, .77),
      const Offset(.94, .57),
    ]) {
      final p = Offset(size.width * point.dx, size.height * point.dy);
      canvas.drawLine(p - const Offset(3, 0), p + const Offset(3, 0), ticks);
      canvas.drawLine(p - const Offset(0, 3), p + const Offset(0, 3), ticks);
    }

    final (pitch, yaw) = orientation.value;
    final points = mesh.map((p) {
      final x = p.x * math.cos(yaw) + p.z * math.sin(yaw);
      final z = p.z * math.cos(yaw) - p.x * math.sin(yaw);
      final y = p.y * math.cos(pitch) - z * math.sin(pitch);
      const roll = .55;
      return (
        x: x * math.cos(roll) - y * math.sin(roll),
        y: y * math.cos(roll) + x * math.sin(roll),
        z: p.y * math.sin(pitch) + z * math.cos(pitch),
      );
    }).toList();
    final faces = <(Point3, Point3, Point3)>[];
    for (var row = 0; row < rings; row++) {
      for (var col = 0; col < sides; col++) {
        final next = (col + 1) % sides;
        final a = points[row * sides + col];
        final b = points[row * sides + next];
        final c = points[(row + 1) * sides + col];
        final d = points[(row + 1) * sides + next];
        faces.addAll([(a, c, b), (b, c, d)]);
      }
    }
    double depth((Point3, Point3, Point3) f) => f.$1.z + f.$2.z + f.$3.z;
    faces.sort((a, b) => depth(a).compareTo(depth(b)));
    Offset project(Point3 p) =>
        center + Offset(p.x, p.y) * unit * 4.5 / (4.5 - p.z);
    final paint = Paint();
    for (final (a, b, c) in faces) {
      final u = (x: b.x - a.x, y: b.y - a.y, z: b.z - a.z);
      final v = (x: c.x - a.x, y: c.y - a.y, z: c.z - a.z);
      final nx = u.y * v.z - u.z * v.y;
      final ny = u.z * v.x - u.x * v.z;
      final nz = u.x * v.y - u.y * v.x;
      final length = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (length < .00001 || nz <= 0) continue;
      final light = ((-.44 * nx - .55 * ny + .70 * nz) / length).clamp(
        0.0,
        1.0,
      );
      final pa = project(a);
      final pb = project(b);
      final pc = project(c);
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy)
        ..lineTo(pc.dx, pc.dy)
        ..close();
      final color = Color.lerp(
        const Color(0xff8b3c28),
        const Color(0xffffe3a0),
        light,
      )!;
      canvas.drawPath(
        path,
        paint
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        paint
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant KernelPainter oldDelegate) =>
      oldDelegate.orientation != orientation;
}
