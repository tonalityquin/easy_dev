class AdjustmentModel {
  final String id;
  final String countType;
  final String area;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  AdjustmentModel({
    required this.id,
    required this.countType,
    required this.area,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  factory AdjustmentModel.fromMap(String id, Map<String, dynamic> data) {
    return AdjustmentModel(
      id: id,
      countType: data['CountType'] ?? '',
      area: data['area'] ?? '',
      basicStandard: int.tryParse(data['basicStandard'].toString()) ?? 0,
      basicAmount: int.tryParse(data['basicAmount'].toString()) ?? 0,
      addStandard: int.tryParse(data['addStandard'].toString()) ?? 0,
      addAmount: int.tryParse(data['addAmount'].toString()) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'CountType': countType,
      'area': area,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
    };
  }
}
