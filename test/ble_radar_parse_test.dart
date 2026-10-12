import 'package:chc115/services/ble_radar_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析雷達 CSV', () {
    final v = BleRadarService.parse('25,30,0,5,1,0,1,0\n')!;
    expect(v.bikeSpeed, 25);
    expect(v.leftDistance, 30);
    expect(v.leftApproaching, false);
    expect(v.rightDistance, 5);
    expect(v.rightApproaching, true);
    expect(v.potholeFrontCenter, true);
  });
  test('格式錯誤回傳 null', () {
    expect(BleRadarService.parse('1,2,3'), isNull);
    expect(BleRadarService.parse('a,b,c,d,e,f,g,h'), isNull);
  });
}
