class RealTimeRowVM {
  final String plateId;
  final String plateNumber;
  final String location;
  final DateTime? primaryAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final bool isSelected;
  final String? selectedBy;

  const RealTimeRowVM({
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.primaryAt,
    required this.updatedAt,
    required this.createdAt,
    this.isSelected = false,
    this.selectedBy,
  });
}
