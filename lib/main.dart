import 'package:flutter/material.dart';

import 'screens/ride_hud_screen.dart';
import 'services/alert_notification_service.dart';
import 'theme/hud_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlertNotificationService.instance.init();
  runApp(const RideHudApp());
}

class RideHudApp extends StatelessWidget {
  const RideHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'chc11509',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: HudColors.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: HudColors.brand,
          brightness: Brightness.light,
        ),
      ),
      home: const RideHudScreen(),
    );
  }
}
