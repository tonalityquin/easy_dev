import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../dev/application/area_state.dart';
import '../../../plate/application/common/view_doc_rows_store.dart';
import '../../../plate/domain/repositories/plate_repository.dart';

class LeftPaneDeparturePlates extends StatelessWidget {
  const LeftPaneDeparturePlates({
    super.key,
    this.columns = 3,
  }) : assert(columns > 0);

  final int columns;

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static String _tail4Digits(String plateNumber) {
    final d = _digitsOnly(plateNumber);
    if (d.length <= 4) return d;
    return d.substring(d.length - 4);
  }

  static List<_DepartureRow> _rowsFromViewRows(List<ViewRowData> rows) {
    final out = rows
        .map(
          (row) => _DepartureRow(
            plateDocId: row.plateId,
            plateNumber: row.plateNumber,
            tail4: _tail4Digits(row.plateNumber),
            primaryAt: row.primaryAt ?? row.updatedAt ?? row.createdAt,
          ),
        )
        .toList(growable: false);

    out.sort((a, b) {
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
    final iconBg = _tintOnSurface(cs,
        opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10);

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
                '출차 요청 번호판(뒷 4자리)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                currentArea.isEmpty ? '지역: -' : '지역: $currentArea',
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

    if (currentArea.trim().isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 10),
          const _InfoBox(
            text: '지역이 설정되지 않았습니다.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 10),
        Expanded(
          child: _DepartureRequestGrid(
            area: currentArea.trim(),
            columns: columns,
            colorScheme: cs,
            textTheme: text,
          ),
        ),
      ],
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
              '[TabletLeftPane][departure_requests_view] a=$_boundArea error=${snap.error}');
          return const _InfoBox(text: '출차 요청 목록을 불러오지 못했습니다.');
        }
        if (!snap.hasData) {
          debugPrint(
              '[TabletLeftPane][departure_requests_view] a=$_boundArea loading...');
          return const Center(child: CircularProgressIndicator());
        }

        final rows = LeftPaneDeparturePlates._rowsFromViewRows(snap.data!);

        debugPrint(
          '[TabletLeftPane][departure_requests_view] a=$_boundArea n=${rows.length}',
        );

        if (rows.isEmpty) {
          return const _InfoBox(text: '출차 요청이 없습니다.');
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const cross = 10.0;
            const main = 10.0;
            const pad = 6.0 * 2;
            final maxW = constraints.maxWidth;

            const minTileW = 72.0;
            var effectiveColumns = widget.columns;
            while (effectiveColumns > 1) {
              final w = (maxW - pad - cross * (effectiveColumns - 1)) /
                  effectiveColumns;
              if (w >= minTileW) break;
              effectiveColumns -= 1;
            }

            final tileW = (maxW - pad - cross * (effectiveColumns - 1)) /
                effectiveColumns;
            const desiredH = 84.0;
            final aspect = (tileW / desiredH).clamp(0.55, 1.10);
            return GridView.builder(
              padding: const EdgeInsets.all(6),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: effectiveColumns,
                crossAxisSpacing: cross,
                mainAxisSpacing: main,
                childAspectRatio: aspect,
              ),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final tail = r.tail4.isEmpty ? '-' : r.tail4;
                return _PlateTile(
                  tail4: tail,
                  plateNumber: r.plateNumber,
                  cs: cs,
                  text: text,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DepartureRow {
  const _DepartureRow({
    required this.plateDocId,
    required this.plateNumber,
    required this.tail4,
    required this.primaryAt,
  });

  final String plateDocId;
  final String plateNumber;
  final String tail4;
  final DateTime? primaryAt;
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: (textTheme.bodyMedium ?? const TextStyle(fontSize: 14))
                  .copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlateTile extends StatelessWidget {
  const _PlateTile({
    required this.tail4,
    required this.plateNumber,
    required this.cs,
    required this.text,
  });

  final String tail4;
  final String plateNumber;
  final ColorScheme cs;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
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
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  tail4,
                  maxLines: 1,
                  softWrap: false,
                  style: (text.headlineSmall ?? const TextStyle(fontSize: 20))
                      .copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              plateNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (text.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
