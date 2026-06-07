import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';

import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/repositories/plate_tts_listener_repository.dart';
import '../../application/parking_requests_dirty_hub.dart';
import '../../application/plate_tts_event_hub.dart';
import '../../application/tts_manager.dart';
import '../../application/tts_ownership.dart';
import '../../application/tts_user_filters.dart';
import '../../data/repositories/firestore_plate_tts_listener_repository.dart';
import 'plate_local_notification_service.dart';

class PlateTtsListenerService {
  static const String _uiEventKind = 'plate_tts_event_v1';

  static Future<void> _markParkingRequestsDirty(
      {required String area, required String docId, required int seq}) async {
    final a = area.trim();
    if (a.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${ParkingRequestsDirtyEvent.prefsKeyPrefix}$a';
      await prefs.setBool(key, true);
      debugPrint(
          '[PlateTtsListenerService] parkingRequestsDirty=true key=$key (id=$docId, seq=$seq, role=$_localRole)');

      final payload = <String, dynamic>{
        'kind': ParkingRequestsDirtyEvent.kind,
        'area': a,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };

      if (_localRole == TtsOwner.foreground) {
        try {
          FlutterForegroundTask.sendDataToMain(payload);
          debugPrint(
              '[PlateTtsListenerService] sendDataToMain parkingRequestsDirty area=$a (id=$docId, seq=$seq)');
        } catch (e) {
          debugPrint(
              '[PlateTtsListenerService] sendDataToMain parkingRequestsDirty failed: $e (id=$docId, seq=$seq)');
        }
      } else {
        ParkingRequestsDirtyHub.emitLocal(
            area: a, timestampMs: payload['ts'] as int?);
      }
    } catch (e) {
      debugPrint(
          '[PlateTtsListenerService] parkingRequestsDirty write failed: $e (area=$a, id=$docId, seq=$seq)');
    }
  }

  static TtsOwner _localRole = TtsOwner.app;
  static TtsOwner? _cachedOwner;
  static DateTime? _lastOwnerCheckedAt;
  static bool _ownerCheckBusy = false;
  static const Duration _ownerCheckCooldown = Duration(milliseconds: 800);

  static void setLocalRole(TtsOwner role) {
    _localRole = role;
    _log('localRole=$_localRole');
  }

  static void configureRepository(PlateTtsListenerRepository repository) {
    _repository = repository;
  }

  static Future<bool> _isOwnerForThisIsolate(
      {required String reason, required bool force}) async {
    if (!force && _lastOwnerCheckedAt != null && _cachedOwner != null) {
      final now = DateTime.now();
      if (now.difference(_lastOwnerCheckedAt!) < _ownerCheckCooldown) {
        return _cachedOwner == _localRole;
      }
    }

    if (_ownerCheckBusy) {
      return _cachedOwner == _localRole;
    }

    _ownerCheckBusy = true;
    try {
      final owner = await TtsOwnership.getOwner();
      _cachedOwner = owner;
      _lastOwnerCheckedAt = DateTime.now();
      final ok = owner == _localRole;
      if (!ok) {
        _log(
            'ownership mismatch: owner=$owner role=$_localRole reason=$reason');
      }
      return ok;
    } catch (e, st) {
      _cachedOwner = null;
      _lastOwnerCheckedAt = DateTime.now();
      _log('owner check error reason=$reason err=$e\n$st');
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'tts.ownerCheck',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'reason': reason,
            'localRole': _localRole.name,
            'cachedOwner': _cachedOwner?.name,
            'currentArea': _currentArea,
          },
        ),
      );
      return false;
    } finally {
      _ownerCheckBusy = false;
    }
  }

  static bool _enabled = true;
  static TtsUserFilters _filters = TtsUserFilters.defaults();

  static String? _lastKnownArea;

  static DateTime? _lastHydratedAt;
  static bool _hydrateBusy = false;
  static const Duration _hydrateCooldown = Duration(milliseconds: 800);

  static bool _policyBusy = false;

  static double _usageSampleRate = 0.2;
  static Duration _speakDedupWindow = const Duration(seconds: 8);

  static void setUsageSampleRate(double r) {
    if (r < 0) r = 0;
    if (r > 1) r = 1;
    _usageSampleRate = r;
    _log('usageSampleRate=$_usageSampleRate');
  }

  static void setSpeakDedupWindow(Duration d) {
    _speakDedupWindow = d;
    _log('speakDedupWindow=${_speakDedupWindow.inMilliseconds}ms');
  }

  static bool _isTabletMode(String mode) => mode.trim() == 'tablet';

  static Future<String> _loadModeSafe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString('mode') ?? '').trim();
    } catch (e) {
      debugPrint('[PlateTtsListenerService] mode load failed: $e');
      return '';
    }
  }

  static bool _effectiveMasterOnForMode(String mode) {
    final isTablet = _isTabletMode(mode);
    final completedOk = _filters.completed && isTablet;
    final anyFilterOn = isTablet
        ? (_filters.departure || completedOk)
        : (_filters.parking || _filters.departure);
    return _enabled && anyFilterOn;
  }

  static bool _isEnabledForType(String? type) {
    if (type == null) return false;

    final mode = _currentMode ?? '';
    if (!_effectiveMasterOnForMode(mode)) return false;

    if (type == PlateType.parkingRequests.firestoreValue) {
      return _filters.parking && !_isTabletMode(mode);
    }
    if (type == PlateType.departureRequests.firestoreValue)
      return _filters.departure;
    if (type == PlateType.departureCompleted.firestoreValue) {
      return _filters.completed && _isTabletMode(mode);
    }
    return false;
  }

  static Future<void> setFilters(TtsUserFilters filters) async {
    _filters = filters;
    await _filters.save();
    _log('filters saved: $filters');
    await _applyEffectiveMasterPolicy(reason: 'setFilters(saved)');
  }

  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    _log('master enabled=$_enabled');
    await _applyEffectiveMasterPolicy(reason: 'setEnabled');
  }

  static void updateFilters(TtsUserFilters filters) {
    _filters = filters;
    _log('filters updated (in-memory): $filters');
    Future.microtask(
        () => _applyEffectiveMasterPolicy(reason: 'updateFilters'));
  }

  static PlateTtsListenerRepository _repository =
      FirestorePlateTtsListenerRepository();

  static StreamSubscription<PlateTtsChangeBatch>? _subscription;
  static final Map<String, String?> _lastTypes = {};
  static final Map<String, DateTime> _lastSpokenAt = {};

  static int _listenSeq = 0;

  static String? _currentArea;
  static String? _currentMode;

  static DateTime? _baselineUpdatedAt;
  static String? _baselineDocId;

  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  static int _readsTotal = 0;
  static int _readsAdded = 0;
  static int _readsModified = 0;
  static int _readsRemoved = 0;
  static int _readsEmptySnapshots = 0;

  static void start(String currentArea, {bool force = false}) {
    _lastKnownArea = currentArea;
    Future.microtask(() => _startListening(currentArea, force: force));
  }

  static Future<void> _ensureFirebaseInThisIsolate() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        _log('Firebase.initializeApp() done (isolate)');
      }
    } catch (e, st) {
      _log('Firebase init error: $e\n$st');
    }
  }

  static Future<void> _hydrateFromPrefsSafe(
      {required String reason, required bool force}) async {
    if (_hydrateBusy) return;

    final now = DateTime.now();
    if (!force &&
        _lastHydratedAt != null &&
        now.difference(_lastHydratedAt!) < _hydrateCooldown) {
      return;
    }

    _hydrateBusy = true;
    try {
      final loaded = await TtsUserFilters.load();
      _filters = loaded;
      _lastHydratedAt = now;
      final masterOn = loaded.parking || loaded.departure || loaded.completed;
      _log(
          'hydrate(prefs) reason=$reason filters=${loaded.toMap()} masterOn=$masterOn');
    } catch (e, st) {
      _log('hydrate(prefs) failed reason=$reason err=$e\n$st (keep in-memory)');
      _lastHydratedAt = now;
    } finally {
      _hydrateBusy = false;
    }
  }

  static Future<void> _applyEffectiveMasterPolicy(
      {required String reason}) async {
    if (_policyBusy) return;
    _policyBusy = true;
    try {
      if (!await _isOwnerForThisIsolate(
          reason: 'policy(' + reason + ')', force: false)) {
        if (_subscription != null) {
          _log('policy(' + reason + '): not owner → stop');
          await stop();
        }
        return;
      }

      final mode = await _loadModeSafe();

      _currentMode = mode;

      final master = _effectiveMasterOnForMode(mode);

      if (!master) {
        if (_subscription != null) {
          _log('policy($reason): effective master OFF → stop listening');
          await stop();
        } else {
          _log('policy($reason): effective master OFF (already stopped)');
        }
        return;
      }

      if (_subscription == null && (_lastKnownArea ?? '').trim().isNotEmpty) {
        final area = _lastKnownArea!.trim();
        _log(
            'policy($reason): effective master ON + no subscription → restart(area=$area)');
        await _startListening(area, force: true);
      } else {
        _log(
            'policy($reason): effective master ON (subscription=${_subscription != null})');
      }
    } finally {
      _policyBusy = false;
    }
  }

  static Future<void> stop() async {
    _listenSeq += 1;

    if (_subscription != null) {
      await _subscription?.cancel();
      _subscription = null;
      _log('■ STOP listen (area=$_currentArea, seq=$_listenSeq)');
      _printReadSummary(prefix: 'READ SUMMARY (stop)');
    }

    _currentArea = null;
    _currentMode = null;
    _baselineUpdatedAt = null;
    _baselineDocId = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
  }

  static Future<void> _startListening(String currentArea,
      {bool force = false}) async {
    await _ensureFirebaseInThisIsolate();

    await PlateLocalNotificationService.instance.ensureInitialized();

    final area = currentArea.trim();
    if (area.isEmpty) {
      _log('start ignored: empty area');
      return;
    }

    if (!await _isOwnerForThisIsolate(
        reason: 'start(area=$area)', force: true)) {
      _log(
          'start aborted: not owner (role=$_localRole owner=$_cachedOwner area=$area)');
      await stop();
      return;
    }

    final mode = await _loadModeSafe();

    if (!force &&
        _subscription != null &&
        _currentArea == area &&
        _currentMode == mode) {
      _log('start no-op: already listening (area=$area, mode=$mode)');
      return;
    }

    _listenSeq += 1;
    final int mySeq = _listenSeq;

    _lastKnownArea = area;

    await _hydrateFromPrefsSafe(
        reason: 'start(area=$area, seq=$mySeq, force=$force)', force: true);

    _currentMode = mode;

    if (!_effectiveMasterOnForMode(mode)) {
      _log(
          'start aborted: effective master OFF → stop() and return (seq=$mySeq)');
      await stop();
      return;
    }

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();

    _baselineUpdatedAt = null;
    _baselineDocId = null;

    _currentArea = area;

    final isTablet = _isTabletMode(mode);

    final typesToMonitor = <PlateType>[
      if (!isTablet) PlateType.parkingRequests,
      PlateType.departureRequests,
      if (isTablet) PlateType.departureCompleted,
    ];

    _log(
        'listen config: area=$area mode=$mode isTablet=$isTablet types=${typesToMonitor.map((e) => e.firestoreValue).toList()} (seq=$mySeq)');

    try {
      await _fetchBaseline(area, typesToMonitor);

      if (_baselineUpdatedAt != null && _baselineDocId != null) {
        _log(
            'apply cursor(startAfter): ts=${_baselineUpdatedAt?.toUtc()} id=$_baselineDocId (seq=$mySeq)');
      } else {
        _log('no baseline available → start without cursor (seq=$mySeq)');
      }

      _resetReadCounters();
      _log('▶ START listen (area=$area, seq=$mySeq)');

      _subscription = _repository
          .watchChanges(
        area: area,
        types: typesToMonitor,
        startAfterUpdatedAt: _baselineUpdatedAt,
        startAfterDocumentId: _baselineDocId,
      )
          .listen((snapshot) async {
        if (mySeq != _listenSeq) {
          _log(
              'drop stale snapshot (seq mismatch) my=$mySeq current=$_listenSeq');
          return;
        }

        if (!await _isOwnerForThisIsolate(
            reason: 'snapshot(area=$_currentArea)', force: false)) {
          _log(
              'snapshot aborted: not owner (role=$_localRole owner=$_cachedOwner)');
          await stop();
          return;
        }

        await _hydrateFromPrefsSafe(
            reason: 'snapshot(area=$_currentArea, seq=$mySeq)', force: false);

        if (!_effectiveMasterOnForMode(_currentMode ?? '')) {
          _log('snapshot aborted: effective master OFF → stop() (seq=$mySeq)');
          await stop();
          return;
        }

        if (snapshot.hasPendingWrites) {
          _log('skip local pendingWrites snapshot (seq=$mySeq)');
          return;
        }

        final bool isFromCache = snapshot.isFromCache;
        final docChanges = snapshot.changes;

        if (docChanges.isEmpty) {
          _readsEmptySnapshots += 1;
          return;
        }

        _readsTotal += 1;
        _readsAdded +=
            docChanges.where((c) => c.type == PlateTtsChangeType.added).length;
        _readsModified += docChanges
            .where((c) => c.type == PlateTtsChangeType.modified)
            .length;
        _readsRemoved += docChanges
            .where((c) => c.type == PlateTtsChangeType.removed)
            .length;

        _log(
            'snapshot changes=${docChanges.length}, fromCache=$isFromCache (seq=$mySeq)');

        if (!isFromCache) {
          final int billedReads = docChanges.length;
          if (billedReads > 0) {
            _reportUsageRead(
              area: _currentArea,
              n: billedReads,
              source: 'PlateTTS.listen',
              sampled: true,
            );
          }
        } else {
          _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.cache');
        }

        for (final change in docChanges) {
          if (mySeq != _listenSeq) {
            _log(
                'drop stale loop (seq mismatch) my=$mySeq current=$_listenSeq');
            return;
          }

          final data = change.data;
          if (data == null) continue;

          final docId = change.docId;
          final newType = data['type'] as String?;

          final plateNumber = _readPlateNumber(data);

          final location = _readLocationForSpeech(data['location']);

          final tail = plateNumber.length >= 4
              ? plateNumber.substring(plateNumber.length - 4)
              : plateNumber;
          final spokenTail = _convertToKoreanDigits(_digitsOnly(tail));

          bool didSpeak = false;
          final prevTypeForUi = _lastTypes[docId];
          final isDepartureCompletedUiEvent =
              _isTabletMode(_currentMode ?? '') &&
                  newType == PlateType.departureCompleted.firestoreValue &&
                  (change.type == PlateTtsChangeType.added ||
                      prevTypeForUi == null ||
                      prevTypeForUi != newType);

          if (!_isEnabledForType(newType)) {
            if (isDepartureCompletedUiEvent) {
              _emitUiEvent(
                docId: docId,
                type: newType,
                plateNumber: plateNumber,
                location: location,
              );
            }
            _log('skip by filter: type=$newType id=$docId (seq=$mySeq)');
            _lastTypes[docId] = newType;
            continue;
          }

          if (change.type == PlateTtsChangeType.added) {
            if (_dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log(
                    'SPEAK(added): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _markParkingRequestsDirty(
                    area: _currentArea ?? '', docId: docId, seq: mySeq);
                _safeSpeak(utter);
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                didSpeak = true;
              } else if (newType ==
                  PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log(
                    'SPEAK(added): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                didSpeak = true;
              } else if (newType ==
                  PlateType.departureCompleted.firestoreValue) {
                final utter = '출차 완료 $spokenTail, $location';
                _log(
                    'SPEAK(added×$_completionRepeat): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                _speakRepeated(utter,
                    times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              } else {
                _log('ignore added: type=$newType id=$docId (seq=$mySeq)');
              }
            } else {
              _log('dedup skip added id=$docId (seq=$mySeq)');
            }
          } else if (change.type == PlateTtsChangeType.modified) {
            final prevType = _lastTypes[docId];
            final typeChanged = prevType != null && prevType != newType;

            if (typeChanged && _dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log(
                    'SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _markParkingRequestsDirty(
                    area: _currentArea ?? '', docId: docId, seq: mySeq);
                _safeSpeak(utter);
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                didSpeak = true;
              } else if (newType ==
                  PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log(
                    'SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                didSpeak = true;
              } else if (newType ==
                  PlateType.departureCompleted.firestoreValue) {
                final utter = '$spokenTail 출차 완료 되었습니다.';
                _log(
                    'SPEAK(modified→type change×$_completionRepeat): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _notifyPlateEvent(
                    docId: docId,
                    type: newType,
                    plateNumber: plateNumber,
                    location: location);
                _speakRepeated(utter,
                    times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              }
            } else {
              _log(
                  'ignore modified (no type change or dedup) id=$docId (seq=$mySeq)');
            }
          } else {
            _log('ignore changeType=${change.type} id=$docId (seq=$mySeq)');
          }

          _lastTypes[docId] = newType;

          if (didSpeak || isDepartureCompletedUiEvent) {
            _emitUiEvent(
              docId: docId,
              type: newType,
              plateNumber: plateNumber,
              location: location,
            );
          }
        }
      }, onError: (e, st) {
        if (mySeq != _listenSeq) return;
        _log('listen error: $e\n$st (seq=$mySeq)');
        unawaited(
          DevFirebaseDebugDialog.show(
            operation: 'tts.plates.listen',
            error: e,
            stackTrace: st,
            details: <String, Object?>{
              'area': _currentArea,
              'mode': _currentMode,
              'seq': mySeq,
              'role': _localRole.name,
              'source': 'PlateTTS.listen.error',
            },
          ),
        );
        _printReadSummary(prefix: 'READ SUMMARY (listen-error)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.error');
      }, onDone: () {
        if (mySeq != _listenSeq) return;
        _log('listen done (seq=$mySeq)');
        _printReadSummary(prefix: 'READ SUMMARY (done)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.done');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st (seq=$mySeq)');
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'tts.plates.start',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'area': area,
            'mode': mode,
            'seq': mySeq,
            'role': _localRole.name,
            'typesToMonitor': typesToMonitor.map((e) => e.firestoreValue).toList(growable: false),
          },
        ),
      );
      _printReadSummary(prefix: 'READ SUMMARY (start-error)');
    }
  }

  static void _emitUiEvent({
    required String docId,
    required String? type,
    required String plateNumber,
    required String location,
  }) {
    final area = (_currentArea ?? '').trim();
    final t = (type ?? '').trim();
    if (area.isEmpty || t.isEmpty) return;

    if (_localRole == TtsOwner.foreground) {
      try {
        FlutterForegroundTask.sendDataToMain(<String, dynamic>{
          'kind': _uiEventKind,
          'area': area,
          'type': t,
          'docId': docId,
          'plateNumber': plateNumber,
          'location': location,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (e, st) {
        _log('sendDataToMain failed: $e');
        unawaited(
          DevFirebaseDebugDialog.show(
            operation: 'tts.plateUiEvent.sendDataToMain',
            error: e,
            stackTrace: st,
            details: <String, Object?>{
              'area': area,
              'type': t,
              'docId': docId,
              'role': _localRole.name,
              'plateNumberEmpty': plateNumber.trim().isEmpty,
            },
          ),
        );
      }
      return;
    }

    PlateTtsEventHub.emitLocal(
      area: area,
      type: t,
      docId: docId,
      plateNumber: plateNumber,
      location: location,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> _fetchBaseline(
      String currentArea, List<PlateType> types) async {
    try {
      final baseline = await _repository.fetchBaseline(
        area: currentArea,
        types: types,
      );

      _baselineUpdatedAt = baseline.updatedAt;
      _baselineDocId = baseline.docId;

      if (_baselineUpdatedAt == null || (_baselineDocId?.isEmpty ?? true)) {
        _log('baseline: none (0 docs)');
        return;
      }

      _log('baseline: ts=${_baselineUpdatedAt?.toUtc()} id=$_baselineDocId');
    } catch (e, st) {
      _baselineUpdatedAt = null;
      _baselineDocId = null;
      _log('baseline fetch error: $e\n$st');
      unawaited(
        DevFirebaseDebugDialog.show(
          operation: 'tts.plates.baseline',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'area': currentArea,
            'types': types.map((e) => e.firestoreValue).toList(growable: false),
            'role': _localRole.name,
            'mode': _currentMode,
            'enabled': _enabled,
            'filters.parking': _filters.parking,
            'filters.departure': _filters.departure,
            'filters.completed': _filters.completed,
          },
        ),
      );
    }
  }

  static void _resetReadCounters() {
    _readsTotal = 0;
    _readsAdded = 0;
    _readsModified = 0;
    _readsRemoved = 0;
    _readsEmptySnapshots = 0;
  }

  static void _printReadSummary({required String prefix}) {
    _log(
      '$prefix: total=$_readsTotal, added=$_readsAdded, modified=$_readsModified, '
      'removed=$_readsRemoved, emptySnapshots=$_readsEmptySnapshots',
    );
  }

  static bool _dedup(String docId) {
    final now = DateTime.now();
    final last = _lastSpokenAt[docId];
    if (last != null && now.difference(last) < _speakDedupWindow) {
      return false;
    }
    _lastSpokenAt[docId] = now;
    return true;
  }

  static Future<void> _safeSpeak(String text) async {
    if (!await _isOwnerForThisIsolate(reason: 'speak', force: false)) return;
    try {
      await TtsManager.speak(text);
    } catch (e) {
      _log('TTS error: $e');
    }
  }

  static Future<void> _speakRepeated(String text,
      {int times = 2, Duration gap = Duration.zero}) async {
    for (var i = 0; i < times; i++) {
      await _safeSpeak(text);
      if (i < times - 1 && gap > Duration.zero) {
        await Future.delayed(gap);
      }
    }
  }

  static String _titleForType(String? type) {
    if (type == PlateType.parkingRequests.firestoreValue) return '입차 요청';
    if (type == PlateType.departureRequests.firestoreValue) return '출차 요청';
    if (type == PlateType.departureCompleted.firestoreValue) return '출차 완료';
    return '';
  }

  static void _notifyPlateEvent({
    required String docId,
    required String? type,
    required String plateNumber,
    required String location,
  }) {
    if (!_isEnabledForType(type)) return;

    final title = _titleForType(type);
    if (title.isEmpty) return;

    Future.microtask(() async {
      if (!await _isOwnerForThisIsolate(reason: 'notify', force: false)) return;
      await PlateLocalNotificationService.instance.showPlateEvent(
        docId: docId,
        title: title,
        area: _currentArea,
        plateNumber: plateNumber,
        parkingLocation: location,
      );
    });
  }

  static String _readPlateNumber(Map<String, dynamic> data) {
    final v1 = data['plateNumber'];
    if (v1 is String && v1.trim().isNotEmpty) return v1.trim();

    final v2 = data['plate_number'];
    if (v2 is String && v2.trim().isNotEmpty) return v2.trim();

    return '';
  }

  static String _readLocationForSpeech(dynamic raw) {
    if (raw == null) return '미지정';

    if (raw is String) {
      final t = raw.trim();
      return t.isEmpty ? '미지정' : t;
    }

    if (raw is Map) {
      final full = raw['full'];
      if (full is String && full.trim().isNotEmpty) return full.trim();

      final leaf = raw['leaf'];
      if (leaf is String && leaf.trim().isNotEmpty) return leaf.trim();

      final anyString = raw.values
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (anyString.isNotEmpty) return anyString.first;

      return '미지정';
    }

    return '미지정';
  }

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '공',
      '1': '일',
      '2': '이',
      '3': '삼',
      '4': '사',
      '5': '오',
      '6': '육',
      '7': '칠',
      '8': '팔',
      '9': '구',
    };
    return digits.split('').map((d) => koreanDigits[d] ?? d).join(', ');
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static void _reportUsageRead({
    required String? area,
    required int n,
    required String source,
    bool sampled = true,
  }) {
    final a = (area == null || area.isEmpty) ? '(unknown)' : area;
    if (n <= 0) return;

    if (_usageSampleRate <= 0) return;
    if (_usageSampleRate < 1.0 && sampled) {
      final r = (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
      if (r > _usageSampleRate) return;
    }

    _log('USAGE(read): area=$a n=$n source=$source (sampled=$sampled)');
  }

  static void _annotateUsage({required String? area, required String source}) {
    final a = (area == null || area.isEmpty) ? '(unknown)' : area;
    _log('USAGE(annotate): area=$a source=$source');
  }

  static void _log(String msg) {
    debugPrint('[PlateTTS] $msg');
  }
}
