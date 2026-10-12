import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chc115/main.dart';

void main() {
  testWidgets('歡迎畫面可用模擬數據進入 HUD，並從選單開啟模擬控制與斷線', (WidgetTester tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();

    expect(find.text('連線'), findsOneWidget);
    expect(find.text('使用模擬數據繼續'), findsOneWidget);

    await tester.tap(find.text('使用模擬數據繼續'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('25'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('斷線'), findsOneWidget);

    await tester.tap(find.text('模擬控制'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('模擬控制'), findsOneWidget);
  });
}
