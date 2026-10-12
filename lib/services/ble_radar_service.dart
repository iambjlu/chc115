import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/simulation_values.dart';

enum BleRadarStatus { idle, scanning, connecting, connected }

/// 與 AMB82 雷達模組（見 arduino/AMB82_Grove_SSCMA.ino）的 BLE 連線服務。
/// 掃描廣播名稱 [deviceName]，連線後訂閱 [txUuid] 的 Notify，將每行
/// 「速度,左距離,左逼近,右距離,右逼近,左前坑洞,正前坑洞,右前坑洞」
/// 解析成 [SimulationValues] 從 [values] 推送出去。
class BleRadarService {
  BleRadarService._();
  static final instance = BleRadarService._();

  static const deviceName = 'AMB82-Radar';
  static final serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final txUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  final status = ValueNotifier<BleRadarStatus>(BleRadarStatus.idle);
  final _values = StreamController<SimulationValues>.broadcast();
  Stream<SimulationValues> get values => _values.stream;

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
    final parsed = parse(utf8.decode(data, allowMalformed: true));
    if (parsed != null) _values.add(parsed);
  }

  /// 解析一行 CSV；格式不符回傳 null。
  @visibleForTesting
  static SimulationValues? parse(String line) {
    final p = line.trim().split(',');
    if (p.length != 8) return null;
    final n = p.map(num.tryParse).toList();
    if (n.any((e) => e == null)) return null;
    return SimulationValues(
      bikeSpeed: n[0]!.toDouble(),
      leftDistance: n[1]!.toDouble(),
      leftApproaching: n[2] != 0,
      rightDistance: n[3]!.toDouble(),
      rightApproaching: n[4] != 0,
      potholeFrontLeft: n[5] != 0,
      potholeFrontCenter: n[6] != 0,
      potholeFrontRight: n[7] != 0,
    );
  }

  Future<void> disconnect() async {
    await FlutterBluePlus.stopScan().catchError((_) {});
    final device = _device;
    _cleanup();
    await device?.disconnect().catchError((_) {});
  }

  void _cleanup() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _dataSub?.cancel();
    _scanSub = _connSub = null;
    _dataSub = null;
    _device = null;
    status.value = BleRadarStatus.idle;
  }
}
