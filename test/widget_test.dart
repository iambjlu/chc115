import 'package:flutter_test/flutter_test.dart';
import 'package:chc115/main.dart';
void main() {
  testWidgets('Welcome exposes BLE connection and labels simulation', (tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();
    expect(find.text('連線'), findsOneWidget);
    expect(find.text('使用模擬數據繼續'), findsOneWidget);
    expect(find.textContaining('尚非真實'), findsOneWidget);
  });
}
