import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../../simple_mode/utils/simple_mode/simple_mode_attendance_repository.dart';

/// 타임카드 펀칭 느낌의 짧은 피드백 시트를 띄우는 헬퍼
///
/// - DB에는 실제 시간(HH:mm)을 저장하지만,
/// - 이 UI에서는 "몇 시"인지는 전혀 보여주지 않고
///   출근/휴게/퇴근 중 어느 칸이 펀칭되었는지만 시각적으로 표현한다.
Future<void> showLiteDashboardPunchCardFeedback(
    BuildContext context, {
      required SimpleModeAttendanceType type,
      required DateTime dateTime,
    }) async {
  // 촉각 + 시스템 사운드로 피드백
  HapticFeedback.mediumImpact();
  SystemSound.play(SystemSoundType.click);

  // 하단에서 올라오는 showModalBottomSheet 대신,
  // 위(topCenter)에서 아래로 내려왔다가,
  // 다시 위로 올라가며 사라지는 showGeneralDialog + SlideTransition 사용
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'simple_punch_card_feedback',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, anim, secondaryAnim) {
      return _PunchCardSheet(
        type: type,
        dateTime: dateTime,
      );
    },
    transitionBuilder: (ctx, anim, secondaryAnim, child) {
      // 0 → 1: 위에서 아래로 떨어지는 등장
      // 1 → 0: 다시 위로 빠져 나가는 퇴장
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1.0), // 화면 위 바깥
          end: Offset.zero, // 제자리 (topCenter)
        ).animate(curved),
        child: child,
      );
    },
  );
}

String _typeLabel(SimpleModeAttendanceType type) {
  switch (type) {
    case SimpleModeAttendanceType.workIn:
      return '출근 펀칭';
    case SimpleModeAttendanceType.workOut:
      return '퇴근 펀칭';
    case SimpleModeAttendanceType.breakTime:
      return '휴게 펀칭';
  }
}

IconData _iconForType(SimpleModeAttendanceType type) {
  switch (type) {
    case SimpleModeAttendanceType.workIn:
      return Icons.login;
    case SimpleModeAttendanceType.workOut:
      return Icons.logout;
    case SimpleModeAttendanceType.breakTime:
      return Icons.free_breakfast;
  }
}

Color _accentColorForType(SimpleModeAttendanceType type) {
  switch (type) {
    case SimpleModeAttendanceType.workIn:
      return const Color(0xFF09367D); // 청록(출근)
    case SimpleModeAttendanceType.workOut:
      return const Color(0xFFEF6C53); // 오렌지(퇴근)
    case SimpleModeAttendanceType.breakTime:
      return const Color(0xFFF2A93B); // 노랑(휴게)
  }
}

/// 요일 문자열(월/화/수...)을 intl locale 초기화 없이 직접 반환
String _weekdayKo(DateTime dt) {
  // DateTime.weekday: 월=1 ... 일=7
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return days[dt.weekday - 1];
}

/// 짧게 나타났다 사라지는 "출퇴근기록카드" 피드백 시트
/// - 상단에 펀칭 헤드(스탬프)가 아래로 떨어지면서 카드에 찍히는 애니메이션
/// - 오늘 행에서 해당 칸만 강하게 하이라이트
class _PunchCardSheet extends StatefulWidget {
  final SimpleModeAttendanceType type;
  final DateTime dateTime;

  const _PunchCardSheet({
    required this.type,
    required this.dateTime,
  });

  @override
  State<_PunchCardSheet> createState() => _PunchCardSheetState();
}

class _PunchCardSheetState extends State<_PunchCardSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sheetScale;
  late final Animation<double> _headDrop; // 펀칭 헤드 낙하량(0~1)
  late final Animation<double> _flash; // 펀칭 셀 하이라이트 강도(0~1)

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    // 시트 전체는 약간 튕기면서 등장
    _sheetScale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    // 펀칭 헤드는 상단에서 카드까지 떨어지는 느낌
    _headDrop = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0.0,
        0.6,
        curve: Curves.easeInOutBack,
      ),
    );

    // 펀칭된 셀은 뒤쪽에서 살짝 번쩍이는 느낌
    _flash = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0.35,
        1.0,
        curve: Curves.easeOutQuad,
      ),
    );

    _controller.forward();

    // 약 1초 후 자동으로 닫히도록
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 950));
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _punchedWorkIn => widget.type == SimpleModeAttendanceType.workIn;
  bool get _punchedBreak => widget.type == SimpleModeAttendanceType.breakTime;
  bool get _punchedWorkOut => widget.type == SimpleModeAttendanceType.workOut;

  @override
  Widget build(BuildContext context) {
    final accentColor = _accentColorForType(widget.type);
    final typeIcon = _iconForType(widget.type);
    final typeLabel = _typeLabel(widget.type);

    final textTheme = Theme.of(context).textTheme;
    final date = widget.dateTime;
    final dateStr = DateFormat('MM.dd').format(date); // 예: 12.08
    final weekDayStr = _weekdayKo(date); // 예: 월, 화, ...
    final monthStr = DateFormat('yyyy.MM').format(date); // 예: 2025.12

    return SafeArea(
      child: Padding(
        // 상단에서 내려오는 시트이므로, 위쪽 여백을 조금 두고 topCenter에 정렬
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ScaleTransition(
            scale: _sheetScale,
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // 펀칭 헤드 낙하에 따라 Y 이동 (위에서 아래로)
                  final headDy = lerpDouble(-32, 0, _headDrop.value) ?? 0;
                  // 하이라이트 강도(0~1)
                  final flashStrength = _flash.value;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCFAF5),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.20),
                            blurRadius: 20,
                            // 상단에 붙은 카드이므로, 그림자는 아래쪽으로 떨어지게 설정
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFFE0D7C5),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 상단 펀칭 헤드(스탬프)
                          Transform.translate(
                            offset: Offset(0, headDy),
                            child: Opacity(
                              // 살짝만 보이게
                              opacity: 0.85,
                              child: Container(
                                width: 68,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.grey[850],
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    typeIcon,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 헤더 라인: 제목 + 월
                          Row(
                            children: [
                              Text(
                                '출퇴근기록카드',
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3C342A),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                monthStr,
                                style: textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF7A6F63),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 두 번째 줄: 펀칭 타입 + 안내
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accentColor.withOpacity(0.12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accentColor.withOpacity(0.35),
                                      blurRadius: 6 * flashStrength,
                                      offset: Offset(
                                        0,
                                        2 * flashStrength,
                                      ),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  typeIcon,
                                  color: accentColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$typeLabel · 카드에 펀칭이 찍혔습니다.',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF8A7A65),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 실제 카드 영역
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE5DFD0),
                                width: 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // 상단 헤더 셀
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF3EEE3),
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      _HeaderCell(
                                        label: '일자',
                                        flex: 3,
                                      ),
                                      _HeaderCell(
                                        label: '출근',
                                        flex: 3,
                                      ),
                                      _HeaderCell(
                                        label: '휴게',
                                        flex: 3,
                                      ),
                                      _HeaderCell(
                                        label: '퇴근',
                                        flex: 3,
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(
                                  height: 1,
                                  thickness: 0.8,
                                  color: Color(0xFFE5DFD0),
                                ),
                                // 오늘 행
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      // 일자 셀
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dateStr,
                                              style: textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                const Color(0xFF3C342A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              weekDayStr,
                                              style: textTheme.labelSmall
                                                  ?.copyWith(
                                                color: const Color(0xFF7A6F63),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 출근 칸
                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedWorkIn,
                                          label: '출근',
                                          accentColor: _accentColorForType(
                                            SimpleModeAttendanceType.workIn,
                                          ),
                                          // 현재 펀칭 대상 칸 하이라이트
                                          highlighted: widget.type ==
                                              SimpleModeAttendanceType.workIn,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                      // 휴게 칸
                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedBreak,
                                          label: '휴게',
                                          accentColor: _accentColorForType(
                                            SimpleModeAttendanceType.breakTime,
                                          ),
                                          highlighted: widget.type ==
                                              SimpleModeAttendanceType
                                                  .breakTime,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                      // 퇴근 칸
                                      Expanded(
                                        flex: 3,
                                        child: _PunchStatusCell(
                                          punched: _punchedWorkOut,
                                          label: '퇴근',
                                          accentColor: _accentColorForType(
                                            SimpleModeAttendanceType.workOut,
                                          ),
                                          highlighted: widget.type ==
                                              SimpleModeAttendanceType.workOut,
                                          flashStrength: flashStrength,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '펀칭 완료',
                              style: textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF7A6F63),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 테이블 헤더 셀
class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _HeaderCell({
    required this.label,
    this.flex = 3,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF5C4E3D),
        ),
      ),
    );
  }
}

/// 시간 대신 "펀칭 여부 + 하이라이트"만 시각적으로 보여주는 셀
class _PunchStatusCell extends StatelessWidget {
  final bool punched;
  final String label;
  final Color accentColor;

  /// 이번에 사용자가 실제로 펀칭한 칸인지 여부
  final bool highlighted;

  /// 0~1 하이라이트 강도(애니메이션 값)
  final double flashStrength;

  const _PunchStatusCell({
    required this.punched,
    required this.label,
    required this.accentColor,
    required this.highlighted,
    required this.flashStrength,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final bool showCheck = punched;
    final double glow = highlighted ? flashStrength : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: highlighted
              ? accentColor.withOpacity(0.15 + 0.20 * glow)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: highlighted && glow > 0
              ? [
            BoxShadow(
              color: accentColor.withOpacity(0.40 * glow),
              blurRadius: 8 * glow,
              offset: Offset(0, 3 * glow),
            ),
          ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showCheck
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 16,
              color: showCheck
                  ? accentColor.withOpacity(0.95)
                  : const Color(0xFFB0A89C),
            ),
            const SizedBox(height: 2),
            Text(
              showCheck ? label : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: showCheck
                    ? const Color(0xFF2E2720)
                    : const Color(0xFF9C9286),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
