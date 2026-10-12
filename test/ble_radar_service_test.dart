import 'package:flutter_test/flutter_test.dart';
import 'package:chc115/models/simulation_values.dart';
import 'package:chc115/services/ble_radar_service.dart';
void main() {
  const base = SimulationValues.empty;
  test('decodes firmware CSV without newline', () {
    final v = BleRadarService.parse('1,3,0,1,0,0,0', base)!;
    expect(v.leftDistance, 30);
    expect(v.rightDistance, 5);
    expect(v.leftApproaching, false);
    expect(v.rightApproaching, true);
    expect(v.potholeFrontCenter, false);
    expect(v.bikeSpeed, base.bikeSpeed);
  });
  test('all twelve firmware phases have matching flags', () {
    for (var t = 0; t < 12; t++) {
      final left = t < 4 ? 1 : (t < 8 ? 2 : 3);
      final right = 3 - ((t ~/ 3) % 3);
      final packet = '$left,$right,${left == 3 ? 1 : 0},${right == 3 ? 1 : 0},'
          '${t == 3 ? 1 : 0},${t == 6 || t == 7 ? 1 : 0},${t == 10 ? 1 : 0}';
      final v = BleRadarService.parse(packet, base)!;
      expect(v.potholeFrontLeft, t == 3);
      expect(v.potholeFrontCenter, t == 6 || t == 7);
      expect(v.potholeFrontRight, t == 10);
    }
  });
  test('rejects partial, combined, malformed and sensor-error packets', () {
    for (final packet in ['', '1,3,0', '1,3,0,1,0,0,0,0',
      '1,3,2,1,0,0,0', '0,3,0,1,0,0,0', '1,9,0,1,0,0,0',
      '1,3,0,1,9,0,0', 'x,3,0,1,0,0,0',
      '1,3,0,1,0,0,0\n1,3,0,1,0,0,0']) {
      expect(BleRadarService.parse(packet, base), isNull, reason: packet);
    }
  });
  test('accepts whitespace and compact legacy packet', () {
    expect(BleRadarService.parse(' 2,1,1,0,1,0,1\r\n', base), isNotNull);
    expect(BleRadarService.parse('2110101', base), isNotNull);
  });
}
