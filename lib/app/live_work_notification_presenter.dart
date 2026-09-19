import 'live_work_diagnostics.dart';
import 'live_work_snapshot.dart';

class LiveWorkNotificationPresentation {
  const LiveWorkNotificationPresentation({
    required this.title,
    required this.text,
    required this.shortText,
    required this.showBreakAction,
  });

  final String title;
  final String text;
  final String shortText;
  final bool showBreakAction;
}

class LiveWorkNotificationPresenter {
  LiveWorkNotificationPresenter._();

  static LiveWorkNotificationPresentation build(LiveWorkSnapshot snapshot) {
    if (!snapshot.isWorking) {
      return const LiveWorkNotificationPresentation(
        title: '업무 대기 중',
        text: '근무 시작을 기다리고 있습니다.',
        shortText: '대기',
        showBreakAction: false,
      );
    }

    final primary = _primary(snapshot);
    final details = <String>[];
    if (snapshot.actualClockIn != null) {
      details.add('출근 ${snapshot.actualClockIn}');
    }
    if (snapshot.currentSessionBreak != null) {
      details.add('휴게 ${snapshot.currentSessionBreak}');
    }
    if (snapshot.scheduledEnd != null) {
      details.add('예정 퇴근 ${_hhmm(snapshot.scheduledEnd!)}');
    }
    final text = details.isEmpty ? primary : '$primary\n${details.join(' · ')}';
    final presentation = LiveWorkNotificationPresentation(
      title: '근무 중',
      text: text,
      shortText: _shortText(snapshot),
      showBreakAction: snapshot.canPunchBreak,
    );
    LiveWorkDiagnostics.record('presentation_built', <String, Object?>{
      'title': presentation.title,
      'text': presentation.text.replaceAll('\n', ' / '),
      'shortText': presentation.shortText,
      'breakAction': presentation.showBreakAction,
      'currentSessionBreak': snapshot.currentSessionBreak,
      'staleBreakSuppressed': snapshot.hasStaleBreakForCurrentSession,
    });
    return presentation;
  }

  static String _primary(LiveWorkSnapshot snapshot) {
    final end = snapshot.scheduledEnd;
    if (end == null) return '현재 근무 세션이 진행 중입니다.';
    final difference = end.difference(snapshot.now);
    if (difference.isNegative || difference == Duration.zero) {
      final overdueMinutes = snapshot.overdueMinutes;
      if (overdueMinutes <= 0) {
        return '퇴근시간입니다 · 퇴근 기록을 확인해 주세요';
      }
      return '퇴근 기록이 필요합니다 · 예정시간 ${_durationText(snapshot.overdueDuration)} 초과';
    }
    return '퇴근까지 ${_durationText(difference)}';
  }

  static String _shortText(LiveWorkSnapshot snapshot) {
    final end = snapshot.scheduledEnd;
    if (end == null) return '근무중';
    final difference = end.difference(snapshot.now);
    if (difference.isNegative || difference == Duration.zero) {
      final overdueMinutes = snapshot.overdueMinutes;
      return overdueMinutes <= 0 ? '퇴근' : '+$overdueMinutes분';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}:${(difference.inMinutes % 60).toString().padLeft(2, '0')}';
    }
    return '${difference.inMinutes.clamp(1, 59)}분';
  }

  static String _durationText(Duration duration) {
    final minutes = duration.inMinutes.abs();
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours == 0) return '${minutes.clamp(0, 59)}분';
    if (remainder == 0) return '$hours시간';
    return '$hours시간 $remainder분';
  }

  static String _hhmm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
