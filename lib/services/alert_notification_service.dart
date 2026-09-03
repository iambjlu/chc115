import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 危險事件的分類，每一類在系統通知中各自固定一個通知 id，
/// 因此同一類的新通知會直接覆蓋舊通知，畫面上只會保留該類最新的一則。
enum HazardCategory {
  pothole, // 坑洞：左前/正前/右前共用同一則通知
  approaching, // 逼近車輛：左右後方共用同一則通知
  distanceShortening, // 距離縮短：左右後方共用同一則通知
}

/// 坑洞、障礙物、車輛逼近等危險事件的警示單例。
///
/// Android：走 `flutter_local_notifications` 系統通知（max importance + heads-up）。
/// iOS：實測發現即使已授權，前景時系統通知橫幅仍時常不會顯示（`timeSensitive`
/// 等級需要額外的時效性通知 entitlement，一般權限也無法保證前景橫幅一定跳出），
/// 因此 iOS 完全不申請通知權限、不使用 `UNUserNotificationCenter`，改用
/// `audioplayers` 播放內建的 `assets/sounds/alert.wav` 提示音——音訊 session
/// 類別設為 `playback`，即使手機切成靜音（響鈴/靜音切換鍵）也會照常出聲，
/// 這點 `SystemSound.play()` 做不到（一定會被靜音鍵靜音）。畫面上則由
/// `RideHudScreen` 改用 SnackBar 顯示在畫面底部，取代系統通知橫幅。
/// 兩平台都搭配一段較長的觸覺震動（連續多次 `heavyImpact`），讓騎士即使
/// 沒看螢幕也能感知警示。
class AlertNotificationService {
  AlertNotificationService._();

  static final AlertNotificationService instance = AlertNotificationService._();

  static const _channelId = 'ride_hazard_alerts';
  static const _channelName = '騎乘危險警示';
  static const _channelDescription = '坑洞、障礙物與車輛逼近的即時警示通知';
  static const _alertSoundAsset = 'sounds/alert.wav';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final AudioPlayer _iosPlayer = AudioPlayer();

  Future<void> init() async {
    if (Platform.isIOS) {
      // playback 類別會忽略手機的靜音切換鍵，確保警示音一定聽得到。
      await _iosPlayer.setAudioContext(
        AudioContext(iOS: AudioContextIOS(category: AVAudioSessionCategory.playback)),
      );
      return; // iOS 不使用系統通知，見上方類別註解。
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: false, // 震動由 HapticFeedback 統一觸發，避免重複震動
          ),
        );

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // Android：用同一個 category 固定同一個通知 id 呼叫 _plugin.show，讓新通知
  // 直接覆蓋舊通知，達到「該類別只保留最新一則」的效果。
  // iOS：不發系統通知，只播放提示音＋較長震動（前景/背景皆會觸發）；畫面上的
  // SnackBar 由呼叫端（RideHudScreen）另外處理，因為此服務沒有 BuildContext。
  Future<void> notifyHazard({
    required HazardCategory category,
    required String title,
    required String body,
  }) async {
    if (Platform.isIOS) {
      await _iosPlayer.stop();
      unawaited(_iosPlayer.play(AssetSource(_alertSoundAsset)));
      await _longVibration();
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    await _plugin.show(
      id: category.index,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
    await _longVibration();
  }

  // 連續三次重擊震動、中間間隔 150ms，模擬出比單次 heavyImpact 更長的震動感。
  Future<void> _longVibration() async {
    for (var i = 0; i < 3; i++) {
      HapticFeedback.heavyImpact();
      if (i < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}
