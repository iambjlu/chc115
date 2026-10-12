import 'package:flutter/material.dart';

import '../services/ble_radar_service.dart';
import '../theme/hud_colors.dart';
import 'ride_hud_screen.dart';

/// 啟動後的歡迎畫面：按「連線」搜尋並連上 AMB82 雷達模組後進入 HUD（藍牙數據），
/// 「使用模擬數據繼續」預設隱藏，長按「連線」按鈕才會顯示（不存檔，重開 App 即恢復隱藏）。
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _ble = BleRadarService.instance;
  String? _error;
  bool _showSimulation = false;

  Future<void> _connect() async {
    setState(() => _error = null);
    await _ble.connect();
    if (!mounted) return;
    if (_ble.status.value == BleRadarStatus.connected) {
      await _openHud(RideHudMode.ble);
    } else {
      final error = _ble.lastError.value ?? '連線未完成，請重試';
      setState(() => _error = error);
      await _showError(error);
    }
  }

  Future<void> _showError(String error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('藍牙連線失敗'),
        content: SingleChildScrollView(child: SelectableText(error)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('確定')),
        ],
      ),
    );
  }

  Future<void> _openHud(RideHudMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RideHudScreen(mode: mode)),
    );
    if (mode == RideHudMode.ble) await _ble.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: HudColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ValueListenableBuilder<BleRadarStatus>(
            valueListenable: _ble.status,
            builder: (context, status, _) {
              final busy = status == BleRadarStatus.scanning || status == BleRadarStatus.connecting;
              return Column(
                children: [
                  const Spacer(flex: 3),
                  Image.asset('assets/bike.png', height: 140),
                  const SizedBox(height: 28),
                  Text('自行車警示系統', style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: HudColors.inkDim)),
                  const Spacer(flex: 3),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _connect,
                      onLongPress: busy ? null : () => setState(() => _showSimulation = true),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.bluetooth_rounded),
                      label: Text(
                        switch (status) {
                          BleRadarStatus.scanning => '搜尋中…',
                          BleRadarStatus.connecting => '連線中…',
                          _ => '連線',
                        },
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 100,
                    child: _error == null
                        ? null
                        : Text(_error!,
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(color: HudColors.danger)),
                  ),
                  // 固定保留按鈕高度，顯示/隱藏時不會讓上方版面位移。
                  SizedBox(
                    height: 48,
                    child: _showSimulation
                        ? TextButton(
                            onPressed: busy ? null : () => _openHud(RideHudMode.simulation),
                            child: Text('使用模擬數據繼續',
                                style: textTheme.bodySmall?.copyWith(color: HudColors.inkDim)),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
