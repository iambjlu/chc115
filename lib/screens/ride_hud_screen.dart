import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/simulation_values.dart';
import '../models/vehicle_threat.dart';
import '../services/alert_notification_service.dart';
import '../services/ble_radar_service.dart';
import '../theme/hud_colors.dart';
import '../widgets/map_card.dart';
import '../widgets/radar_view.dart';
import '../widgets/simulation_sheet.dart';

/// HUD 的資料來源：藍牙（AMB82 板子）或手動模擬面板。
enum RideHudMode { ble, simulation }

/// 騎乘中的後方雷達 HUD 主畫面：白底車速讀數、警示文字、深色夜間地圖、
/// 白底雷達視圖，左下角浮動按鈕開啟模擬控制面板。
class RideHudScreen extends StatefulWidget {
  const RideHudScreen({super.key, this.mode = RideHudMode.simulation});

  final RideHudMode mode;

  @override
  State<RideHudScreen> createState() => _RideHudScreenState();
}

class _RideHudScreenState extends State<RideHudScreen> {
  late SimulationValues _sim =
      widget.mode == RideHudMode.ble
          ? BleRadarService.instance.latest
          : SimulationValues.demo;
  StreamSubscription<SimulationValues>? _bleSub;
  StreamSubscription<Position>? _gpsSub;
  // 藍牙模式的車速（km/h）來自 GPS；尚未取得定位或權限被拒時為 null，顯示「—」。
  int? _gpsSpeed;
  ScaffoldMessengerState? _messenger;

  bool get _isBle => widget.mode == RideHudMode.ble;

  @override
  void initState() {
    super.initState();
    if (_isBle) {
      BleRadarService.instance.dataStatus.addListener(_onDataStatus);
      // 藍牙收到的數據與模擬面板走同一條路徑（含通知比對）。
      _bleSub = BleRadarService.instance.values.listen(
        (v) => _applySimulationValues(v.copyWith(bikeSpeed: _sim.bikeSpeed)),
      );
      // 連線中斷（板子斷電、離開範圍）時自動回到歡迎畫面。
      BleRadarService.instance.status.addListener(_onBleStatus);
      unawaited(_startGps());
    }
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }
      if (!mounted) return;
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).listen((p) {
        // m/s 換算 km/h；speed 可能為負（無效），低於 1 km/h 視為靜止以免漂移。
        final kmh = p.speed < 0 ? 0.0 : p.speed * 3.6;
        final next = kmh < 1 ? 0 : kmh.round();
        if (mounted && next != _gpsSpeed) setState(() => _gpsSpeed = next);
      });
    } catch (e) {
      debugPrint('[GPS] 無法取得車速：$e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // 保險：離開此頁時一併撤銷 SnackBar（它掛在全域 ScaffoldMessenger 上，不會隨頁面消失）。
    _messenger?.clearSnackBars();
    _bleSub?.cancel();
    _gpsSub?.cancel();
    if (_isBle) {
      BleRadarService.instance.status.removeListener(_onBleStatus);
      BleRadarService.instance.dataStatus.removeListener(_onDataStatus);
    }
    super.dispose();
  }

  void _onDataStatus() {
    if (mounted) setState(() {});
  }

  void _onBleStatus() {
    if (BleRadarService.instance.status.value == BleRadarStatus.idle &&
        mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _disconnect() async {
    if (_isBle) {
      await BleRadarService.instance.disconnect();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

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
      return const _AlertInfo(label: '左右後方');
    }
    final threat = approaching.first;
    return _AlertInfo(label: threat.label);
  }

  // 依左前/正前/右前順序列出目前亮起的坑洞方向，多個方向用「、」分隔。
  String? get _potholeAlertText {
    final directions = <String>[
      if (_sim.potholeFrontLeft) '左前',
      if (_sim.potholeFrontCenter) '正前',
      if (_sim.potholeFrontRight) '右前',
    ];
    if (directions.isEmpty) return null;
    return '請注意${directions.join('、')}坑洞';
  }

  void _openSimulationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => SimulationSheet(
            initialValues: _sim,
            onChanged: _applySimulationValues,
          ),
    );
  }

  // 通知依「坑洞／逼近車輛／距離縮短」三個類別各自固定一個通知 id
  // （見 AlertNotificationService.HazardCategory），同類別新通知會覆蓋
  // 舊通知，因此畫面上每個類別永遠只會保留最新的一則：
  // - 距離縮短：左右後方只要新距離比前一次更近就觸發，不論
  //   leftApproaching/rightApproaching 開關是否開啟。
  // - 逼近車輛：由假變真才觸發，避免逼近開關持續開啟時反覆通知。
  // - 坑洞：同樣由假變真才觸發，避免同一坑洞持續開啟時反覆通知。
  void _applySimulationValues(SimulationValues next) {
    final previous = _sim;
    setState(() => _sim = next);

    if (next.leftDistance < previous.leftDistance) {
      _notifyHazard(
        category: HazardCategory.distanceShortening,
        title: '左後方車輛逐漸接近',
        body: '與後方車輛距離持續縮短',
      );
    }
    if (next.rightDistance < previous.rightDistance) {
      _notifyHazard(
        category: HazardCategory.distanceShortening,
        title: '右後方車輛逐漸接近',
        body: '與後方車輛距離持續縮短',
      );
    }
    if (next.leftApproaching && !previous.leftApproaching) {
      _notifyHazard(
        category: HazardCategory.approaching,
        title: '左後方車輛逼近',
        body: '左後方車輛正在逼近中',
      );
    }
    if (next.rightApproaching && !previous.rightApproaching) {
      _notifyHazard(
        category: HazardCategory.approaching,
        title: '右後方車輛逼近',
        body: '右後方車輛正在逼近中',
      );
    }
    if (next.potholeFrontLeft && !previous.potholeFrontLeft) {
      _notifyHazard(
        category: HazardCategory.pothole,
        title: '前方左側坑洞',
        body: '請減速並注意路面',
      );
    }
    if (next.potholeFrontCenter && !previous.potholeFrontCenter) {
      _notifyHazard(
        category: HazardCategory.pothole,
        title: '前方中央坑洞',
        body: '請減速並注意路面',
      );
    }
    if (next.potholeFrontRight && !previous.potholeFrontRight) {
      _notifyHazard(
        category: HazardCategory.pothole,
        title: '前方右側坑洞',
        body: '請減速並注意路面',
      );
    }
  }

  // iOS 不使用系統通知（見 AlertNotificationService 說明），改在畫面底部
  // 用 SnackBar 顯示同樣的標題／內文，取代系統通知橫幅；Android 則維持
  // 只靠系統通知呈現，不疊加 SnackBar。
  void _notifyHazard({
    required HazardCategory category,
    required String title,
    required String body,
  }) {
    AlertNotificationService.instance.notifyHazard(
      category: category,
      title: title,
      body: body,
    );
    if (Platform.isIOS) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: HudColors.danger,
            duration: const Duration(seconds: 3),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(body, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData =
        !_isBle ||
        BleRadarService.instance.dataStatus.value == RadarDataStatus.receiving;
    final threats = _threats;
    final alert = _activeAlert;
    final potholeAlertText = _potholeAlertText;

    // 一開始返回歡迎畫面（含手勢返回、斷線）就立刻撤銷 SnackBar，不等轉場動畫結束。
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _messenger?.clearSnackBars();
      },
      child: Scaffold(
        backgroundColor: HudColors.surface,
        floatingActionButton: PopupMenuButton<_HudMenu>(
          tooltip: '選單',
          position: PopupMenuPosition.over,
          onSelected:
              (item) => switch (item) {
                _HudMenu.simulation => _openSimulationSheet(),
                _HudMenu.disconnect => _disconnect(),
              },
          itemBuilder:
              (context) => [
                if (!_isBle)
                  const PopupMenuItem(
                    value: _HudMenu.simulation,
                    child: ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text('模擬控制'),
                    ),
                  ),
                const PopupMenuItem(
                  value: _HudMenu.disconnect,
                  child: ListTile(
                    leading: Icon(Icons.bluetooth_disabled_rounded),
                    title: Text('斷線'),
                  ),
                ),
              ],
          child: IgnorePointer(
            child: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.menu_rounded),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        body: SafeArea(
          child: Column(
            children: [
              // Android 的 heads-up 通知會蓋住最上方，預留空間避免擋到車速。
              if (Platform.isAndroid) const SizedBox(height: 48),
              _StatusBar(speed: _isBle ? _gpsSpeed : _sim.bikeSpeed.round()),
              _AlertLines(alert: hasData ? alert : null),
              _PotholeAlertLine(text: hasData ? potholeAlertText : null),
              const SizedBox(height: 14),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: MapCard(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child:
                    !hasData
                        ? const Center(child: Text('尚無有效資料，雷達暫停顯示'))
                        : RadarView(
                          threats: threats,
                          potholeFrontLeft: _sim.potholeFrontLeft,
                          potholeFrontCenter: _sim.potholeFrontCenter,
                          potholeFrontRight: _sim.potholeFrontRight,
                        ),
              ),
              if (_isBle && BleRadarService.instance.debugMode.value)
                const _RawDataPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 除錯模式：雷達下方列出收到的原始資料（新的在最上面）。
class _RawDataPanel extends StatelessWidget {
  const _RawDataPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
      padding: const EdgeInsets.all(8),
      color: Colors.black,
      child: ValueListenableBuilder<List<String>>(
        valueListenable: BleRadarService.instance.rawLog,
        builder:
            (context, lines, _) => lines.isEmpty
                ? const Text(
                    '等待原始資料…',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  )
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder:
                        (context, i) => Text(
                          lines[i],
                          style: TextStyle(
                            color: lines[i].endsWith('✓')
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontFamily: 'Menlo',
                            fontSize: 11,
                          ),
                        ),
                  ),
      ),
    );
  }
}

enum _HudMenu { simulation, disconnect }

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.speed});

  final int? speed;

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
            speed?.toString() ?? '—',
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
/// 樣式比照後方車輛逼近警示（Icon + 粗體文字），並固定保留一行高度，
/// 避免在「有坑洞提示」與「無坑洞提示」間切換時造成下方 MapCard／
/// 雷達視圖位移，因此以 `AnimatedOpacity` 淡入淡出取代整塊展開/收合。
class _PotholeAlertLine extends StatelessWidget {
  const _PotholeAlertLine({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: HudColors.danger,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: text == null ? 0 : 1,
        child: Row(
          children: [
            const Icon(Icons.warning_rounded, size: 18, color: HudColors.warn),
            const SizedBox(width: 8),
            Text(text ?? ' ', style: titleStyle),
          ],
        ),
      ),
    );
  }
}

class _AlertInfo {
  const _AlertInfo({required this.label});

  final String label;
}

class _AlertLines extends StatelessWidget {
  const _AlertLines({required this.alert});

  final _AlertInfo? alert;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: HudColors.danger,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: alert == null ? 0 : 1,
        child: Row(
          children: [
            const Icon(Icons.warning_rounded, size: 18, color: HudColors.warn),
            const SizedBox(width: 8),
            Text(
              alert == null ? ' ' : '${alert!.label}車輛快速逼近',
              style: titleStyle,
            ),
          ],
        ),
      ),
    );
  }
}
