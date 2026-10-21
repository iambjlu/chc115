import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/vehicle_threat.dart';
import '../theme/hud_colors.dart';

/// 虛擬道路檢視：鏡頭在自行車後上方往前看，自行車位於道路中間，
/// 左右後方來車以立方體顯示在自行車後方的左右車道（距離越近越靠近車身），
/// 前方坑洞以球體顯示。標記為「逼近中」的立方體上方會有硬切閃爍（無淡入淡出）
/// 的黃色警示三角形，左右共用同一個時鐘，節奏永遠同步。
/// 路面分隔線依車速往後捲動，營造行進感。
class RoadView extends StatefulWidget {
  const RoadView({
    super.key,
    required this.threats,
    required this.speedKmh,
    this.potholeFrontLeft = false,
    this.potholeFrontCenter = false,
    this.potholeFrontRight = false,
  });

  final List<VehicleThreat> threats;
  final double speedKmh;
  final bool potholeFrontLeft;
  final bool potholeFrontCenter;
  final bool potholeFrontRight;

  @override
  State<RoadView> createState() => _RoadViewState();
}

/// 單一時鐘：累計路面捲動距離與閃爍相位，painter 以它作為 repaint 來源，
/// 不需每個 frame 重建整個 widget 樹。
class _Clock extends ChangeNotifier {
  double scroll = 0; // 公尺，0~dashPeriod
  bool blinkVisible = true;

  void tick(double dt, double elapsedMs, double speedMps) {
    scroll = (scroll + speedMps * dt) % _Cam.dashPeriod;
    blinkVisible = (elapsedMs ~/ 220).isEven;
    notifyListeners();
  }
}

class _RoadViewState extends State<RoadView> with SingleTickerProviderStateMixin {
  final _clock = _Clock();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _clock.tick(dt, elapsed.inMilliseconds.toDouble(), widget.speedKmh / 3.6);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final cam = _Cam(size);
        final bikeCenter = cam.p(0, 0, 0);
        final bikeHeight = _Cam.bikeLength * cam.scaleAt(0);
        final bikeWidth = bikeHeight * 542 / 1072;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RoadPainter(
                clock: _clock,
                potholeLeft: widget.potholeFrontLeft,
                potholeCenter: widget.potholeFrontCenter,
                potholeRight: widget.potholeFrontRight,
              ),
            ),
            Positioned(
              left: bikeCenter.dx - bikeWidth / 2,
              top: bikeCenter.dy - bikeHeight / 2,
              width: bikeWidth,
              height: bikeHeight,
              child: Image.asset('assets/bike.png', fit: BoxFit.contain),
            ),
            CustomPaint(painter: _CarsPainter(clock: _clock, threats: widget.threats)),
          ],
        );
      },
    );
  }
}

/// 針孔透視：世界座標 x 往右、h 往上、z 往前（公尺，自行車在原點），
/// 鏡頭在自行車後方 [camBehind] 公尺、高度依版面算出，讓自行車落在畫面約 60% 高處。
class _Cam {
  _Cam(Size size)
      : cx = size.width / 2,
        f = size.width * 7,
        yh = size.height * 0.03 {
    hc = (size.height * 0.60 - yh) * camBehind / f;
  }

  static const double camBehind = 100;
  static const double dashPeriod = 6;
  static const double bikeLength = 4.0;
  static const double laneX = 3; // 左右車道中心
  static const double roadHalf = 4.5;

  final double cx;
  final double f;
  final double yh;
  late final double hc;

  Offset p(double x, double h, double z) {
    final dz = z + camBehind;
    return Offset(cx + f * x / dz, yh + f * (hc - h) / dz);
  }

  double scaleAt(double z) => f / (z + camBehind);
}

Path _poly(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Color _shade(Color c, double lightnessDelta) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + lightnessDelta).clamp(0.0, 1.0)).toColor();
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.clock,
    required this.potholeLeft,
    required this.potholeCenter,
    required this.potholeRight,
  }) : super(repaint: clock);

  final _Clock clock;
  final bool potholeLeft;
  final bool potholeCenter;
  final bool potholeRight;

  static const _zNear = -60.0;
  static const _zFar = 3000.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(size);
    const half = _Cam.roadHalf;

    canvas.drawPath(
      _poly([
        cam.p(-half, 0, _zNear),
        cam.p(half, 0, _zNear),
        cam.p(half, 0, _zFar),
        cam.p(-half, 0, _zFar),
      ]),
      Paint()..color = HudColors.road,
    );

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = HudColors.ink.withValues(alpha: 0.55);
    for (final x in [-half, half]) {
      canvas.drawLine(cam.p(x, 0, _zNear), cam.p(x, 0, _zFar), edge);
    }

    // 車道分隔虛線，依車速往鏡頭方向（z 變小）捲動。
    final dash = Paint()..color = HudColors.ink.withValues(alpha: 0.7);
    for (var k = -12; k < 50; k++) {
      final z0 = k * _Cam.dashPeriod - clock.scroll;
      final z1 = z0 + _Cam.dashPeriod / 2;
      if (z1 < _zNear) continue;
      for (final x in [-_Cam.laneX / 2, _Cam.laneX / 2]) {
        canvas.drawPath(
          _poly([
            cam.p(x - 0.07, 0, z0),
            cam.p(x + 0.07, 0, z0),
            cam.p(x + 0.07, 0, z1),
            cam.p(x - 0.07, 0, z1),
          ]),
          dash,
        );
      }
    }

    // 前方坑洞：球體，左前 / 正前 / 右前。
    const potholeZ = 14.0;
    if (potholeLeft) _sphere(canvas, cam, -1.5, potholeZ);
    if (potholeCenter) _sphere(canvas, cam, 0, potholeZ);
    if (potholeRight) _sphere(canvas, cam, 1.5, potholeZ);

    // 遠端淡出到背景色，避免道路在地平線硬切。
    final fadeRect = Rect.fromLTWH(0, 0, size.width, size.height * 0.4);
    canvas.drawRect(
      fadeRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.surface, Color(0x000A0B0D)],
        ).createShader(fadeRect),
    );
  }

  void _sphere(Canvas canvas, _Cam cam, double x, double z) {
    const radius = 0.7;
    final c = cam.p(x, radius, z);
    final r = radius * cam.scaleAt(z);
    final ground = cam.p(x, 0, z);
    canvas.drawOval(
      Rect.fromCenter(center: ground, width: r * 2.2, height: r * 0.7),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [_shade(HudColors.warn, 0.25), HudColors.warn, _shade(HudColors.warn, -0.3)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.potholeLeft != potholeLeft ||
      old.potholeCenter != potholeCenter ||
      old.potholeRight != potholeRight;
}

class _CarsPainter extends CustomPainter {
  _CarsPainter({required this.clock, required this.threats}) : super(repaint: clock);

  final _Clock clock;
  final List<VehicleThreat> threats;

  static const _cubeSize = 1.6;

  Color _colorFor(ThreatLevel level) => switch (level) {
        ThreatLevel.safe => HudColors.safe,
        ThreatLevel.caution => HudColors.warn,
        ThreatLevel.danger => HudColors.danger,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(size);
    for (final t in threats) {
      final left = t.side == ThreatSide.left;
      final x = left ? -_Cam.laneX : _Cam.laneX;
      // 方塊前緣離自行車 distanceMeters，向鏡頭方向延伸一個方塊長度。
      final zFar = -t.distanceMeters;
      final zNear = zFar - _cubeSize;
      _cube(canvas, cam, x, zFar, zNear, _colorFor(t.level), left);
      if (t.isApproaching && clock.blinkVisible) {
        _triangle(canvas, cam, x, (zFar + zNear) / 2);
      }
    }
  }

  void _cube(Canvas canvas, _Cam cam, double cx, double zFar, double zNear, Color base, bool left) {
    const s = _cubeSize;
    final x0 = cx - s / 2;
    final x1 = cx + s / 2;
    // 地面陰影
    canvas.drawPath(
      _poly([cam.p(x0, 0, zFar), cam.p(x1, 0, zFar), cam.p(x1, 0, zNear), cam.p(x0, 0, zNear)]),
      Paint()..color = const Color(0x55000000),
    );
    final sideX = left ? x1 : x0; // 朝向道路中心的側面
    canvas.drawPath(
      _poly([
        cam.p(sideX, 0, zFar),
        cam.p(sideX, 0, zNear),
        cam.p(sideX, s, zNear),
        cam.p(sideX, s, zFar),
      ]),
      Paint()..color = _shade(base, -0.22),
    );
    canvas.drawPath(
      _poly([cam.p(x0, 0, zNear), cam.p(x1, 0, zNear), cam.p(x1, s, zNear), cam.p(x0, s, zNear)]),
      Paint()..color = base,
    );
    canvas.drawPath(
      _poly([cam.p(x0, s, zFar), cam.p(x1, s, zFar), cam.p(x1, s, zNear), cam.p(x0, s, zNear)]),
      Paint()..color = _shade(base, 0.18),
    );
  }

  void _triangle(Canvas canvas, _Cam cam, double x, double z) {
    final c = cam.p(x, _cubeSize + 0.9, z);
    final side = 1.1 * cam.scaleAt(z);
    final path = Path()
      ..moveTo(c.dx, c.dy - side * 0.5)
      ..lineTo(c.dx - side * 0.55, c.dy + side * 0.45)
      ..lineTo(c.dx + side * 0.55, c.dy + side * 0.45)
      ..close();
    canvas.drawPath(path, Paint()..color = HudColors.warn);
    // 驚嘆號
    final mark = Paint()
      ..color = HudColors.surface
      ..strokeWidth = math.max(2, side * 0.1)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx, c.dy - side * 0.12), Offset(c.dx, c.dy + side * 0.17), mark);
    canvas.drawCircle(Offset(c.dx, c.dy + side * 0.32), mark.strokeWidth / 2, mark);
  }

  @override
  bool shouldRepaint(covariant _CarsPainter old) => old.threats != threats;
}
