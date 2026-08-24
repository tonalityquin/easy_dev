class OperationalAreaMeta {
  const OperationalAreaMeta({
    required this.area,
    required this.locationsReady,
    required this.generalBillsReady,
    required this.regularBillsReady,
    required this.sectorsReady,
    required this.locationCount,
    required this.generalBillCount,
    required this.regularBillCount,
    required this.sectorCount,
    required this.totalCapacity,
    required this.hasMonthlyParking,
    required this.syncedAt,
  });

  final String area;
  final bool locationsReady;
  final bool generalBillsReady;
  final bool regularBillsReady;
  final bool sectorsReady;
  final int locationCount;
  final int generalBillCount;
  final int regularBillCount;
  final int sectorCount;
  final int totalCapacity;
  final bool? hasMonthlyParking;
  final DateTime? syncedAt;

  bool get billsReady => generalBillsReady && regularBillsReady;
}
