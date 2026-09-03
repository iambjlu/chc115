import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 危險事件的分類，每一類在系統通知中各自固定一個通知 id，
/// 因此同一類的新通知會直接覆蓋舊通知，畫面上只會保留該類最新的一則。
enum HazardCategory {
  pothole, // 坑洞：左前/正前/右前共用同一則通知
  approaching, // 逼近車輛：左右後方共用同一則通知
  distanceShortening, // 距離縮短：左右後方共用同一則通知
}

/// 坑洞、障礙物、車輛逼近等危險事件的系統通知。
/// 使用高優先權（Android: max importance + heads-up、iOS: 前景也彈出+聲音），
/// 並搭配一次觸覺震動，讓騎士即使沒看螢幕也能感知警示。
class AlertNotificationService {
  AlertNotificationService._();

  static final AlertNotificationService instance = AlertNotificationService._();

  static const _channelId = 'ride_hazard_alerts';
  static const _channelName = '騎乘危險警示';
  static const _channelDescription = '坑洞、障礙物與車輛逼近的即時警示通知';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
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
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: false, sound: true);
  }

  // 用同一個 category 固定同一個通知 id 呼叫 _plugin.show，讓新通知直接
  // 覆蓋舊通知，達到「該類別只保留最新一則」的效果。
  Future<void> notifyHazard({
    required HazardCategory category,
    required String title,
    required String body,
  }) async {
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
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      id: category.index,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
    HapticFeedback.heavyImpact(); // 一次震動
  }
}
