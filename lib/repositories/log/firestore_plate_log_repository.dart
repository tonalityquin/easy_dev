import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/plate_log_model.dart';
import 'plate_log_repository.dart';

class FirestorePlateLogRepository implements PlateLogRepository {
  final _collection = FirebaseFirestore.instance
      .collection('logs')
      .doc('plate_movements')
      .collection('entries');

  @override
  Future<void> savePlateLog(PlateLogModel log) async {
    await _collection.add(log.toMap());
  }
}
