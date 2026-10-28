import '../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountAssignmentResolver {
  const AccountAssignmentResolver._();

  static Future<Map<String, Set<String>>> load(
    Iterable<String> divisions,
  ) async {
    final normalized = divisions
        .map((division) => division.trim())
        .where((division) => division.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final result = <String, Set<String>>{};
    for (var index = 0; index < normalized.length; index += 10) {
      final end = index + 10 < normalized.length
          ? index + 10
          : normalized.length;
      final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
          .collection('areas')
          .where('division', whereIn: normalized.sublist(index, end))
          .get(const GetOptions(source: Source.server)), source: 'account_assignment_resolver.get');
      for (final document in snapshot.docs) {
        final data = document.data();
        final name = (data['name'] ?? '').toString().trim();
        final division = (data['division'] ?? '').toString().trim();
        if (name.isEmpty || !normalized.contains(division)) continue;
        result.putIfAbsent(name, () => <String>{}).add(division);
      }
    }
    return result;
  }
}
