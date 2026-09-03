import 'package:flutter/material.dart';

/// 配色對齊原始參考稿：整體介面為白底、黑字的高對比 HUD，
/// 只有地圖卡片採深色（夜間地圖樣式）。語意色（安全/注意/危險）
/// 與互動用的品牌色（浮動按鈕、模擬面板滑桿）各自獨立。
class HudColors {
  HudColors._();

  // 主畫面：白底
  static const Color surface = Color(0xFFFFFFFF);
  static const Color hairline = Color(0x14000000);

  static const Color ink = Color(0xFF14161A);
  static const Color inkDim = Color(0xFF6B7280);
  static const Color inkFaint = Color(0xFFA8AEB8);

  // 品牌色：僅用於浮動按鈕與模擬面板等互動元件
  static const Color brand = Color(0xFF4A55E0);
  static const Color brandDim = Color(0x1F4A55E0);

  // 語意色：安全 / 注意 / 危險
  static const Color safe = Color(0xFF2FAE60);
  static const Color safeDim = Color(0x1F2FAE60);
  static const Color warn = Color(0xFFF0A825);
  static const Color warnDim = Color(0x24F0A825);
  static const Color danger = Color(0xFFE13B32);
  static const Color dangerDim = Color(0x1FE13B32);
}
