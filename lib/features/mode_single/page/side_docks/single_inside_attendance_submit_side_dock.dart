import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../shared/attendance_submission/attendance_submission_diagnostics.dart';
import '../../../../shared/attendance_submission/attendance_submission_review_model.dart';
import '../../../../shared/attendance_submission/attendance_submission_review_surface.dart';
import '../../application/single_attendance_submission_summary_service.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideAttendanceSubmitSideDock extends StatefulWidget {
  const SingleInsideAttendanceSubmitSideDock({
    super.key,
    required this.kind,
    required this.area,
    required this.refreshRevision,
    required this.onClose,
    required this.onCloseEnabledChanged,
    required this.onSubmitted,
    required this.onDeveloperStatus,
  });

  final SingleAttendanceSubmissionKind kind;
  final String area;
  final int refreshRevision;
  final VoidCallback onClose;
  final ValueChanged<bool> onCloseEnabledChanged;
  final VoidCallback onSubmitted;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<SingleInsideAttendanceSubmitSideDock> createState() =>
      _SingleInsideAttendanceSubmitSideDockState();
}

class _SingleInsideAttendanceSubmitSideDockState
    extends State<SingleInsideAttendanceSubmitSideDock> {
  bool _busy = false;

  AttendanceSubmissionKind get _reviewKind =>
      widget.kind == SingleAttendanceSubmissionKind.commute
          ? AttendanceSubmissionKind.commute
          : AttendanceSubmissionKind.restTime;

  void _handleBusyChanged(bool busy) {
    if (_busy == busy) return;
    setState(() => _busy = busy);
    widget.onCloseEnabledChanged(!busy);
    SingleInsideDiagnostics.log(
      'submit_dock',
      'review_busy kind=${widget.kind.name} value=$busy',
    );
  }

  @override
  Widget build(BuildContext context) {
    final areaLabel =
        widget.area.trim().isEmpty ? '현재 근무지' : widget.area.trim();
    final reviewKind = _reviewKind;
    return CommonSideDockFrame(
      title: reviewKind.title,
      subtitle: areaLabel,
      icon: reviewKind.icon,
      closeEnabled: !_busy,
      showCloseTooltip: false,
      onClose: widget.onClose,
      onLongPress: () {
        SingleInsideDiagnostics.log(
          'status',
          'developer_status_request source=attendance_review_side_dock kind=${widget.kind.name}',
        );
        AttendanceSubmissionDiagnostics.log(
          'status',
          'developer_status_request source=single kind=${reviewKind.name}',
        );
        unawaited(
          AttendanceSubmissionDiagnostics.showStatus(
            context,
            title: '${reviewKind.title} Review 상태',
          ),
        );
      },
      child: AttendanceSubmissionReviewSurface(
        key: ValueKey<String>(
          'single_${reviewKind.name}_${widget.refreshRevision}',
        ),
        kind: reviewKind,
        source: 'single',
        onBusyChanged: _handleBusyChanged,
        onSubmitted: () {
          SingleInsideDiagnostics.log(
            'submit_dock',
            'review_submitted kind=${widget.kind.name}',
          );
          widget.onSubmitted();
        },
      ),
    );
  }
}
