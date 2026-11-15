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

enum Grain {
  wheat('Wheat', Color(0xffffce79), Color(0xff8a4426)),
  rice('Rice', Color(0xfff9e9cb), Color(0xff285d55));

  const Grain(this.label, this.accent, this.dye);
  final String label;
  final Color accent;
  final Color dye;

  String get sackLabel => '$label sack';
}

class SackStage extends StatefulWidget {
  const SackStage({
    super.key,
    required this.grain,
    this.interactive = true,
    this.height = 236,
  });

  final Grain grain;
  final bool interactive;
  final double height;

  @override
  State<SackStage> createState() => _SackStageState();
}

class _SackStageState extends State<SackStage> {
  final orientation = ValueNotifier((.55, -.32));

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
      label:
          'Illustration of a sack filled with ${widget.grain.label.toLowerCase()}',
      child: GestureDetector(
        onPanUpdate: drag
            ? (details) {
                final (pitch, yaw) = orientation.value;
                orientation.value = (
                  (pitch + details.delta.dy * .012).clamp(.23, 1.04),
                  (yaw + details.delta.dx * .012) % (2 * math.pi),
                );
              }
            : null,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: SackPainter(widget.grain, orientation),
            child: SizedBox(width: double.infinity, height: widget.height),
          ),
        ),
      ),
    );
  }
}

typedef _Point = ({double x, double y, double z});
typedef _Face = ({int a, int b, int c, Color color});

class _SackMesh {
  final points = <_Point>[];
  final faces = <_Face>[];

  _SackMesh(Grain grain) {
    const sides = 32;
    final random = math.Random(77);
    const rings = [
      (-1.10, .02),
      (-1.10, .62),
      (-1.02, .87),
      (-.78, 1.00),
      (-.53, 1.04),
      (-.31, 1.03),
      (-.05, .99),
      (.27, .91),
      (.56, .83),
      (.66, .89),
      (.75, .92),
      (.82, .86),
      (.77, .76),
      (.65, .73),
    ];
    for (final (y, radius) in rings) {
      for (var i = 0; i < sides; i++) {
        final angle = 2 * math.pi * i / sides;
        final fold =
            1 +
            .055 * math.cos(5 * angle + y) +
            .035 * math.sin(9 * angle - y * 2);
        points.add((
          x: math.cos(angle) * radius * fold,
          y: y + radius * .05 * math.sin(3 * angle + y),
          z: math.sin(angle) * radius * fold * .83,
        ));
      }
    }
    for (var row = 0; row < rings.length - 1; row++) {
      final base = switch (row) {
        4 || 5 => grain.dye,
        9 || 10 => const Color(0xffd2ac79),
        11 || 12 => const Color(0xff9f754f),
        _ => const Color(0xffb88b5d),
      };
      for (var i = 0; i < sides; i++) {
        final a = row * sides + i;
        final b = row * sides + (i + 1) % sides;
        final color = Color.lerp(
          base,
          Colors.white,
          random.nextDouble() * .085,
        )!;
        faces.addAll([
          (a: a, b: a + sides, c: b, color: color),
          (a: b, b: a + sides, c: b + sides, color: color),
        ]);
      }
    }

    double mound(double x, double z) =>
        .69 + .30 * (1 - (x * x + z * z / .69) / (.76 * .76)).clamp(0.0, 1.0);
    final pile = Color.lerp(grain.accent, const Color(0xff604326), .38)!;
    final summit = points.length;
    points.add((x: 0, y: mound(0, 0), z: 0));
    for (var i = 0; i < sides; i++) {
      final angle = 2 * math.pi * i / sides;
      final x = math.cos(angle) * .745;
      final z = math.sin(angle) * .62;
      points.add((x: x, y: mound(x, z), z: z));
      faces.add((
        a: summit,
        b: summit + 1 + (i + 1) % sides,
        c: summit + 1 + i,
        color: pile,
      ));
    }

    // Staggered rows cover the mound with individual faceted grains.
    for (var row = -7; row <= 7; row++) {
      for (var col = -8; col <= 8; col++) {
        final x =
            (col + (row.isOdd ? .5 : 0)) * .081 +
            (random.nextDouble() - .5) * .041;
        final z = row * .076 + (random.nextDouble() - .5) * .045;
        if (x * x + z * z / .69 > .69 * .69) continue;
        final y = mound(x, z) + .018 + random.nextDouble() * .022;
        final angle = random.nextDouble() * math.pi;
        final length =
            (grain == Grain.rice ? .084 : .068) *
            (.8 + random.nextDouble() * .35);
        final width = length * (grain == Grain.rice ? .25 : .51);
        final start = points.length;
        for (final (along, across) in [
          (length, 0.0),
          (0.0, width),
          (-length, 0.0),
          (0.0, -width),
        ]) {
          points.add((
            x: x + along * math.cos(angle) - across * math.sin(angle),
            y: y,
            z: z + along * math.sin(angle) + across * math.cos(angle),
          ));
        }
        points.add((x: x, y: y + width * .72, z: z));
        final color = Color.lerp(
          grain.accent,
          pile,
          random.nextDouble() * .65,
        )!;
        for (var edge = 0; edge < 4; edge++) {
          faces.add((
            a: start + edge,
            b: start + 4,
            c: start + (edge + 1) % 4,
            color: color,
          ));
        }
      }
    }
  }
}

class SackPainter extends CustomPainter {
  SackPainter(this.grain, this.orientation) : super(repaint: orientation);

  final Grain grain;
  final ValueNotifier<(double, double)> orientation;
  static final _meshes = {
    for (final grain in Grain.values) grain: _SackMesh(grain),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .47);
    final scale = math.min(size.height * .33, size.width * .34);
    final paint = Paint();
    final ground = center + Offset(0, scale * .76);
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: scale * 2.4, height: scale * .62),
      paint..color = const Color(0x590b0b18),
    );
    for (final radius in [1.36, 1.57, 1.79]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: ground,
          width: scale * radius * 2,
          height: scale * radius * .64,
        ),
        paint
          ..color = grain.accent.withValues(alpha: .18)
          ..style = PaintingStyle.stroke,
      );
    }

    final (pitch, yaw) = orientation.value;
    final mesh = _meshes[grain]!;
    final sinPitch = math.sin(pitch);
    final cosPitch = math.cos(pitch);
    final sinYaw = math.sin(yaw);
    final cosYaw = math.cos(yaw);
    final rotated = mesh.points.map((point) {
      final z = point.z * cosYaw - point.x * sinYaw;
      return (
        x: point.x * cosYaw + point.z * sinYaw,
        y: point.y * cosPitch - z * sinPitch,
        z: point.y * sinPitch + z * cosPitch,
      );
    }).toList();
    final projected = rotated
        .map((p) => center + Offset(p.x, -p.y) * scale * 6 / (6 - p.z))
        .toList();
    final ordered = [
      for (final face in mesh.faces)
        (
          face: face,
          depth: rotated[face.a].z + rotated[face.b].z + rotated[face.c].z,
        ),
    ]..sort((a, b) => a.depth.compareTo(b.depth));

    for (final entry in ordered) {
      final face = entry.face;
      final a = rotated[face.a];
      final b = rotated[face.b];
      final c = rotated[face.c];
      final ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z;
      final vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z;
      final nx = uy * vz - uz * vy;
      final ny = uz * vx - ux * vz;
      final nz = ux * vy - uy * vx;
      final magnitude = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (magnitude == 0) continue;
      final light = ((-.4 * nx + .64 * ny + .66 * nz) / magnitude).abs();
      final color = Color.lerp(
        const Color(0xff392534),
        face.color,
        .48 + .52 * light,
      )!;
      final pa = projected[face.a];
      final pb = projected[face.b];
      final pc = projected[face.c];
      final path = Path()
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy)
        ..lineTo(pc.dx, pc.dy)
        ..close();
      canvas.drawPath(
        path,
        paint
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = .45,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SackPainter oldDelegate) =>
      oldDelegate.grain != grain || oldDelegate.orientation != orientation;
}
