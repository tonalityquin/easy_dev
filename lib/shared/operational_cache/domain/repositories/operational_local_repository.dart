import '../../../../features/location/domain/models/location_model.dart';
import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/payment/domain/models/regular_bill_model.dart';
import '../../../../features/sector/domain/models/sector_model.dart';
import '../models/bill_local_snapshot.dart';
import '../models/operational_area_meta.dart';

abstract interface class OperationalLocalRepository {
  Future<List<LocationModel>> readLocations(String area);

  Future<void> replaceLocations({
    required String area,
    required List<LocationModel> locations,
    required int totalCapacity,
  });

  Future<void> clearLocations(String area);

  Future<bool> hasLocationsSnapshot(String area);

  Future<int> countLocations(String area);

  Future<BillLocalSnapshot> readBills(String area);

  Future<void> replaceBills({
    required String area,
    required List<BillModel> generalBills,
    required List<RegularBillModel> regularBills,
  });

  Future<void> clearBills(String area);

  Future<bool> hasBillsSnapshot(String area);

  Future<int> countGeneralBills(String area);

  Future<int> countRegularBills(String area);

  Future<List<SectorModel>> readSectors(String area);

  Future<void> replaceSectors({
    required String area,
    required List<SectorModel> sectors,
  });

  Future<void> clearSectors(String area);

  Future<bool> hasSectorsSnapshot(String area);

  Future<int> countSectors(String area);

  Future<OperationalAreaMeta?> readAreaMeta(String area);

  Future<void> clearOperationalMetadata(String area);

  Future<void> saveOperationalMetadata({
    required String area,
    required bool hasMonthlyParking,
    required String syncedAtIso,
  });

  Future<void> updateMonthlyParking({
    required String area,
    required bool hasMonthlyParking,
  });
}
