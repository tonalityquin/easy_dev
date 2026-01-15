// lib/utils/tts/plate_tts_listener_service.dart
//
// 변경 요약 (updatedAt 커서/윈도우 A안 + 컴파일 에러 수정 + UsageReporter 계측 + ✅ 이번 요청 반영):
// - 서버 기준선 1건 조회 후 ✨ startAfter(updatedAt, __name__) 커서 적용
// - ✨ 첫 스냅샷 무음 규칙 제거(커서가 초기 잡음을 제거하므로 안전)
// - setEnabled: Future<void>로 변경(호출부 await 가능)
// - updateFilters 추가(저장 없이 인메모리 반영)
// - Firestore fromCache 로깅
// - ✅ UsageReporter로 "읽기(read)" 비용 계측 추가(샘플링 적용)
//
// ✅ 이번 요청(핵심 원인 해결):
// - ✅ start() 시점에 SharedPreferences(TtsUserFilters.load) 하이드레이션(자동 로드)
// - ✅ snapshot 처리 직전에도 짧은 쿨다운 기반으로 prefs 재동기화(전달 누락/다른 isolate stale 방지)
// - ✅ "실효 마스터" = (_enabled && (parking||departure||completed))가 false이면 즉시 stop() → Firestore 이벤트 수신 중단
// - ✅ 실효 마스터가 다시 true가 되면 마지막 area로 자동 재시작(OFF→ON 전환 복구)
//
// ✅ 이번 수정(경고 해결):
// - ✅ _listenSeq를 "리스닝 세션 토큰"으로 실제 사용하여 unused_field 경고 제거
//   - start/stop 시 _listenSeq 증가
//   - snapshot 콜백에서 mySeq != _listenSeq면 stale 이벤트로 즉시 드랍
// - ✅ force 파라미터를 의미 있게 사용(이미 구독 중이면 force=false에서는 재시작하지 않음)
//
// 주의: 쿼리 정렬 순서와 startAfter 필드 순서는 반드시 동일해야 함.
// 필요한 인덱스(예): area + type + updatedAt + __name__ (ASC/ASC/ASC/ASC)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../enums/plate_type.dart';
import '../tts/tts_manager.dart';
import '../tts/tts_user_filters.dart';
import 'plate_local_notification_service.dart';

// import '../usage_reporter.dart';

class PlateTtsListenerService {
  // -----------------------------
  // Runtime master / filters
  // -----------------------------

  static bool _enabled = true;
  static TtsUserFilters _filters = TtsUserFilters.defaults();

  // 마지막으로 성공적으로 listen했던 area (OFF→ON 복구용)
  static String? _lastKnownArea;

  // ✅ prefs 하이드레이션(짧은 쿨다운으로 빈번한 prefs read 방지)
  static DateTime? _lastHydratedAt;
  static bool _hydrateBusy = false;
  static const Duration _hydrateCooldown = Duration(milliseconds: 800);

  // ✅ 정책 적용 중 중복 실행 방지
  static bool _policyBusy = false;

  // -----------------------------
  // Usage sampling
  // -----------------------------

  /// 설치 단위 사용량 보고 샘플링 비율(0.0~1.0). 너무 자주 쓰면 보고(write) 비용이 증가합니다.
  static double _usageSampleRate = 0.2; // 기본 20%

  /// speak 중복 방지 윈도우
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

  /// ✅ 실효 마스터: "스위치가 하나도 켜져있지 않으면" 구독/발화 모두 중단
  static bool _effectiveMasterOn() {
    final anyFilterOn = _filters.parking || _filters.departure || _filters.completed;
    return _enabled && anyFilterOn;
  }

  static bool _isEnabledForType(String? type) {
    if (type == null) return false;
    if (!_effectiveMasterOn()) return false; // ✅ 실효 마스터 OFF면 모두 스킵
    if (type == PlateType.parkingRequests.firestoreValue) return _filters.parking;
    if (type == PlateType.departureRequests.firestoreValue) return _filters.departure;
    if (type == PlateType.departureCompleted.firestoreValue) return _filters.completed;
    return false;
  }

  /// 저장 없이 즉시 in-memory만 바꾸고 싶으면 [updateFilters] 사용
  static Future<void> setFilters(TtsUserFilters filters) async {
    _filters = filters;
    await _filters.save();
    _log('filters saved: $filters');

    // ✅ 저장 후에도 정책 적용(OFF면 stop, ON이면 재시작 가능)
    await _applyEffectiveMasterPolicy(reason: 'setFilters(saved)');
  }

  /// 호출부에서 await로 사용하므로 반환형을 Future로 변경
  static Future<void> setEnabled(bool v) async {
    _enabled = v;
    _log('master enabled=$_enabled');

    // ✅ 마스터 변경 즉시 정책 적용(OFF면 stop)
    await _applyEffectiveMasterPolicy(reason: 'setEnabled');
  }

  /// 저장 없이 앱/FG isolate에 바로 반영하고 싶을 때 사용
  static void updateFilters(TtsUserFilters filters) {
    _filters = filters;
    _log('filters updated (in-memory): $filters');

    // ✅ sync API 유지 + 정책 적용은 microtask로
    Future.microtask(() => _applyEffectiveMasterPolicy(reason: 'updateFilters'));
  }

  // -----------------------------
  // Listening state
  // -----------------------------

  // 리스닝 핸들
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  // 타입 전환 감지용
  static final Map<String, String?> _lastTypes = {};

  // 짧은 디듀프(문서별 일정 시간 내 중복 발화 방지)
  static final Map<String, DateTime> _lastSpokenAt = {};

  // ✅ 리스닝 세션 토큰(경고 해결 포인트: 실제로 사용)
  // - start/stop 시 증가
  // - snapshot 콜백에서 mySeq != _listenSeq면 stale 이벤트로 드랍
  static int _listenSeq = 0;

  // 기준 상태
  static String? _currentArea;

  // 서버 기준선(해당 지역 최신 1건, updatedAt 기준)
  static Timestamp? _baselineUpdatedAt;
  static String? _baselineDocId;

  // 출차 완료 반복
  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  // read counters (approx)
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

  static Future<void> _hydrateFromPrefsSafe({required String reason, required bool force}) async {
    if (_hydrateBusy) return;

    final now = DateTime.now();
    if (!force && _lastHydratedAt != null && now.difference(_lastHydratedAt!) < _hydrateCooldown) {
      return;
    }

    _hydrateBusy = true;
    try {
      final loaded = await TtsUserFilters.load();
      _filters = loaded;
      _lastHydratedAt = now;
      final masterOn = loaded.parking || loaded.departure || loaded.completed;
      _log('hydrate(prefs) reason=$reason filters=${loaded.toMap()} masterOn=$masterOn');
    } catch (e, st) {
      _log('hydrate(prefs) failed reason=$reason err=$e\n$st (keep in-memory)');
      _lastHydratedAt = now; // 실패시에도 과도한 재시도 방지
    } finally {
      _hydrateBusy = false;
    }
  }

  // ✅ 실효 마스터 정책 적용:
  // - OFF면 stop() (Firestore 이벤트 수신 자체 중단)
  // - ON이고 구독이 끊겨있으면 lastKnownArea로 재시작
  static Future<void> _applyEffectiveMasterPolicy({required String reason}) async {
    if (_policyBusy) return;
    _policyBusy = true;
    try {
      final master = _effectiveMasterOn();

      if (!master) {
        if (_subscription != null) {
          _log('policy($reason): effective master OFF → stop listening');
          await stop();
        } else {
          _log('policy($reason): effective master OFF (already stopped)');
        }
        return;
      }

      // master ON
      if (_subscription == null && (_lastKnownArea ?? '').trim().isNotEmpty) {
        final area = _lastKnownArea!.trim();
        _log('policy($reason): effective master ON + no subscription → restart(area=$area)');
        // force=true로 재시작 (baseline/cursor 재확보)
        await _startListening(area, force: true);
      } else {
        _log('policy($reason): effective master ON (subscription=${_subscription != null})');
      }
    } finally {
      _policyBusy = false;
    }
  }

  static Future<void> stop() async {
    // ✅ stop 시점에 listenSeq 증가 → 이전 세션의 늦은 콜백을 무효화
    _listenSeq += 1;

    if (_subscription != null) {
      await _subscription?.cancel();
      _subscription = null;
      _log('■ STOP listen (area=$_currentArea, seq=$_listenSeq)');
      _printReadSummary(prefix: 'READ SUMMARY (stop)');
    }

    _currentArea = null;
    _baselineUpdatedAt = null;
    _baselineDocId = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();
  }

  static Future<void> _startListening(String currentArea, {bool force = false}) async {
    await _ensureFirebaseInThisIsolate();

    // ✅ FG isolate에서도 heads-up 알림을 띄울 수 있도록 로컬 알림 초기화(베스트 에포트)
    await PlateLocalNotificationService.instance.ensureInitialized();

    final area = currentArea.trim();
    if (area.isEmpty) {
      _log('start ignored: empty area');
      return;
    }

    // ✅ 이미 같은 area를 구독 중이고 force=false면 재시작하지 않음
    if (!force && _subscription != null && _currentArea == area) {
      _log('start no-op: already listening (area=$area)');
      return;
    }

    // ✅ 세션 토큰 증가 및 캡처(경고 해결 포인트)
    _listenSeq += 1;
    final int mySeq = _listenSeq;

    _lastKnownArea = area;

    // ✅ start 시점 prefs 하이드레이션(자동 로드)
    await _hydrateFromPrefsSafe(reason: 'start(area=$area, seq=$mySeq, force=$force)', force: true);

    // ✅ 실효 마스터 OFF면 구독 자체를 시작하지 않음
    if (!_effectiveMasterOn()) {
      _log('start aborted: effective master OFF → stop() and return (seq=$mySeq)');
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

    // 모니터링할 타입
    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];

    try {
      // 서버 기준선(지역 최신 1건) 확보
      await _fetchBaseline(area, typesToMonitor);

      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', whereIn: typesToMonitor)
          .orderBy('updatedAt')
          .orderBy(FieldPath.documentId);

      if (_baselineUpdatedAt != null && _baselineDocId != null) {
        query = query.startAfter([_baselineUpdatedAt, _baselineDocId]);
        _log('apply cursor(startAfter): ts=${_baselineUpdatedAt?.toDate().toUtc()} id=$_baselineDocId (seq=$mySeq)');
      } else {
        _log('no baseline available → start without cursor (seq=$mySeq)');
      }

      _resetReadCounters();
      _log('▶ START listen (area=$area, seq=$mySeq)');

      _subscription = query.snapshots().listen((snapshot) async {
        // ✅ stale 콜백 드랍: start/stop 재진입 시 늦게 오는 이벤트 무시
        if (mySeq != _listenSeq) {
          _log('drop stale snapshot (seq mismatch) my=$mySeq current=$_listenSeq');
          return;
        }

        // ✅ snapshot 진입 시점에도 prefs 재동기화(전달 누락/다른 isolate stale 방지)
        await _hydrateFromPrefsSafe(reason: 'snapshot(area=$_currentArea, seq=$mySeq)', force: false);

        // ✅ 실효 마스터 OFF로 바뀌었다면 즉시 stop()하고 더 이상 처리하지 않음
        if (!_effectiveMasterOn()) {
          _log('snapshot aborted: effective master OFF → stop() (seq=$mySeq)');
          await stop();
          return;
        }

        // Firestore 로컬 보류 스냅샷은 과금 기준이 아님 → 건너뜀
        if (snapshot.metadata.hasPendingWrites) {
          _log('skip local pendingWrites snapshot (seq=$mySeq)');
          return;
        }

        final bool isFromCache = snapshot.metadata.isFromCache;
        final docChanges = snapshot.docChanges;

        if (docChanges.isEmpty) {
          _readsEmptySnapshots += 1;
          return;
        }

        // 통계
        _readsTotal += 1;
        _readsAdded += docChanges.where((c) => c.type == DocumentChangeType.added).length;
        _readsModified += docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        _readsRemoved += docChanges.where((c) => c.type == DocumentChangeType.removed).length;

        _log('snapshot changes=${docChanges.length}, fromCache=$isFromCache (seq=$mySeq)');

        // ✅ 비용 보고: snapshot이 캐시가 아니고, 문서 변경이 있다면 → 문서 읽기 수 만큼 report
        if (!isFromCache) {
          final int billedReads = docChanges.length; // added/modified/removed 모두 읽기 1로 취급
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
          // stale 콜백 방어(루프 중에도 stop/start가 일어날 수 있음)
          if (mySeq != _listenSeq) {
            _log('drop stale loop (seq mismatch) my=$mySeq current=$_listenSeq');
            return;
          }

          final doc = change.doc;
          final data = doc.data();
          if (data == null) continue;

          final docId = doc.id;
          final newType = data['type'] as String?;
          final location = (data['location'] as String?) ?? '';
          final plateNumber = (data['plate_number'] as String?) ?? '';

          final tail = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;
          final spokenTail = _convertToKoreanDigits(_digitsOnly(tail));

          bool didSpeak = false;

          // 필터 미적용 타입은 즉시 skip (ON/OFF 정책 그대로 반영)
          if (!_isEnabledForType(newType)) {
            _log('skip by filter: type=$newType id=$docId (seq=$mySeq)');
            _lastTypes[docId] = newType; // 상태는 갱신
            continue;
          }

          if (change.type == DocumentChangeType.added) {
            // Added는 쿼리 집합에 '처음' 들어온 것 — startAfter 덕에 기준선 이후만 들어옴
            if (_dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '출차 완료 $spokenTail, $location';
                _log('SPEAK(added×$_completionRepeat): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              } else {
                _log('ignore added: type=$newType id=$docId (seq=$mySeq)');
              }
            } else {
              _log('dedup skip added id=$docId (seq=$mySeq)');
            }
          } else if (change.type == DocumentChangeType.modified) {
            // ✨ 타입 변경에 대해서만 발화
            final prevType = _lastTypes[docId];
            final typeChanged = prevType != null && prevType != newType;

            if (typeChanged && _dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _safeSpeak(utter);
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '$spokenTail 출차 완료 되었습니다.';
                _log('SPEAK(modified→type change×$_completionRepeat): $utter (id=$docId, area=$_currentArea, seq=$mySeq)');
                _notifyPlateEvent(docId: docId, type: newType, plateNumber: plateNumber, location: location);
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              }
            } else {
              _log('ignore modified (no type change or dedup) id=$docId (seq=$mySeq)');
            }
          } else {
            _log('ignore changeType=${change.type} id=$docId (seq=$mySeq)');
          }

          _lastTypes[docId] = newType;

          if (didSpeak) {
            // 후처리 훅(필요 시 확장)
          }
        }
      }, onError: (e, st) {
        if (mySeq != _listenSeq) return; // stale 에러 콜백은 무시
        _log('listen error: $e\n$st (seq=$mySeq)');
        _printReadSummary(prefix: 'READ SUMMARY (listen-error)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.error');
      }, onDone: () {
        if (mySeq != _listenSeq) return; // stale done 콜백은 무시
        _log('listen done (seq=$mySeq)');
        _printReadSummary(prefix: 'READ SUMMARY (done)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.done');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st (seq=$mySeq)');
      _printReadSummary(prefix: 'READ SUMMARY (start-error)');
    }
  }

  static Future<void> _fetchBaseline(String currentArea, List<String> types) async {
    try {
      // 최신 1건(서버 기준)으로 baseline 잡기
      final qs = await FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: types)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        _baselineUpdatedAt = null;
        _baselineDocId = null;
        _log('baseline: none (0 docs)');
        return;
      }

      final doc = qs.docs.first;
      final data = doc.data();
      final ts = data['updatedAt'];
      if (ts is Timestamp) {
        _baselineUpdatedAt = ts;
        _baselineDocId = doc.id;
        _log('baseline: ts=${ts.toDate().toUtc()} id=${doc.id}');
      } else {
        _baselineUpdatedAt = null;
        _baselineDocId = null;
        _log('baseline: updatedAt not Timestamp (id=${doc.id})');
      }
    } catch (e, st) {
      _baselineUpdatedAt = null;
      _baselineDocId = null;
      _log('baseline fetch error: $e\n$st');
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
    try {
      await TtsManager.speak(text);
    } catch (e) {
      _log('TTS error: $e');
    }
  }

  static Future<void> _speakRepeated(String text, {int times = 2, Duration gap = Duration.zero}) async {
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

  /// ✅ 번호판 이벤트 발생 시 로컬 알림(팝업) 발행
  ///
  /// 요구사항:
  /// - 차량 번호 전체(plate_number) + 주차 구역 명(location)이 반드시 알림에 포함
  /// - DashboardSetting 스위치(입차/출차/완료) 기준으로 ON인 타입만 알림 발생
  static void _notifyPlateEvent({
    required String docId,
    required String? type,
    required String plateNumber,
    required String location,
  }) {
    // 필터 OFF면 알림도 OFF
    if (!_isEnabledForType(type)) return;

    final title = _titleForType(type);
    if (title.isEmpty) return;

    // fire-and-forget: 스냅샷 처리 성능 저하 방지
    Future.microtask(() => PlateLocalNotificationService.instance.showPlateEvent(
      docId: docId,
      title: title,
      area: _currentArea,
      plateNumber: plateNumber,
      parkingLocation: location,
    ));
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

  // ===== UsageReporter 헬퍼 =====

  static void _reportUsageRead({
    required String? area,
    required int n,
    required String source,
    bool sampled = true,
  }) {
    final a = (area == null || area.isEmpty) ? '(unknown)' : area;
    if (n <= 0) return;

    // 샘플링
    if (_usageSampleRate <= 0) return;
    if (_usageSampleRate < 1.0 && sampled) {
      final r = (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
      if (r > _usageSampleRate) return;
    }

    // UsageReporter.read(...) 같은 실제 계측이 있었다면 여기서 호출
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
