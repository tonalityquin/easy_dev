import '../models/status_model.dart';

abstract class StatusRepository {
  Stream<List<StatusModel>> getStatusStream(String area);
  Future<void> addToggleItem(StatusModel status);
  Future<void> updateToggleStatus(String id, bool isActive);
  Future<void> deleteToggleItem(String id);
}
