import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/plate/application/common/view_doc_rows_store.dart';
import '../../../features/plate/domain/repositories/plate_repository.dart';

@immutable
class ViewDocSyncSpec {
  final String collection;
  final String primaryAtField;

  const ViewDocSyncSpec({
    required this.collection,
    required this.primaryAtField,
  });
}

class ViewDocRowsFirestoreSync extends StatefulWidget {
  final List<ViewDocSyncSpec> specs;
  final String sourceTag;

  const ViewDocRowsFirestoreSync({
    super.key,
    required this.specs,
    required this.sourceTag,
  });

  @override
  State<ViewDocRowsFirestoreSync> createState() =>
      _ViewDocRowsFirestoreSyncState();
}

class _ViewDocRowsFirestoreSyncState extends State<ViewDocRowsFirestoreSync> {
  final Map<String, StreamSubscription<List<ViewRowData>>> _subs =
      <String, StreamSubscription<List<ViewRowData>>>{};

  String _lastArea = '';
  int _listenSeq = 0;

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  Future<void> _resubscribe(String area) async {
    _listenSeq++;
    final int mySeq = _listenSeq;

    for (final s in _subs.values) {
      await s.cancel();
    }
    _subs.clear();

    if (!mounted) return;
    if (area.isEmpty) return;

    for (final spec in widget.specs) {
      final c = spec.collection.trim();
      if (c.isEmpty) continue;

      final repo = context.read<PlateRepository>();

      _subs[c] = repo
          .watchViewRows(
        collection: c,
        area: area,
        primaryAtField: spec.primaryAtField,
      )
          .listen(
        (rows) {
          if (!mounted) return;
          if (mySeq != _listenSeq) return;

          try {
            context.read<ViewDocRowsStore>().setRows(
                  collection: c,
                  area: area,
                  rows: rows,
                  source: widget.sourceTag,
                );
          } catch (e) {
            debugPrint(
                '[ViewDocRowsFirestoreSync] setRows failed $c/$area: $e');
          }
        },
        onError: (e) {
          if (!mounted) return;
          if (mySeq != _listenSeq) return;
          debugPrint('[ViewDocRowsFirestoreSync] snap error $c/$area: $e');

          try {
            context.read<ViewDocRowsStore>().setRows(
                  collection: c,
                  area: area,
                  rows: const <ViewRowData>[],
                  source: '${widget.sourceTag}/error',
                );
          } catch (_) {}
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userArea =
        context.select<UserState, String>((s) => s.currentArea.trim());
    final stateArea =
        context.select<AreaState, String>((s) => s.currentArea.trim());
    final area = userArea.isNotEmpty ? userArea : stateArea;

    if (area != _lastArea) {
      _lastArea = area;
      Future.microtask(() {
        if (!mounted) return;
        _resubscribe(area);
      });
    }

    return const SizedBox.shrink();
  }
}
