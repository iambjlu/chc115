import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chc115/main.dart';

void main() {
  testWidgets('歡迎畫面：標題、連線按鈕，模擬數據按鈕預設隱藏、長按連線後顯示', (tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();
    expect(find.text('自行車警示系統'), findsOneWidget);
    expect(find.text('連線'), findsOneWidget);
    expect(find.textContaining('MAC'), findsNothing);
    expect(find.text('使用模擬數據繼續'), findsNothing);

    await tester.longPress(find.text('連線'));
    await tester.pump();
    expect(find.text('使用模擬數據繼續'), findsOneWidget);

    await tester.tap(find.text('使用模擬數據繼續'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('25'), findsOneWidget);
    expect(find.text('BLE 板子模擬資料', findRichText: true, skipOffstage: false), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('斷線'), findsOneWidget);
    expect(find.text('模擬控制'), findsOneWidget);
  });
}
