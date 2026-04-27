import 'real_time_table_row_vm.dart';

abstract class NoStrategy {
  List<int> buildNos(
    List<RealTimeRowVM> rows, {
    required bool sortOldFirst,
  });
}

class LinearNoStrategy implements NoStrategy {
  @override
  List<int> buildNos(
    List<RealTimeRowVM> rows, {
    required bool sortOldFirst,
  }) {
    final n = rows.length;
    if (n <= 0) return const <int>[];
    return List<int>.generate(n, (i) => sortOldFirst ? (n - i) : (i + 1));
  }
}

class DayGroupNoStrategy implements NoStrategy {
  String _dayKey(DateTime? dt) {
    if (dt == null) return 'unknown';
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  List<int> buildNos(
    List<RealTimeRowVM> rows, {
    required bool sortOldFirst,
  }) {
    if (rows.isEmpty) return const <int>[];

    final out = List<int>.filled(rows.length, 0);

    int start = 0;
    while (start < rows.length) {
      final k = _dayKey(rows[start].createdAt);
      int end = start + 1;
      while (end < rows.length && _dayKey(rows[end].createdAt) == k) {
        end++;
      }

      final count = end - start;
      for (int i = 0; i < count; i++) {
        out[start + i] = sortOldFirst ? (count - i) : (i + 1);
      }

      start = end;
    }

    return out;
  }
}

class DayNewestRankNoStrategy implements NoStrategy {
  String _dayKey(DateTime? dt) {
    if (dt == null) return 'unknown';
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  List<int> buildNos(
    List<RealTimeRowVM> rows, {
    required bool sortOldFirst,
  }) {
    if (rows.isEmpty) return const <int>[];

    final indicesByDay = <String, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      final k = _dayKey(rows[i].createdAt);
      indicesByDay.putIfAbsent(k, () => <int>[]).add(i);
    }

    final out = List<int>.filled(rows.length, 0);

    for (final e in indicesByDay.entries) {
      final idxs = e.value;

      idxs.sort((ia, ib) {
        final a = rows[ia].createdAt;
        final b = rows[ib].createdAt;

        if (a == null && b == null) {
          return rows[ia].plateId.compareTo(rows[ib].plateId);
        }
        if (a == null) return 1;
        if (b == null) return -1;

        final c = b.compareTo(a);
        if (c != 0) return c;

        return rows[ia].plateId.compareTo(rows[ib].plateId);
      });

      for (int rank = 0; rank < idxs.length; rank++) {
        out[idxs[rank]] = rank + 1;
      }
    }

    return out;
  }
}
