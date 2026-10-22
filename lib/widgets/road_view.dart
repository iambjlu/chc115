import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/simulation_values.dart';
import '../models/vehicle_threat.dart';
import '../theme/hud_colors.dart';

/// 虛擬道路檢視：鏡頭在自行車後上方往前看，自行車位於道路中間，
/// 左右後方來車以立方體顯示在自行車後方的左右兩側（距離越近越靠近車身），
/// 前方坑洞畫成路面上的坑、障礙物為自行車前方的弧形燈條。標記為「逼近中」的立方體會硬切閃爍
/// （無淡入淡出），左右共用同一個時鐘，節奏永遠同步。
/// 地面橫向格線依車速往後捲動，營造行進感（刻意不畫車道線）。
class RoadView extends StatefulWidget {
  const RoadView({
    super.key,
    required this.threats,
    required this.speedKmh,
    this.frontLeft = FrontHazard.none,
    this.frontCenter = FrontHazard.none,
    this.frontRight = FrontHazard.none,
  });

  final List<VehicleThreat> threats;
  final double speedKmh;
  final FrontHazard frontLeft;
  final FrontHazard frontCenter;
  final FrontHazard frontRight;

  @override
  State<RoadView> createState() => _RoadViewState();
}

/// 單一時鐘：累計路面捲動距離與閃爍相位，painter 以它作為 repaint 來源，
/// 不需每個 frame 重建整個 widget 樹。
class _Clock extends ChangeNotifier {
  double scroll = 0; // 公尺，0~gridPeriod
  bool blinkVisible = true;

  void tick(double dt, double elapsedMs, double speedMps) {
    scroll = (scroll + speedMps * dt) % _Cam.gridPeriod;
    blinkVisible = (elapsedMs ~/ 220).isEven;
    notifyListeners();
  }
}

class _RoadViewState extends State<RoadView>
    with SingleTickerProviderStateMixin {
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
        final bikeHeight = _Cam.bikeLength * cam.scaleAt(0) * 1.25;
        final bikeWidth = bikeHeight * 542 / 1072;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _RoadPainter(
                  clock: _clock,
                  frontLeft: widget.frontLeft,
                  frontCenter: widget.frontCenter,
                  frontRight: widget.frontRight,
                ),
              ),
              // 車身後方的白色光暈與橢圓底盤，讓自行車從深色路面上浮出來。
              Positioned(
                left: bikeCenter.dx - bikeWidth * 1.3,
                top: bikeCenter.dy - bikeHeight * 0.75,
                width: bikeWidth * 2.6,
                height: bikeHeight * 1.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.18),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: bikeCenter.dx - bikeWidth / 2,
                top: bikeCenter.dy - bikeHeight / 2,
                width: bikeWidth,
                height: bikeHeight,
                child: Image.asset('assets/bike.png', fit: BoxFit.contain),
              ),
              CustomPaint(
                painter: _CarsPainter(clock: _clock, threats: widget.threats),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 針孔透視：世界座標 x 往右、h 往上、z 往前（公尺，自行車在原點），
/// 鏡頭在自行車後方 [camBehind] 公尺、高度 [camHeight] 公尺（偏俯視），
/// 地平線位置依版面算出，讓自行車落在畫面約 60% 高處。
class _Cam {
  _Cam(Size size)
    : cx = size.width / 2,
      f = size.width * 7,
      yh = size.height * 0.60 - size.width * 7 * camHeight / camBehind;

  static const double camBehind = 100;
  static const double camHeight = 20;
  static const double gridPeriod = 6;
  static const double bikeLength = 2.4;
  static const double laneX = 3; // 左右來車的橫向位置
  static const double roadHalf = 5.2;

  final double cx;
  final double f;
  final double yh;
  double get hc => camHeight;

  Offset p(double x, double h, double z) {
    final dz = z + camBehind;
    return Offset(cx + f * x / dz, yh + f * (hc - h) / dz);
  }

  double scaleAt(double z) => f / (z + camBehind);
}

const _obstacle = Color(0xFFFF6A1F);

Path _poly(List<Offset> pts) {
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Color _shade(Color c, double lightnessDelta) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + lightnessDelta).clamp(0.0, 1.0))
      .toColor();
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.clock,
    required this.frontLeft,
    required this.frontCenter,
    required this.frontRight,
  }) : super(repaint: clock);

  final _Clock clock;
  final FrontHazard frontLeft;
  final FrontHazard frontCenter;
  final FrontHazard frontRight;

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

    // 不畫車道線（避免誤導成三車道視野）；改用橫向淡色格線依車速往鏡頭方向捲動，
    // 只表現地面與行進感。
    final grid =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = HudColors.ink.withValues(alpha: 0.10);
    for (var k = -12; k < 80; k++) {
      final z = k * _Cam.gridPeriod - clock.scroll;
      if (z < _zNear) continue;
      canvas.drawLine(cam.p(-half, 0, z), cam.p(half, 0, z), grid);
    }

    // 前方路況，左前 / 正前 / 右前：坑洞是畫在路面上的坑、障礙物是自行車前方的弧形燈條，
    // 兩者並存時坑洞與弧形燈條同時顯示。
    const slots = [(-2.8, 0), (0.0, 1), (2.8, 2)];
    final hazards = [frontLeft, frontCenter, frontRight];
    for (final (x, i) in slots) {
      if (hazards[i].hasPothole) _pit(canvas, cam, x, 12);
    }
    // 障礙物：自行車前方的分段弧形燈條（倒車雷達樣式），左前／正前／右前各一區。
    _arc(canvas, cam, [for (final h in hazards) h.hasObstacle]);

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

  /// 障礙物弧形燈條：沿自行車前方半圈分成 9 小段（右前 / 正前 / 左前各 3 段），
  /// 該方向有障礙物時整區亮紅橘色並帶光暈，沒有障礙物的區域不畫。
  void _arc(Canvas canvas, _Cam cam, List<bool> sectorOn) {
    const segs = 9;
    const gap = 0.05; // 段與段之間的縫（弧度）
    const r0 = 1.35, r1 = 1.85;
    Offset pt(double r, double a) =>
        cam.p(r * math.cos(a), 0, 1.0 + 1.1 * r * math.sin(a));
    for (var k = 0; k < segs; k++) {
      // k 0..2 右前、3..5 正前、6..8 左前；sectorOn 順序為左前、正前、右前。
      final on = sectorOn[2 - k ~/ 3];
      if (!on) continue;
      final a0 = k * math.pi / segs + gap, a1 = (k + 1) * math.pi / segs - gap;
      final path = Path()..moveTo(pt(r1, a0).dx, pt(r1, a0).dy);
      for (var j = 1; j <= 4; j++) {
        final p = pt(r1, a0 + (a1 - a0) * j / 4);
        path.lineTo(p.dx, p.dy);
      }
      for (var j = 4; j >= 0; j--) {
        final p = pt(r0, a0 + (a1 - a0) * j / 4);
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = _obstacle.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawPath(path, Paint()..color = const Color(0xFFFF3B1F));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFFFFB27A),
      );
    }
  }

  /// 坑洞：畫在路面上的一個坑——黃色外框加較亮的坑緣，內部是由遠端坑壁（亮）
  /// 漸層到坑底（近黑），不會與灰色路面融為一體。
  void _pit(Canvas canvas, _Cam cam, double x, double z) {
    // 地面在畫面上被透視壓扁，z 方向放大約 2 倍，坑看起來才像坑而不是細環。
    const zStretch = 2.0;
    Path ring(double r, [double dz = 0]) {
      final pts = [
        for (var i = 0; i < 36; i++)
          cam.p(
            x + r * math.cos(i * math.pi / 18),
            0,
            z + dz + zStretch * r * math.sin(i * math.pi / 18),
          ),
      ];
      return _poly(pts);
    }

    final rim = ring(1.0);
    canvas.drawPath(rim, Paint()..color = const Color(0xFF555B66));
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = HudColors.warn,
    );
    final hole = ring(0.74);
    final bounds = hole.getBounds();
    canvas.drawPath(
      hole,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF454B55), Color(0xFF0B0C0F), Color(0xFF020203)],
          stops: [0, 0.45, 1],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) =>
      old.frontLeft != frontLeft ||
      old.frontCenter != frontCenter ||
      old.frontRight != frontRight;
}

class _CarsPainter extends CustomPainter {
  _CarsPainter({required this.clock, required this.threats})
    : super(repaint: clock);

  final _Clock clock;
  final List<VehicleThreat> threats;

  static const _cubeSize = 1.2;

  Color _colorFor(ThreatLevel level) => switch (level) {
    ThreatLevel.safe => HudColors.safe,
    ThreatLevel.caution => HudColors.warn,
    ThreatLevel.danger => HudColors.danger,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cam = _Cam(size);
    // 方塊最靠近車身的位置：頂面前緣不可高過自行車中心（畫面上不超過車身）。
    final nearest =
        cam.f * (cam.hc - _cubeSize) / (cam.p(0, 0, 0).dy - cam.yh) -
        _Cam.camBehind;
    for (final t in threats) {
      final left = t.side == ThreatSide.left;
      final x = left ? -_Cam.laneX : _Cam.laneX;
      // 距離遠（安全）時不顯示方塊。
      if (t.level != ThreatLevel.safe) {
        // 前緣離車尾 distanceMeters*0.9 公尺，並不超過 nearest 限制。
        final zFar = math.min(
          -(_Cam.bikeLength / 2 + t.distanceMeters * 0.9),
          nearest,
        );
        // 逼近中：方塊硬切閃爍（左右共用同一個時鐘，節奏同步）。
        if (!t.isApproaching || clock.blinkVisible) {
          _cube(
            canvas,
            cam,
            x,
            zFar,
            zFar - _cubeSize,
            _colorFor(t.level),
            left,
          );
        }
      }
    }
  }

  void _cube(
    Canvas canvas,
    _Cam cam,
    double cx,
    double zFar,
    double zNear,
    Color base,
    bool left,
  ) {
    const s = _cubeSize;
    final x0 = cx - s / 2;
    final x1 = cx + s / 2;
    // 地面陰影
    canvas.drawPath(
      _poly([
        cam.p(x0, 0, zFar),
        cam.p(x1, 0, zFar),
        cam.p(x1, 0, zNear),
        cam.p(x0, 0, zNear),
      ]),
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
      _poly([
        cam.p(x0, 0, zNear),
        cam.p(x1, 0, zNear),
        cam.p(x1, s, zNear),
        cam.p(x0, s, zNear),
      ]),
      Paint()..color = base,
    );
    canvas.drawPath(
      _poly([
        cam.p(x0, s, zFar),
        cam.p(x1, s, zFar),
        cam.p(x1, s, zNear),
        cam.p(x0, s, zNear),
      ]),
      Paint()..color = _shade(base, 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant _CarsPainter old) => old.threats != threats;
}
