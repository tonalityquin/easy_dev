import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firestore_document_sizer.dart';

enum FirebaseActivityDocumentCommand { set, create, update, delete }

class FirestoreWriteMetric {
  const FirestoreWriteMetric({
    required this.kind,
    required this.bytes,
    required this.fields,
    required this.sizeKnown,
    this.indexWriteUnits = 0,
    this.documentPath,
  });

  final FirebaseActivityDocumentCommand kind;
  final int bytes;
  final int fields;
  final bool sizeKnown;
  final int indexWriteUnits;
  final String? documentPath;
}

class FirebaseActivityWriteCounts {
  int sets = 0;
  int creates = 0;
  int updates = 0;
  int deletes = 0;
  int attempts = 0;
  int dataBytes = 0;
  int dataFields = 0;
  final List<FirestoreWriteMetric> metrics = <FirestoreWriteMetric>[];
  int? operationId;
  int? parentOperationId;
  bool parentCaptured = false;
  bool submitted = false;

  int get total => sets + creates + updates + deletes;

  void add(FirebaseActivityDocumentCommand kind, {
    int bytes = 0,
    int fields = 0,
    bool sizeKnown = false,
    int indexWriteUnits = 0,
    String? documentPath,
  }) {
    metrics.add(FirestoreWriteMetric(
      kind: kind,
      bytes: bytes,
      fields: fields,
      sizeKnown: sizeKnown,
      indexWriteUnits: indexWriteUnits,
      documentPath: documentPath,
    ));
    dataBytes += bytes;
    dataFields += fields;
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
    dataBytes = 0;
    dataFields = 0;
    metrics.clear();
    attempts++;
  }

  FirebaseActivityWriteCounts copy() => FirebaseActivityWriteCounts()
    ..sets = sets
    ..creates = creates
    ..updates = updates
    ..deletes = deletes
    ..attempts = attempts
    ..dataBytes = dataBytes
    ..dataFields = dataFields
    ..metrics.addAll(metrics)
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
    void Function() execute, {
    int documentBytes = 0,
    int fieldCount = 0,
    Object? documentData,
    String? documentPath,
    int indexWriteUnits = 0,
    bool partialWrite = false,
  }) {
    final counts = _batches[batch] ?? FirebaseActivityWriteCounts();
    if (counts.submitted) {
      throw StateError('firebase_batch_already_submitted');
    }
    execute();
    final size = documentData == null ? null
        : FirestoreDocumentSizer.document(documentPath ?? '', documentData);
    counts.add(kind,
        bytes: size?.bytes ?? documentBytes,
        fields: size?.fieldCount ?? fieldCount,
        sizeKnown: (size != null || documentBytes > 0) && !partialWrite,
        indexWriteUnits: indexWriteUnits,
        documentPath: documentPath);
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
