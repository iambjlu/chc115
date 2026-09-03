import 'package:flutter/foundation.dart';

/// 模擬面板目前的數值狀態：自身車速、左右後方車輛的距離（下拉選單挑選）
/// 與是否正在逼近（開關），以及前方三個方向的坑洞預警開關。
@immutable
class SimulationValues {
  const SimulationValues({
    required this.bikeSpeed,
    required this.leftDistance,
    required this.leftApproaching,
    required this.rightDistance,
    required this.rightApproaching,
    required this.potholeFrontLeft,
    required this.potholeFrontCenter,
    required this.potholeFrontRight,
  });

  static const demo = SimulationValues(
    bikeSpeed: 25,
    leftDistance: 30, // 遠
    leftApproaching: false,
    rightDistance: 5, // 近
    rightApproaching: true,
    potholeFrontLeft: false,
    potholeFrontCenter: true,
    potholeFrontRight: false,
  );

  final double bikeSpeed;
  final double leftDistance;
  final bool leftApproaching;
  final double rightDistance;
  final bool rightApproaching;
  final bool potholeFrontLeft;
  final bool potholeFrontCenter;
  final bool potholeFrontRight;

  SimulationValues copyWith({
    double? bikeSpeed,
    double? leftDistance,
    bool? leftApproaching,
    double? rightDistance,
    bool? rightApproaching,
    bool? potholeFrontLeft,
    bool? potholeFrontCenter,
    bool? potholeFrontRight,
  }) {
    return SimulationValues(
      bikeSpeed: bikeSpeed ?? this.bikeSpeed,
      leftDistance: leftDistance ?? this.leftDistance,
      leftApproaching: leftApproaching ?? this.leftApproaching,
      rightDistance: rightDistance ?? this.rightDistance,
      rightApproaching: rightApproaching ?? this.rightApproaching,
      potholeFrontLeft: potholeFrontLeft ?? this.potholeFrontLeft,
      potholeFrontCenter: potholeFrontCenter ?? this.potholeFrontCenter,
      potholeFrontRight: potholeFrontRight ?? this.potholeFrontRight,
    );
  }
}
