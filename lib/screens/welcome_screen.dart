import 'dart:io';
import 'package:flutter/material.dart';

import '../services/ble_radar_service.dart';
import '../theme/hud_colors.dart';
import 'ride_hud_screen.dart';

/// 啟動後的歡迎畫面：按「連線」搜尋並連上 AMB82 雷達模組後進入 HUD（藍牙數據），
/// 底下小字「使用模擬數據繼續」則直接進入 HUD 並使用模擬控制面板。
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _ble = BleRadarService.instance;
  String? _error;

  Future<void> _connect({bool direct = false}) async {
    setState(() => _error = null);
    await _ble.connect(direct: direct);
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
                  Text('騎乘後方雷達', style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('連線 AMB82-Radar，接收板子模擬資料。\n目前尚非真實人物、車輛或坑洞辨識。',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(color: HudColors.inkDim)),
                  const Spacer(flex: 3),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _connect(),
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
                  if (Platform.isAndroid)
                    TextButton(
                      onPressed: busy ? null : () => _connect(direct: true),
                      child: const Text('以 MAC 直接連線\n${BleRadarService.deviceMac}', textAlign: TextAlign.center),
                    ),
                  TextButton(
                    onPressed: busy ? null : () => _openHud(RideHudMode.simulation),
                    child: Text('使用模擬數據繼續',
                        style: textTheme.bodySmall?.copyWith(color: HudColors.inkDim)),
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
