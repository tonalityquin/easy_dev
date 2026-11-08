import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../app/diagnostics/firebase_activity_meter.dart';

class UserStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Future<bool>> _pendingExactUpdates =
      <String, Future<bool>>{};
  final Map<String, Future<void>> _documentWriteTails =
      <String, Future<void>>{};
  final Map<String, String> _latestQueuedSignature = <String, String>{};
  final LinkedHashMap<String, Map<String, dynamic>> _confirmedFields =
      LinkedHashMap<String, Map<String, dynamic>>();

  void invalidateConfirmedFields() {
    _confirmedFields.clear();
  }

  CollectionReference<Map<String, dynamic>> _getUserCollectionRef() =>
      _firestore.collection('user_accounts');

  CollectionReference<Map<String, dynamic>> _getTabletCollectionRef() =>
      _firestore.collection('tablet_accounts');

  String _updateSignature(
    CollectionReference<Map<String, dynamic>> collection,
    String documentId,
    Map<String, dynamic> updates,
  ) {
    final fields = updates.keys.toList()..sort();
    final normalized = <String, dynamic>{
      for (final field in fields) field: updates[field],
    };
    return '${collection.path}/$documentId|${jsonEncode(normalized)}';
  }

  void _recordOptimization(
    String operation,
    String opName,
    String reason,
    Iterable<String> fields,
  ) {
    final names = fields.toList()..sort();
    FirebaseActivityMeter.instance.record(
      service: 'optimization',
      operation: operation,
      source: 'features/account/data/services/user_status_service.dart.$opName',
      result: 'skipped',
      detail: 'reason=$reason fields=${names.join(',')}',
    );
  }

  Future<bool> _safeUpdate(
    CollectionReference<Map<String, dynamic>> col,
    String docId,
    Map<String, dynamic> updates, {
    required String opName,
  }) async {
    if (updates.isEmpty) {
      _recordOptimization('WRITE_SKIPPED', opName, 'empty_fields', updates.keys);
      return false;
    }
    final signature = _updateSignature(col, docId, updates);
    final documentKey = '${col.path}/$docId';
    final pending = _pendingExactUpdates[signature];
    if (pending != null && _latestQueuedSignature[documentKey] == signature) {
      await pending;
      _recordOptimization(
        'WRITE_COALESCED',
        opName,
        'identical_inflight',
        updates.keys,
      );
      return false;
    }

    _latestQueuedSignature[documentKey] = signature;
    final task = _processUpdate(col, docId, updates, opName: opName);
    _pendingExactUpdates[signature] = task;
    try {
      return await task;
    } finally {
      if (identical(_pendingExactUpdates[signature], task)) {
        _pendingExactUpdates.remove(signature);
      }
    }
  }

  Future<bool> _processUpdate(
    CollectionReference<Map<String, dynamic>> col,
    String docId,
    Map<String, dynamic> updates, {
    required String opName,
  }) async {
    final documentKey = '${col.path}/$docId';
    final previous = _documentWriteTails[documentKey];
    final barrier = Completer<void>();
    _documentWriteTails[documentKey] = barrier.future;
    try {
      if (previous != null) await previous;
      final confirmed = _confirmedFields[documentKey];
      final delta = <String, dynamic>{};
      for (final entry in updates.entries) {
        if (confirmed == null ||
            !confirmed.containsKey(entry.key) ||
            confirmed[entry.key] != entry.value) {
          delta[entry.key] = entry.value;
        }
      }
      if (delta.isEmpty) {
        _recordOptimization(
          'WRITE_SKIPPED',
          opName,
          'confirmed_same_remote_fields',
          updates.keys,
        );
        return false;
      }

      if (delta.length != updates.length) {
        _recordOptimization(
          'WRITE_FIELDS_REDUCED',
          opName,
          'partial_confirmed_remote_fields',
          updates.keys.where((field) => !delta.containsKey(field)),
        );
      }

      try {
        await _performUpdate(col, docId, delta, updates, opName: opName);
      } catch (_) {
        _confirmedFields.remove(documentKey);
        rethrow;
      }
      final snapshot = <String, dynamic>{
        ...?confirmed,
        ...updates,
      };
      _confirmedFields.remove(documentKey);
      _confirmedFields[documentKey] = snapshot;
      while (_confirmedFields.length > 256) {
        _confirmedFields.remove(_confirmedFields.keys.first);
      }
      return true;
    } finally {
      barrier.complete();
      if (identical(_documentWriteTails[documentKey], barrier.future)) {
        _documentWriteTails.remove(documentKey);
        _latestQueuedSignature.remove(documentKey);
      }
    }
  }

  Future<void> _performUpdate(
    CollectionReference<Map<String, dynamic>> col,
    String docId,
    Map<String, dynamic> delta,
    Map<String, dynamic> fullUpdates, {
    required String opName,
  }) async {
    final docRef = col.doc(docId);
    final source =
        'features/account/data/services/user_status_service.dart.$opName';
    try {
      await docRef.update(delta).trackFirestore('UPDATE', source, collection: col.id, pathTemplate: col.path,);
    } on FirebaseException catch (error) {
      if (error.code != 'not-found' || opName == 'updateLoginSession') {
        rethrow;
      }
      await docRef
          .set(fullUpdates, SetOptions(merge: true))
          .trackFirestore('SET', source, collection: col.id, pathTemplate: col.path,);
    }
  }

  Future<void> updateLogOutUserStatus(
    String codeNumber,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;
    await _safeUpdate(
      _getUserCollectionRef(),
      '$codeNumber-$area',
      updates,
      opName: 'updateLogOutUserStatus',
    );
  }

  Future<void> updateWorkingUserStatus(
    String codeNumber,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;
    await _safeUpdate(
      _getUserCollectionRef(),
      '$codeNumber-$area',
      updates,
      opName: 'updateWorkingUserStatus',
    );
  }

  Future<bool> updateLoginSession({
    required String userId,
    required bool isSaved,
    String? currentArea,
    String? selectedArea,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }
    final updates = <String, dynamic>{'isSaved': isSaved};
    final normalizedCurrentArea = (currentArea ?? '').trim();
    final normalizedSelectedArea = (selectedArea ?? '').trim();
    if (normalizedCurrentArea.isNotEmpty) {
      updates['currentArea'] = normalizedCurrentArea;
    }
    if (normalizedSelectedArea.isNotEmpty) {
      updates['selectedArea'] = normalizedSelectedArea;
    }
    final fields = updates.keys.toList()..sort();
    final startedAt = DateTime.now();
    debugPrint(
      '[USER-STATUS][${startedAt.toIso8601String()}] loginSession update start fields=${fields.join(',')}',
    );
    try {
      final wrote = await _safeUpdate(
        _getUserCollectionRef(),
        normalizedUserId,
        updates,
        opName: 'updateLoginSession',
      );
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '[USER-STATUS][${DateTime.now().toIso8601String()}] loginSession update success fields=${fields.join(',')} elapsedMs=$elapsedMs firebaseWrite=${wrote ? 1 : 0}',
      );
      return wrote;
    } catch (error, stackTrace) {
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      debugPrint(
        '[USER-STATUS][${DateTime.now().toIso8601String()}] loginSession update failed fields=${fields.join(',')} elapsedMs=$elapsedMs error=$error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> updateLoadCurrentArea(
    String codeNumber,
    String area,
    String currentArea,
  ) async {
    await _safeUpdate(
      _getUserCollectionRef(),
      '$codeNumber-$area',
      <String, dynamic>{'currentArea': currentArea},
      opName: 'updateLoadCurrentArea',
    );
  }

  Future<bool> areaPickerCurrentArea(
    String codeNumber,
    String area,
    String currentArea,
  ) =>
      _safeUpdate(
        _getUserCollectionRef(),
        '$codeNumber-$area',
        <String, dynamic>{'currentArea': currentArea},
        opName: 'areaPickerCurrentArea',
      );

  Future<void> updateLogOutTabletStatus(
    String tabletId, {
    bool? isWorking,
    bool? isSaved,
  }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      updates,
      opName: 'updateLogOutTabletStatus',
    );
  }

  Future<void> updateWorkingTabletStatus(
    String tabletId, {
    bool? isWorking,
    bool? isSaved,
  }) async {
    final updates = <String, dynamic>{};
    if (isWorking != null) updates['isWorking'] = isWorking;
    if (isSaved != null) updates['isSaved'] = isSaved;
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      updates,
      opName: 'updateWorkingTabletStatus',
    );
  }

  Future<void> updateLoadCurrentAreaTablet(
    String tabletId,
    String currentArea,
  ) async {
    await _safeUpdate(
      _getTabletCollectionRef(),
      tabletId,
      <String, dynamic>{'currentArea': currentArea},
      opName: 'updateLoadCurrentAreaTablet',
    );
  }

  Future<bool> areaPickerCurrentAreaTablet(
    String tabletId,
    String currentArea,
  ) =>
      _safeUpdate(
        _getTabletCollectionRef(),
        tabletId,
        <String, dynamic>{'currentArea': currentArea},
        opName: 'areaPickerCurrentAreaTablet',
      );
}
