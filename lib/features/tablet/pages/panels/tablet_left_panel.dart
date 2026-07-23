import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../dev/application/area_state.dart';
import '../widgets/tablet_prompt_components.dart';

@immutable
class TabletCompletedDepartureNotice {
  const TabletCompletedDepartureNotice({
    required this.docId,
    required this.tail4,
    required this.completedAt,
  });

  final String docId;
  final String tail4;
  final DateTime completedAt;
}

class LeftPaneDeparturePlates extends StatelessWidget {
  const LeftPaneDeparturePlates({
    super.key,
    this.columns = 3,
    this.completedNotices = const <TabletCompletedDepartureNotice>[],
  }) : assert(columns > 0);

  final int columns;
  final List<TabletCompletedDepartureNotice> completedNotices;

  static List<_DepartureRow> _rowsFromViewRows(List<ViewRowData> rows) {
    final out = rows
        .map(
          (row) => _DepartureRow(
            plateDocId: row.plateId,
            tail4: _tail4Digits(row.plateNumber),
            primaryAt: row.primaryAt ?? row.updatedAt ?? row.createdAt,
            isSelected: row.isSelected,
          ),
        )
        .toList(growable: false);
    out.sort((a, b) {
      final aSelected = a.isSelected ? 0 : 1;
      final bSelected = b.isSelected ? 0 : 1;
      if (aSelected != bSelected) return aSelected.compareTo(bSelected);
      final aDate = a.primaryAt;
      final bDate = b.primaryAt;
      if (aDate == null && bDate == null) {
        return a.plateDocId.compareTo(b.plateDocId);
      }
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final compared = bDate.compareTo(aDate);
      return compared != 0 ? compared : a.plateDocId.compareTo(b.plateDocId);
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final currentArea =
        context.select<AreaState, String?>((state) => state.currentArea) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PromptAnimatedReveal(
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: tokens.accent),
                ),
                child: Icon(
                  Icons.directions_car_rounded,
                  color: tokens.onAccentContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '태블릿 출차 현황',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentArea.isEmpty ? '지역 -' : '지역 $currentArea',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 3,
          child: PromptAnimatedReveal(
            delay: const Duration(milliseconds: 50),
            child: _PanelSection(
              title: '출차 요청',
              icon: Icons.logout_rounded,
              tone: tokens.statusDepartureRequested,
              child: currentArea.trim().isEmpty
                  ? const TabletPromptEmptyState(
                      title: '선택된 지역이 없습니다',
                      icon: Icons.map_outlined,
                    )
                  : _DepartureRequestGrid(
                      area: currentArea.trim(),
                      columns: columns,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 2,
          child: PromptAnimatedReveal(
            delay: const Duration(milliseconds: 100),
            child: _PanelSection(
              title: '업무 중 출차 완료',
              icon: Icons.check_circle_outline_rounded,
              tone: tokens.statusSynchronized,
              child: _CompletedDepartureGrid(
                notices: completedNotices,
                columns: columns,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({
    required this.title,
    required this.icon,
    required this.tone,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.component),
      curve: PromptUiMotion.standard,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      tone.withOpacity(tokens.isDark ? 0.20 : 0.12),
                      tokens.surfaceRaised,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: tone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DepartureRequestGrid extends StatefulWidget {
  const _DepartureRequestGrid({
    required this.area,
    required this.columns,
  });

  final String area;
  final int columns;

  @override
  State<_DepartureRequestGrid> createState() => _DepartureRequestGridState();
}

class _DepartureRequestGridState extends State<_DepartureRequestGrid> {
  Stream<List<ViewRowData>>? _stream;
  String _boundArea = '';

  @override
  void initState() {
    super.initState();
    _bindStream(widget.area);
  }

  @override
  void didUpdateWidget(covariant _DepartureRequestGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) _bindStream(widget.area);
  }

  void _bindStream(String area) {
    final trimmedArea = area.trim();
    _boundArea = trimmedArea;
    _stream = context.read<PlateRepository>().watchViewRows(
          collection: 'departure_requests_view',
          area: trimmedArea,
          primaryAtField: 'departureRequestedAt',
        );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ViewRowData>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            '[TabletLeftPane][departure_requests_view] a=$_boundArea error=${snapshot.error}',
          );
          unawaited(
            DevFirebaseDebugDialog.show(
              context: context,
              operation: 'tablet.departure_requests_view.listen',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
              details: <String, Object?>{
                'collection': 'departure_requests_view',
                'area': _boundArea,
                'primaryAtField': 'departureRequestedAt',
                'widget': 'LeftPaneDeparturePlates',
              },
              usePromptUi: true,
            ),
          );
          return const TabletPromptEmptyState(
            title: '출차 요청을 불러오지 못했습니다',
            icon: Icons.cloud_off_rounded,
          );
        }
        if (!snapshot.hasData) {
          return const TabletPromptLoadingState(label: '출차 요청 확인 중');
        }
        final rows = LeftPaneDeparturePlates._rowsFromViewRows(snapshot.data!);
        if (rows.isEmpty) {
          return const TabletPromptEmptyState(
            title: '대기 중인 출차 요청이 없습니다',
            icon: Icons.directions_car_outlined,
          );
        }
        return _PlateGrid(
          itemCount: rows.length,
          columns: widget.columns,
          minTileWidth: 72,
          desiredTileHeight: 90,
          itemBuilder: (context, index) {
            final row = rows[index];
            return PromptAnimatedReveal(
              key: ValueKey<String>('request-${row.plateDocId}-${row.isSelected}'),
              delay: Duration(milliseconds: index.clamp(0, 8).toInt() * 24),
              offset: const Offset(0, 0.05),
              child: _PlateTile(
                tail4: row.tail4.isEmpty ? '-' : row.tail4,
                completed: false,
                inProgress: row.isSelected,
              ),
            );
          },
        );
      },
    );
  }
}

class _CompletedDepartureGrid extends StatelessWidget {
  const _CompletedDepartureGrid({
    required this.notices,
    required this.columns,
  });

  final List<TabletCompletedDepartureNotice> notices;
  final int columns;

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return const TabletPromptEmptyState(
        title: '업무 중 완료된 출차가 없습니다',
        icon: Icons.task_alt_rounded,
      );
    }
    return _PlateGrid(
      itemCount: notices.length,
      columns: columns,
      minTileWidth: 78,
      desiredTileHeight: 98,
      itemBuilder: (context, index) {
        final notice = notices[index];
        return PromptAnimatedReveal(
          key: ValueKey<String>('completed-${notice.docId}'),
          delay: Duration(milliseconds: index.clamp(0, 8).toInt() * 24),
          offset: const Offset(0, 0.05),
          child: _PlateTile(
            tail4: notice.tail4.isEmpty ? '-' : notice.tail4,
            completed: true,
            timeLabel: _formatTime(notice.completedAt),
          ),
        );
      },
    );
  }
}

class _PlateGrid extends StatelessWidget {
  const _PlateGrid({
    required this.itemCount,
    required this.columns,
    required this.minTileWidth,
    required this.desiredTileHeight,
    required this.itemBuilder,
  });

  final int itemCount;
  final int columns;
  final double minTileWidth;
  final double desiredTileHeight;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossSpacing = 10.0;
        const mainSpacing = 10.0;
        const padding = 12.0;
        var effectiveColumns = columns;
        while (effectiveColumns > 1) {
          final width = (constraints.maxWidth -
                  padding -
                  crossSpacing * (effectiveColumns - 1)) /
              effectiveColumns;
          if (width >= minTileWidth) break;
          effectiveColumns -= 1;
        }
        final tileWidth = (constraints.maxWidth -
                padding -
                crossSpacing * (effectiveColumns - 1)) /
            effectiveColumns;
        final aspect =
            (tileWidth / desiredTileHeight).clamp(0.55, 1.10).toDouble();
        return GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveColumns,
            crossAxisSpacing: crossSpacing,
            mainAxisSpacing: mainSpacing,
            childAspectRatio: aspect,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

class _DepartureRow {
  const _DepartureRow({
    required this.plateDocId,
    required this.tail4,
    required this.primaryAt,
    required this.isSelected,
  });

  final String plateDocId;
  final String tail4;
  final DateTime? primaryAt;
  final bool isSelected;
}

class _PlateTile extends StatelessWidget {
  const _PlateTile({
    required this.tail4,
    required this.completed,
    this.inProgress = false,
    this.timeLabel,
  });

  final String tail4;
  final bool completed;
  final bool inProgress;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final tone = completed
        ? tokens.statusSynchronized
        : inProgress
            ? tokens.statusDepartureRequested
            : tokens.accent;
    final background = completed
        ? tokens.statusSynchronizedContainer
        : inProgress
            ? tokens.statusDepartureRequestedContainer
            : tokens.surfaceRaised;
    final foreground = completed
        ? tokens.onStatusSynchronizedContainer
        : inProgress
            ? tokens.onStatusDepartureRequestedContainer
            : tokens.textPrimary;
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tone),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (completed || inProgress) ...<Widget>[
                Icon(
                  completed
                      ? Icons.check_circle_outline_rounded
                      : Icons.directions_car_filled_rounded,
                  color: tone,
                  size: 18,
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tail4,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: foreground,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                  ),
                ),
              ),
            ],
          ),
          if (completed && timeLabel != null) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              '완료 $timeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
            ),
          ] else if (inProgress) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              '출차 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

String _tail4Digits(String plateNumber) {
  final digits = _digitsOnly(plateNumber);
  if (digits.length <= 4) return digits;
  return digits.substring(digits.length - 4);
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
