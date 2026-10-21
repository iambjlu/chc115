import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/hud_colors.dart';

/// 車速儀表：左側 V 形刻度尺（0 在底、[maxSpeed] 在頂）加一根綠色指針，
/// 右側是大字車速。指針會平滑移動；超過 [maxSpeed] 時指針停在頂端。
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({super.key, required this.speed});

  final int? speed;

  /// 刻度尺上限（km/h）。
  static const double maxSpeed = 25;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final target = (speed ?? 0).clamp(0, maxSpeed).toDouble();
    return SizedBox(
      height: 176,
      child: Row(
        children: [
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            height: 176,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: target),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (context, value, _) =>
                  CustomPaint(painter: _GaugePainter(value)),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    speed?.toString() ?? '—',
                    style: textTheme.displayLarge?.copyWith(
                      fontSize: 104,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      color: HudColors.ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text('km/h',
                    style: textTheme.titleMedium?.copyWith(color: HudColors.inkDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // V 形刻度尺：底部 0 → 左側轉折 → 頂部最大值。
    final path = Path()
      ..moveTo(w * 0.80, h * 0.96)
      ..lineTo(w * 0.14, h * 0.56)
      ..lineTo(w * 0.80, h * 0.04);
    final metric = path.computeMetrics().first;
    final length = metric.length;
    const max = SpeedGauge.maxSpeed;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = HudColors.hairline;
    canvas.drawPath(path, track);
    canvas.drawPath(
      metric.extractPath(0, length * value / max),
      track..color = HudColors.ink.withValues(alpha: 0.85),
    );

    Offset normalAt(Tangent t) {
      final n = Offset(-t.vector.dy, t.vector.dx);
      return n.dx < 0 ? -n : n; // 一律朝 V 形內側（右）
    }

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i <= max.toInt(); i++) {
      final t = metric.getTangentForOffset(length * i / max)!;
      final n = normalAt(t);
      final major = i % 5 == 0;
      final len = major ? 12.0 : 6.0;
      tick.color = major ? HudColors.ink : HudColors.inkFaint;
      canvas.drawLine(t.position, t.position + n * len, tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: const TextStyle(color: HudColors.inkDim, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final c = t.position + n * 24;
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // 指針：跨在刻度線上的綠色短條。
    final t = metric.getTangentForOffset(length * value / max)!;
    final n = normalAt(t);
    canvas.drawLine(
      t.position - n * 14,
      t.position + n * 8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = HudColors.gauge,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value;
}
