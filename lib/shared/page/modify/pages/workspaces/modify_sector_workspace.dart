import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/sector/applications/sector_state.dart';
import '../../../../../features/sector/domain/models/sector_model.dart';

class ModifySectorWorkspace extends StatefulWidget {
  const ModifySectorWorkspace({
    super.key,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
    required this.onExit,
    this.onDebug,
  });

  final String? selectedId;
  final String? selectedName;
  final Future<void> Function(SectorModel sector) onSelected;
  final VoidCallback onExit;
  final ValueChanged<String>? onDebug;

  @override
  State<ModifySectorWorkspace> createState() => _ModifySectorWorkspaceState();
}

class _ModifySectorWorkspaceState extends State<ModifySectorWorkspace> {
  bool _loading = true;
  bool _applying = false;
  String? _error;
  String _area = '';
  List<SectorModel> _sectors = const <SectorModel>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _debug(String message) {
    widget.onDebug?.call(message);
    debugPrint('[ModifySectorWorkspace] $message');
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final areaState = context.read<AreaState>();
      final requestedArea = areaState.currentArea.trim();
      final hasSector =
          areaState.capabilitiesOfCurrentArea.contains(Capability.sector);
      _debug(
        'sector_workspace=load_start area=$requestedArea capability=$hasSector',
      );
      if (!hasSector) {
        throw StateError('현재 지역은 방문 구역 기능을 사용하지 않습니다.');
      }
      if (requestedArea.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }

      final sectorState = context.read<SectorState>();
      final wait = Stopwatch()..start();
      await sectorState.waitUntilReady();
      wait.stop();
      if (!mounted) return;

      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea != requestedArea) {
        throw StateError('방문 구역을 준비하는 동안 현재 지역이 변경되었습니다.');
      }
      if (sectorState.isBusy) {
        throw StateError('방문 구역 로컬 데이터를 준비하고 있습니다.');
      }

      final raw = sectorState.sectors;
      final valid = raw
          .where(
            (sector) =>
                sector.id.trim().isNotEmpty &&
                sector.name.trim().isNotEmpty &&
                sector.area.trim() == requestedArea,
          )
          .toList(growable: false)
        ..sort((a, b) => a.name.compareTo(b.name));

      if (raw.length != valid.length || valid.isEmpty) {
        throw StateError('현재 지역의 방문 구역 로컬 데이터가 유효하지 않습니다.');
      }

      setState(() {
        _area = requestedArea;
        _sectors = valid;
        _loading = false;
      });
      _debug(
        'sector_workspace=load_success area=$requestedArea count=${valid.length} elapsedMs=${wait.elapsedMilliseconds}',
      );
    } catch (error, stackTrace) {
      _debug('sector_workspace=load_failed error=$error');
      debugPrint('[ModifySectorWorkspace] error=$error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _select(SectorModel selected) async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      final areaState = context.read<AreaState>();
      final currentArea = areaState.currentArea.trim();
      if (currentArea != _area ||
          !areaState.capabilitiesOfCurrentArea.contains(Capability.sector)) {
        throw StateError('현재 지역 또는 방문 구역 기능 설정이 변경되었습니다.');
      }
      final currentSectors = context.read<SectorState>().sectors;
      final confirmed = currentSectors.where((item) {
        return item.id == selected.id &&
            item.area.trim() == currentArea &&
            item.name.trim() == selected.name.trim();
      }).toList(growable: false);
      if (confirmed.length != 1) {
        throw StateError('방문 구역 정보가 변경되어 다시 선택해야 합니다.');
      }
      final resolved = confirmed.single;
      _debug(
        'sector_workspace=selected id=${resolved.id.trim()} name=${resolved.name.trim()} area=$currentArea',
      );
      await widget.onSelected(resolved);
      await HapticFeedback.selectionClick();
    } catch (error, stackTrace) {
      _debug('sector_workspace=select_failed error=$error');
      debugPrint('[ModifySectorWorkspace] selectError=$error\n$stackTrace');
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: widget.onExit,
                ),
                const SizedBox(width: 6),
                Icon(Icons.place_rounded, color: tokens.accent, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '방문 구역',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.selectedName?.trim().isNotEmpty == true
                            ? '현재 ${widget.selectedName!.trim()}'
                            : '현재 선택된 방문 구역이 없습니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: AnimatedSwitcher(
              duration:
                  reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _loading
                  ? _SectorLoading(key: const ValueKey<String>('loading'))
                  : _error != null
                      ? _SectorError(
                          key: const ValueKey<String>('error'),
                          onRetry: _load,
                        )
                      : ListView.separated(
                          key: const ValueKey<String>('ready'),
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                          itemCount: _sectors.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final sector = _sectors[index];
                            final selected = sector.id.trim() ==
                                (widget.selectedId?.trim() ?? '');
                            return Material(
                              color: tokens.transparent,
                              borderRadius:
                                  BorderRadius.circular(CommonUiShapes.control),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _applying ? null : () => _select(sector),
                                child: AnimatedContainer(
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 150),
                                  curve: Curves.easeOutCubic,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? tokens.surfaceSelected
                                        : tokens.surfaceOverlay,
                                    borderRadius: BorderRadius.circular(
                                      CommonUiShapes.control,
                                    ),
                                    border: Border.all(
                                      color: selected
                                          ? tokens.accent
                                          : tokens.borderSubtle,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      AnimatedSwitcher(
                                        duration: reduceMotion
                                            ? Duration.zero
                                            : const Duration(milliseconds: 150),
                                        child: Icon(
                                          selected
                                              ? Icons.check_circle_rounded
                                              : Icons.circle_outlined,
                                          key: ValueKey<bool>(selected),
                                          color: selected
                                              ? tokens.accent
                                              : tokens.iconSecondary,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          sector.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: tokens.textPrimary,
                                                fontWeight: selected
                                                    ? FontWeight.w900
                                                    : FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      if (_applying && selected)
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: tokens.accent,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectorLoading extends StatelessWidget {
  const _SectorLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: tokens.surfaceOverlay,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: 90 + (index * 13),
            height: 9,
            child: LinearProgressIndicator(
              color: tokens.accent.withOpacity(.5),
              backgroundColor: tokens.surfaceDisabled,
            ),
          ),
        );
      },
    );
  }
}

class _SectorError extends StatelessWidget {
  const _SectorError({
    super.key,
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: tokens.warning, size: 34),
            const SizedBox(height: 10),
            Text(
              '방문 구역 정보를 불러오지 못했습니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            CommonButton(
              label: '다시 시도',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
