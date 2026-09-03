import 'package:flutter/material.dart';

import '../models/simulation_values.dart';
import '../models/vehicle_threat.dart';
import '../services/alert_notification_service.dart';
import '../theme/hud_colors.dart';
import '../widgets/map_card.dart';
import '../widgets/radar_view.dart';
import '../widgets/simulation_sheet.dart';

/// 騎乘中的後方雷達 HUD 主畫面：白底車速讀數、警示文字、深色夜間地圖、
/// 白底雷達視圖，左下角浮動按鈕開啟模擬控制面板。
class RideHudScreen extends StatefulWidget {
  const RideHudScreen({super.key});

  @override
  State<RideHudScreen> createState() => _RideHudScreenState();
}

class _RideHudScreenState extends State<RideHudScreen> {
  SimulationValues _sim = SimulationValues.demo;

  List<VehicleThreat> get _threats => [
    VehicleThreat(
      side: ThreatSide.left,
      distanceMeters: _sim.leftDistance,
      isApproaching: _sim.leftApproaching,
    ),
    VehicleThreat(
      side: ThreatSide.right,
      distanceMeters: _sim.rightDistance,
      isApproaching: _sim.rightApproaching,
    ),
  ];

  // 不論距離遠近，只要標記為逼近中就要顯示警告。
  _AlertInfo? get _activeAlert {
    final approaching = _threats.where((t) => t.isApproaching).toList();
    if (approaching.isEmpty) return null;
    if (approaching.length > 1) {
      return const _AlertInfo(label: '左右後方', suggestion: '請注意安全');
    }
    final threat = approaching.first;
    return _AlertInfo(label: threat.label, suggestion: threat.suggestion);
  }

  // 依左前/正前/右前順序列出目前亮起的坑洞方向，多個方向用「、」分隔。
  String? get _potholeAlertText {
    final directions = <String>[
      if (_sim.potholeFrontLeft) '左前',
      if (_sim.potholeFrontCenter) '正前',
      if (_sim.potholeFrontRight) '右前',
    ];
    if (directions.isEmpty) return null;
    return '⚠️請注意${directions.join('、')}坑洞';
  }

  void _openSimulationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SimulationSheet(
        initialValues: _sim,
        onChanged: _applySimulationValues,
      ),
    );
  }

  // 左右後方車輛只要距離比先前更近（不論 leftApproaching/rightApproaching
  // 開關是否開啟）就觸發一次系統通知（高優先權、有聲音）＋一次震動；
  // 坑洞則維持「由假變真」才觸發，避免同一個危險狀態持續觸發時反覆通知造成干擾。
  void _applySimulationValues(SimulationValues next) {
    final previous = _sim;
    setState(() => _sim = next);

    if (next.leftDistance < previous.leftDistance) {
      AlertNotificationService.instance.notifyHazard(
        title: '左後方車輛逼近',
        body: '建議向右側變換車道',
      );
    }
    if (next.rightDistance < previous.rightDistance) {
      AlertNotificationService.instance.notifyHazard(
        title: '右後方車輛逼近',
        body: '建議向左側變換車道',
      );
    }
    if (next.potholeFrontLeft && !previous.potholeFrontLeft) {
      AlertNotificationService.instance.notifyHazard(
        title: '前方左側坑洞',
        body: '請減速並注意路面',
      );
    }
    if (next.potholeFrontCenter && !previous.potholeFrontCenter) {
      AlertNotificationService.instance.notifyHazard(
        title: '前方中央坑洞',
        body: '請減速並注意路面',
      );
    }
    if (next.potholeFrontRight && !previous.potholeFrontRight) {
      AlertNotificationService.instance.notifyHazard(
        title: '前方右側坑洞',
        body: '請減速並注意路面',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final threats = _threats;
    final alert = _activeAlert;
    final potholeAlertText = _potholeAlertText;

    return Scaffold(
      backgroundColor: HudColors.surface,
      floatingActionButton: FloatingActionButton(
        onPressed: _openSimulationSheet,
        tooltip: '模擬控制',
        child: const Icon(Icons.tune_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: SafeArea(
        child: Column(
          children: [
            _StatusBar(speed: _sim.bikeSpeed.round()),
            _AlertLines(alert: alert),
            _PotholeAlertLine(text: potholeAlertText),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: MapCard(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RadarView(
                threats: threats,
                potholeFrontLeft: _sim.potholeFrontLeft,
                potholeFrontCenter: _sim.potholeFrontCenter,
                potholeFrontRight: _sim.potholeFrontRight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.speed});

  final int speed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '$speed',
            style: textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 6),
          Text('km/h', style: textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// 坑洞提示文字（除了系統通知外，畫面上也常駐顯示目前亮起的坑洞方向）。
class _PotholeAlertLine extends StatelessWidget {
  const _PotholeAlertLine({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: HudColors.warn);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
              child: Text(text!, style: style),
            ),
    );
  }
}

class _AlertInfo {
  const _AlertInfo({required this.label, required this.suggestion});

  final String label;
  final String suggestion;
}

class _AlertLines extends StatelessWidget {
  const _AlertLines({required this.alert});

  final _AlertInfo? alert;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: HudColors.danger);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: alert == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_rounded, size: 18, color: HudColors.warn),
                      const SizedBox(width: 8),
                      Text('${alert!.label}車輛快速逼近', style: titleStyle),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.info_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(alert!.suggestion, style: titleStyle),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
