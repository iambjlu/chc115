import 'package:flutter/material.dart';
import '../services/ble_radar_service.dart';

class BleConnectionBanner extends StatelessWidget {
  const BleConnectionBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final ble = BleRadarService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([ble.dataStatus, ble.receivedCount, ble.rawPacket]),
      builder: (context, _) {
        final label = switch (ble.dataStatus.value) {
          RadarDataStatus.waiting => '已連線，等待資料',
          RadarDataStatus.receiving => '接收中',
          RadarDataStatus.stale => '超過 5 秒未收到有效資料',
          RadarDataStatus.invalid => '資料格式或感測狀態異常',
        };
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.amber.shade100,
          child: Text(
            'BLE 板子模擬資料・$label・${ble.receivedCount.value} 筆\n'
            '${ble.rawPacket.value.isEmpty ? "等待封包…" : ble.rawPacket.value}\n'
            '遠／中／近為模擬等級；本協定未提供車速。',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        );
      },
    );
  }
}
