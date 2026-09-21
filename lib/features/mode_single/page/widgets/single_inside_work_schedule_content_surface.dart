import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../dashboard/widgets/widgets/schedule/weekly_work_schedule_editor.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideWorkScheduleContentSurface extends StatefulWidget {
  const SingleInsideWorkScheduleContentSurface({
    super.key,
    required this.scheduleRevision,
    required this.onChanged,
    required this.onDeveloperStatus,
  });

  final int scheduleRevision;
  final VoidCallback onChanged;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<SingleInsideWorkScheduleContentSurface> createState() =>
      _SingleInsideWorkScheduleContentSurfaceState();
}

class _SingleInsideWorkScheduleContentSurfaceState
    extends State<SingleInsideWorkScheduleContentSurface> {
  late final WeeklyWorkScheduleEditorController _editorController;

  @override
  void initState() {
    super.initState();
    _editorController = WeeklyWorkScheduleEditorController()
      ..addListener(_handleEditorStateChanged);
  }

  void _handleEditorStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save() async {
    if (!_editorController.canSave) return;
    await HapticFeedback.mediumImpact();
    SingleInsideDiagnostics.log(
      'schedule',
      'explicit_save_requested source=work_schedule_workspace dirty=${_editorController.hasChanges} saving=${_editorController.saving}',
    );
    final ok = await _editorController.save();
    SingleInsideDiagnostics.log(
      'schedule',
      'explicit_save_finished source=work_schedule_workspace success=$ok dirty=${_editorController.hasChanges} saving=${_editorController.saving}',
    );
  }

  @override
  void dispose() {
    _editorController
      ..removeListener(_handleEditorStateChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final actionDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final saveEnabled = _editorController.canSave;
    final saving = _editorController.saving;

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () async {
              await HapticFeedback.mediumImpact();
              SingleInsideDiagnostics.log(
                'status',
                'developer_status_request source=work_schedule_workspace_header revision=${widget.scheduleRevision} saveMode=explicit dirty=${_editorController.hasChanges} saving=${_editorController.saving}',
              );
              await widget.onDeveloperStatus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '근무 일정',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: WeeklyWorkScheduleEditor(
                    source: 'single_workspace',
                    embedded: true,
                    presentation: WeeklyWorkSchedulePresentation.editorOnly,
                    saveMode: WeeklyWorkScheduleSaveMode.explicit,
                    controller: _editorController,
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: AnimatedOpacity(
                  duration: actionDuration,
                  curve: Curves.easeOutCubic,
                  opacity: saveEnabled || saving ? 1 : .58,
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: saveEnabled ? _save : null,
                      icon: AnimatedSwitcher(
                        duration: actionDuration,
                        child: saving
                            ? SizedBox(
                                key: const ValueKey<String>('saving'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: tokens.onAccent,
                                ),
                              )
                            : const Icon(
                                Icons.save_rounded,
                                key: ValueKey<String>('save'),
                              ),
                      ),
                      label: AnimatedSwitcher(
                        duration: actionDuration,
                        child: Text(
                          saving ? '저장 중' : '저장',
                          key: ValueKey<String>(saving ? 'saving' : 'save'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
