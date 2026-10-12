import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/single_inside_diagnostics.dart';
import '../../application/single_inside_hot_key_prefs.dart';
import '../../application/single_inside_hot_key_summary_loader.dart';
import '../dialogs/single_inside_hot_key_settings_dialog.dart';
import '../hot_keys/single_inside_hot_key_content.dart';
import '../side_docks/single_inside_side_dock.dart';
import 'single_inside_hot_key_card.dart';

class SingleInsideHotKeySection extends StatefulWidget {
  const SingleInsideHotKeySection({
    super.key,
    required this.userId,
    required this.division,
    required this.area,
    required this.allowReports,
    required this.refreshRevision,
    required this.onRequest,
    required this.onDeveloperStatus,
  });

  final String userId;
  final String division;
  final String area;
  final bool allowReports;
  final int refreshRevision;
  final SingleInsideDashboardRequestHandler onRequest;
  final Future<void> Function() onDeveloperStatus;

  @override
  State<SingleInsideHotKeySection> createState() =>
      _SingleInsideHotKeySectionState();
}

class _SingleInsideHotKeySectionState extends State<SingleInsideHotKeySection> {
  SingleInsideHotKeyConfig _config = const SingleInsideHotKeyConfig(
    slot1: null,
    slot2: null,
    slot3: null,
    slot4: null,
  );
  final Map<SingleInsideHotKeyContent, SingleInsideHotKeySummary> _summaries =
      <SingleInsideHotKeyContent, SingleInsideHotKeySummary>{};
  final Set<SingleInsideHotKeyContent> _loading =
      <SingleInsideHotKeyContent>{};
  int _generation = 0;
  int _summaryGeneration = 0;
  bool _prefsLoaded = false;

  List<SingleInsideHotKeyContent> get _available {
    return SingleInsideHotKeyContent.values.where((content) {
      if (!widget.allowReports &&
          (content == SingleInsideHotKeyContent.workStartReport ||
              content == SingleInsideHotKeyContent.workEndReport)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  bool _isAllowed(SingleInsideHotKeyContent content) {
    return _available.contains(content);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefsAndSummaries(source: 'init'));
  }

  @override
  void didUpdateWidget(covariant SingleInsideHotKeySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged = oldWidget.userId != widget.userId ||
        oldWidget.division != widget.division ||
        oldWidget.area != widget.area ||
        oldWidget.allowReports != widget.allowReports;
    if (identityChanged) {
      unawaited(_loadPrefsAndSummaries(source: 'identity_changed'));
      return;
    }
    if (oldWidget.refreshRevision != widget.refreshRevision) {
      unawaited(_loadSummaries(source: 'refresh_revision'));
    }
  }

  Future<void> _loadPrefsAndSummaries({required String source}) async {
    final generation = ++_generation;
    final allowed = _available.toSet();
    try {
      final config = await SingleInsideHotKeyPrefs.load(
        userId: widget.userId,
        allowed: allowed,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _config = config;
        _prefsLoaded = true;
        _summaries.clear();
        _loading.clear();
      });
      SingleInsideDiagnostics.log(
        'hotkey',
        'config_ready source=$source slot1=${config.slot1?.name ?? 'empty'} slot2=${config.slot2?.name ?? 'empty'} slot3=${config.slot3?.name ?? 'empty'} slot4=${config.slot4?.name ?? 'empty'} allowReports=${widget.allowReports} refreshRevision=${widget.refreshRevision}',
      );
      await _loadSummaries(source: source);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _prefsLoaded = true;
        _config = const SingleInsideHotKeyConfig(
          slot1: null,
          slot2: null,
          slot3: null,
          slot4: null,
        );
        _summaries.clear();
        _loading.clear();
      });
      SingleInsideDiagnostics.log(
        'hotkey',
        'config_failure source=$source error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _loadSummaries({required String source}) async {
    if (!_prefsLoaded) return;
    final generation = ++_summaryGeneration;
    final targets = _config.slots
        .whereType<SingleInsideHotKeyContent>()
        .where(_isAllowed)
        .toSet();
    if (targets.isEmpty) {
      if (mounted && _loading.isNotEmpty) {
        setState(_loading.clear);
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading
          ..clear()
          ..addAll(targets);
      });
    }
    for (final content in targets) {
      final summary = await SingleInsideHotKeySummaryLoader.load(
        content: content,
        division: widget.division,
        area: widget.area,
      );
      if (!mounted || generation != _summaryGeneration) return;
      setState(() {
        _summaries[content] = summary;
        _loading.remove(content);
      });
    }
    SingleInsideDiagnostics.log(
      'hotkey',
      'summaries_ready source=$source targets=${targets.map((item) => item.name).join(',')} refreshRevision=${widget.refreshRevision}',
    );
  }

  Future<void> _edit() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final next = await showSingleInsideHotKeySettingsDialog(
      context: context,
      initial: _config,
      available: _available,
      onDeveloperStatus: widget.onDeveloperStatus,
    );
    if (next == null || !mounted || next.hasDuplicate) return;
    final before = _config.slots
        .map((item) => item?.name ?? 'empty')
        .join('|');
    try {
      await SingleInsideHotKeyPrefs.save(
        userId: widget.userId,
        config: next,
        markConfigured: true,
      );
      if (!mounted) return;
      final selected = next.slots.whereType<SingleInsideHotKeyContent>().toSet();
      setState(() {
        _config = next;
        _summaries.removeWhere((content, _) => !selected.contains(content));
      });
      SingleInsideDiagnostics.log(
        'hotkey',
        'settings_saved before=$before after=${next.slots.map((item) => item?.name ?? 'empty').join('|')}',
      );
      await _loadSummaries(source: 'settings_saved');
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'hotkey',
        'settings_save_failure before=$before error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _open(
    SingleInsideHotKeyContent content,
    int slot,
  ) async {
    if (!_isAllowed(content)) {
      SingleInsideDiagnostics.log(
        'hotkey',
        'quick_open_denied slot=$slot content=${content.name} reason=not_allowed allowReports=${widget.allowReports}',
      );
      return;
    }
    await HapticFeedback.selectionClick();
    SingleInsideDiagnostics.log(
      'hotkey',
      'quick_open slot=$slot content=${content.name} request=${content.request.name}',
    );
    await widget.onRequest(content.request, 'home_hotkey_slot_$slot');
  }

  Widget _card(int slot) {
    final content = _config.contentAt(slot);
    return SingleInsideHotKeyCard(
      content: content,
      summary: content == null ? null : _summaries[content],
      loading: content != null && _loading.contains(content),
      onOpen: content == null ? _edit : () => _open(content, slot),
      onEdit: _prefsLoaded ? _edit : () {},
    );
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
          onLongPress: () async {
            await HapticFeedback.mediumImpact();
            SingleInsideDiagnostics.log(
              'status',
              'developer_status_request source=home_hotkey_header slot1=${_config.slot1?.name ?? 'empty'} slot2=${_config.slot2?.name ?? 'empty'} slot3=${_config.slot3?.name ?? 'empty'} slot4=${_config.slot4?.name ?? 'empty'} allowReports=${widget.allowReports}',
            );
            await widget.onDeveloperStatus();
          },
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '빠른 실행',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _prefsLoaded ? _edit : null,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('편집'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: AnimatedOpacity(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            curve: CommonUiMotion.standard,
            opacity: _prefsLoaded ? 1 : .55,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _card(1)),
                      const SizedBox(width: 10),
                      Expanded(child: _card(2)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _card(3)),
                      const SizedBox(width: 10),
                      Expanded(child: _card(4)),
                    ],
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
