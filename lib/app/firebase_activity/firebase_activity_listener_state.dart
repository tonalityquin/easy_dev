import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_activity_billing_config.dart';
import 'firestore_document_sizer.dart';

class FirebaseListenerAssessment {
  const FirebaseListenerAssessment({
    required this.server,
    required this.initial,
    required this.reconnectCandidate,
    required this.metadataOnly,
    required this.billableDocuments,
    required this.unknownRemoved,
    required this.size,
    required this.reason,
  });

  final bool server;
  final bool initial;
  final bool reconnectCandidate;
  final bool metadataOnly;
  final int billableDocuments;
  final int unknownRemoved;
  final FirestoreSizeEstimate size;
  final String reason;
}

class FirebaseActivityListenerState {
  FirebaseActivityListenerState(this.id, this.origin);

  final int id;
  final String origin;
  final DateTime subscribedAt = DateTime.now();
  DateTime? lastServerSnapshotAt;
  DateTime? lastCacheSnapshotAt;
  DateTime? cacheTransitionAt;
  bool serverInitialized = false;
  bool _wasFromCache = false;
  int? _lastDataFingerprint;

  int _fingerprint(Object? snapshot) {
    Object? simplified(Object? value) {
      if (value is Map) {
        final keys = value.keys.map((key) => key.toString()).toList()..sort();
        return <String, Object?>{
          for (final key in keys) key: simplified(value[key]),
        };
      }
      if (value is Iterable) return value.map(simplified).toList();
      if (value is Timestamp) return value.microsecondsSinceEpoch;
      if (value is DateTime) return value.toUtc().microsecondsSinceEpoch;
      if (value is GeoPoint) return <double>[value.latitude, value.longitude];
      if (value is DocumentReference) return value.path;
      if (value is Blob) return _fingerprintBytes(value.bytes);
      if (value is Uint8List) return _fingerprintBytes(value);
      if (value is num || value is String || value is bool || value == null) return value;
      return value.runtimeType.toString();
    }
    if (snapshot is DocumentSnapshot) {
      return _hash(jsonEncode(simplified(snapshot.data())));
    }
    if (snapshot is QuerySnapshot) {
      final docs = snapshot.docs.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return _hash(jsonEncode(<Object?>[
        for (final doc in docs) <Object?>[doc.reference.path, simplified(doc.data())],
      ]));
    }
    return 0;
  }

  int _fingerprintBytes(Uint8List bytes) {
    var hash = 2166136261;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }

  int _hash(String input) {
    var hash = 2166136261;
    for (final unit in utf8.encode(input)) {
      hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }

  FirebaseListenerAssessment examine(Object? event) {
    final now = DateTime.now();
    if (event is! QuerySnapshot && event is! DocumentSnapshot) {
      return const FirebaseListenerAssessment(
        server: false, initial: false, reconnectCandidate: false,
        metadataOnly: false, billableDocuments: 0, unknownRemoved: 0,
        size: FirestoreSizeEstimate(bytes: 0, fieldCount: 0, documents: 0),
        reason: 'non_firestore_event',
      );
    }
    final metadata = event is QuerySnapshot ? event.metadata : (event as DocumentSnapshot).metadata;
    final cache = metadata.isFromCache;
    final server = !cache && !metadata.hasPendingWrites;
    if (cache) {
      lastCacheSnapshotAt = now;
      if (!_wasFromCache && serverInitialized) cacheTransitionAt = now;
    }
    final gap = cacheTransitionAt == null ? Duration.zero : now.difference(cacheTransitionAt!);
    final reconnectCandidate = server && serverInitialized && _wasFromCache &&
        (!FirebaseActivityBillingConfig.offlinePersistenceEnabled ||
            gap >= const Duration(minutes: 30));
    final initial = server && !serverInitialized;
    final fingerprint = _fingerprint(event);
    final unchanged = _lastDataFingerprint == fingerprint;
    final metadataOnly = server && serverInitialized && unchanged && !reconnectCandidate;
    var added = 0;
    var modified = 0;
    var removed = 0;
    if (event is QuerySnapshot) {
      for (final change in event.docChanges) {
        switch (change.type) {
          case DocumentChangeType.added:
            added++;
          case DocumentChangeType.modified:
            modified++;
          case DocumentChangeType.removed:
            removed++;
        }
      }
    }
    final size = initial || reconnectCandidate
        ? FirestoreDocumentSizer.fromSnapshot(event)
        : FirestoreDocumentSizer.fromChanges(event);
    final docs = !server || metadataOnly ? 0
        : initial || reconnectCandidate
            ? (event is QuerySnapshot ? event.docs.length : event is DocumentSnapshot && event.exists ? 1 : 0)
            : event is QuerySnapshot ? added + modified
                : unchanged ? 0 : event is DocumentSnapshot && event.exists ? 1 : 0;
    final unknownRemoved = server && !initial && !reconnectCandidate && !metadataOnly
        ? removed : 0;
    if (server) {
      serverInitialized = true;
      lastServerSnapshotAt = now;
      cacheTransitionAt = null;
    }
    _wasFromCache = cache;
    _lastDataFingerprint = fingerprint;
    return FirebaseListenerAssessment(
      server: server, initial: initial,
      reconnectCandidate: reconnectCandidate, metadataOnly: metadataOnly,
      billableDocuments: docs, unknownRemoved: unknownRemoved,
      size: size,
      reason: metadataOnly ? 'metadata_only' : reconnectCandidate
          ? 'reconnect_requery_candidate' : initial ? 'initial_server_sync'
          : unknownRemoved > 0 ? 'removed_reason_unknown' : 'server_change',
    );
  }
}
