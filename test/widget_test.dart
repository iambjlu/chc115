import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chc115/main.dart';

void main() {
  testWidgets('HUD shows initial speed and opens simulation sheet', (WidgetTester tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();

    expect(find.text('25'), findsOneWidget);
    expect(find.text('km/h'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('模擬控制'), findsOneWidget);
  });
}
