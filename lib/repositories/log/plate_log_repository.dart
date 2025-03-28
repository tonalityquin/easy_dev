import '../../models/plate_log_model.dart';

abstract class PlateLogRepository {
  Future<void> savePlateLog(PlateLogModel log);
}
