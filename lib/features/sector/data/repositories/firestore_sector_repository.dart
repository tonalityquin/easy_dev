import '../../domain/models/sector_model.dart';
import '../../domain/repositories/sector_repository.dart';
import '../services/sector_delete_service.dart';
import '../services/sector_read_service.dart';
import '../services/sector_write_service.dart';

class FirestoreSectorRepository implements SectorRepository {
  FirestoreSectorRepository({
    SectorReadService? readService,
    SectorWriteService? writeService,
    SectorDeleteService? deleteService,
  })  : _readService = readService ?? SectorReadService(),
        _writeService = writeService ?? SectorWriteService(),
        _deleteService = deleteService ?? SectorDeleteService();

  final SectorReadService _readService;
  final SectorWriteService _writeService;
  final SectorDeleteService _deleteService;

  @override
  Future<List<SectorModel>> getSectors(String area) {
    return _readService.getSectors(area);
  }

  @override
  Future<SectorModel> addSector({
    required String area,
    required String name,
  }) {
    return _writeService.addSector(area: area, name: name);
  }

  @override
  Future<SectorModel> updateSector({
    required String id,
    required String area,
    required String name,
  }) {
    return _writeService.updateSector(id: id, area: area, name: name);
  }

  @override
  Future<void> deleteSector({
    required String id,
    required String area,
  }) {
    return _deleteService.deleteSector(id: id, area: area);
  }
}
