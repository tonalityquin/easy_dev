import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/account/applications/user_state.dart';
import '../operational_cache/domain/location_cache_scope.dart';
import '../../app/utils/location_debug_status.dart';
import '../../features/dev/application/area_state.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import '../plate/domain/repositories/plate_repository.dart';

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

  String? _lastScope;
  bool _scopeInitialized = false;
  int _listenSeq = 0;

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  Future<void> _resubscribe(String area, String company, String? scope) async {
    if (_lastScope != scope) return;
    final int mySeq = ++_listenSeq;
    final previous = _subs.values.toList(growable: false);
    _subs.clear();
    context.read<ViewDocRowsStore>().switchCompanyScope(company);
    for (final subscription in previous) {
      await subscription.cancel();
    }
    if (!mounted || mySeq != _listenSeq || _lastScope != scope) return;
    final currentCompany = context.read<AreaState>().currentDivision.trim();
    if (currentCompany != company) return;
    if (_lastScope != LocationCacheScope.maybeKey(company, area)) return;
    if (scope == null) return;

    for (final spec in widget.specs) {
      final c = spec.collection.trim();
      if (c.isEmpty) continue;

      final repo = context.read<PlateRepository>();

      _subs[c] = repo
          .watchViewRows(
        collection: c,
        area: area,
        companyId: company,
        primaryAtField: spec.primaryAtField,
      )
          .listen(
        (rows) {
          if (!mounted) return;
          if (mySeq != _listenSeq) return;
          if (context.read<AreaState>().currentDivision.trim() != company) return;
          if (_lastScope != LocationCacheScope.maybeKey(company, area)) return;

          try {
            context.read<ViewDocRowsStore>().setRows(
                  collection: c,
                  area: area,
                  companyId: company,
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
          if (context.read<AreaState>().currentDivision.trim() != company) return;
          if (_lastScope != LocationCacheScope.maybeKey(company, area)) return;
          debugPrint('[ViewDocRowsFirestoreSync] snap error $c/$area: $e');
          LocationDebugStatus.report(
            context: context,
            title: '주차 현황 동기화 오류',
            operation: 'ViewDocRowsFirestoreSync.watchViewRows',
            error: e,
            details: <String, Object?>{
              'companyId': company,
              'area': area,
              'collection': c,
            },
          );

          try {
            context.read<ViewDocRowsStore>().setRows(
                  collection: c,
                  area: area,
                  companyId: company,
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
    final company = context.select<AreaState, String>(
      (s) => s.currentDivision.trim(),
    );
    final scope = LocationCacheScope.maybeKey(company, area);

    if (!_scopeInitialized || _lastScope != scope) {
      _scopeInitialized = true;
      _lastScope = scope;
      Future.microtask(() {
        if (!mounted) return;
        _resubscribe(area, company, scope);
      });
    }

    return const SizedBox.shrink();
  }
}
