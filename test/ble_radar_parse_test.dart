import 'package:chc115/models/simulation_values.dart';
import 'package:chc115/services/ble_radar_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = SimulationValues.demo;

  test('解析範例 3,1,1,0,1,0,1', () {
    final v = BleRadarService.parse('3,1,1,0,1,0,1\n', base)!;
    expect(v.leftDistance, 5);
    expect(v.rightDistance, 30);
    expect(v.leftApproaching, true);
    expect(v.rightApproaching, false);
    expect(v.potholeFrontLeft, true);
    expect(v.potholeFrontCenter, false);
    expect(v.potholeFrontRight, true);
    expect(v.bikeSpeed, base.bikeSpeed);
  });
  test('也接受連續數字', () {
    expect(BleRadarService.parse('3110101', base)!.leftDistance, 5);
  });
  test('9 代表錯誤，沿用舊值', () {
    final v = BleRadarService.parse('9,2,9,1,9,9,9', base)!;
    expect(v.leftDistance, base.leftDistance);
    expect(v.rightDistance, 15);
    expect(v.leftApproaching, base.leftApproaching);
    expect(v.rightApproaching, true);
    expect(v.potholeFrontCenter, base.potholeFrontCenter);
  });
  test('格式或數值錯誤回傳 null', () {
    expect(BleRadarService.parse('1,2,3', base), isNull);
    expect(BleRadarService.parse('a,b,c,d,e,f,g', base), isNull);
    expect(BleRadarService.parse('4,1,1,0,1,0,1', base), isNull);
    expect(BleRadarService.parse('1,1,2,0,1,0,1', base), isNull);
  });
}
