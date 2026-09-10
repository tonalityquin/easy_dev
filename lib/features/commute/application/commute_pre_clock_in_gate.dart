import 'package:flutter/material.dart';

class CommutePreClockInItem {
  const CommutePreClockInItem({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

class CommutePreClockInDecision {
  const CommutePreClockInDecision({
    required this.eligible,
    required this.shouldShow,
    required this.reason,
    required this.items,
    this.contextLabel = '',
    this.diagnosticsSummary = '',
    this.state,
  });

  final bool eligible;
  final bool shouldShow;
  final String reason;
  final List<CommutePreClockInItem> items;
  final String contextLabel;
  final String diagnosticsSummary;
  final Object? state;

  factory CommutePreClockInDecision.skip({
    required String reason,
    bool eligible = false,
    String contextLabel = '',
    String diagnosticsSummary = '',
    Object? state,
  }) {
    return CommutePreClockInDecision(
      eligible: eligible,
      shouldShow: false,
      reason: reason,
      items: const <CommutePreClockInItem>[],
      contextLabel: contextLabel,
      diagnosticsSummary: diagnosticsSummary,
      state: state,
    );
  }
}

abstract interface class CommutePreClockInGate {
  Future<CommutePreClockInDecision> evaluate(
    BuildContext context, {
    bool force = false,
  });

  Future<void> confirm(
    BuildContext context,
    CommutePreClockInDecision decision,
  );

  Future<void> onClockInSucceeded(
    BuildContext context,
    CommutePreClockInDecision decision,
  );
}
