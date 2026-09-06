import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/fab/hub_quick_actions.dart';

class HeadquarterQuickButtonHeaderToggle extends StatefulWidget {
  const HeadquarterQuickButtonHeaderToggle({super.key});

  @override
  State<HeadquarterQuickButtonHeaderToggle> createState() =>
      _HeadquarterQuickButtonHeaderToggleState();
}

class _HeadquarterQuickButtonHeaderToggleState
    extends State<HeadquarterQuickButtonHeaderToggle> {
  bool _busy = false;

  Future<void> _setEnabled(bool target) async {
    if (_busy || HeadHubActions.enabled.value == target) return;

    setState(() => _busy = true);
    HapticFeedback.selectionClick();

    DeveloperOperationTrace? trace;
    final previous = HeadHubActions.enabled.value;

    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '본사 퀵버튼 상태 변경',
        initialMessage:
            'toggle_request previous=$previous target=$target source=headquarter_calendar_header',
        useCommonUi: true,
        developerModeMessage: 'developerMode=true',
        standardModeMessage: 'developerMode=false',
        showDialogImmediately: false,
      );

      trace.log(
        'state_before enabled=${HeadHubActions.enabled.value}',
        progress: 0.25,
      );

      await HeadHubActions.init();
      HeadHubActions.setEnabled(target);
      if (target) {
        await HeadHubActions.mountIfNeeded();
      }

      final applied = HeadHubActions.enabled.value;
      trace.log(
        'state_after enabled=$applied expected=$target',
        progress: 0.82,
      );

      if (applied != target) {
        throw StateError(
          '본사 퀵버튼 상태 적용 불일치: expected=$target actual=$applied',
        );
      }

      await trace.succeed(
        'toggle_complete enabled=$applied source=headquarter_calendar_header',
      );

      if (trace.developerMode && mounted) {
        await trace.showSnapshotStatusDialog(
          context,
          title: '본사 퀵버튼 ${target ? 'ON' : 'OFF'}',
          description: target
              ? '본사 퀵버튼이 활성화되었습니다.'
              : '본사 퀵버튼이 비활성화되었습니다.',
        );
      }
    } catch (error, stackTrace) {
      if (HeadHubActions.enabled.value != previous) {
        HeadHubActions.setEnabled(previous);
        if (previous) {
          await HeadHubActions.mountIfNeeded();
        }
      }

      if (trace == null) {
        debugPrint(
          '[HQ_QUICK_BUTTON][${DateTime.now().toIso8601String()}] toggle_failure previous=$previous target=$target error=$error',
        );
        debugPrint('$stackTrace');
      } else {
        await trace.fail(
          'toggle_failure previous=$previous target=$target',
          error: error,
          stackTrace: stackTrace,
        );
        if (trace.developerMode && mounted) {
          await trace.showSnapshotStatusDialog(
            context,
            title: '본사 퀵버튼 상태 변경 실패',
            description: '본사 퀵버튼 상태를 변경하지 못했습니다.',
            failure: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final componentDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.component;

    return ValueListenableBuilder<bool>(
      valueListenable: HeadHubActions.enabled,
      builder: (context, enabled, _) {
        return MergeSemantics(
          child: Semantics(
            label: '본사 퀵버튼',
            value: enabled ? 'ON' : 'OFF',
            toggled: enabled,
            enabled: !_busy,
            child: AnimatedOpacity(
              duration: componentDuration,
              curve: CommonUiMotion.standard,
              opacity: _busy ? 0.58 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder<Color?>(
                    duration: selectionDuration,
                    curve: CommonUiMotion.standard,
                    tween: ColorTween(
                      end: enabled ? tokens.accent : tokens.iconSecondary,
                    ),
                    builder: (context, color, child) {
                      return Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: color,
                      );
                    },
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '본사 퀵버튼',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.1,
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 24,
                    child: AnimatedSwitcher(
                      duration: selectionDuration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) {
                        if (reduceMotion) return child;
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slide,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        enabled ? 'ON' : 'OFF',
                        key: ValueKey<bool>(enabled),
                        textAlign: TextAlign.center,
                        style: textTheme.labelSmall?.copyWith(
                          color:
                              enabled ? tokens.accent : tokens.textSecondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  SizedBox(
                    width: 42,
                    height: 36,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Switch(
                        value: enabled,
                        onChanged: _busy
                            ? null
                            : (value) => unawaited(_setEnabled(value)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
