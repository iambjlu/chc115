import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/simulation_values.dart';

enum BleRadarStatus { idle, scanning, connecting, connected }

/// 與 AMB82 雷達模組（見 arduino/AMB82_Grove_SSCMA.ino）的 BLE 連線服務。
/// 掃描廣播名稱 [deviceName]，連線後訂閱 [txUuid] 的 Notify，將每行
/// 「左後距離,右後距離,左後逼近,右後逼近,左前坑,正前坑,右前坑」
/// 解析成 [SimulationValues] 從 [values] 推送出去（格式見 [parse]）。
class BleRadarService {
  BleRadarService._();
  static final instance = BleRadarService._();

  static const deviceName = 'AMB82-Radar';
  static final serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final txUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  final status = ValueNotifier<BleRadarStatus>(BleRadarStatus.idle);
  final _values = StreamController<SimulationValues>.broadcast();
  Stream<SimulationValues> get values => _values.stream;

  SimulationValues _latest = SimulationValues.empty;

  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _dataSub;

  /// 掃描並連線；已在連線/掃描中時忽略。逾時 10 秒找不到裝置就回到 idle。
  Future<void> connect() async {
    if (status.value != BleRadarStatus.idle) return;
    status.value = BleRadarStatus.scanning;
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 5));
      final completer = Completer<BluetoothDevice?>();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          if (r.advertisementData.advName == deviceName ||
              r.advertisementData.serviceUuids.contains(serviceUuid)) {
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      final device = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      if (device == null) {
        status.value = BleRadarStatus.idle;
        return;
      }
      await _connectTo(device);
    } catch (e) {
      debugPrint('BLE connect failed: $e');
      await disconnect();
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    status.value = BleRadarStatus.connecting;
    _device = device;
    _connSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _cleanup();
    });
    await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));
    final services = await device.discoverServices();
    final tx = services
        .where((s) => s.uuid == serviceUuid)
        .expand((s) => s.characteristics)
        .where((c) => c.uuid == txUuid)
        .firstOrNull;
    if (tx == null) throw StateError('找不到雷達 TX characteristic');
    _dataSub = tx.onValueReceived.listen(_onData);
    await tx.setNotifyValue(true);
    status.value = BleRadarStatus.connected;
  }

  void _onData(List<int> data) {
    final parsed = parse(utf8.decode(data, allowMalformed: true), _latest);
    if (parsed == null) return;
    _latest = parsed;
    _values.add(parsed);
  }

  /// 解析一行 7 欄資料，欄位依序為：
  /// 左後距離、右後距離（1 遠／2 中／3 近）、左後逼近、右後逼近、
  /// 左前坑、正前坑、右前坑（1 有／0 沒有）；任何欄位為 9 代表感測錯誤，
  /// 該欄沿用 [base] 的舊值。欄位以逗號分隔，也接受 7 個連續數字。
  /// 格式不符回傳 null。車速不在此協定內，沿用 [base.bikeSpeed]。
  @visibleForTesting
  static SimulationValues? parse(String line, SimulationValues base) {
    final text = line.trim();
    final parts = text.contains(',') ? text.split(',').map((e) => e.trim()).toList() : text.split('');
    if (parts.length != 7) return null;
    final n = parts.map(int.tryParse).toList();
    if (n.any((e) => e == null)) return null;

    double? distance(int code, double old) => switch (code) {
      1 => 30.0, // 遠
      2 => 15.0, // 中
      3 => 5.0, // 近
      _ => code == 9 ? old : null,
    };
    bool? flag(int code, bool old) => switch (code) {
      1 => true,
      0 => false,
      _ => code == 9 ? old : null,
    };

    final left = distance(n[0]!, base.leftDistance);
    final right = distance(n[1]!, base.rightDistance);
    final la = flag(n[2]!, base.leftApproaching);
    final ra = flag(n[3]!, base.rightApproaching);
    final pl = flag(n[4]!, base.potholeFrontLeft);
    final pc = flag(n[5]!, base.potholeFrontCenter);
    final pr = flag(n[6]!, base.potholeFrontRight);
    if ([left, right, la, ra, pl, pc, pr].contains(null)) return null;
    return base.copyWith(
      leftDistance: left,
      rightDistance: right,
      leftApproaching: la,
      rightApproaching: ra,
      potholeFrontLeft: pl,
      potholeFrontCenter: pc,
      potholeFrontRight: pr,
    );
  }

  Future<void> disconnect() async {
    await FlutterBluePlus.stopScan().catchError((_) {});
    final device = _device;
    _cleanup();
    await device?.disconnect().catchError((_) {});
  }

  void _cleanup() {
    _latest = SimulationValues.empty;
    _scanSub?.cancel();
    _connSub?.cancel();
    _dataSub?.cancel();
    _scanSub = _connSub = null;
    _dataSub = null;
    _device = null;
    status.value = BleRadarStatus.idle;
  }
}
