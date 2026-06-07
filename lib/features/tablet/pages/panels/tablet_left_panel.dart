import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../dev/application/area_state.dart';

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

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  static List<_DepartureRow> _rowsFromViewRows(List<ViewRowData> rows) {
    final out = rows
        .map(
          (row) => _DepartureRow(
            plateDocId: row.plateId,
            tail4: _tail4Digits(row.plateNumber),
            primaryAt: row.primaryAt ?? row.updatedAt ?? row.createdAt,
            isSelected: row.isSelected,
            selectedBy: row.selectedBy,
          ),
        )
        .toList(growable: false);

    out.sort((a, b) {
      final aSelected = a.isSelected ? 0 : 1;
      final bSelected = b.isSelected ? 0 : 1;
      if (aSelected != bSelected) return aSelected.compareTo(bSelected);
      final ad = a.primaryAt;
      final bd = b.primaryAt;
      if (ad == null && bd == null) return a.plateDocId.compareTo(b.plateDocId);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = bd.compareTo(ad);
      if (c != 0) return c;
      return a.plateDocId.compareTo(b.plateDocId);
    });

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final currentArea =
        context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final iconBg = _tintOnSurface(
      cs,
      opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10,
    );

    final header = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline.withOpacity(.10)),
          ),
          child: Icon(Icons.directions_car, color: cs.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '태블릿 출차 현황',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                currentArea.isEmpty ? '지역 -' : '지역 $currentArea',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (text.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final area = currentArea.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 10),
        Expanded(
          flex: 3,
          child: _PanelSection(
            title: '출차 요청',
            icon: Icons.logout,
            accentColor: cs.primary,
            child: area.isEmpty
                ? const SizedBox.expand()
                : _DepartureRequestGrid(
                    area: area,
                    columns: columns,
                    colorScheme: cs,
                    textTheme: text,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          flex: 2,
          child: _PanelSection(
            title: '업무 중 출차 완료',
            icon: Icons.check_circle_outline,
            accentColor: cs.tertiary,
            child: _CompletedDepartureGrid(
              notices: completedNotices,
              columns: columns,
              colorScheme: cs,
              textTheme: text,
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
    required this.accentColor,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accentColor),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (text.titleSmall ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
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
    required this.colorScheme,
    required this.textTheme,
  });

  final String area;
  final int columns;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

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
    if (oldWidget.area != widget.area) {
      _bindStream(widget.area);
    }
  }

  void _bindStream(String area) {
    final trimmedArea = area.trim();
    _boundArea = trimmedArea;
    final repo = context.read<PlateRepository>();
    _stream = repo.watchViewRows(
      collection: 'departure_requests_view',
      area: trimmedArea,
      primaryAtField: 'departureRequestedAt',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final text = widget.textTheme;

    return StreamBuilder<List<ViewRowData>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          debugPrint(
            '[TabletLeftPane][departure_requests_view] a=$_boundArea error=${snap.error}',
          );
          unawaited(
            DevFirebaseDebugDialog.show(
              context: context,
              operation: 'tablet.departure_requests_view.listen',
              error: snap.error,
              stackTrace: snap.stackTrace,
              details: <String, Object?>{
                'collection': 'departure_requests_view',
                'area': _boundArea,
                'primaryAtField': 'departureRequestedAt',
                'widget': 'LeftPaneDeparturePlates',
              },
            ),
          );
          return const SizedBox.expand();
        }
        if (!snap.hasData) {
          debugPrint(
            '[TabletLeftPane][departure_requests_view] a=$_boundArea loading...',
          );
          return const Center(child: CircularProgressIndicator());
        }

        final rows = LeftPaneDeparturePlates._rowsFromViewRows(snap.data!);

        debugPrint(
          '[TabletLeftPane][departure_requests_view] a=$_boundArea n=${rows.length}',
        );

        if (rows.isEmpty) {
          return const SizedBox.expand();
        }

        return _PlateGrid(
          itemCount: rows.length,
          columns: widget.columns,
          minTileWidth: 72,
          desiredTileHeight: 90,
          itemBuilder: (context, index) {
            final row = rows[index];
            final tail = row.tail4.isEmpty ? '-' : row.tail4;
            return _PlateTile(
              tail4: tail,
              colorScheme: cs,
              textTheme: text,
              completed: false,
              inProgress: row.isSelected,
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
    required this.colorScheme,
    required this.textTheme,
  });

  final List<TabletCompletedDepartureNotice> notices;
  final int columns;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return const SizedBox.expand();
    }

    return _PlateGrid(
      itemCount: notices.length,
      columns: columns,
      minTileWidth: 78,
      desiredTileHeight: 98,
      itemBuilder: (context, index) {
        final notice = notices[index];
        final tail = notice.tail4.isEmpty ? '-' : notice.tail4;
        return _PlateTile(
          tail4: tail,
          colorScheme: colorScheme,
          textTheme: textTheme,
          completed: true,
          timeLabel: _formatTime(notice.completedAt),
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
        const cross = 10.0;
        const main = 10.0;
        const pad = 6.0 * 2;
        final maxW = constraints.maxWidth;

        var effectiveColumns = columns;
        while (effectiveColumns > 1) {
          final w =
              (maxW - pad - cross * (effectiveColumns - 1)) / effectiveColumns;
          if (w >= minTileWidth) break;
          effectiveColumns -= 1;
        }

        final tileW =
            (maxW - pad - cross * (effectiveColumns - 1)) / effectiveColumns;
        final aspect = (tileW / desiredTileHeight).clamp(0.55, 1.10).toDouble();

        return GridView.builder(
          padding: const EdgeInsets.all(6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveColumns,
            crossAxisSpacing: cross,
            mainAxisSpacing: main,
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
    required this.selectedBy,
  });

  final String plateDocId;
  final String tail4;
  final DateTime? primaryAt;
  final bool isSelected;
  final String? selectedBy;
}

class _PlateTile extends StatelessWidget {
  const _PlateTile({
    required this.tail4,
    required this.colorScheme,
    required this.textTheme,
    required this.completed,
    this.inProgress = false,
    this.timeLabel,
  });

  final String tail4;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool completed;
  final bool inProgress;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final accent = completed
        ? cs.tertiary
        : inProgress
            ? cs.error
            : cs.primary;
    final background = completed || inProgress
        ? Color.alphaBlend(accent.withOpacity(.08), cs.surface)
        : cs.surface;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completed || inProgress
              ? accent.withOpacity(.40)
              : cs.outlineVariant.withOpacity(.70),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.07),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (completed) ...[
                  Icon(Icons.check_circle_outline, color: accent, size: 18),
                  const SizedBox(width: 5),
                ] else if (inProgress) ...[
                  Icon(Icons.directions_car_filled, color: accent, size: 18),
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
                      style: (textTheme.headlineSmall ??
                              const TextStyle(fontSize: 20))
                          .copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (completed && timeLabel != null) ...[
              const SizedBox(height: 2),
              Text(
                '완료 $timeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (textTheme.labelSmall ?? const TextStyle(fontSize: 11))
                        .copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ] else if (inProgress) ...[
              const SizedBox(height: 2),
              Text(
                '출차 중',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (textTheme.labelSmall ?? const TextStyle(fontSize: 11))
                        .copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

String _tail4Digits(String plateNumber) {
  final d = _digitsOnly(plateNumber);
  if (d.length <= 4) return d;
  return d.substring(d.length - 4);
}

String _formatTime(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
