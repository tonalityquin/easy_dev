import '../../models/adjustment_model.dart';

abstract class AdjustmentRepository {
  Stream<List<AdjustmentModel>> getAdjustmentStream(String currentArea);

  Future<void> addAdjustment(AdjustmentModel adjustment);

  Future<void> deleteAdjustment(List<String> ids);
}
