enum FirebaseActivityDocumentCommand { set, create, update, delete }

class FirebaseActivityWriteCounts {
  int sets = 0;
  int creates = 0;
  int updates = 0;
  int deletes = 0;
  int attempts = 0;

  int get total => sets + creates + updates + deletes;

  void add(FirebaseActivityDocumentCommand kind) {
    switch (kind) {
      case FirebaseActivityDocumentCommand.set:
        sets++;
      case FirebaseActivityDocumentCommand.create:
        creates++;
      case FirebaseActivityDocumentCommand.update:
        updates++;
      case FirebaseActivityDocumentCommand.delete:
        deletes++;
    }
  }

  void resetAttempt() {
    sets = 0;
    creates = 0;
    updates = 0;
    deletes = 0;
    attempts++;
  }

  FirebaseActivityWriteCounts copy() => FirebaseActivityWriteCounts()
    ..sets = sets
    ..creates = creates
    ..updates = updates
    ..deletes = deletes
    ..attempts = attempts;
}

class FirebaseActivityWriteScope {
  FirebaseActivityWriteScope._();

  static final Expando<FirebaseActivityWriteCounts> _batches =
      Expando<FirebaseActivityWriteCounts>('firebase_activity_batch');

  static void batchCommand(
    Object batch,
    FirebaseActivityDocumentCommand kind,
    void Function() execute,
  ) {
    execute();
    final counts = _batches[batch] ?? FirebaseActivityWriteCounts();
    counts.add(kind);
    _batches[batch] = counts;
  }

  static FirebaseActivityWriteCounts? takeBatch(Object? batch) {
    if (batch == null) return null;
    final counts = _batches[batch]?.copy();
    _batches[batch] = null;
    return counts;
  }
}
