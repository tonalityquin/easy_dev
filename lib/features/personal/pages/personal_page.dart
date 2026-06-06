import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/tts/application/plate_tts_event_hub.dart';
import '../../dev/application/area_state.dart';
import '../../tablet/applications/tablet_work_session_state.dart';
import 'panels/personal_search_panel.dart';
import 'widgets/personal_sticky_notice_bar.dart';
import 'widgets/personal_top_navigation.dart';

class PersonalPage extends StatefulWidget {
  const PersonalPage({super.key});

  @override
  State<PersonalPage> createState() => _PersonalPageState();
}

class _PersonalPageState extends State<PersonalPage> {
  final List<String> _completedChips = <String>[];
  final Set<String> _completedChipSet = <String>{};
  final Set<String> _selectedChips = <String>{};
  String? _areaCache;
  StreamSubscription<PlateTtsEvent>? _ttsEventSub;

  void _addCompletedChip(String plateNumber) {
    if (_completedChipSet.add(plateNumber)) {
      setState(() => _completedChips.insert(0, plateNumber));
    }
  }

  void _removeCompletedChip(String plateNumber) {
    if (_completedChipSet.remove(plateNumber)) {
      setState(() {
        _completedChips.remove(plateNumber);
        _selectedChips.remove(plateNumber);
      });
    }
  }

  void _toggleChipSelection(String plateNumber) {
    setState(() {
      if (_selectedChips.contains(plateNumber)) {
        _selectedChips.remove(plateNumber);
      } else {
        _selectedChips.add(plateNumber);
      }
    });
  }

  void _clearChipsForAreaChange() {
    setState(() {
      _completedChips.clear();
      _completedChipSet.clear();
      _selectedChips.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    PlateTtsEventHub.ensureStarted();
    _ttsEventSub = PlateTtsEventHub.stream.listen((e) {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isEmpty || e.area != currentArea) return;
      if (e.type == PlateType.departureCompleted.firestoreValue) {
        final p = e.plateNumber.trim();
        if (p.isNotEmpty) _addCompletedChip(p);
      }
    });
  }

  @override
  void dispose() {
    _ttsEventSub?.cancel();
    _ttsEventSub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final workState = context.watch<TabletWorkSessionState>();
    final workStateReady = workState.isReady;
    final workActive = workState.isActive;
    final canRenderWorkingContent = workStateReady && workActive;

    if (_areaCache != area) {
      _areaCache = area;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearChipsForAreaChange();
      });
    }

    final pageContent = canRenderWorkingContent
        ? ColoredBox(
            color: cs.surface,
            child: PersonalSearchPanel(
              key: ValueKey('personal-mobile-pane-$area'),
              area: area,
            ),
          )
        : const SizedBox.expand();

    final scaffold = Scaffold(
      backgroundColor: cs.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          bottom: false,
          child: PersonalTopNavigation(isAreaSelectable: canRenderWorkingContent),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            if (canRenderWorkingContent)
              PersonalStickyNoticeBar(
                plates: _completedChips,
                selectedPlates: _selectedChips,
                onToggleSelect: _toggleChipSelection,
                onRemove: _removeCompletedChip,
              ),
            Expanded(
              child: pageContent,
            ),
          ],
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
      },
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: !canRenderWorkingContent,
            child: scaffold,
          ),
          if (!workStateReady)
            const Positioned.fill(
              child: _PersonalWorkSessionLoadingOverlay(),
            )
          else if (!workActive)
            const Positioned.fill(
              child: _PersonalWorkSessionInactiveOverlay(),
            ),
        ],
      ),
    );
  }
}

class _PersonalWorkSessionLoadingOverlay extends StatelessWidget {
  const _PersonalWorkSessionLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.28),
        ),
        Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.14),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '개인형 사용 상태를 확인하는 중입니다.',
                  textAlign: TextAlign.center,
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
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

class _PersonalWorkSessionInactiveOverlay extends StatelessWidget {
  const _PersonalWorkSessionInactiveOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.34),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withOpacity(.80)),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(.18),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.pause_circle_outline,
                          color: cs.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '개인형 사용이 종료된 상태입니다.',
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '업무 시작 버튼을 누르면 개인형 모바일 화면이 다시 활성화되고 현재 지역 기준 검색 기능을 다시 사용할 수 있습니다.',
                    style: (text.bodyMedium ?? const TextStyle()).copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      await context.read<TabletWorkSessionState>().startWork();
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('업무 시작'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
