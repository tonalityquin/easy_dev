// lib/services/latest_message_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// import '../utils/usage_reporter.dart';

/// 최근 메시지 데이터(텍스트/타임스탬프/메타)
class LatestMessageData {
  final String text;
  final String? name;
  final Timestamp? timestamp;
  final bool isFromCache;
  final bool hasPendingWrites;

  const LatestMessageData({
    required this.text,
    required this.name,
    required this.timestamp,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  factory LatestMessageData.empty() => const LatestMessageData(
    text: '',
    name: null,
    timestamp: null,
    isFromCache: true,
    hasPendingWrites: false,
  );

  LatestMessageData copyWith({
    String? text,
    String? name,
    Timestamp? timestamp,
    bool? isFromCache,
    bool? hasPendingWrites,
  }) {
    return LatestMessageData(
      text: text ?? this.text,
      name: name ?? this.name,
      timestamp: timestamp ?? this.timestamp,
      isFromCache: isFromCache ?? this.isFromCache,
      hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
    );
  }
}

/// 전역 단일 Firestore 구독자
/// - 서버 확정 스냅(!isFromCache && !hasPendingWrites)에서만 캐시/집계
/// - UI/다른 서비스는 latest(ValueListenable)만 구독
/// - ‘다시 듣기’는 SharedPreferences만 읽음 → 클릭 시 READ 0
class LatestMessageService {
  LatestMessageService._();
  static final instance = LatestMessageService._();

  final _db = FirebaseFirestore.instance;

  String _area = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// 메모리 캐시 (UI/리스너는 이것만 구독)
  final ValueNotifier<LatestMessageData> latest =
  ValueNotifier<LatestMessageData>(LatestMessageData.empty());

  String _prefsKey(String area) => 'chat.latest_message.$area';

  // 중복 집계 방지(서버 확정 스냅 기준)
  String? _lastCountedText;
  Timestamp? _lastCountedTs;

  Future<void> start(String area) async {
    final next = area.trim();
    if (next.isEmpty) return;
    if (_area == next && _sub != null) return; // 이미 같은 area로 구독 중이면 무시

    await stop();
    _area = next;

    // 1) SharedPreferences 캐시 선반영 → 버튼 즉시 활성/비활성
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = (sp.getString(_prefsKey(_area)) ?? '').trim();
      latest.value = latest.value.copyWith(
        text: cached,
        // name/timestamp는 로컬에 별도 저장하지 않으므로 유지
        isFromCache: true,
        hasPendingWrites: false,
      );
    } catch (_) {
      // ignore
    }

    // 2) Firestore 실시간 구독 시작(유일한 구독 지점)
    final ref =
    _db.collection('chats').doc(_area).collection('state').doc('latest_message');

    _sub = ref.snapshots(/* includeMetadataChanges: false */).listen((snap) async {
      final data = snap.data();
      final msg = (data == null) ? '' : (data['message'] as String? ?? '');
      final name = (data == null) ? null : (data['name'] as String?);
      final ts = (data == null) ? null : (data['timestamp'] as Timestamp?);

      // 메모리 캐시는 항상 갱신(UX 즉시성 확보)
      latest.value = LatestMessageData(
        text: msg.trim(),
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : null,
        timestamp: ts,
        isFromCache: snap.metadata.isFromCache,
        hasPendingWrites: snap.metadata.hasPendingWrites,
      );

      // 서버 확정 스냅샷에서만 캐시/집계
      final bool isServer =
          !snap.metadata.isFromCache && !snap.metadata.hasPendingWrites;
      if (!isServer) return;

      // SharedPreferences 캐시 저장(‘다시 듣기’는 여기만 읽음)
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_prefsKey(_area), msg.trim());
      } catch (_) {
        // ignore
      }

      // 중복 집계 방지(동일 텍스트 + 동일 타임스탬프는 스킵)
      final sameText = _lastCountedText == msg.trim();
      final sameTs = (_lastCountedTs == null && ts == null) ||
          (_lastCountedTs != null &&
              ts != null &&
              _lastCountedTs!.millisecondsSinceEpoch ==
                  ts.millisecondsSinceEpoch);
      if (sameText && sameTs) return;

      _lastCountedText = msg.trim();
      _lastCountedTs = ts;

      // 서버 확정 스냅샷 1회만 READ 집계
      try {
        /*await UsageReporter.instance.report(
          area: _area,
          action: 'read',
          n: 1,
          source: 'latest_message.service.server',
        );*/
      } catch (_) {
        // ignore
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _lastCountedText = null;
    _lastCountedTs = null;
  }

  /// 버튼은 무조건 로컬 캐시만 통해 재생 → 클릭 시 READ 0
  Future<String> readFromPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return (sp.getString(_prefsKey(_area)) ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}
