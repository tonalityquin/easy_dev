import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';

enum FirebaseActivityDocumentCommand { set, create, update, delete }

class FirebaseActivityWriteCounts {
  int sets = 0;
  int creates = 0;
  int updates = 0;
  int deletes = 0;
  int attempts = 0;
  int? operationId;
  int? parentOperationId;
  bool parentCaptured = false;
  bool submitted = false;

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
    ..attempts = attempts
    ..operationId = operationId
    ..parentOperationId = parentOperationId
    ..parentCaptured = parentCaptured
    ..submitted = submitted;
}

class FirebaseActivityWriteScope {
  FirebaseActivityWriteScope._();

  static final Expando<FirebaseActivityWriteCounts> _batches =
      Expando<FirebaseActivityWriteCounts>('firebase_activity_batch');
  static void Function(FirebaseActivityWriteCounts counts)? onBatchChanged;
  static void Function(FirebaseActivityWriteCounts counts)? onBatchCancelled;

  static FirebaseActivityWriteCounts? inspectBatch(Object? batch) =>
      batch == null ? null : _batches[batch];

  static void batchCommand(
    Object batch,
    FirebaseActivityDocumentCommand kind,
    void Function() execute,
  ) {
    final counts = _batches[batch] ?? FirebaseActivityWriteCounts();
    if (counts.submitted) {
      throw StateError('firebase_batch_already_submitted');
    }
    execute();
    counts.add(kind);
    _batches[batch] = counts;
    _notifyObserver(onBatchChanged, counts);
  }

  static void cancelBatch(Object batch) {
    final counts = _batches[batch];
    if (counts == null || counts.submitted) return;
    _batches[batch] = null;
    _notifyObserver(onBatchCancelled, counts);
  }

  static void _notifyObserver(
    void Function(FirebaseActivityWriteCounts counts)? observer,
    FirebaseActivityWriteCounts counts,
  ) {
    if (observer == null) return;
    try {
      observer(counts);
    } catch (error) {
      if (DevAuth.devModeEnabled.value) {
        try {
          debugPrint('[FIREBASE_ACTIVITY] observerFailure=${error.runtimeType}');
        } catch (_) {}
      }
    }
  }

  static void markSubmitted(Object? batch) {
    if (batch == null) return;
    final counts = _batches[batch];
    if (counts == null) return;
    counts.submitted = true;
  }

  static FirebaseActivityWriteCounts? takeBatch(Object? batch) {
    if (batch == null) return null;
    final counts = _batches[batch]?.copy();
    _batches[batch] = null;
    return counts;
  }
}
