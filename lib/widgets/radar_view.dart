import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/vehicle_threat.dart';
import '../theme/hud_colors.dart';

/// 白底雷達視圖：自身車輛（俯視）置中，左右後方偵測弧線在下方展開
/// （安全側多層綠色弧線、危險側單層貼近的紅色弧線，類似 Wi-Fi 訊號的
/// 視覺隱喻）。當某側車輛標記為「逼近中」時（不論距離），該側外緣
/// 會浮現硬切閃爍（無淡入淡出餘暉）的黃色警示三角形；左右兩個三角形
/// 共用同一個計時器，閃爍節奏永遠同步、不會此起彼落。車輛前方（上方）
/// 可另外顯示左前 / 正前 / 右前三個造型各異的鋸齒波形，代表坑洞預警——
/// 這是單純的路況提示，不隨威脅逼近閃爍。
class RadarView extends StatefulWidget {
  const RadarView({
    super.key,
    required this.threats,
    this.potholeFrontLeft = false,
    this.potholeFrontCenter = false,
    this.potholeFrontRight = false,
  });

  final List<VehicleThreat> threats;
  final bool potholeFrontLeft;
  final bool potholeFrontCenter;
  final bool potholeFrontRight;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> {
  static const _blinkInterval = Duration(milliseconds: 220);

  Timer? _timer;
  bool _blinkVisible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_blinkInterval, (_) => setState(() => _blinkVisible = !_blinkVisible));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final approachingLeft = widget.threats.where(
      (t) => t.side == ThreatSide.left && t.isApproaching,
    );
    final approachingRight = widget.threats.where(
      (t) => t.side == ThreatSide.right && t.isApproaching,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        // 車輛大小同時受寬、高限制，避免在極端寬高比下過大。
        final bikeSize = math.min(width * 0.3, height * 0.34);
        // 車輛上方預留一段固定高度給前方坑洞波形，避免顯示/隱藏時版面跳動。
        const potholeRowHeight = 26.0;
        final bikeTop = height * 0.05 + potholeRowHeight;
        final bikeBottom = bikeTop + bikeSize;

        // 弧線半徑先依寬度縮放（維持左右弧線的水平分佈感），
        final widthScale = (width / 360.0).clamp(0.55, 1.3);
        var radii = _RadarArcsPainter.baseRadii.map((r) => r * widthScale).toList();

        // 圓心錨定在「車輛畫完之後」，而不是用跟車輛無關的高度比例，
        // 這樣弧線就不會因為容器高寬比不同而跟車身重疊在一起。
        final gapBelowBike = math.max(14.0, bikeSize * 0.14);
        final centerY = bikeBottom + gapBelowBike;

        // 若剩餘垂直空間不足以容納完整弧線，再依高度等比縮小，
        // 確保弧線永遠落在車輛下方、且不超出容器邊界。
        final bottomPadding = 28.0;
        final availableBelow = height - centerY - bottomPadding;
        if (availableBelow < radii.last) {
          final heightScale = (availableBelow / radii.last).clamp(0.35, 1.0);
          radii = radii.map((r) => r * heightScale).toList();
        }
        final maxRadius = radii.last;
        final center = Offset(width / 2, centerY);

        final triangleY = math.min(centerY + maxRadius * 0.75, height - 30);
        final triangleOffsetX = maxRadius * 0.85;

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _RadarArcsPainter(threats: widget.threats, center: center, radii: radii),
            ),
            Positioned(
              top: bikeTop,
              left: (width - bikeSize) / 2,
              width: bikeSize,
              height: bikeSize,
              child: Image.asset('assets/bike.png', fit: BoxFit.contain),
            ),
            if (widget.potholeFrontCenter)
              Positioned(
                top: bikeTop - potholeRowHeight,
                left: width / 2 - 20,
                child: const _PotholeMarker(shape: _PotholeShape.center),
              ),
            if (widget.potholeFrontLeft)
              Positioned(
                top: bikeTop - potholeRowHeight + 4,
                left: width / 2 - bikeSize * 0.65 - 20,
                child: const _PotholeMarker(shape: _PotholeShape.left),
              ),
            if (widget.potholeFrontRight)
              Positioned(
                top: bikeTop - potholeRowHeight + 4,
                left: width / 2 + bikeSize * 0.65 - 20,
                child: const _PotholeMarker(shape: _PotholeShape.right),
              ),
            if (approachingLeft.isNotEmpty)
              Positioned(
                top: triangleY,
                left: width / 2 - triangleOffsetX - 15,
                child: _WarningTriangle(visible: _blinkVisible),
              ),
            if (approachingRight.isNotEmpty)
              Positioned(
                top: triangleY,
                left: width / 2 + triangleOffsetX - 15,
                child: _WarningTriangle(visible: _blinkVisible),
              ),
          ],
        );
      },
    );
  }
}

/// 閃爍警示三角形：顯示狀態由外層 [_RadarViewState] 的單一計時器統一
/// 驅動並硬切（無透明度補間、沒有淡入淡出餘暉），確保多個三角形同步閃爍。
class _WarningTriangle extends StatelessWidget {
  const _WarningTriangle({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: CustomPaint(size: const Size(30, 27), painter: _TrianglePainter()),
    );
  }
}

/// 前方坑洞預警的方向：左前 / 正前 / 右前，各自用不同角度的鋸齒波形
/// 呈現，跟後方威脅用的圓弧波形明顯不同造型，且不會閃爍。
enum _PotholeShape { left, center, right }

class _PotholeMarker extends StatelessWidget {
  const _PotholeMarker({required this.shape});

  final _PotholeShape shape;

  @override
  Widget build(BuildContext context) {
    final angle = switch (shape) {
      _PotholeShape.left => -0.55,
      _PotholeShape.center => 0.0,
      _PotholeShape.right => 0.55,
    };
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(size: const Size(40, 14), painter: _PotholeZigzagPainter()),
    );
  }
}

class _PotholeZigzagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(size.width * 0.2, 0)
      ..lineTo(size.width * 0.4, size.height)
      ..lineTo(size.width * 0.6, 0)
      ..lineTo(size.width * 0.8, size.height)
      ..lineTo(size.width, size.height * 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = HudColors.warn,
    );
  }

  @override
  bool shouldRepaint(covariant _PotholeZigzagPainter oldDelegate) => false;
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = HudColors.warn
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => false;
}

class _RadarArcsPainter extends CustomPainter {
  _RadarArcsPainter({required this.threats, required this.center, required this.radii});

  final List<VehicleThreat> threats;
  final Offset center;
  final List<double> radii;

  static const _leftRange = (115.0, 172.0);
  static const _rightRange = (8.0, 65.0);
  static const baseRadii = [30.0, 46.0, 62.0];

  Color _colorFor(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.safe:
        return HudColors.safe;
      case ThreatLevel.caution:
        return HudColors.warn;
      case ThreatLevel.danger:
        return HudColors.danger;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final threat in threats) {
      final range = threat.side == ThreatSide.left ? _leftRange : _rightRange;
      final startRad = range.$1 * math.pi / 180;
      final sweepRad = (range.$2 - range.$1) * math.pi / 180;
      final color = _colorFor(threat.level);

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4.5
        ..color = color;
      for (var i = 0; i < threat.arcCount; i++) {
        final rect = Rect.fromCircle(center: center, radius: radii[i]);
        canvas.drawArc(rect, startRad, sweepRad, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarArcsPainter oldDelegate) =>
      oldDelegate.threats != threats || oldDelegate.center != center || oldDelegate.radii != radii;
}
