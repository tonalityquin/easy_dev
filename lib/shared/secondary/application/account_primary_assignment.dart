class AccountPrimaryAssignment {
  const AccountPrimaryAssignment._();

  static List<String> normalize(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final name = value.trim();
      if (name.isNotEmpty && seen.add(name)) result.add(name);
    }
    return result;
  }

  static List<String> replacePrimary({
    required Iterable<String> existing,
    required String previousPrimary,
    required String nextPrimary,
    bool retainPreviousPrimary = false,
  }) {
    final previous = previousPrimary.trim();
    final next = nextPrimary.trim();
    if (next.isEmpty) throw StateError('PRIMARY_ASSIGNMENT_REQUIRED');
    final changed = previous.isNotEmpty && previous != next;
    final values = normalize(existing);
    return normalize(<String>[
      next,
      for (final value in values)
        if (value != next && (!changed || value != previous)) value,
      if (changed && retainPreviousPrimary) previous,
    ]);
  }

  static bool primaryChanged({
    required String oldDivision,
    required String oldArea,
    required String newDivision,
    required String newArea,
  }) => oldDivision.trim() != newDivision.trim() ||
      oldArea.trim() != newArea.trim();
}
