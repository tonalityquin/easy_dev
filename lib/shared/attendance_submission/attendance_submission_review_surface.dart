import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import 'attendance_submission_diagnostics.dart';
import 'attendance_submission_repository.dart';
import 'attendance_submission_review_model.dart';

enum AttendanceSubmissionReviewSide {
  left,
  right,
}

class AttendanceSubmissionReviewWorkspace extends StatefulWidget {
  const AttendanceSubmissionReviewWorkspace({
    super.key,
    required this.kind,
    required this.area,
    required this.side,
    required this.onBack,
    this.developerMode = false,
    this.onBusyChanged,
    this.onSubmitted,
    this.source = 'workspace',
  });

  final AttendanceSubmissionKind kind;
  final String area;
  final AttendanceSubmissionReviewSide side;
  final VoidCallback onBack;
  final bool developerMode;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onSubmitted;
  final String source;

  @override
  State<AttendanceSubmissionReviewWorkspace> createState() =>
      _AttendanceSubmissionReviewWorkspaceState();
}

class _AttendanceSubmissionReviewWorkspaceState
    extends State<AttendanceSubmissionReviewWorkspace> {
  bool _busy = false;

  void _setBusy(bool value) {
    if (_busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            AttendanceSubmissionDiagnostics.log(
              'status',
              'developer_status_request source=${widget.source} kind=${widget.kind.name}',
            );
            unawaited(
              AttendanceSubmissionDiagnostics.showStatus(
                context,
                title: '${widget.kind.title} Review 상태',
              ),
            );
          },
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              children: [
                Semantics(
                  button: true,
                  label: '목록으로',
                  child: IconButton(
                    onPressed: _busy
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            widget.onBack();
                          },
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: _busy ? tokens.iconDisabled : tokens.iconPrimary,
                    ),
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.kind.icon,
                    size: 20,
                    color: tokens.onAccentContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.kind.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.area.trim().isEmpty ? '현재 근무지' : widget.area.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.developerMode)
                  Semantics(
                    button: true,
                    label: 'Review 상태',
                    child: IconButton(
                      onPressed: () {
                        AttendanceSubmissionDiagnostics.log(
                          'status',
                          'developer_status_button source=${widget.source} kind=${widget.kind.name}',
                        );
                        unawaited(
                          AttendanceSubmissionDiagnostics.showStatus(
                            context,
                            title: '${widget.kind.title} Review 상태',
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.bug_report_outlined,
                        color: tokens.iconSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AttendanceSubmissionReviewSurface(
            kind: widget.kind,
            source: widget.source,
            onBusyChanged: _setBusy,
            onSubmitted: widget.onSubmitted,
          ),
        ),
      ],
    );
  }
}

class AttendanceSubmissionReviewSurface extends StatefulWidget {
  const AttendanceSubmissionReviewSurface({
    super.key,
    required this.kind,
    required this.source,
    this.onBusyChanged,
    this.onSubmitted,
  });

  final AttendanceSubmissionKind kind;
  final String source;
  final ValueChanged<bool>? onBusyChanged;
  final VoidCallback? onSubmitted;

  @override
  State<AttendanceSubmissionReviewSurface> createState() =>
      _AttendanceSubmissionReviewSurfaceState();
}

class _AttendanceSubmissionReviewSurfaceState
    extends State<AttendanceSubmissionReviewSurface> {
  final AttendanceSubmissionReviewRepository _repository =
      AttendanceSubmissionReviewRepository.instance;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _draftDates = <String>{};
  AttendanceSubmissionReviewSnapshot? _snapshot;
  bool _loading = true;
  bool _busy = false;
  bool _messageFailure = false;
  String? _message;
  int _generation = 0;
  String? _lastSafeAreaSignature;

  DateFormat get _dateFormatter => DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    AttendanceSubmissionDiagnostics.log(
      'surface',
      'mounted source=${widget.source} kind=${widget.kind.name}',
    );
    unawaited(_load(source: 'init'));
  }

  @override
  void didUpdateWidget(covariant AttendanceSubmissionReviewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _draftDates.clear();
      _message = null;
      unawaited(_load(source: 'kind_changed'));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    AttendanceSubmissionDiagnostics.log(
      'surface',
      'disposed source=${widget.source} kind=${widget.kind.name}',
    );
    super.dispose();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
    AttendanceSubmissionDiagnostics.log(
      'surface',
      'busy source=${widget.source} kind=${widget.kind.name} value=$value',
    );
  }

  void _setMessage(String? message, {bool failure = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageFailure = failure;
    });
  }

  void _logSafeArea({
    required double bottomPadding,
    required double bottomViewPadding,
    required double bottomViewInset,
  }) {
    final signature =
        '${bottomPadding.toStringAsFixed(1)}|'
        '${bottomViewPadding.toStringAsFixed(1)}|'
        '${bottomViewInset.toStringAsFixed(1)}';
    if (_lastSafeAreaSignature == signature) return;
    _lastSafeAreaSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastSafeAreaSignature != signature) return;
      AttendanceSubmissionDiagnostics.log(
        'layout',
        'safe_area source=${widget.source} kind=${widget.kind.name} bottomPadding=${bottomPadding.toStringAsFixed(1)} bottomViewPadding=${bottomViewPadding.toStringAsFixed(1)} bottomViewInset=${bottomViewInset.toStringAsFixed(1)}',
      );
    });
  }

  Future<void> _load({required String source}) async {
    final generation = ++_generation;
    if (mounted) setState(() => _loading = true);
    try {
      final snapshot = await _repository.load(widget.kind);
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      AttendanceSubmissionDiagnostics.log(
        'surface',
        'ready source=${widget.source}/$source kind=${widget.kind.name} days=${snapshot.days.length} drafts=${_draftDates.length}',
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _snapshot = null;
        _loading = false;
        _message = '기록을 불러오지 못했습니다.';
        _messageFailure = true;
      });
      AttendanceSubmissionDiagnostics.log(
        'surface',
        'load_failure source=${widget.source}/$source kind=${widget.kind.name} error=$error stack=$stackTrace',
      );
    }
  }

  List<AttendanceReviewDay> _visibleDays() {
    final days = <AttendanceReviewDay>[
      ...?_snapshot?.days,
    ];
    final present = days
        .map((day) => _dateFormatter.format(day.date))
        .toSet();
    for (final key in _draftDates) {
      if (present.contains(key)) continue;
      try {
        days.add(
          AttendanceReviewDay(
            date: _dateFormatter.parseStrict(key),
            draft: true,
          ),
        );
      } catch (_) {}
    }
    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }

  Future<void> _addDate() async {
    if (_busy) return;
    final today = DateTime.now();
    final cutoff = _snapshot?.cutoffDay ??
        DateTime(today.year, today.month, today.day)
            .subtract(const Duration(days: 1));
    final firstDate = DateTime(2000, 1, 1);
    final initialDate = cutoff.isBefore(firstDate) ? firstDate : cutoff;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: initialDate,
    );
    if (selected == null || !mounted) return;
    final key = _dateFormatter.format(selected);
    final alreadyExists = _visibleDays().any(
      (day) => _dateFormatter.format(day.date) == key,
    );
    if (alreadyExists) {
      _setMessage('이미 Review 목록에 있는 날짜입니다.', failure: true);
      AttendanceSubmissionDiagnostics.log(
        'edit',
        'date_add_duplicate source=${widget.source} kind=${widget.kind.name} date=$key',
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _draftDates.add(key);
      _message = null;
    });
    AttendanceSubmissionDiagnostics.log(
      'edit',
      'date_added source=${widget.source} kind=${widget.kind.name} date=$key',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : CommonUiMotion.component,
        curve: CommonUiMotion.enter,
      );
    });
  }

  Future<void> _saveDay(
    AttendanceReviewDay day, {
    String? workIn,
    String? workOut,
    String? breakTime,
  }) async {
    if (_busy) return;
    _setBusy(true);
    try {
      await _repository.saveDay(
        kind: widget.kind,
        date: day.date,
        workIn: workIn,
        workOut: workOut,
        breakTime: breakTime,
      );
      final allEmpty = widget.kind == AttendanceSubmissionKind.commute
          ? (workIn == null || workIn.trim().isEmpty) &&
              (workOut == null || workOut.trim().isEmpty)
          : breakTime == null || breakTime.trim().isEmpty;
      final key = _dateFormatter.format(day.date);
      if (allEmpty) {
        _draftDates.add(key);
      } else {
        _draftDates.remove(key);
      }
      _setMessage('수정한 기록을 저장했습니다.');
      await _load(source: 'edit_saved');
    } catch (error, stackTrace) {
      _setMessage('기록을 저장하지 못했습니다.', failure: true);
      AttendanceSubmissionDiagnostics.log(
        'edit',
        'save_failure source=${widget.source} kind=${widget.kind.name} date=${_dateFormatter.format(day.date)} error=$error stack=$stackTrace',
      );
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<bool> _confirmDelete(AttendanceReviewDay day) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final text = Theme.of(dialogContext).textTheme;
        return Dialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${_formatDate(day.date)} 기록을 삭제하시겠습니까?',
                  style: text.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.kind == AttendanceSubmissionKind.commute
                      ? '해당 날짜의 출근과 퇴근 기록만 삭제합니다.'
                      : '해당 날짜의 휴게시간 기록만 삭제합니다.',
                  style: text.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('삭제'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!reduceMotion) await Future<void>.delayed(Duration.zero);
    return result ?? false;
  }

  Future<void> _deleteDay(AttendanceReviewDay day) async {
    if (_busy) return;
    final confirmed = await _confirmDelete(day);
    if (!confirmed || !mounted) return;
    _setBusy(true);
    try {
      final key = _dateFormatter.format(day.date);
      if (!day.draft) {
        await _repository.deleteDay(kind: widget.kind, date: day.date);
      }
      _draftDates.remove(key);
      _setMessage('날짜 기록을 삭제했습니다.');
      AttendanceSubmissionDiagnostics.log(
        'edit',
        'delete_complete source=${widget.source} kind=${widget.kind.name} date=$key draft=${day.draft}',
      );
      await _load(source: 'delete');
    } catch (error, stackTrace) {
      _setMessage('기록을 삭제하지 못했습니다.', failure: true);
      AttendanceSubmissionDiagnostics.log(
        'edit',
        'delete_failure source=${widget.source} kind=${widget.kind.name} date=${_dateFormatter.format(day.date)} error=$error stack=$stackTrace',
      );
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final days = _visibleDays();
    final invalid = days
        .where((day) =>
            day.stateFor(widget.kind) != AttendanceReviewDayState.complete)
        .toList(growable: false);
    if (invalid.isNotEmpty) {
      final missing = invalid
          .where((day) =>
              day.stateFor(widget.kind) == AttendanceReviewDayState.missing)
          .length;
      final empty = invalid.length - missing;
      _setMessage(
        widget.kind == AttendanceSubmissionKind.commute
            ? '누락 $missing일, 미기록 $empty일을 먼저 수정하거나 삭제해 주세요.'
            : '미기록 $empty일을 먼저 수정하거나 삭제해 주세요.',
        failure: true,
      );
      AttendanceSubmissionDiagnostics.log(
        'validation',
        'blocked source=${widget.source} kind=${widget.kind.name} missing=$missing empty=$empty',
      );
      HapticFeedback.mediumImpact();
      return;
    }
    if ((_snapshot?.eligibleRecordCount ?? 0) <= 0) {
      _setMessage('제출할 기록이 없습니다.', failure: true);
      return;
    }
    _setBusy(true);
    _setMessage(null);
    AttendanceSubmissionDiagnostics.log(
      'submit',
      'requested source=${widget.source} kind=${widget.kind.name} days=${days.length} records=${_snapshot?.eligibleRecordCount ?? 0}',
    );
    try {
      final result = await _repository.submit(context, widget.kind);
      if (!mounted) return;
      if (!result.confirmed) {
        _setMessage('제출을 취소했습니다.');
        return;
      }
      _setMessage(
        result.message ?? '제출 처리가 완료되었습니다.',
        failure: result.failedCount > 0,
      );
      await _load(source: 'after_submit');
      widget.onSubmitted?.call();
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  String _formatDate(DateTime date) => DateFormat('yyyy.MM.dd').format(date);

  String _weekday(DateTime date) {
    const labels = <String>['월', '화', '수', '목', '금', '토', '일'];
    return labels[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mediaQuery = MediaQuery.maybeOf(context);
    _logSafeArea(
      bottomPadding: mediaQuery?.padding.bottom ?? 0,
      bottomViewPadding: mediaQuery?.viewPadding.bottom ?? 0,
      bottomViewInset: mediaQuery?.viewInsets.bottom ?? 0,
    );
    final snapshot = _snapshot;
    final days = _visibleDays();
    final missingCount = days
        .where((day) =>
            day.stateFor(widget.kind) == AttendanceReviewDayState.missing)
        .length;
    final emptyCount = days
        .where((day) =>
            day.stateFor(widget.kind) == AttendanceReviewDayState.empty)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReviewSummary(
          kind: widget.kind,
          dayCount: days.length,
          missingCount: missingCount,
          emptyCount: emptyCount,
          cutoffDay: snapshot?.cutoffDay,
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          child: _message == null
              ? const SizedBox.shrink(key: ValueKey<String>('message_empty'))
              : _ReviewMessage(
                  key: ValueKey<String>('message_${_messageFailure}_$_message'),
                  message: _message!,
                  failure: _messageFailure,
                ),
        ),
        if (_message != null) const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              final curved = CurvedAnimation(
                parent: animation,
                curve: CommonUiMotion.enter,
                reverseCurve: CommonUiMotion.exit,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .02),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: _loading
                ? Center(
                    key: const ValueKey<String>('loading'),
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : days.isEmpty
                    ? _EmptyReview(
                        key: const ValueKey<String>('empty'),
                        kind: widget.kind,
                      )
                    : ListView.separated(
                        key: ValueKey<String>(
                          'list_${widget.kind.name}_${days.map((e) => _dateFormatter.format(e.date)).join('_')}',
                        ),
                        controller: _scrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: days.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final day = days[index];
                          return _AttendanceReviewDayTile(
                            key: ValueKey<String>(
                              '${widget.kind.name}_${_dateFormatter.format(day.date)}',
                            ),
                            kind: widget.kind,
                            day: day,
                            dateLabel:
                                '${_formatDate(day.date)} ${_weekday(day.date)}',
                            enabled: !_busy,
                            order: index,
                            onSave: ({workIn, workOut, breakTime}) => _saveDay(
                              day,
                              workIn: workIn,
                              workOut: workOut,
                              breakTime: breakTime,
                            ),
                            onDelete: () => _deleteDay(day),
                          );
                        },
                      ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
          curve: CommonUiMotion.standard,
          alignment: Alignment.topCenter,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _loading ? null : _addDate,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('날짜 추가'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _loading ? null : _submit,
                    icon: _busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.onAccent,
                            ),
                          )
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(_busy ? '처리 중' : '제출하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({
    required this.kind,
    required this.dayCount,
    required this.missingCount,
    required this.emptyCount,
    required this.cutoffDay,
  });

  final AttendanceSubmissionKind kind;
  final int dayCount;
  final int missingCount;
  final int emptyCount;
  final DateTime? cutoffDay;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final cutoff = cutoffDay == null
        ? '-'
        : DateFormat('yyyy.MM.dd').format(cutoffDay!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kind == AttendanceSubmissionKind.commute
                      ? '제출 대상 $dayCount일 · 누락 $missingCount일 · 미기록 $emptyCount일'
                      : '제출 대상 $dayCount일 · 미기록 $emptyCount일',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '제출 가능 날짜: $cutoff까지 · 오늘 기록은 제출 대상에서 제외됩니다.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    super.key,
    required this.message,
    required this.failure,
  });

  final String message;
  final bool failure;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: failure ? tokens.warningContainer : tokens.successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: failure
              ? tokens.onWarningContainer.withOpacity(.18)
              : tokens.onSuccessContainer.withOpacity(.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            failure ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: failure ? tokens.onWarningContainer : tokens.onSuccessContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(
                color: failure
                    ? tokens.onWarningContainer
                    : tokens.onSuccessContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({
    super.key,
    required this.kind,
  });

  final AttendanceSubmissionKind kind;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 32,
            color: tokens.iconSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            '현재 제출 가능한 ${kind.shortLabel} 기록이 없습니다.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

typedef _ReviewSaveCallback = Future<void> Function({
  String? workIn,
  String? workOut,
  String? breakTime,
});

class _AttendanceReviewDayTile extends StatefulWidget {
  const _AttendanceReviewDayTile({
    super.key,
    required this.kind,
    required this.day,
    required this.dateLabel,
    required this.enabled,
    required this.order,
    required this.onSave,
    required this.onDelete,
  });

  final AttendanceSubmissionKind kind;
  final AttendanceReviewDay day;
  final String dateLabel;
  final bool enabled;
  final int order;
  final _ReviewSaveCallback onSave;
  final Future<void> Function() onDelete;

  @override
  State<_AttendanceReviewDayTile> createState() =>
      _AttendanceReviewDayTileState();
}

class _AttendanceReviewDayTileState extends State<_AttendanceReviewDayTile> {
  bool _editing = false;
  bool _pressed = false;
  String? _workIn;
  String? _workOut;
  String? _breakTime;

  @override
  void initState() {
    super.initState();
    _resetValues();
  }

  @override
  void didUpdateWidget(covariant _AttendanceReviewDayTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.day != widget.day) {
      _resetValues();
    }
  }

  void _resetValues() {
    _workIn = widget.day.workIn;
    _workOut = widget.day.workOut;
    _breakTime = widget.day.breakTime;
  }

  Future<String?> _pickTime(String? current) async {
    final initial = _parseTime(current) ?? TimeOfDay.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null) return current;
    return '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay? _parseTime(String? value) {
    final parts = value?.split(':') ?? const <String>[];
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _save() async {
    await widget.onSave(
      workIn: _workIn,
      workOut: _workOut,
      breakTime: _breakTime,
    );
    if (!mounted) return;
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final state = widget.day.stateFor(widget.kind);
    final tone = _stateTone(tokens, state);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: 150 + widget.order.clamp(0, 6).toInt() * 18),
      curve: CommonUiMotion.enter,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 7),
            child: child,
          ),
        );
      },
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.standard,
        scale: _pressed ? .988 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled && !_editing
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _resetValues();
                      _editing = true;
                    });
                  }
                : null,
            onHighlightChanged: widget.enabled
                ? (pressed) {
                    if (_pressed == pressed) return;
                    setState(() => _pressed = pressed);
                  }
                : null,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _pressed ? tokens.surfaceSelected : tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tone.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.dateLabel,
                          style: text.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: tone.background,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          state.label,
                          style: text.labelSmall?.copyWith(
                            color: tone.foreground,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSize(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                    curve: CommonUiMotion.standard,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        if (reduceMotion) return child;
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .03),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _editing
                          ? _buildEditor(context)
                          : _buildDisplay(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDisplay(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey<String>('display'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.kind == AttendanceSubmissionKind.commute)
          Row(
            children: [
              Expanded(
                child: _TimeDisplay(
                  label: '출근',
                  value: widget.day.workIn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeDisplay(
                  label: '퇴근',
                  value: widget.day.workOut,
                ),
              ),
            ],
          )
        else
          _TimeDisplay(label: '휴게시간', value: widget.day.breakTime),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: widget.enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _resetValues();
                        _editing = true;
                      });
                    }
                  : null,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('수정'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: widget.enabled ? widget.onDelete : null,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 17,
                color: widget.enabled ? tokens.danger : tokens.textDisabled,
              ),
              label: Text(
                '삭제',
                style: text.labelLarge?.copyWith(
                  color: widget.enabled ? tokens.danger : tokens.textDisabled,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditor(BuildContext context) {
    return Column(
      key: const ValueKey<String>('editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.kind == AttendanceSubmissionKind.commute) ...[
          _TimeEditor(
            label: '출근',
            value: _workIn,
            enabled: widget.enabled,
            onPick: () async {
              final value = await _pickTime(_workIn);
              if (!mounted) return;
              setState(() => _workIn = value);
            },
            onClear: () => setState(() => _workIn = null),
          ),
          const SizedBox(height: 8),
          _TimeEditor(
            label: '퇴근',
            value: _workOut,
            enabled: widget.enabled,
            onPick: () async {
              final value = await _pickTime(_workOut);
              if (!mounted) return;
              setState(() => _workOut = value);
            },
            onClear: () => setState(() => _workOut = null),
          ),
        ] else
          _TimeEditor(
            label: '휴게시간',
            value: _breakTime,
            enabled: widget.enabled,
            onPick: () async {
              final value = await _pickTime(_breakTime);
              if (!mounted) return;
              setState(() => _breakTime = value);
            },
            onClear: () => setState(() => _breakTime = null),
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.enabled
                  ? () {
                      setState(() {
                        _resetValues();
                        _editing = false;
                      });
                    }
                  : null,
              child: const Text('취소'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: widget.enabled ? _save : null,
              child: const Text('저장'),
            ),
          ],
        ),
      ],
    );
  }

  _ReviewTone _stateTone(
    CommonUiTokens tokens,
    AttendanceReviewDayState state,
  ) {
    switch (state) {
      case AttendanceReviewDayState.complete:
        return _ReviewTone(
          background: tokens.successContainer,
          foreground: tokens.onSuccessContainer,
          border: tokens.borderSubtle,
        );
      case AttendanceReviewDayState.missing:
        return _ReviewTone(
          background: tokens.warningContainer,
          foreground: tokens.onWarningContainer,
          border: tokens.onWarningContainer.withOpacity(.28),
        );
      case AttendanceReviewDayState.empty:
        return _ReviewTone(
          background: tokens.surfaceSelected,
          foreground: tokens.textSecondary,
          border: tokens.borderSubtle,
        );
    }
  }
}

class _TimeDisplay extends StatelessWidget {
  const _TimeDisplay({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final resolved = value?.trim().isNotEmpty == true ? value!.trim() : '--';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            resolved,
            style: text.titleSmall?.copyWith(
              color: resolved == '--' ? tokens.textDisabled : tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEditor extends StatelessWidget {
  const _TimeEditor({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final resolved = value?.trim().isNotEmpty == true ? value!.trim() : '--';
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: text.labelMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: OutlinedButton(
            onPressed: enabled ? onPick : null,
            child: Text(resolved),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: '$label 지우기',
          child: IconButton(
            onPressed: enabled && resolved != '--' ? onClear : null,
            icon: Icon(
              Icons.clear_rounded,
              color: enabled && resolved != '--'
                  ? tokens.iconSecondary
                  : tokens.iconDisabled,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewTone {
  const _ReviewTone({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}
