import '../models/sector_model.dart';

abstract class SectorRepository {
  Future<List<SectorModel>> getSectors(String area);

  Future<SectorModel> addSector({
    required String area,
    required String name,
  });

  Future<SectorModel> updateSector({
    required String id,
    required String area,
    required String name,
  });

  Future<void> deleteSector({
    required String id,
    required String area,
  });
}
