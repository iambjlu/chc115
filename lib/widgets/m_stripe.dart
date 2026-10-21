import 'package:flutter/material.dart';

import '../theme/hud_colors.dart';

/// 畫面邊緣的 M 三色條（淺藍／深藍／紅）。
class MStripe extends StatelessWidget {
  const MStripe({super.key, this.height = 4});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: const Row(
        children: [
          Expanded(child: ColoredBox(color: HudColors.mLightBlue)),
          Expanded(child: ColoredBox(color: HudColors.mBlue)),
          Expanded(child: ColoredBox(color: HudColors.mRed)),
        ],
      ),
    );
  }
}
