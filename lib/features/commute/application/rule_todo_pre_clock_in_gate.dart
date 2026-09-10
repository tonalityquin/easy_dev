import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../account/applications/user_state.dart';
import 'commute_pre_clock_in_gate.dart';
import '../../dev/application/area_state.dart';
import '../../launcher/application/launcher_diagnostics.dart';
import '../../rule/domain/models/rule_model.dart';
import '../../mode_single/application/single_rule_todo_prompt_policy.dart';
import '../../mode_single/application/single_rule_todo_prompt_repository.dart';

class RuleTodoPreClockInGate implements CommutePreClockInGate {
  const RuleTodoPreClockInGate();

  static final Random _random = Random();
  static const SingleRuleTodoPromptPolicy _policy =
      SingleRuleTodoPromptPolicy();
  static const SingleRuleTodoPromptRepository _historyRepository =
      SingleRuleTodoPromptRepository();

  @override
  Future<CommutePreClockInDecision> evaluate(
    BuildContext context, {
    bool force = false,
  }) async {
    try {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final userId = userState.session?.id.trim() ?? '';
      final areaStateDivision = areaState.currentDivision.trim();
      final areaStateArea = areaState.currentArea.trim();
      final userStateDivision = userState.division.trim();
      final userStateArea = userState.currentArea.trim();

      late final String division;
      late final String area;
      late final String identitySource;

      if (areaStateDivision.isNotEmpty && areaStateArea.isNotEmpty) {
        division = areaStateDivision;
        area = areaStateArea;
        identitySource = 'area_state';
      } else if (userStateDivision.isNotEmpty && userStateArea.isNotEmpty) {
        division = userStateDivision;
        area = userStateArea;
        identitySource = 'user_state_fallback';
      } else {
        return _skipAndLog(
          reason: 'identity_unavailable',
          userIdPresent: userId.isNotEmpty,
          division: areaStateDivision.isNotEmpty
              ? areaStateDivision
              : userStateDivision,
          area: areaStateArea.isNotEmpty ? areaStateArea : userStateArea,
          identitySource: 'unavailable',
          force: force,
        );
      }

      if (userId.isEmpty) {
        return _skipAndLog(
          reason: 'identity_unavailable',
          userIdPresent: false,
          division: division,
          area: area,
          identitySource: identitySource,
          force: force,
        );
      }

      final rule = await context.read<OperationalLocalRepository>().readRule(
            division: division,
            area: area,
          );
      if (rule == null) {
        return _skipAndLog(
          reason: 'rule_absent',
          userIdPresent: true,
          division: division,
          area: area,
          identitySource: identitySource,
          force: force,
        );
      }

      final todos = rule.todoItems
          .where(
            (item) =>
                item.id.trim().isNotEmpty &&
                item.text.trim().isNotEmpty,
          )
          .toList(growable: false)
        ..sort((a, b) {
          final orderCompare = a.order.compareTo(b.order);
          if (orderCompare != 0) return orderCompare;
          return a.id.compareTo(b.id);
        });
      if (todos.isEmpty) {
        return _skipAndLog(
          reason: 'todo_empty',
          userIdPresent: true,
          division: division,
          area: area,
          identitySource: identitySource,
          force: force,
        );
      }

      final fingerprint = _fingerprint(todos);
      final history = await _historyRepository.read(
        userId: userId,
        division: division,
        area: area,
      );
      final state = _RuleTodoPromptDecisionState(
        userId: userId,
        division: division,
        area: area,
        fingerprint: fingerprint,
        clockInsSincePrompt: history?.clockInsSincePrompt ?? 0,
        promptCount: history?.promptCount ?? 0,
      );

      if (force) {
        final summary = <String>[
          'reason=forced_more_press',
          'identitySource=$identitySource',
          'forcePrompt=true',
          'todoCount=${todos.length}',
          'clockInsSincePrompt=${history?.clockInsSincePrompt ?? 0}',
          'promptCount=${history?.promptCount ?? 0}',
          'probability=1.0000',
          'roll=forced',
          'fingerprint=$fingerprint',
          'gate=shared_rule_todo',
          'firebaseRead=0',
          'firebaseWrite=0',
        ].join(' ');

        LauncherDiagnostics.record(
          'rule_todo_prompt_evaluated',
          scope: 'commute_todo',
          meta: <String, Object?>{
            'division': division,
            'area': area,
            'identitySource': identitySource,
            'ruleFound': true,
            'todoCount': todos.length,
            'fingerprint': fingerprint,
            'historyFingerprint': history?.todoFingerprint ?? '',
            'clockInsSincePrompt': history?.clockInsSincePrompt ?? 0,
            'promptCount': history?.promptCount ?? 0,
            'forcePrompt': true,
            'probability': '1.0000',
            'roll': 'forced',
            'decision': 'show',
            'reason': 'forced_more_press',
            'firebaseRead': 0,
            'firebaseWrite': 0,
            'gate': 'shared_rule_todo',
          },
        );

        return CommutePreClockInDecision(
          eligible: true,
          shouldShow: true,
          reason: 'forced_more_press',
          items: todos
              .map(
                (item) => CommutePreClockInItem(
                  id: item.id,
                  label: item.text,
                ),
              )
              .toList(growable: false),
          contextLabel: '$division · $area',
          diagnosticsSummary: summary,
          state: state,
        );
      }

      final roll = _random.nextDouble();
      final policyResult = _policy.evaluate(
        clockInsSincePrompt: history?.clockInsSincePrompt ?? 0,
        promptCount: history?.promptCount ?? 0,
        roll: roll,
      );
      final summary = <String>[
        'reason=${policyResult.reason}',
        'identitySource=$identitySource',
        'forcePrompt=false',
        'todoCount=${todos.length}',
        'clockInsSincePrompt=${history?.clockInsSincePrompt ?? 0}',
        'promptCount=${history?.promptCount ?? 0}',
        'probability=${policyResult.probability.toStringAsFixed(4)}',
        'roll=${policyResult.roll.toStringAsFixed(4)}',
        'fingerprint=$fingerprint',
        'gate=shared_rule_todo',
        'firebaseRead=0',
        'firebaseWrite=0',
      ].join(' ');

      LauncherDiagnostics.record(
        'rule_todo_prompt_evaluated',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'division': division,
          'area': area,
          'identitySource': identitySource,
          'ruleFound': true,
          'todoCount': todos.length,
          'fingerprint': fingerprint,
          'historyFingerprint': history?.todoFingerprint ?? '',
          'clockInsSincePrompt': history?.clockInsSincePrompt ?? 0,
          'promptCount': history?.promptCount ?? 0,
          'forcePrompt': false,
          'probability': policyResult.probability.toStringAsFixed(4),
          'roll': policyResult.roll.toStringAsFixed(4),
          'decision': policyResult.shouldShow ? 'show' : 'skip',
          'reason': policyResult.reason,
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );

      return CommutePreClockInDecision(
        eligible: true,
        shouldShow: policyResult.shouldShow,
        reason: policyResult.reason,
        items: todos
            .map(
              (item) => CommutePreClockInItem(
                id: item.id,
                label: item.text,
              ),
            )
            .toList(growable: false),
        contextLabel: '$division · $area',
        diagnosticsSummary: summary,
        state: state,
      );
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'rule_todo_prompt_exception',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'error': error,
          'stack': stackTrace,
          'forcePrompt': force,
          'decision': 'skip',
          'reason': 'gate_exception',
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );
      return CommutePreClockInDecision.skip(
        reason: 'gate_exception',
        diagnosticsSummary:
            'reason=gate_exception forcePrompt=$force gate=shared_rule_todo firebaseRead=0 firebaseWrite=0',
      );
    }
  }

  @override
  Future<void> confirm(
    BuildContext context,
    CommutePreClockInDecision decision,
  ) async {
    final state = decision.state;
    if (state is! _RuleTodoPromptDecisionState) return;
    try {
      await _historyRepository.markPrompted(
        userId: state.userId,
        division: state.division,
        area: state.area,
        todoFingerprint: state.fingerprint,
      );
      LauncherDiagnostics.record(
        'rule_todo_prompt_confirmed',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'division': state.division,
          'area': state.area,
          'fingerprint': state.fingerprint,
          'previousClockInsSincePrompt': state.clockInsSincePrompt,
          'previousPromptCount': state.promptCount,
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'rule_todo_prompt_confirm_history_failed',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'error': error,
          'stack': stackTrace,
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );
    }
  }

  @override
  Future<void> onClockInSucceeded(
    BuildContext context,
    CommutePreClockInDecision decision,
  ) async {
    if (!decision.eligible || decision.shouldShow) return;
    final state = decision.state;
    if (state is! _RuleTodoPromptDecisionState) return;
    try {
      await _historyRepository.markEligibleClockInSucceeded(
        userId: state.userId,
        division: state.division,
        area: state.area,
        todoFingerprint: state.fingerprint,
      );
      LauncherDiagnostics.record(
        'rule_todo_prompt_skip_clock_in_counted',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'division': state.division,
          'area': state.area,
          'fingerprint': state.fingerprint,
          'previousClockInsSincePrompt': state.clockInsSincePrompt,
          'nextClockInsSincePrompt': state.clockInsSincePrompt + 1,
          'reason': decision.reason,
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'rule_todo_prompt_count_history_failed',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'error': error,
          'stack': stackTrace,
          'firebaseRead': 0,
          'firebaseWrite': 0,
          'gate': 'shared_rule_todo',
        },
      );
    }
  }

  CommutePreClockInDecision _skipAndLog({
    required String reason,
    required bool userIdPresent,
    required String division,
    required String area,
    required String identitySource,
    required bool force,
  }) {
    LauncherDiagnostics.record(
      'rule_todo_prompt_evaluated',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'userIdPresent': userIdPresent,
        'division': division,
        'area': area,
        'identitySource': identitySource,
        'forcePrompt': force,
        'decision': 'skip',
        'reason': reason,
        'firebaseRead': 0,
        'firebaseWrite': 0,
        'gate': 'shared_rule_todo',
      },
    );
    return CommutePreClockInDecision.skip(
      reason: reason,
      diagnosticsSummary:
          'reason=$reason identitySource=$identitySource forcePrompt=$force gate=shared_rule_todo firebaseRead=0 firebaseWrite=0',
    );
  }

  String _fingerprint(List<RuleTodoItem> todos) {
    final canonical = todos
        .map(
          (item) => '${item.id.trim()}|${item.order}|${item.text.trim()}',
        )
        .join('\n');
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(canonical)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _RuleTodoPromptDecisionState {
  const _RuleTodoPromptDecisionState({
    required this.userId,
    required this.division,
    required this.area,
    required this.fingerprint,
    required this.clockInsSincePrompt,
    required this.promptCount,
  });

  final String userId;
  final String division;
  final String area;
  final String fingerprint;
  final int clockInsSincePrompt;
  final int promptCount;
}
