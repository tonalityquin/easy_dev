import 'dart:math' as math;

enum ChatRole { user, assistant }

enum ChatMode { auto, localOnly, onlineOnly, offlineOnly }

enum ChillMood {
  calm,
  focus,
  breakTime,
  proud,
  sleepy,
}

class ChillCompanionProfile {
  final int seed;
  final String name;

  const ChillCompanionProfile({required this.seed, required this.name});

  ChillCompanionProfile copyWith({int? seed, String? name}) {
    return ChillCompanionProfile(
      seed: seed ?? this.seed,
      name: name ?? this.name,
    );
  }
}

class ChillCompanionEngine {
  ChillCompanionEngine({required int seed}) : _rng = math.Random(seed);

  final math.Random _rng;

  String greeting({required String name}) {
    return _pick([
      '$name 준비 완료.',
      '$name 대기 중.',
      '입력 대기.',
      '작업 선택.',
    ]);
  }

  String onFocusStart({required String name, required int minutes}) {
    return _pick([
      '집중 시작: ${minutes}분',
      '집중 진행: ${minutes}분',
      '타이머 시작: ${minutes}분',
    ]);
  }

  String onFocusStop({required String name}) {
    return _pick([
      '집중 중단',
      '타이머 중단',
      '집중 해제',
    ]);
  }

  String onFocusDone({required String name}) {
    return _pick([
      '집중 완료',
      '타이머 종료',
      '집중 종료',
    ]);
  }

  String onTodoAdded({required String title}) {
    final t = _short(title);
    return _pick([
      '할 일 추가: $t',
      '할 일 등록: $t',
      '할 일 저장: $t',
    ]);
  }

  String onTodoDone({required String title}) {
    final t = _short(title);
    return _pick([
      '할 일 완료: $t',
      '완료 처리: $t',
      '완료 저장: $t',
    ]);
  }

  String onNoteSaved() {
    return _pick([
      '메모 저장',
      '메모 완료',
      '저장 완료',
    ]);
  }

  String onEventAdded() {
    return _pick([
      '일정 추가',
      '일정 등록',
      '일정 저장',
    ]);
  }

  String idleHint({required String name}) {
    return _pick([
      '입력 대기.',
      '작업 선택.',
      '다음 작업 입력.',
      '상태 확인 필요.',
    ]);
  }

  String replyToUser({
    required String name,
    required String input,
    required ChillMood mood,
    required bool focusRunning,
    required String focusRemainLabel,
  }) {
    final raw = input.trim();
    if (raw.isEmpty) return idleHint(name: name);
    final t = raw.toLowerCase();

    bool has(List<String> keys) => keys.any((k) => t.contains(k));

    if (has(['안녕', 'ㅎㅇ', 'hello', 'hi'])) {
      return greeting(name: name);
    }
    if (has(['고마', 'thanks', 'thx'])) {
      return _pick([
        '확인.',
        '처리됨.',
        '응답 완료.',
      ]);
    }
    if (has(['힘들', '지쳐', '피곤', '우울', '멘붕', '스트레스'])) {
      return _pick([
        '휴식 권장.',
        '부하 높음.',
        '상태 조정 필요.',
        '우선순위 축소 필요.',
      ]);
    }
    if (has(['집중', '공부', '일해', '작업', '포모', 'pomodoro'])) {
      if (focusRunning) {
        final left = focusRemainLabel.isEmpty ? '집중 진행 중.' : '집중 진행 중: $focusRemainLabel';
        return _pick([
          left,
          '집중 유지.',
          '남은 시간 확인.',
        ]);
      }
      return _pick([
        '집중 시작 가능.',
        '집중 시간 입력.',
        '타이머 설정 가능.',
      ]);
    }
    if (has(['할 일', 'todo', '투두'])) {
      return _pick([
        '할 일 입력.',
        '할 일 추가 가능.',
        '할 일 목록 확인.',
      ]);
    }
    if (has(['일정', '캘린더', 'calendar'])) {
      return _pick([
        '일정 입력.',
        '일정 추가 가능.',
        '시간 정보 입력.',
      ]);
    }
    if (t.endsWith('?') || has(['어떻게', '뭐', '왜', '어디', '언제'])) {
      return _pick([
        '목표 입력.',
        '우선순위 입력.',
        '대상 입력.',
      ]);
    }

    switch (mood) {
      case ChillMood.focus:
        return _pick([
          '집중 유지.',
          '작업 계속.',
        ]);
      case ChillMood.breakTime:
        return _pick([
          '휴식 중.',
          '재개 전 대기.',
        ]);
      case ChillMood.proud:
        return _pick([
          '완료 상태.',
          '다음 작업 가능.',
        ]);
      case ChillMood.sleepy:
        return _pick([
          '휴식 필요.',
          '집중 저하.',
        ]);
      case ChillMood.calm:
        return _pick([
          '다음 작업 입력.',
          '상태 대기.',
        ]);
    }
  }

  String _pick(List<String> list) {
    if (list.isEmpty) return '';
    return list[_rng.nextInt(list.length)];
  }

  String _short(String s) {
    final t = s.trim().replaceAll('\n', ' ');
    if (t.length <= 18) return t;
    return '${t.substring(0, 18)}…';
  }
}
