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
// 주의: 쿼리 정렬 순서와 startAfter 필드 순서는 반드시 동일해야 함.
// 필요한 인덱스(예): area + type + updatedAt + __name__ (ASC/ASC/ASC/ASC)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../enums/plate_type.dart';
import '../tts/tts_manager.dart';
import '../tts/tts_user_filters.dart';

// import '../usage_reporter.dart';

class PlateTtsListenerService {
  // -----------------------------
  // Runtime master / filters
  // -----------------------------

  // 마스터 토글(호출부에서 masterOn을 주입할 수 있으나,
  // ✅ 이번 리팩터링에서는 prefs 하이드레이션으로도 보정됩니다.)
  static bool _enabled = true;

  // ✅ 유저 선택 필터(기본: 전부 on)
  static TtsUserFilters _filters = TtsUserFilters.defaults();

  // ✅ 마지막으로 알고 있는 지역(OFF→ON 재시작용)
  static String? _lastKnownArea;

  // ✅ prefs 하이드레이션(짧은 쿨다운으로 빈번한 prefs read 방지)
  static DateTime? _lastHydratedAt;
  static bool _hydrateBusy = false;
  static const Duration _hydrateCooldown = Duration(milliseconds: 800);

  // ✅ 정책 적용 중 중복 실행 방지
  static bool _policyBusy = false;

  // -----------------------------
  // Usage sampling (기존)
  // -----------------------------

  /// 설치 단위 사용량 보고 샘플링 비율(0.0~1.0). 너무 자주 쓰면 보고(write) 비용이 증가합니다.
  static double _usageSampleRate = 0.2; // 기본 20%
  static void setUsageSampleRate(double r) {
    if (r < 0) r = 0;
    if (r > 1) r = 1;
    _usageSampleRate = r;
    _log('usageSampleRate=$_usageSampleRate');
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
  // Listening state (기존)
  // -----------------------------

  // 리스닝 핸들
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  // 타입 전환 감지용
  static final Map<String, String?> _lastTypes = {};

  // 짧은 디듀프(문서별 일정 시간 내 중복 발화 방지)
  static final Map<String, DateTime> _lastSpokenAt = {};

  // 기준 상태
  static int _listenSeq = 0;
  static String? _currentArea;

  // 서버 기준선(해당 지역 최신 1건, updatedAt 기준)
  static Timestamp? _baselineUpdatedAt;
  static String? _baselineDocId;

  // 출차 완료 반복
  static const int _completionRepeat = 2;
  static const Duration _completionRepeatGap = Duration(milliseconds: 700);

  // (옵션) 기준선이 전혀 없을 때 참고용으로만 쓰는 초기 포함 윈도우
  static Duration _initialWindow = const Duration(minutes: 30);

  static Future<void> setInitialWindow(Duration d) async {
    _initialWindow = d;
    _log('initialWindow=${_initialWindow.inMinutes}m');
  }

  // speak 디듀프 윈도우
  static Duration _speakDedupWindow = const Duration(seconds: 2);

  static Future<void> setSpeakDedupWindow(Duration d) async {
    _speakDedupWindow = d;
    _log('speakDedupWindow=${_speakDedupWindow.inMilliseconds}ms');
  }

  // ✅ 실효 마스터: "스위치가 하나도 켜져있지 않으면" 구독/발화 모두 중단
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

  static void _log(String msg) => debugPrint('[PLATE_TTS][$_listenSeq][${_ts()}] $msg');

  static String _ts() => DateTime.now().toIso8601String();

  // ✅ prefs 하이드레이션: 필터/마스터가 stale로 남는 것을 차단
  static Future<void> _hydrateFromPrefsSafe({
    required String reason,
    bool force = false,
  }) async {
    final now = DateTime.now();

    if (!force && _lastHydratedAt != null) {
      final dt = now.difference(_lastHydratedAt!);
      if (dt < _hydrateCooldown) return;
    }

    if (_hydrateBusy) return;
    _hydrateBusy = true;
    try {
      final loaded = await TtsUserFilters.load();
      _filters = loaded;

      // ✅ 이 프로젝트에서 masterOn은 filters OR로 결정되는 구조이므로
      // prefs 하이드레이션 시에도 동일 규칙으로 _enabled를 보정합니다.
      final masterOn = loaded.parking || loaded.departure || loaded.completed;
      _enabled = masterOn;

      _lastHydratedAt = now;
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
    if (_subscription != null) {
      _log('▶ STOP listen (area=$_currentArea)');
      // 비용 카운트를 증가시키지 않는 흔적만 남김
      _annotateUsage(area: _currentArea, source: 'PlateTTS.stop');
    }
    await _subscription?.cancel();
    _subscription = null;

    // ✅ OFF→ON 재시작을 위해 _lastKnownArea는 유지
    _currentArea = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();

    _baselineUpdatedAt = null;
    _baselineDocId = null;
  }

  static Future<void> _startListening(String currentArea, {bool force = false}) async {
    await _ensureFirebaseInThisIsolate();

    _listenSeq += 1;
    _lastKnownArea = currentArea;

    // ✅ start 시점 prefs 하이드레이션(자동 로드)
    await _hydrateFromPrefsSafe(reason: 'start(area=$currentArea)', force: true);

    // ✅ 실효 마스터 OFF면 구독 자체를 시작하지 않음
    if (!_effectiveMasterOn()) {
      _log('start aborted: effective master OFF → stop() and return');
      await stop();
      return;
    }

    await _subscription?.cancel();
    _subscription = null;
    _lastTypes.clear();
    _lastSpokenAt.clear();

    _baselineUpdatedAt = null;
    _baselineDocId = null;

    _currentArea = currentArea;

    // 시작 흔적(증분 없음)
    /*_annotateUsage(area: _currentArea, source: 'PlateTTS.start');*/

    // 모니터링할 타입
    final typesToMonitor = <String>[
      PlateType.parkingRequests.firestoreValue,
      PlateType.departureRequests.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];

    try {
      // 1) 기준선(앵커) 확보 — 최신 updatedAt DESC, __name__ DESC
      await _fetchBaseline(currentArea, typesToMonitor);

      // 2) 리스닝 쿼리 구성 (updatedAt ASC, __name__ ASC)
      //    ✨ startAfter([_baselineUpdatedAt, _baselineDocId])로 첫 스냅샷도 '기준선 이후'만 수신
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: currentArea)
          .where('type', whereIn: typesToMonitor)
          .orderBy('updatedAt')
          .orderBy(FieldPath.documentId);

      if (_baselineUpdatedAt != null && _baselineDocId != null) {
        query = query.startAfter([_baselineUpdatedAt, _baselineDocId]);
        _log('apply cursor(startAfter): ts=${_baselineUpdatedAt?.toDate().toUtc()} id=$_baselineDocId');
      } else {
        // 기준선이 없으면 — 문서 0건 상황.
        // (옵션) 여기서 where(updatedAt >= now - _initialWindow) 하한을 추가할 수도 있음.
        _log('no baseline available → start without cursor');
      }

      _resetReadCounters();
      _log('▶ START listen (area=$currentArea)');

      _subscription = query.snapshots().listen((snapshot) async {
        // ✅ snapshot 진입 시점에도 prefs 재동기화(전달 누락/다른 isolate stale 방지)
        await _hydrateFromPrefsSafe(reason: 'snapshot(area=$_currentArea)', force: false);

        // ✅ 실효 마스터 OFF로 바뀌었다면 즉시 stop()하고 더 이상 처리하지 않음
        if (!_effectiveMasterOn()) {
          _log('snapshot aborted: effective master OFF → stop()');
          await stop();
          return;
        }

        // Firestore 로컬 보류 스냅샷은 과금 기준이 아님 → 건너뜀
        if (snapshot.metadata.hasPendingWrites) {
          _log('skip local pendingWrites snapshot');
          return;
        }

        final bool isFromCache = snapshot.metadata.isFromCache;
        final docChanges = snapshot.docChanges;

        if (docChanges.isEmpty) {
          _readsEmptySnapshots += 1;
          // 빈 스냅샷도 네트워크 왕복이 가능하지만, Firestore 과금은 "문서 읽기" 단위이므로 0으로 처리.
          // 추적만 남김(증분 없음).
          /*_annotateUsage(area: _currentArea, source: 'PlateTTS.listen.empty');*/
          return;
        }

        // 통계
        _readsTotal += 1;
        _readsAdded += docChanges.where((c) => c.type == DocumentChangeType.added).length;
        _readsModified += docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        _readsRemoved += docChanges.where((c) => c.type == DocumentChangeType.removed).length;

        _log('snapshot changes=${docChanges.length}, fromCache=$isFromCache');

        // ✅ 비용 보고: snapshot이 캐시가 아니고, 문서 변경이 있다면 → 문서 읽기 수 만큼 report
        if (!isFromCache) {
          final int billedReads = docChanges.length; // added/modified/removed 모두 읽기 1로 취급
          if (billedReads > 0) {
            _reportUsageRead(
              area: _currentArea,
              n: billedReads,
              source: 'PlateTTS.listen.snapshot',
              sampled: true,
            );
          }
        } else {
          // 캐시 스냅샷이면 비용 증가 없이 흔적만 남김
          _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.cache');
        }

        // ✨ 첫 스냅샷도 커서 이후만 오므로 발화 OK

        for (final change in docChanges) {
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

          // 필터 미적용 타입은 즉시 skip
          if (!_isEnabledForType(newType)) {
            _log('skip by filter: type=$newType id=$docId');
            _lastTypes[docId] = newType; // 상태는 갱신
            continue;
          }

          if (change.type == DocumentChangeType.added) {
            // Added는 쿼리 집합에 '처음' 들어온 것 — startAfter 덕에 기준선 이후만 들어옴
            if (_dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청'; // 필요시 '입차 요청 $spokenTail, $location'로 확장 가능
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(added): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '출차 완료 $spokenTail, $location';
                _log('SPEAK(added×$_completionRepeat): $utter (id=$docId, area=$_currentArea)');
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              } else {
                _log('ignore added: type=$newType id=$docId');
              }
            } else {
              _log('dedup skip added id=$docId');
            }
          } else if (change.type == DocumentChangeType.modified) {
            // ✨ 타입 변경에 대해서만 발화
            final prevType = _lastTypes[docId];
            final typeChanged = prevType != null && prevType != newType;

            if (typeChanged && _dedup(docId)) {
              if (newType == PlateType.parkingRequests.firestoreValue) {
                final utter = '입차 요청';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureRequests.firestoreValue) {
                final utter = '출차 요청 $spokenTail, $location';
                _log('SPEAK(modified→type change): $utter (id=$docId, area=$_currentArea)');
                _safeSpeak(utter);
                didSpeak = true;
              } else if (newType == PlateType.departureCompleted.firestoreValue) {
                final utter = '$spokenTail 출차 완료 되었습니다.';
                _log('SPEAK(modified→type change×$_completionRepeat): $utter (id=$docId, area=$_currentArea)');
                _speakRepeated(utter, times: _completionRepeat, gap: _completionRepeatGap);
                didSpeak = true;
              }
            } else {
              _log('ignore modified (no type change or dedup) id=$docId');
            }
          } else {
            _log('ignore changeType=${change.type} id=$docId');
          }

          _lastTypes[docId] = newType;

          if (didSpeak) {
            // 후처리 훅(필요 시 확장)
          }
        }
      }, onError: (e, st) {
        _log('listen error: $e\n$st');
        _printReadSummary(prefix: 'READ SUMMARY (listen-error)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.error');
      }, onDone: () {
        _log('listen done');
        _printReadSummary(prefix: 'READ SUMMARY (done)');
        _annotateUsage(area: _currentArea, source: 'PlateTTS.listen.done');
      });
    } catch (e, st) {
      _log('START ERROR: $e\n$st');
      _printReadSummary(prefix: 'READ SUMMARY (start-error)');
      /*_annotateUsage(area: _currentArea, source: 'PlateTTS.start.error');*/
    }
  }

  static Future<void> _fetchBaseline(
      String area,
      List<String> typesToMonitor,
      ) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', whereIn: typesToMonitor)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) {
        _baselineUpdatedAt = null;
        _baselineDocId = null;
        _log('baseline(updatedAt): (none)');
      } else {
        final d = qs.docs.first;
        _baselineUpdatedAt = d.data()['updatedAt'] as Timestamp?;
        _baselineDocId = d.id;
        _log(
          'baseline(updatedAt): ts=${_baselineUpdatedAt?.toDate().toUtc()} id=$_baselineDocId (reads+${qs.docs.length})',
        );
      }

      // ✅ 기준선 조회로 발생한 "문서 읽기 수" 보고(샘플링)
      // limit(1)이므로 0 또는 1
      if (qs.docs.isNotEmpty) {
        _reportUsageRead(
          area: area,
          n: qs.docs.length,
          source: 'PlateTTS.baseline',
          sampled: true,
        );
      } else {
        _annotateUsage(area: area, source: 'PlateTTS.baseline.empty');
      }

      _printReadSummary(prefix: 'READ SUMMARY (after baseline)');
    } catch (e, st) {
      _log('baseline fetch error: $e\n$st');
      _annotateUsage(area: area, source: 'PlateTTS.baseline.error');
    }
  }

  // ===== 통계 및 유틸 =====
  static int _readsTotal = 0;
  static int _readsAdded = 0;
  static int _readsModified = 0;
  static int _readsRemoved = 0;
  static int _readsEmptySnapshots = 0;

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

  static String _convertToKoreanDigits(String digits) {
    const koreanDigits = {
      '0': '영',
      '1': '하나',
      '2': '둘',
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
    if (n <= 0) {
      _annotateUsage(area: a, source: '$source.zero');
      return;
    }
    if (sampled) {
      /*UsageReporter.instance.reportSampled(
        area: a,
        action: 'read',
        n: n,
        source: source,
        sampleRate: _usageSampleRate,
      );*/
    } else {
      /*UsageReporter.instance.report(
        area: a,
        action: 'read',
        n: n,
        source: source,
      );*/
    }
  }

  static void _annotateUsage({required String? area, required String source}) {
    // ignore: unused_local_variable
    final a = (area == null || area.isEmpty) ? '(unknown)' : area;
    /*UsageReporter.instance.annotate(
      area: a,
      source: source,
    );*/
  }
}
