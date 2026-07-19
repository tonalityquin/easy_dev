import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../features/dev/application/area_state.dart';
import '../../../../../features/location/applications/location_state.dart';
import '../../../../../features/location/domain/models/grid_rect.dart';
import '../../../../../features/location/domain/models/location_model.dart';
import '../../../../../features/location/domain/models/parking_grid_model.dart';
import '../../../../plate/domain/repositories/plate_repository.dart';

enum _BlockedSlotKind { parked, departureRequest }

int? _parseFirstInt(String raw) {
  final m = RegExp(r'(\d+)').firstMatch(raw);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? '');
}

List<String> _splitLocationSegments(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return const <String>[];
  return v
      .split(' - ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

bool _slotOverlapsGridRects(ChildSlot s, List<GridRect> rects) {
  if (rects.isEmpty) return false;
  final sr = GridRect(r0: s.r0, c0: s.c0, r1: s.r1, c1: s.c1).normalized();
  for (final r in rects) {
    if (r.normalized().overlaps(sr)) return true;
  }
  return false;
}

class _ViewRow {
  final String location;

  const _ViewRow({required this.location});
}

class _ParkingViewMemCache {
  _ParkingViewMemCache._();

  static final Map<String, List<_ViewRow>> _cacheByKey =
      <String, List<_ViewRow>>{};
  static final Map<String, int> _cacheAtMsByKey = <String, int>{};

  static String _k(String collection, String area) =>
      '$collection|${area.trim()}';

  static bool _shouldUseCache(String collection) {
    switch (collection) {
      case 'parking_completed_view':
        return false;
      case 'parking_requests_view':
      case 'departure_requests_view':
      default:
        return true;
    }
  }

  static Duration _ttlForCollection(String collection) {
    switch (collection) {
      case 'parking_requests_view':
      case 'departure_requests_view':
      default:
        return const Duration(seconds: 3);
    }
  }

  static void invalidate({
    required String collection,
    required String area,
  }) {
    final a = area.trim();
    if (a.isEmpty) return;
    final k = _k(collection, a);
    _cacheByKey.remove(k);
    _cacheAtMsByKey.remove(k);
  }

  static void invalidateArea(String area) {
    final a = area.trim();
    if (a.isEmpty) return;
    invalidate(collection: 'parking_completed_view', area: a);
    invalidate(collection: 'parking_requests_view', area: a);
    invalidate(collection: 'departure_requests_view', area: a);
  }

  static Future<List<_ViewRow>> fetch({
    required PlateRepository plateRepository,
    required String collection,
    required String area,
    required bool forceRefresh,
  }) async {
    final a = area.trim();
    if (a.isEmpty) return const <_ViewRow>[];

    final k = _k(collection, a);
    final useCache = !forceRefresh && _shouldUseCache(collection);
    final ttl = _ttlForCollection(collection);

    if (useCache) {
      final atMs = _cacheAtMsByKey[k] ?? 0;
      if (atMs > 0) {
        final age = DateTime.now().millisecondsSinceEpoch - atMs;
        if (age >= 0 && age <= ttl.inMilliseconds) {
          return List<_ViewRow>.of(_cacheByKey[k] ?? const <_ViewRow>[]);
        }
      }
    }

    final locations = await plateRepository.fetchViewLocations(
      collectionName: collection,
      area: a,
    );
    final out = locations
        .map((location) => _ViewRow(location: location))
        .toList(growable: false);

    if (out.isEmpty) {
      if (useCache) {
        _cacheByKey[k] = const <_ViewRow>[];
        _cacheAtMsByKey[k] = DateTime.now().millisecondsSinceEpoch;
      } else {
        _cacheByKey.remove(k);
        _cacheAtMsByKey.remove(k);
      }
      return const <_ViewRow>[];
    }

    if (useCache) {
      _cacheByKey[k] = List<_ViewRow>.of(out);
      _cacheAtMsByKey[k] = DateTime.now().millisecondsSinceEpoch;
    } else {
      _cacheByKey.remove(k);
      _cacheAtMsByKey.remove(k);
    }
    return out;
  }
}


String _normalizeParkingAreaCategory(String value) {
  final v = value.trim().toLowerCase().replaceAll('×', 'x').replaceAll(RegExp(r'\s+'), '');
  if (v.isEmpty) return '';
  final isEv = v.contains('전기차') || v.contains('전기') || v.contains('ev') || v.contains('electric');
  final isPregnant = v.contains('임산부') || v.contains('pregnant') || v.contains('maternity');
  final isDisabled = v.contains('장애인') || v.contains('disabled') || v.contains('accessible') || v.contains('handicap');
  final isExtendedB = v.contains('확장형b') || v.contains('확장b') || v.contains('extendedb') || v.contains('expandedb');
  final isExtendedA = v.contains('확장형a') || v.contains('확장a') || v.contains('extendeda') || v.contains('expandeda');
  final isExtended = isExtendedA || isExtendedB || v.contains('확장형') || v.contains('확장') || v.contains('extended') || v.contains('expand');
  final isStandard = v.contains('일반형') || v.contains('일반') || v.contains('standard') || v.contains('normal') || v.contains('general');
  final isCompact = v.contains('경형') || v.contains('경차') || v.contains('compact') || v.contains('light') || v.contains('small');
  if (isEv) {
    if (isExtendedB) return '전기차 확장형 B';
    if (isExtendedA || isExtended) return '전기차 확장형 A';
    if (isStandard) return '전기차 일반형';
    if (isCompact) return '전기차 경형';
    return '전기차';
  }
  if (isPregnant) {
    if (isExtendedB) return '임산부 배려 확장형 B';
    return '임산부 배려 확장형 A';
  }
  if (isDisabled) {
    if (isExtendedB) return '장애인 확장형 B';
    if (isExtendedA || isExtended) return '장애인 확장형 A';
    if (isStandard) return '장애인 일반형';
    return '장애인';
  }
  if (isExtendedB) return '확장형 B';
  if (isExtendedA) return '확장형 A';
  if (isExtended) return '확장형';
  if (isStandard) return '일반형';
  if (isCompact) return '경형';
  return value.trim();
}

String _slotCategoryOf(ChildSlot slot) {
  final candidates = <String>[
    slot.categoryLabel,
    slot.label,
    slot.category,
    slot.kind,
  ];

  for (final value in candidates) {
    final normalized = _normalizeParkingAreaCategory(value);
    if (normalized == '확장형' ||
        normalized == '확장형 A' ||
        normalized == '확장형 B' ||
        normalized == '일반형' ||
        normalized == '경형' ||
        normalized == '전기차' ||
        normalized == '전기차 경형' ||
        normalized == '전기차 일반형' ||
        normalized == '전기차 확장형 A' ||
        normalized == '전기차 확장형 B' ||
        normalized == '임산부 배려 확장형 A' ||
        normalized == '임산부 배려 확장형 B' ||
        normalized == '장애인' ||
        normalized == '장애인 일반형' ||
        normalized == '장애인 확장형 A' ||
        normalized == '장애인 확장형 B') {
      return normalized;
    }
  }

  return '';
}

class _RecommendedParkingSlot {
  final LocationModel child;
  final ChildSlot slot;
  final String matchedPriority;
  final int priorityIndex;

  const _RecommendedParkingSlot({
    required this.child,
    required this.slot,
    required this.matchedPriority,
    required this.priorityIndex,
  });

  String get priorityLabel => '${priorityIndex + 1}순위 $matchedPriority';
  String get slotLabel => '$matchedPriority ${slot.no}번';
}


class InputLocationBottomSheet extends StatefulWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;
  final List<String> preferredParkingAreas;

  const InputLocationBottomSheet({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
    this.preferredParkingAreas = const <String>[],
  });

  static Future<void> show(
    BuildContext context,
    TextEditingController controller,
    Function(String) onSelected, {
    List<String> preferredParkingAreas = const <String>[],
    bool usePromptUi = false,
  }) async {
    String area = '';
    try {
      area = context.read<AreaState>().currentArea.trim();
    } catch (_) {}
    if (area.isNotEmpty) {
      _ParkingViewMemCache.invalidateArea(area);
    }

    Widget buildSheet(BuildContext sheetContext) {
      return InputLocationBottomSheet(
        locationController: controller,
        onLocationSelected: onSelected,
        preferredParkingAreas: preferredParkingAreas,
      );
    }

    if (usePromptUi) {
      await showPromptOverlayBottomSheet<void>(
        context: context,
        useSafeArea: false,
        transparentBackground: true,
        builder: buildSheet,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PromptUiTheme.of(context).transparent,
      builder: buildSheet,
    );
  }

  @override
  State<InputLocationBottomSheet> createState() =>
      _InputLocationBottomSheetState();
}

class _InputLocationBottomSheetState extends State<InputLocationBottomSheet> {
  String? _selectedParentName;

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  static bool _isCompositeChild(LocationModel l) {
    final t = (l.type ?? '').trim();
    if (t == 'composite_child' || t == 'composite') return true;
    final p = (l.parent ?? '').trim();
    return p.isNotEmpty;
  }

  void _applyAndClose(String fullName) {
    widget.locationController.text = fullName;
    widget.onLocationSelected(fullName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final cs = Theme.of(context).colorScheme;
    final currentArea =
        context.select<AreaState, String>((s) => s.currentArea.trim());

    return WillPopScope(
      onWillPop: () async {
        if (_selectedParentName != null) {
          setState(() => _selectedParentName = null);
          return false;
        }
        return true;
      },
      child: PromptAnimatedReveal(
        offset: const Offset(0, .03),
        child: SafeArea(
          child: Material(
            color: tokens.transparent,
            child: Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: tokens.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Consumer<LocationState>(
              builder: (context, locationState, _) {
                if (locationState.isLoading) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  );
                }

                final all = locationState.locations;
                final locations =
                    all.where((l) => l.area.trim() == currentArea).toList();

                if (locations.isEmpty) {
                  return _EmptyState(
                    title: '주차 구역 데이터가 없습니다.',
                    message:
                        '현재 지역(${currentArea.isEmpty ? "미설정" : currentArea})에 해당하는 주차 구역이 없습니다.\n'
                        '데이터 동기화 후 다시 시도하세요.',
                    onClose: () => Navigator.of(context).pop(),
                  );
                }

                final topLevels = locations
                    .where((l) => !_isCompositeChild(l))
                    .toList()
                  ..sort((a, b) => a.locationName.compareTo(b.locationName));

                final children = locations.where(_isCompositeChild).toList()
                  ..sort((a, b) => a.locationName.compareTo(b.locationName));

                if (topLevels.isEmpty) {
                  return _EmptyState(
                    title: '표시할 주차 구역이 없습니다.',
                    message:
                        '현재 지역(${currentArea.isEmpty ? "미설정" : currentArea})에서\n'
                        '상위(Top-level) 구역 문서가 없습니다.\n'
                        '데이터 구조를 확인하세요. (child 문서만 있는 상태일 수 있습니다)',
                    onClose: () => Navigator.of(context).pop(),
                  );
                }

                if (_selectedParentName != null) {
                  final parentKey = _nameKey(_selectedParentName!);

                  LocationModel? parentDoc;
                  for (final p in topLevels) {
                    if (_nameKey(p.locationName) == parentKey) {
                      parentDoc = p;
                      break;
                    }
                  }

                  final parentGrid = parentDoc?.parkingGrid;
                  if (parentGrid == null ||
                      parentGrid.rows <= 0 ||
                      parentGrid.cols <= 0) {
                    return _GridError(
                      title: '부모 그리드가 없습니다.',
                      message:
                          '선택한 부모 구역에 parkingGrid가 없거나 rows/cols가 올바르지 않습니다.',
                      onBack: () => setState(() => _selectedParentName = null),
                    );
                  }

                  final parentName = _selectedParentName!;
                  final childDocs = children
                      .where((c) => _nameKey((c.parent ?? '')) == parentKey)
                      .toList()
                    ..sort((a, b) => a.locationName.compareTo(b.locationName));

                  return _ParentChildViewportSlotFlow(
                    parentName: parentName,
                    parentGrid: parentGrid,
                    childDocs: childDocs,
                    preferredParkingAreas: widget.preferredParkingAreas,
                    onBackToParents: () =>
                        setState(() => _selectedParentName = null),
                    onPickFinal: (full) => _applyAndClose(full),
                  );
                }

                return _LocationListPicker(
                  currentArea: currentArea,
                  topLevels: topLevels,
                  onPickLocation: (loc) {
                    final grid = loc.parkingGrid;
                    final hasGrid =
                        grid != null && grid.rows > 0 && grid.cols > 0;

                    if (hasGrid) {
                      setState(() => _selectedParentName = loc.locationName);
                    } else {
                      _applyAndClose(loc.locationName);
                    }
                  },
                  onClose: () => Navigator.of(context).pop(),
                );
              },
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onClose;

  const _EmptyState({
    required this.title,
    required this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, color: cs.primary),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  label: const Text('닫기'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationListPicker extends StatelessWidget {
  final String currentArea;
  final List<LocationModel> topLevels;
  final ValueChanged<LocationModel> onPickLocation;
  final VoidCallback onClose;

  const _LocationListPicker({
    required this.currentArea,
    required this.topLevels,
    required this.onPickLocation,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: cs.outlineVariant.withOpacity(0.9),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '주차 구역 선택',
                  style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                      .copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              _Pill(
                text: currentArea.isEmpty ? '지역 미설정' : currentArea,
                tone: _PillTone.neutral,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '닫기',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              const _SectionHeader(
                title: '주차 구역(부모)',
                subtitle: '부모 선택 → 자식 선택 → (자식 영역만) 슬롯 선택',
              ),
              const SizedBox(height: 8),
              ...topLevels.map((loc) {
                final grid = loc.parkingGrid;
                final hasGrid = grid != null && grid.rows > 0 && grid.cols > 0;
                final subtitle = hasGrid
                    ? '그리드: ${grid.rows}×${grid.cols}'
                    : '그리드 없음 · 바로 선택';
                return _CardTile(
                  title: loc.locationName,
                  subtitle: subtitle,
                  leading: hasGrid ? Icons.layers_rounded : Icons.place_rounded,
                  onTap: () => onPickLocation(loc),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: (tt.titleSmall ?? const TextStyle(fontSize: 13)).copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CardTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leading;
  final VoidCallback onTap;

  const _CardTile({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(leading, color: cs.primary),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

class _ParentChildViewportSlotFlow extends StatefulWidget {
  final String parentName;
  final ParkingGridModel parentGrid;
  final List<LocationModel> childDocs;
  final List<String> preferredParkingAreas;

  final VoidCallback onBackToParents;
  final ValueChanged<String> onPickFinal;

  const _ParentChildViewportSlotFlow({
    required this.parentName,
    required this.parentGrid,
    required this.childDocs,
    required this.preferredParkingAreas,
    required this.onBackToParents,
    required this.onPickFinal,
  });

  @override
  State<_ParentChildViewportSlotFlow> createState() =>
      _ParentChildViewportSlotFlowState();
}

class _ParentChildViewportSlotFlowState
    extends State<_ParentChildViewportSlotFlow> {
  String? _selectedChildName;
  bool _isBlockedSlotsLoading = false;
  Map<int, _BlockedSlotKind> _blockedSlotsByNo = <int, _BlockedSlotKind>{};

  bool _isParentOverlayLoading = false;
  final Map<String, Map<int, _BlockedSlotKind>> _blockedSlotsByChildKey =
      <String, Map<int, _BlockedSlotKind>>{};
  final List<_ChildSlotOverlay> _childSlotOverlaysForParent =
      <_ChildSlotOverlay>[];

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  bool _isTowerChildDoc(LocationModel l) {
    try {
      final v = (l as dynamic).childKind;
      final s = (v == null) ? '' : v.toString().trim().toLowerCase();
      if (s == 'tower') return true;
    } catch (_) {}
    try {
      final v = (l as dynamic).isTowerChild;
      if (v is bool) return v;
    } catch (_) {}
    return false;
  }

  bool _rectSame(GridRect a, GridRect b) {
    final x = a.normalized();
    final y = b.normalized();
    return x.r0 == y.r0 && x.r1 == y.r1 && x.c0 == y.c0 && x.c1 == y.c1;
  }

  int _readCapacityAny(LocationModel l) {
    try {
      final v = (l as dynamic).capacity;
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  LocationModel? _findChildByName(String? name) {
    final key = _nameKey(name ?? '');
    if (key.isEmpty) return null;
    for (final c in widget.childDocs) {
      if (_nameKey(c.locationName) == key) return c;
    }
    return null;
  }

  void _selectChild(String childName) {
    setState(() {
      _selectedChildName = childName;
      _isBlockedSlotsLoading = true;
      _blockedSlotsByNo = <int, _BlockedSlotKind>{};
    });
    Future.microtask(() => _refreshBlockedSlots(
        parentName: widget.parentName, childName: childName));
  }

  void _backToChildPicker() {
    setState(() {
      _selectedChildName = null;
      _isBlockedSlotsLoading = false;
      _blockedSlotsByNo = <int, _BlockedSlotKind>{};
    });
    _refreshParentOverlay(forceRefresh: true);
  }

  @override
  void initState() {
    super.initState();
    _refreshParentOverlay(forceRefresh: true);
  }

  @override
  void didUpdateWidget(covariant _ParentChildViewportSlotFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentName != widget.parentName ||
        oldWidget.childDocs != widget.childDocs) {
      _refreshParentOverlay(forceRefresh: true);
    }
  }

  Future<void> _refreshParentOverlay({required bool forceRefresh}) async {
    if (!mounted) return;

    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      setState(() {
        _isParentOverlayLoading = false;
        _blockedSlotsByChildKey.clear();
        _childSlotOverlaysForParent.clear();
      });
      return;
    }

    setState(() => _isParentOverlayLoading = true);

    List<_ViewRow> completed = const <_ViewRow>[];
    List<_ViewRow> departures = const <_ViewRow>[];

    try {
      final results = await Future.wait(<Future<List<_ViewRow>>>[
        _ParkingViewMemCache.fetch(
          plateRepository: context.read<PlateRepository>(),
          collection: 'parking_completed_view',
          area: area,
          forceRefresh: forceRefresh,
        ),
        _ParkingViewMemCache.fetch(
          plateRepository: context.read<PlateRepository>(),
          collection: 'departure_requests_view',
          area: area,
          forceRefresh: forceRefresh,
        ),
      ]);
      completed = results[0];
      departures = results[1];
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isParentOverlayLoading = false;
        _blockedSlotsByChildKey.clear();
        _childSlotOverlaysForParent.clear();
      });
      return;
    }

    final parentKey = _nameKey(widget.parentName);
    final childKeySet = widget.childDocs
        .map((c) => _nameKey(c.locationName))
        .where((k) => k.isNotEmpty)
        .toSet();

    final outByChild = <String, Map<int, _BlockedSlotKind>>{};

    void apply(List<_ViewRow> rows, _BlockedSlotKind kind) {
      for (final r in rows) {
        final seg = _splitLocationSegments(r.location);
        if (seg.length < 3) continue;
        if (_nameKey(seg[0]) != parentKey) continue;
        final ck = _nameKey(seg[1]);
        if (ck.isEmpty || !childKeySet.contains(ck)) continue;
        final no = _parseFirstInt(seg[2]);
        if (no == null || no <= 0) continue;
        outByChild.putIfAbsent(ck, () => <int, _BlockedSlotKind>{})[no] = kind;
      }
    }

    apply(completed, _BlockedSlotKind.parked);
    apply(departures, _BlockedSlotKind.departureRequest);

    final overlays = <_ChildSlotOverlay>[];
    for (final c in widget.childDocs) {
      final ck = _nameKey(c.locationName);
      if (ck.isEmpty) continue;
      final slots = c.childSlots;
      if (slots.isEmpty) continue;
      for (final s in slots) {
        overlays.add(_ChildSlotOverlay(childKey: ck, slot: s));
      }
    }

    if (!mounted) return;
    setState(() {
      _isParentOverlayLoading = false;
      _blockedSlotsByChildKey
        ..clear()
        ..addAll(outByChild);
      _childSlotOverlaysForParent
        ..clear()
        ..addAll(overlays);
    });
  }

  Future<void> _refreshBlockedSlots({
    required String parentName,
    required String childName,
  }) async {
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isBlockedSlotsLoading = false;
        _blockedSlotsByNo = <int, _BlockedSlotKind>{};
      });
      return;
    }

    final parentKey = _nameKey(parentName);
    final childKey = _nameKey(childName);

    List<_ViewRow> completed = const <_ViewRow>[];
    List<_ViewRow> departures = const <_ViewRow>[];

    try {
      final results = await Future.wait(<Future<List<_ViewRow>>>[
        _ParkingViewMemCache.fetch(
          plateRepository: context.read<PlateRepository>(),
          collection: 'parking_completed_view',
          area: area,
          forceRefresh: true,
        ),
        _ParkingViewMemCache.fetch(
          plateRepository: context.read<PlateRepository>(),
          collection: 'departure_requests_view',
          area: area,
          forceRefresh: true,
        ),
      ]);
      completed = results[0];
      departures = results[1];
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isBlockedSlotsLoading = false;
        _blockedSlotsByNo = <int, _BlockedSlotKind>{};
      });
      return;
    }

    final out = <int, _BlockedSlotKind>{};

    void apply(List<_ViewRow> rows, _BlockedSlotKind kind) {
      for (final r in rows) {
        final seg = _splitLocationSegments(r.location);
        if (seg.length < 3) continue;
        if (_nameKey(seg[0]) != parentKey) continue;
        if (_nameKey(seg[1]) != childKey) continue;
        final no = _parseFirstInt(seg[2]);
        if (no == null || no <= 0) continue;
        out[no] = kind;
      }
    }

    apply(completed, _BlockedSlotKind.parked);
    apply(departures, _BlockedSlotKind.departureRequest);

    if (!mounted) return;
    setState(() {
      _blockedSlotsByNo = out;
      _isBlockedSlotsLoading = false;
    });
  }

  String? _readSlotLabelAny(dynamic s) {
    for (final getter in <String? Function()>[
      () {
        try {
          final v = s.slotLabel;
          final t = (v == null) ? '' : v.toString().trim();
          return t.isEmpty ? null : t;
        } catch (_) {
          return null;
        }
      },
      () {
        try {
          final v = s.label;
          final t = (v == null) ? '' : v.toString().trim();
          return t.isEmpty ? null : t;
        } catch (_) {
          return null;
        }
      },
      () {
        try {
          final v = s.name;
          final t = (v == null) ? '' : v.toString().trim();
          return t.isEmpty ? null : t;
        } catch (_) {
          return null;
        }
      },
    ]) {
      final v = getter();
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  int _readSlotNoAny(dynamic s) {
    try {
      final v = s.no;
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString().trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  List<String> _normalizedPreferredParkingAreas() {
    return widget.preferredParkingAreas
        .map(_normalizeParkingAreaCategory)
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  _RecommendedParkingSlot? _findRecommendedSlot({
    required List<LocationModel> children,
    required Map<String, Map<int, _BlockedSlotKind>> blockedSlotsByChildKey,
  }) {
    final priorities = _normalizedPreferredParkingAreas();
    if (priorities.isEmpty) return null;

    for (var priorityIndex = 0;
        priorityIndex < priorities.length;
        priorityIndex++) {
      final priority = priorities[priorityIndex];
      final candidates = <_RecommendedParkingSlot>[];

      for (final child in children) {
        if (_isTowerChildDoc(child)) continue;
        final childKey = _nameKey(child.locationName);
        final blocked =
            blockedSlotsByChildKey[childKey] ?? const <int, _BlockedSlotKind>{};

        final slots = child.childSlots
            .where((slot) => _slotCategoryOf(slot) == priority)
            .where((slot) => !blocked.containsKey(slot.no))
            .toList()
          ..sort((a, b) => a.no.compareTo(b.no));

        if (slots.isEmpty) continue;

        candidates.add(
          _RecommendedParkingSlot(
            child: child,
            slot: slots.first,
            matchedPriority: priority,
            priorityIndex: priorityIndex,
          ),
        );
      }

      if (candidates.isEmpty) continue;

      candidates.sort((a, b) {
        final slotCompare = a.slot.no.compareTo(b.slot.no);
        if (slotCompare != 0) return slotCompare;
        return a.child.locationName.compareTo(b.child.locationName);
      });

      return candidates.first;
    }

    return null;
  }

  _RecommendedParkingSlot? _findRecommendedSlotForChild({
    required LocationModel child,
    required Map<int, _BlockedSlotKind> blockedSlotsByNo,
  }) {
    final priorities = _normalizedPreferredParkingAreas();
    if (priorities.isEmpty) return null;
    if (_isTowerChildDoc(child)) return null;

    for (var priorityIndex = 0;
        priorityIndex < priorities.length;
        priorityIndex++) {
      final priority = priorities[priorityIndex];
      final slots = child.childSlots
          .where((slot) => _slotCategoryOf(slot) == priority)
          .where((slot) => !blockedSlotsByNo.containsKey(slot.no))
          .toList()
        ..sort((a, b) => a.no.compareTo(b.no));

      if (slots.isEmpty) continue;

      return _RecommendedParkingSlot(
        child: child,
        slot: slots.first,
        matchedPriority: priority,
        priorityIndex: priorityIndex,
      );
    }

    return null;
  }

  void _pickSlotAndClose(LocationModel child, ChildSlot slot) {
    final dynamic s = slot;
    final label = _readSlotLabelAny(s)?.trim() ?? '';
    final no = _readSlotNoAny(s);

    final slotSeg = no > 0
        ? '슬롯 $no${label.isNotEmpty ? ' · $label' : ''}'
        : (label.isNotEmpty ? label : '슬롯');

    final full = '${widget.parentName} - ${child.locationName} - $slotSeg';
    widget.onPickFinal(full);
  }

  void _pickTowerSlotAndClose(LocationModel child, int no) {
    final seg = '슬롯 $no';
    final full = '${widget.parentName} - ${child.locationName} - $seg';
    widget.onPickFinal(full);
  }

  Widget _buildChildQuickChips(
    List<LocationModel> children,
    _RecommendedParkingSlot? recommendation,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Align(
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    _ChoiceChip(
                      selected: recommendation != null &&
                          _nameKey(recommendation.child.locationName) ==
                              _nameKey(children[i].locationName),
                      label: _isTowerChildDoc(children[i])
                          ? '${children[i].locationName} (타워)'
                          : (recommendation != null &&
                                  _nameKey(recommendation.child.locationName) ==
                                      _nameKey(children[i].locationName)
                              ? '${children[i].locationName} · 추천'
                              : children[i].locationName),
                      onTap: () => _selectChild(children[i].locationName),
                    ),
                    if (i != children.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final grid = widget.parentGrid;
    final children = [...widget.childDocs]
      ..sort((a, b) => a.locationName.compareTo(b.locationName));
    final selectedChild = _findChildByName(_selectedChildName);
    final parentRecommendation =
        (!_isParentOverlayLoading && _selectedChildName == null)
            ? _findRecommendedSlot(
                children: children,
                blockedSlotsByChildKey: _blockedSlotsByChildKey,
              )
            : null;

    if (selectedChild == null) {
      final overlays = <ChildRegionOverlay>[
        for (final c in children)
          if (c.childRect != null)
            ChildRegionOverlay(
              rect: c.childRect!,
              label: c.locationName,
              isSelected: false,
            ),
      ];

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                IconButton(
                  tooltip: '부모 목록으로',
                  onPressed: widget.onBackToParents,
                  icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '자식 주차 구역 선택',
                    style: (tt.titleSmall ?? const TextStyle(fontSize: 14))
                        .copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                _Pill(text: widget.parentName, tone: _PillTone.primary),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
          if (_isParentOverlayLoading)
            LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.surfaceVariant.withOpacity(0.35),
            ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                child: Text(
                  '이 부모 구역에 연결된 자식(composite_child) 문서가 없습니다.\n'
                  'child 문서의 parent 필드가 부모 이름과 매칭되는지 확인하세요.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '자식 구역을 선택하면 해당 영역만 확대(크롭)되어 슬롯 선택 화면으로 이동합니다.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxExtent = math.min(constraints.maxWidth, 520.0);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _InteractiveParkingGridPreview(
                      grid: grid,
                      showTowers: true,
                      viewport: null,
                      maxExtent: maxExtent,
                      showLegend: true,
                      showWalls: true,
                      showGates: true,
                      showWallNames: true,
                      showParkingAreas: true,
                      showParkingAreaLabels: true,
                      showChildRegions: overlays.isNotEmpty,
                      childRegions: overlays,
                      showChildRegionLabels: true,
                      showAllChildRegionLabels: true,
                      showChildSlotOverlay: true,
                      childSlotOverlays: _childSlotOverlaysForParent,
                      blockedSlotsByChildKey: _blockedSlotsByChildKey,
                      recommendedChildKey: parentRecommendation == null
                          ? null
                          : _nameKey(parentRecommendation.child.locationName),
                      recommendedSlotNo: parentRecommendation?.slot.no,
                      showChildSlotNumbers: false,
                      childSlotsToLabel: const <ChildSlot>[],
                      onTapChildRegion: (childLabel) =>
                          _selectChild(childLabel),
                      onTapTowerRect: (tr) async {
                        LocationModel? match;
                        for (final c in children) {
                          if (!_isTowerChildDoc(c)) continue;
                          final cr = c.childRect;
                          if (cr == null) continue;
                          if (_rectSame(cr, tr)) {
                            match = c;
                            break;
                          }
                        }
                        if (match != null) {
                          _selectChild(match.locationName);
                          return;
                        }
                      },
                      onTapChildSlot: null,
                      blockedSlotsByNo: const <int, _BlockedSlotKind>{},
                      legendBottom: (children.isNotEmpty)
                          ? _buildChildQuickChips(children, parentRecommendation)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                Icon(Icons.touch_app_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '그리드에서 자식 영역(라벨)을 탭하거나, 범례 아래 칩을 탭해 선택하세요.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final rect = selectedChild.childRect?.normalized();
    if (rect == null) {
      return _GridError(
        title: '자식 영역(childRect)이 없습니다.',
        message: '선택한 자식 구역(${selectedChild.locationName})에 childRect가 없어\n'
            '부모 그리드에서 자식 영역만 표시(크롭)할 수 없습니다.\n'
            'childRect를 저장하도록 데이터 구조를 확인하세요.',
        onBack: _backToChildPicker,
      );
    }

    final isTowerChild = _isTowerChildDoc(selectedChild);
    if (isTowerChild) {
      final cap = _readCapacityAny(selectedChild);
      return _TowerSlotPicker(
        parentName: widget.parentName,
        child: selectedChild,
        rect: rect,
        capacity: cap,
        isLoading: _isBlockedSlotsLoading,
        blockedSlotsByNo: _blockedSlotsByNo,
        onBack: _backToChildPicker,
        onPick: (no) => _pickTowerSlotAndClose(selectedChild, no),
      );
    }

    final slotsToLabel = selectedChild.childSlots;
    final hasSlots = slotsToLabel.isNotEmpty;
    final recommendedForChild =
        (!_isBlockedSlotsLoading && hasSlots)
            ? _findRecommendedSlotForChild(
                child: selectedChild,
                blockedSlotsByNo: _blockedSlotsByNo,
              )
            : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: '자식 선택으로',
                onPressed: _backToChildPicker,
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '슬롯 선택(자식 영역만)',
                  style:
                      (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              _Pill(text: widget.parentName, tone: _PillTone.primary),
              const SizedBox(width: 8),
              _Pill(text: selectedChild.locationName, tone: _PillTone.neutral),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
        if (_isBlockedSlotsLoading)
          LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.surfaceVariant.withOpacity(0.35)),
        if (!hasSlots)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              child: Text(
                '이 자식 구역에서 표시할 childSlots가 없습니다.\n'
                '- 자식 문서에 childSlots가 저장되어 있는지 확인하세요.\n'
                '- slotLabel/label 값이 있으면 “P####” 같은 라벨로 저장할 수 있습니다.\n'
                '뒤로가기를 눌러 다른 자식을 선택할 수 있습니다.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const legendReserve = 88.0;
                final maxH =
                    math.max(220.0, constraints.maxHeight - legendReserve);
                final maxExtent =
                    math.min(math.min(constraints.maxWidth, maxH), 560.0);

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _FixedCellPanGridPreview(
                    grid: grid,
                    viewport: rect,
                    boxExtent: maxExtent,
                    targetCellPx: 34,
                    paddingPx: 10,
                    gapPx: 2,
                    showLegend: true,
                    showWalls: true,
                    showGates: true,
                    showWallNames: true,
                    showParkingAreas: true,
                    showParkingAreaLabels: true,
                    showChildSlotNumbers: true,
                    childSlotsToLabel: slotsToLabel,
                    onTapChildSlot: (hasSlots && !_isBlockedSlotsLoading)
                        ? (slot) => _pickSlotAndClose(selectedChild, slot)
                        : null,
                    blockedSlotsByNo: _blockedSlotsByNo,
                    recommendedSlotNo: recommendedForChild?.slot.no,
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasSlots
                      ? '슬롯 번호(배지)를 탭하면 즉시 입력되고 닫힙니다.\n뒤로가기를 누르면 같은 부모의 다른 자식 구역을 선택할 수 있습니다.'
                      : '뒤로가기를 누르면 같은 부모의 다른 자식 구역을 선택할 수 있습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool> _onWillPop() async {
    if (_selectedChildName != null) {
      _backToChildPicker();
    } else {
      widget.onBackToParents();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: _content(context),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = selected
        ? cs.primaryContainer.withOpacity(0.55)
        : cs.surfaceContainerLow;
    final bd = selected
        ? cs.primary.withOpacity(0.45)
        : cs.outlineVariant.withOpacity(0.85);
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: bd),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _GridError extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onBack;

  const _GridError({
    required this.title,
    required this.message,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '그리드 선택',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded, color: cs.error),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
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

class _TowerSlotPicker extends StatelessWidget {
  final String parentName;
  final LocationModel child;
  final GridRect rect;
  final int capacity;

  final bool isLoading;
  final Map<int, _BlockedSlotKind> blockedSlotsByNo;

  final VoidCallback onBack;
  final ValueChanged<int> onPick;

  const _TowerSlotPicker({
    required this.parentName,
    required this.child,
    required this.rect,
    required this.capacity,
    required this.isLoading,
    required this.blockedSlotsByNo,
    required this.onBack,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final cap = math.max(0, capacity);
    final title = child.locationName;

    Widget pill(String text, {bool primary = false}) {
      final bg = primary
          ? cs.primaryContainer.withOpacity(0.55)
          : cs.surfaceVariant.withOpacity(0.55);
      final fg = primary ? cs.onPrimaryContainer : cs.onSurfaceVariant;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: fg),
        ),
      );
    }

    Color accentFor(_BlockedSlotKind k) {
      switch (k) {
        case _BlockedSlotKind.parked:
          return const Color(0xFF2E7D32);
        case _BlockedSlotKind.departureRequest:
          return const Color(0xFFC62828);
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              IconButton(
                tooltip: '자식 선택으로',
                onPressed: onBack,
                icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '타워 슬롯 선택',
                  style:
                      (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              pill(parentName, primary: true),
              const SizedBox(width: 8),
              pill(title),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
        if (isLoading)
          LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.surfaceVariant.withOpacity(0.35)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '영역 r:${rect.r0}-${rect.r1}, c:${rect.c0}-${rect.c1} · 수용 ${cap}대',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cross = math.max(3, (w / 64.0).floor());
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.18,
                ),
                itemCount: cap,
                itemBuilder: (context, i) {
                  final no = i + 1;
                  final kind = blockedSlotsByNo[no];
                  final disabled = kind != null;

                  final baseBg = cs.surfaceContainerLow;
                  final bd = disabled
                      ? accentFor(kind).withOpacity(0.88)
                      : cs.outlineVariant.withOpacity(0.85);
                  final fill =
                      disabled ? accentFor(kind).withOpacity(0.10) : baseBg;

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: disabled ? null : () => onPick(no),
                    child: Container(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: bd),
                      ),
                      child: Center(
                        child: Text(
                          '$no',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: disabled ? bd : cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '숫자를 탭하면 즉시 입력되고 닫힙니다. 3D 버튼으로 타워 미리보기를 열 수 있습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _PillTone { neutral, primary }

class _Pill extends StatelessWidget {
  final String text;
  final _PillTone tone;

  const _Pill({
    required this.text,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = (tone == _PillTone.primary)
        ? cs.primaryContainer.withOpacity(0.55)
        : cs.surfaceVariant.withOpacity(0.55);

    final fg = (tone == _PillTone.primary)
        ? cs.onPrimaryContainer
        : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: fg,
        ),
      ),
    );
  }
}

class ChildRegionOverlay {
  final GridRect rect;
  final String label;
  final bool isSelected;

  const ChildRegionOverlay({
    required this.rect,
    required this.label,
    required this.isSelected,
  });
}

class _ChildSlotOverlay {
  final String childKey;
  final ChildSlot slot;

  const _ChildSlotOverlay({required this.childKey, required this.slot});
}

class _InteractiveParkingGridPreview extends StatelessWidget {
  final ParkingGridModel grid;

  final GridRect? viewport;

  final double maxExtent;

  final bool showLegend;
  final bool showWalls;
  final bool showGates;
  final bool showTowers;
  final bool showWallNames;

  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;
  final List<ChildRegionOverlay> childRegions;

  final bool showChildSlotOverlay;
  final List<_ChildSlotOverlay> childSlotOverlays;
  final Map<String, Map<int, _BlockedSlotKind>> blockedSlotsByChildKey;
  final String? recommendedChildKey;
  final int? recommendedSlotNo;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;

  final ValueChanged<String>? onTapChildRegion;
  final ValueChanged<ChildSlot>? onTapChildSlot;
  final ValueChanged<GridRect>? onTapTowerRect;

  final Widget? legendBottom;
  final Map<int, _BlockedSlotKind> blockedSlotsByNo;

  const _InteractiveParkingGridPreview({
    required this.grid,
    this.viewport,
    this.maxExtent = 280,
    this.showLegend = true,
    this.showWalls = true,
    this.showGates = true,
    this.showTowers = true,
    this.showWallNames = true,
    this.showParkingAreas = true,
    this.showParkingAreaLabels = true,
    this.showChildRegions = true,
    this.showChildRegionLabels = true,
    this.showAllChildRegionLabels = false,
    this.childRegions = const <ChildRegionOverlay>[],
    this.showChildSlotOverlay = false,
    this.childSlotOverlays = const <_ChildSlotOverlay>[],
    this.blockedSlotsByChildKey = const <String, Map<int, _BlockedSlotKind>>{},
    this.recommendedChildKey,
    this.recommendedSlotNo,
    this.showChildSlotNumbers = true,
    this.childSlotsToLabel = const <ChildSlot>[],
    this.onTapChildRegion,
    this.onTapChildSlot,
    this.onTapTowerRect,
    this.legendBottom,
    this.blockedSlotsByNo = const <int, _BlockedSlotKind>{},
  });

  GridRect _effectiveViewport() {
    final rows = grid.rows;
    final cols = grid.cols;
    if (rows <= 0 || cols <= 0) {
      return GridRect(r0: 0, r1: 0, c0: 0, c1: 0).normalized();
    }

    final full = GridRect(r0: 0, r1: rows - 1, c0: 0, c1: cols - 1);
    final v = (viewport == null) ? full : viewport!.normalized();

    int clampR(int r) => r.clamp(0, rows - 1);
    int clampC(int c) => c.clamp(0, cols - 1);

    final r0 = clampR(math.min(v.r0, v.r1));
    final r1 = clampR(math.max(v.r0, v.r1));
    final c0 = clampC(math.min(v.c0, v.c1));
    final c1 = clampC(math.max(v.c0, v.c1));

    return GridRect(r0: r0, r1: r1, c0: c0, c1: c1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color cellColor(ParkingGridCellType t) {
      switch (t) {
        case ParkingGridCellType.road:
          return cs.surfaceVariant.withOpacity(0.95);
        case ParkingGridCellType.pillar:
          return cs.errorContainer.withOpacity(0.75);
        case ParkingGridCellType.empty:
          return cs.primaryContainer.withOpacity(0.55);
      }
    }

    Widget legendDot(Color c, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    const road1Stripe = Color(0xFFFFA000);
    const road2Stripe = Color(0xFFFFFFFF);

    Widget markBox({
      required Color bg,
      required Widget child,
    }) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
        ),
        child: child,
      );
    }

    Widget legendMark(Widget mark, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget roadMark(bool isRoad2) {
      final stripe = (isRoad2 ? road2Stripe : road1Stripe).withOpacity(0.92);

      return markBox(
        bg: cellColor(ParkingGridCellType.road),
        child: Center(
          child: Container(
            width: 2.2,
            height: 8.0,
            decoration: BoxDecoration(
              color: stripe,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }

    Widget gateMark(bool isEntrance) {
      final accent =
          isEntrance ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
      final icon = isEntrance ? Icons.login_rounded : Icons.logout_rounded;

      return markBox(
        bg: cs.surface,
        child: Icon(icon, size: 12, color: accent.withOpacity(0.95)),
      );
    }

    Widget towerMark() {
      final accent = cs.tertiary;
      return markBox(
        bg: cs.surface,
        child: Icon(Icons.apartment_rounded,
            size: 12, color: accent.withOpacity(0.95)),
      );
    }

    Widget pill(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final v = _effectiveViewport();
    final viewRows = (v.r1 - v.r0 + 1).clamp(1, grid.rows);
    final viewCols = (v.c1 - v.c0 + 1).clamp(1, grid.cols);

    final ratio = (viewRows > 0) ? (viewCols / viewRows) : 1.0;

    final wallCount = grid.walls.length;
    final groupCount = grid.wallGroups.length;
    final hasGateRects =
        grid.entranceRects.isNotEmpty || grid.exitRects.isNotEmpty;
    final gateCount = hasGateRects
        ? (grid.entranceRects.length + grid.exitRects.length)
        : ((grid.entranceGate != null ? 1 : 0) +
            (grid.exitGate != null ? 1 : 0));
    final towerCount = grid.towerRects.length;

    void handleTap(Size size, Offset p) {
      if (grid.rows <= 0 || grid.cols <= 0) return;

      final layout = _GridLayout.fit(
        size: size,
        rows: viewRows,
        cols: viewCols,
        padding: 10,
        gap: 2,
      );

      if (!layout.gridRect().contains(p)) return;

      if (onTapChildSlot != null && childSlotsToLabel.isNotEmpty) {
        for (final s in childSlotsToLabel) {
          if (_slotOverlapsGridRects(s, grid.towerRects)) continue;
          final topG = math.min(s.r0, s.r1);
          final bottomG = math.max(s.r0, s.r1);
          final leftG = math.min(s.c0, s.c1);
          final rightG = math.max(s.c0, s.c1);

          final interTop = math.max(topG, v.r0);
          final interBottom = math.min(bottomG, v.r1);
          final interLeft = math.max(leftG, v.c0);
          final interRight = math.min(rightG, v.c1);
          if (interTop > interBottom || interLeft > interRight) continue;

          final top = interTop - v.r0;
          final bottom = interBottom - v.r0;
          final left = interLeft - v.c0;
          final right = interRight - v.c0;

          final rect =
              layout.rectForCellRange(r0: top, r1: bottom, c0: left, c1: right);
          if (rect.contains(p)) {
            if (blockedSlotsByNo.containsKey(s.no)) return;
            onTapChildSlot!(s);
            return;
          }
        }
      }

      if (onTapTowerRect != null && showTowers && grid.towerRects.isNotEmpty) {
        for (final tr in grid.towerRects) {
          final rrG = tr.normalized();

          final interTop = math.max(rrG.r0, v.r0);
          final interBottom = math.min(rrG.r1, v.r1);
          final interLeft = math.max(rrG.c0, v.c0);
          final interRight = math.min(rrG.c1, v.c1);
          if (interTop > interBottom || interLeft > interRight) continue;

          final top = interTop - v.r0;
          final bottom = interBottom - v.r0;
          final left = interLeft - v.c0;
          final right = interRight - v.c0;

          final rect =
              layout.rectForCellRange(r0: top, r1: bottom, c0: left, c1: right);
          if (rect.contains(p)) {
            onTapTowerRect!(rrG);
            return;
          }
        }
      }

      if (onTapChildRegion != null && childRegions.isNotEmpty) {
        for (final ov in childRegions) {
          final rrG = ov.rect.normalized();

          final interTop = math.max(rrG.r0, v.r0);
          final interBottom = math.min(rrG.r1, v.r1);
          final interLeft = math.max(rrG.c0, v.c0);
          final interRight = math.min(rrG.c1, v.c1);
          if (interTop > interBottom || interLeft > interRight) continue;

          final top = interTop - v.r0;
          final bottom = interBottom - v.r0;
          final left = interLeft - v.c0;
          final right = interRight - v.c0;

          final rect =
              layout.rectForCellRange(r0: top, r1: bottom, c0: left, c1: right);
          if (rect.contains(p)) {
            onTapChildRegion!(ov.label);
            return;
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxExtent,
            maxHeight: maxExtent,
          ),
          child: AspectRatio(
            aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => handleTap(size, d.localPosition),
                    child: CustomPaint(
                      painter: _ParkingGridPainter(
                        grid: grid,
                        viewport: v,
                        colorScheme: cs,
                        showWalls: showWalls,
                        showGates: showGates,
                        showTowers: true,
                        showWallNames: showWallNames,
                        showParkingAreas: showParkingAreas,
                        showParkingAreaLabels: showParkingAreaLabels,
                        showChildRegions: showChildRegions,
                        childRegions: childRegions,
                        showChildRegionLabels: showChildRegionLabels,
                        showAllChildRegionLabels: showAllChildRegionLabels,
                        showChildSlotOverlay: showChildSlotOverlay,
                        childSlotOverlays: childSlotOverlays,
                        blockedSlotsByChildKey: blockedSlotsByChildKey,
                        recommendedChildKey: recommendedChildKey,
                        recommendedSlotNo: recommendedSlotNo,
                        showChildSlotNumbers: showChildSlotNumbers,
                        childSlotsToLabel: childSlotsToLabel,
                        blockedSlotsByNo: blockedSlotsByNo,
                        paddingPx: 10,
                        gapPx: 2,
                        fixedCellPx: null,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              legendDot(cellColor(ParkingGridCellType.empty), '빈칸'),
              legendMark(roadMark(false), '도로1'),
              legendMark(roadMark(true), '도로2'),
              legendDot(cellColor(ParkingGridCellType.pillar), '기둥'),
              legendMark(gateMark(true), '입구'),
              legendMark(gateMark(false), '출구'),
              if (showTowers && towerCount > 0)
                legendMark(towerMark(), '주차 타워'),
              pill('${viewRows}×${viewCols}'),
              if (showWalls && wallCount > 0) pill('벽 $wallCount'),
              if (showGates && gateCount > 0) pill('게이트 $gateCount'),
              if (showTowers && towerCount > 0) pill('타워 $towerCount'),
              if (showWalls && groupCount > 0) pill('그룹 $groupCount'),
              if (showChildRegions && childRegions.isNotEmpty)
                pill('자식영역 ${childRegions.length}'),
              if (showChildSlotNumbers && childSlotsToLabel.isNotEmpty)
                pill('슬롯번호 ${childSlotsToLabel.length}'),
            ],
          ),
          if (legendBottom != null) ...[
            const SizedBox(height: 10),
            legendBottom!,
          ],
        ],
      ],
    );
  }
}

class _FixedCellPanGridPreview extends StatelessWidget {
  final ParkingGridModel grid;
  final GridRect viewport;

  final double boxExtent;
  final double targetCellPx;
  final double paddingPx;
  final double gapPx;

  final bool showLegend;
  final bool showWalls;
  final bool showGates;
  final bool showWallNames;

  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;

  final ValueChanged<ChildSlot>? onTapChildSlot;
  final Map<int, _BlockedSlotKind> blockedSlotsByNo;
  final int? recommendedSlotNo;

  const _FixedCellPanGridPreview({
    required this.grid,
    required this.viewport,
    required this.boxExtent,
    required this.targetCellPx,
    this.paddingPx = 10,
    this.gapPx = 2,
    this.showLegend = true,
    this.showWalls = true,
    this.showGates = true,
    this.showWallNames = true,
    this.showParkingAreas = true,
    this.showParkingAreaLabels = true,
    this.showChildSlotNumbers = true,
    this.childSlotsToLabel = const <ChildSlot>[],
    this.onTapChildSlot,
    this.blockedSlotsByNo = const <int, _BlockedSlotKind>{},
    this.recommendedSlotNo,
  });

  double _resolveAdaptiveCellPx({
    required double box,
    required int rows,
    required int cols,
  }) {
    final usable = math.max(40.0, box - 2 * paddingPx);
    final gapCols = gapPx * math.max(0, cols - 1);
    final gapRows = gapPx * math.max(0, rows - 1);
    final fitCellW = (usable - gapCols) / cols;
    final fitCellH = (usable - gapRows) / rows;
    final fitCell = math.max(6.0, math.min(fitCellW, fitCellH));
    return math.min(targetCellPx, fitCell).clamp(14.0, targetCellPx);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color cellColor(ParkingGridCellType t) {
      switch (t) {
        case ParkingGridCellType.road:
          return cs.surfaceVariant.withOpacity(0.95);
        case ParkingGridCellType.pillar:
          return cs.errorContainer.withOpacity(0.75);
        case ParkingGridCellType.empty:
          return cs.primaryContainer.withOpacity(0.55);
      }
    }

    Widget legendDot(Color c, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    const road1Stripe = Color(0xFFFFA000);
    const road2Stripe = Color(0xFFFFFFFF);

    Widget markBox({
      required Color bg,
      required Widget child,
    }) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
        ),
        child: child,
      );
    }

    Widget legendMark(Widget mark, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget roadMark(bool isRoad2) {
      final stripe = (isRoad2 ? road2Stripe : road1Stripe).withOpacity(0.92);

      return markBox(
        bg: cellColor(ParkingGridCellType.road),
        child: Center(
          child: Container(
            width: 2.2,
            height: 8.0,
            decoration: BoxDecoration(
              color: stripe,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }

    Widget gateMark(bool isEntrance) {
      final accent =
          isEntrance ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

      final icon = isEntrance ? Icons.login_rounded : Icons.logout_rounded;

      return markBox(
        bg: cs.surface,
        child: Icon(icon, size: 12, color: accent.withOpacity(0.95)),
      );
    }

    Widget towerMark() {
      final accent = cs.tertiary;
      return markBox(
        bg: cs.surface,
        child: Icon(Icons.apartment_rounded,
            size: 12, color: accent.withOpacity(0.95)),
      );
    }

    Widget pill(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final v = viewport.normalized();
    final viewRows = (v.r1 - v.r0 + 1).clamp(1, grid.rows);
    final viewCols = (v.c1 - v.c0 + 1).clamp(1, grid.cols);

    final wallCount = grid.walls.length;
    final groupCount = grid.wallGroups.length;
    final hasGateRects =
        grid.entranceRects.isNotEmpty || grid.exitRects.isNotEmpty;
    final gateCount = hasGateRects
        ? (grid.entranceRects.length + grid.exitRects.length)
        : ((grid.entranceGate != null ? 1 : 0) +
            (grid.exitGate != null ? 1 : 0));
    final towerCount = grid.towerRects.length;

    final box = boxExtent;
    final adaptiveCellPx =
        _resolveAdaptiveCellPx(box: box, rows: viewRows, cols: viewCols);
    final denseLayout = adaptiveCellPx < 22.0;

    void handleTap(Offset p) {
      if (onTapChildSlot == null || childSlotsToLabel.isEmpty) return;

      final layout = _GridLayout.fixed(
        size: Size(box, box),
        rows: viewRows,
        cols: viewCols,
        cell: adaptiveCellPx,
        padding: paddingPx,
        gap: gapPx,
      );

      if (!layout.gridRect().contains(p)) return;

      for (final s in childSlotsToLabel) {
        if (_slotOverlapsGridRects(s, grid.towerRects)) continue;
        final topG = math.min(s.r0, s.r1);
        final bottomG = math.max(s.r0, s.r1);
        final leftG = math.min(s.c0, s.c1);
        final rightG = math.max(s.c0, s.c1);

        final interTop = math.max(topG, v.r0);
        final interBottom = math.min(bottomG, v.r1);
        final interLeft = math.max(leftG, v.c0);
        final interRight = math.min(rightG, v.c1);
        if (interTop > interBottom || interLeft > interRight) continue;

        final top = interTop - v.r0;
        final bottom = interBottom - v.r0;
        final left = interLeft - v.c0;
        final right = interRight - v.c0;

        final rect =
            layout.rectForCellRange(r0: top, r1: bottom, c0: left, c1: right);
        if (rect.contains(p)) {
          if (blockedSlotsByNo.containsKey(s.no)) return;
          onTapChildSlot!(s);
          return;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox.square(
          dimension: box,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => handleTap(d.localPosition),
              child: CustomPaint(
                painter: _ParkingGridPainter(
                  grid: grid,
                  viewport: v,
                  colorScheme: cs,
                  showWalls: showWalls,
                  showGates: showGates,
                  showTowers: true,
                  showWallNames: showWallNames && !denseLayout,
                  showParkingAreas: showParkingAreas,
                  showParkingAreaLabels: showParkingAreaLabels && !denseLayout,
                  showChildRegions: false,
                  childRegions: const <ChildRegionOverlay>[],
                  showChildRegionLabels: false,
                  showAllChildRegionLabels: false,
                  showChildSlotOverlay: false,
                  childSlotOverlays: const <_ChildSlotOverlay>[],
                  blockedSlotsByChildKey: const <String,
                      Map<int, _BlockedSlotKind>>{},
                  recommendedChildKey: null,
                  showChildSlotNumbers: showChildSlotNumbers,
                  childSlotsToLabel: childSlotsToLabel,
                  blockedSlotsByNo: blockedSlotsByNo,
                  recommendedSlotNo: recommendedSlotNo,
                  paddingPx: paddingPx,
                  gapPx: gapPx,
                  fixedCellPx: adaptiveCellPx,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              legendDot(cellColor(ParkingGridCellType.empty), '빈칸'),
              legendMark(roadMark(false), '도로1'),
              legendMark(roadMark(true), '도로2'),
              legendDot(cellColor(ParkingGridCellType.pillar), '기둥'),
              legendMark(gateMark(true), '입구'),
              legendMark(gateMark(false), '출구'),
              if (towerCount > 0) legendMark(towerMark(), '주차 타워'),
              pill('${viewRows}×${viewCols}'),
              pill(
                  '셀 ${adaptiveCellPx.toStringAsFixed(adaptiveCellPx >= 10 ? 0 : 1)}'),
              if (showWalls && wallCount > 0) pill('벽 $wallCount'),
              if (showGates && gateCount > 0) pill('게이트 $gateCount'),
              if (towerCount > 0) pill('타워 $towerCount'),
              if (showWalls && groupCount > 0) pill('그룹 $groupCount'),
              if (showChildSlotNumbers && childSlotsToLabel.isNotEmpty)
                pill('슬롯번호 ${childSlotsToLabel.length}'),
            ],
          ),
        ],
      ],
    );
  }
}

@immutable
class _GridLayout {
  final int rows;
  final int cols;
  final double gap;
  final double cell;
  final Offset origin;

  const _GridLayout({
    required this.rows,
    required this.cols,
    required this.gap,
    required this.cell,
    required this.origin,
  });

  factory _GridLayout.fit({
    required Size size,
    required int rows,
    required int cols,
    double padding = 10,
    double gap = 2,
  }) {
    final usableW = math.max(40.0, size.width - 2 * padding);
    final usableH = math.max(40.0, size.height - 2 * padding);

    final cellW = (usableW - gap * (cols - 1)) / cols;
    final cellH = (usableH - gap * (rows - 1)) / rows;
    final cell = math.min(cellW, cellH).clamp(6.0, 120.0);

    final gridW = cell * cols + gap * (cols - 1);
    final gridH = cell * rows + gap * (rows - 1);

    final ox = (size.width - gridW) / 2;
    final oy = (size.height - gridH) / 2;

    return _GridLayout(
      rows: rows,
      cols: cols,
      gap: gap,
      cell: cell,
      origin: Offset(ox, oy),
    );
  }

  factory _GridLayout.fixed({
    required Size size,
    required int rows,
    required int cols,
    required double cell,
    double padding = 10,
    double gap = 2,
  }) {
    final gridW = cell * cols + gap * (cols - 1);
    final gridH = cell * rows + gap * (rows - 1);

    final ox = (size.width - gridW) / 2;
    final oy = (size.height - gridH) / 2;

    return _GridLayout(
      rows: rows,
      cols: cols,
      gap: gap,
      cell: cell,
      origin: Offset(ox, oy),
    );
  }

  Rect cellRect(int r, int c) {
    final dx = origin.dx + c * (cell + gap);
    final dy = origin.dy + r * (cell + gap);
    return Rect.fromLTWH(dx, dy, cell, cell);
  }

  Rect gridRect() {
    final w = cell * cols + gap * (cols - 1);
    final h = cell * rows + gap * (rows - 1);
    return Rect.fromLTWH(origin.dx, origin.dy, w, h);
  }

  Rect rectForCellRange({
    required int r0,
    required int r1,
    required int c0,
    required int c1,
  }) {
    final rr0 = math.min(r0, r1);
    final rr1 = math.max(r0, r1);
    final cc0 = math.min(c0, c1);
    final cc1 = math.max(c0, c1);

    final left = origin.dx + cc0 * (cell + gap);
    final top = origin.dy + rr0 * (cell + gap);

    final spanCols = (cc1 - cc0 + 1);
    final spanRows = (rr1 - rr0 + 1);

    final width = spanCols * cell + (spanCols - 1) * gap;
    final height = spanRows * cell + (spanRows - 1) * gap;

    return Rect.fromLTWH(left, top, width, height);
  }
}

enum _GateKind { entrance, exit, mixed }

class _ParkingGridPainter extends CustomPainter {
  final ParkingGridModel grid;

  final GridRect viewport;

  final ColorScheme colorScheme;

  ColorScheme get cs => colorScheme;
  final bool showWalls;
  final bool showGates;
  final bool showTowers;
  final bool showWallNames;

  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final List<ChildRegionOverlay> childRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;

  final bool showChildSlotOverlay;
  final List<_ChildSlotOverlay> childSlotOverlays;
  final Map<String, Map<int, _BlockedSlotKind>> blockedSlotsByChildKey;
  final String? recommendedChildKey;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;
  final Map<int, _BlockedSlotKind> blockedSlotsByNo;
  final int? recommendedSlotNo;

  final double paddingPx;
  final double gapPx;

  final double? fixedCellPx;

  _ParkingGridPainter({
    required this.grid,
    required this.viewport,
    required this.colorScheme,
    required this.showWalls,
    required this.showGates,
    required this.showTowers,
    required this.showWallNames,
    required this.showParkingAreas,
    required this.showParkingAreaLabels,
    required this.showChildRegions,
    required this.childRegions,
    required this.showChildRegionLabels,
    required this.showAllChildRegionLabels,
    required this.showChildSlotOverlay,
    required this.childSlotOverlays,
    required this.blockedSlotsByChildKey,
    required this.recommendedChildKey,
    required this.showChildSlotNumbers,
    required this.childSlotsToLabel,
    required this.blockedSlotsByNo,
    required this.recommendedSlotNo,
    required this.paddingPx,
    required this.gapPx,
    required this.fixedCellPx,
  });

  int get _viewRows => (viewport.r1 - viewport.r0 + 1).clamp(1, grid.rows);

  int get _viewCols => (viewport.c1 - viewport.c0 + 1).clamp(1, grid.cols);

  bool _inViewportCell(int rG, int cG) =>
      rG >= viewport.r0 &&
      rG <= viewport.r1 &&
      cG >= viewport.c0 &&
      cG <= viewport.c1;

  ParkingGridCellType _cellTypeAtGlobal(int rG, int cG) {
    final rows = grid.rows;
    final cols = grid.cols;
    if (rG < 0 || cG < 0 || rG >= rows || cG >= cols) {
      return ParkingGridCellType.empty;
    }

    final idx = rG * cols + cG;
    if (idx < 0 || idx >= grid.cells.length) return ParkingGridCellType.empty;
    return grid.cells[idx];
  }

  Color _cellColor(ParkingGridCellType t) {
    switch (t) {
      case ParkingGridCellType.road:
        return cs.surfaceVariant.withOpacity(0.95);
      case ParkingGridCellType.pillar:
        return cs.errorContainer.withOpacity(0.75);
      case ParkingGridCellType.empty:
        return cs.primaryContainer.withOpacity(0.55);
    }
  }

  _GateKind _gateKindFor(EdgePlacement g) {
    final e = grid.entranceGate;
    final x = grid.exitGate;
    final isE = (e != null && e == g);
    final isX = (x != null && x == g);
    if (isE && isX) return _GateKind.mixed;
    if (isE) return _GateKind.entrance;
    return _GateKind.exit;
  }

  Color _gateAccent(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return const Color(0xFF2E7D32);
      case _GateKind.exit:
        return const Color(0xFFC62828);
      case _GateKind.mixed:
        return const Color(0xFFFFA000);
    }
  }

  IconData _gateIcon(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return Icons.login_rounded;
      case _GateKind.exit:
        return Icons.logout_rounded;
      case _GateKind.mixed:
        return Icons.swap_horiz_rounded;
    }
  }

  EdgePlacement? _shiftEdgeToLocalIfVisible(EdgePlacement g) {
    if (!_inViewportCell(g.r, g.c)) return null;
    return EdgePlacement(
        r: g.r - viewport.r0, c: g.c - viewport.c0, side: g.side);
  }

  void _drawGate(Canvas canvas, _GridLayout layout, EdgePlacement localEdge,
      _GateKind kind) {
    final rect = layout.cellRect(localEdge.r, localEdge.c);
    final cell = layout.cell;

    Offset edgeCenter;
    Offset outward;
    switch (localEdge.side) {
      case EdgeSide.north:
        edgeCenter = Offset(rect.center.dx, rect.top);
        outward = const Offset(0, -1);
        break;
      case EdgeSide.south:
        edgeCenter = Offset(rect.center.dx, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case EdgeSide.west:
        edgeCenter = Offset(rect.left, rect.center.dy);
        outward = const Offset(-1, 0);
        break;
      case EdgeSide.east:
        edgeCenter = Offset(rect.right, rect.center.dy);
        outward = const Offset(1, 0);
        break;
    }

    final accent = _gateAccent(kind);
    final th = math.max(5.0, cell * 0.12);
    final len = cell * 0.78;
    final out = math.max(4.0, cell * 0.10);

    Rect barRect;
    if (localEdge.side == EdgeSide.north || localEdge.side == EdgeSide.south) {
      barRect = Rect.fromCenter(
        center: edgeCenter + outward * out,
        width: len,
        height: th,
      );
    } else {
      barRect = Rect.fromCenter(
        center: edgeCenter + outward * out,
        width: th,
        height: len,
      );
    }

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surface.withOpacity(0.96);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, th * 0.12)
      ..color = accent.withOpacity(0.95);

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(th * 0.45)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(th * 0.45)),
      stroke,
    );

    final icon = _gateIcon(kind);
    final iconSize = math.max(10.0, cell * 0.26);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: iconSize,
          fontWeight: FontWeight.w900,
          color: accent.withOpacity(0.96),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset(
          barRect.center.dx - tp.width / 2, barRect.center.dy - tp.height / 2),
    );
  }

  void _drawWall(Canvas canvas, _GridLayout layout, EdgePlacement localEdge,
      {required bool named}) {
    final rect = layout.cellRect(localEdge.r, localEdge.c);
    final cell = layout.cell;

    final th = math.max(2.6, cell * 0.11);
    final out = math.max(3.5, cell * 0.10);

    Offset a;
    Offset b;
    Offset outward;

    switch (localEdge.side) {
      case EdgeSide.north:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.right, rect.top);
        outward = const Offset(0, -1);
        break;
      case EdgeSide.south:
        a = Offset(rect.left, rect.bottom);
        b = Offset(rect.right, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case EdgeSide.west:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.left, rect.bottom);
        outward = const Offset(-1, 0);
        break;
      case EdgeSide.east:
        a = Offset(rect.right, rect.top);
        b = Offset(rect.right, rect.bottom);
        outward = const Offset(1, 0);
        break;
    }

    a = a + outward * out;
    b = b + outward * out;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = th
      ..color = cs.onSurface.withOpacity(0.35);

    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = th + 1.0
      ..color = named
          ? cs.primary.withOpacity(0.90)
          : cs.outlineVariant.withOpacity(0.80);

    canvas.drawLine(a, b, base);
    canvas.drawLine(a, b, hi);
  }

  void _drawWallName(
      Canvas canvas, _GridLayout layout, EdgePlacement localEdge, String name) {
    final rect = layout.cellRect(localEdge.r, localEdge.c);
    final cell = layout.cell;

    Offset pos;
    switch (localEdge.side) {
      case EdgeSide.north:
        pos = Offset(rect.center.dx, rect.top - math.max(18.0, cell * 0.28));
        break;
      case EdgeSide.south:
        pos = Offset(rect.center.dx, rect.bottom + math.max(6.0, cell * 0.12));
        break;
      case EdgeSide.west:
        pos =
            Offset(rect.left - math.max(60.0, cell * 0.80), rect.center.dy - 8);
        break;
      case EdgeSide.east:
        pos =
            Offset(rect.right + math.max(6.0, cell * 0.12), rect.center.dy - 8);
        break;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: math.max(10.0, cell * 0.18),
          fontWeight: FontWeight.w900,
          color: cs.onSurface.withOpacity(0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);

    tp.paint(canvas, pos);
  }

  Rect? _rectForGlobalRangeToLocal(
      _GridLayout layout, int r0, int r1, int c0, int c1) {
    final topG = math.min(r0, r1);
    final bottomG = math.max(r0, r1);
    final leftG = math.min(c0, c1);
    final rightG = math.max(c0, c1);

    final interTop = math.max(topG, viewport.r0);
    final interBottom = math.min(bottomG, viewport.r1);
    final interLeft = math.max(leftG, viewport.c0);
    final interRight = math.min(rightG, viewport.c1);
    if (interTop > interBottom || interLeft > interRight) return null;

    final top = interTop - viewport.r0;
    final bottom = interBottom - viewport.r0;
    final left = interLeft - viewport.c0;
    final right = interRight - viewport.c0;

    if (top < 0 || left < 0 || bottom >= layout.rows || right >= layout.cols) {
      return null;
    }
    return layout.rectForCellRange(r0: top, r1: bottom, c0: left, c1: right);
  }

  ({Color fill, Color stroke, Color text}) _parkingAreaStyle(ParkingAreaKind kind) {
    switch (kind.categoryKey) {
      case 'compact':
        return (
          fill: const Color(0xFF64B5F6).withOpacity(0.58),
          stroke: const Color(0xFF1565C0).withOpacity(0.92),
          text: const Color(0xFF0D47A1),
        );
      case 'standard':
        return (
          fill: cs.secondaryContainer.withOpacity(0.52),
          stroke: cs.secondary.withOpacity(0.92),
          text: cs.onSecondaryContainer,
        );
      case 'extendedA':
      case 'extendedB':
        return (
          fill: const Color(0xFFFFD54F).withOpacity(0.62),
          stroke: const Color(0xFFF9A825).withOpacity(0.92),
          text: const Color(0xFF5D4037),
        );
      case 'evCompact':
      case 'evStandard':
      case 'evExtendedA':
      case 'evExtendedB':
        return (
          fill: const Color(0xFFA5D6A7).withOpacity(0.62),
          stroke: const Color(0xFF2E7D32).withOpacity(0.92),
          text: const Color(0xFF1B5E20),
        );
      case 'pregnantExtendedA':
      case 'pregnantExtendedB':
        return (
          fill: const Color(0xFFF8BBD0).withOpacity(0.62),
          stroke: const Color(0xFFC2185B).withOpacity(0.92),
          text: const Color(0xFF880E4F),
        );
      case 'disabledStandard':
      case 'disabledExtendedA':
      case 'disabledExtendedB':
        return (
          fill: const Color(0xFFB39DDB).withOpacity(0.62),
          stroke: const Color(0xFF512DA8).withOpacity(0.92),
          text: const Color(0xFF311B92),
        );
      default:
        return (
          fill: cs.secondaryContainer.withOpacity(0.42),
          stroke: cs.secondary.withOpacity(0.90),
          text: cs.onSecondaryContainer.withOpacity(0.90),
        );
    }
  }

  void _drawParkingArea(Canvas canvas, _GridLayout layout, ParkingArea a,
      {required bool drawLabel}) {
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, a.r0, a.r1, a.c0, a.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.10));
    final style = _parkingAreaStyle(a.kind);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = style.fill;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, layout.cell * 0.07)
      ..color = style.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
      stroke,
    );

    if (!drawLabel) return;
    if (rect.width < 14 || rect.height < 14) return;

    final tp = TextPainter(
      text: TextSpan(
        text: a.kind.shortLabel,
        style: TextStyle(
          fontSize: math.max(7.0, math.min(layout.cell * 0.38, 13.0)),
          fontWeight: FontWeight.w900,
          color: style.text,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      textAlign: TextAlign.center,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0.0, rect.width - 4));

    tp.paint(canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  void _drawChildRegion(
      Canvas canvas, _GridLayout layout, ChildRegionOverlay ov) {
    final rrG = ov.rect.normalized();

    final rectLocal =
        _rectForGlobalRangeToLocal(layout, rrG.r0, rrG.r1, rrG.c0, rrG.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.06));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = (ov.isSelected
          ? cs.tertiaryContainer.withOpacity(0.22)
          : cs.surfaceVariant.withOpacity(0.10));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ov.isSelected
          ? math.max(2.2, layout.cell * 0.10)
          : math.max(1.4, layout.cell * 0.07)
      ..color = (ov.isSelected
          ? cs.tertiary.withOpacity(0.95)
          : cs.outlineVariant.withOpacity(0.85));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect, Radius.circular(math.max(6.0, layout.cell * 0.22))),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect, Radius.circular(math.max(6.0, layout.cell * 0.22))),
      stroke,
    );

    final shouldLabel =
        showChildRegionLabels && (showAllChildRegionLabels || ov.isSelected);
    if (!shouldLabel) return;
    if (rect.width < 24 || rect.height < 18) return;

    final tp = TextPainter(
      text: TextSpan(
        text: ov.label,
        style: TextStyle(
          fontSize: math.max(11.0, math.min(layout.cell * 0.65, 18.0)),
          fontWeight: FontWeight.w900,
          color: ov.isSelected
              ? cs.onTertiaryContainer.withOpacity(0.95)
              : cs.onSurface.withOpacity(0.80),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 6);

    tp.paint(canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  void _drawRecommendedChildSlot(
      Canvas canvas, _GridLayout layout, ChildSlot s) {
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, s.r0, s.r1, s.c0, s.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.12));
    if (rect.width < 10 || rect.height < 10) return;

    final rr = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.max(6.0, layout.cell * 0.22)),
    );

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.primary.withOpacity(0.20);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.4, layout.cell * 0.12)
      ..color = cs.primary.withOpacity(0.98);

    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);

    final badgeSize = math.min(rect.width, rect.height) * 0.42;
    final badge = Rect.fromCenter(
      center: rect.center,
      width: badgeSize.clamp(16.0, 32.0),
      height: badgeSize.clamp(16.0, 32.0),
    );

    final badgeFill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.primary.withOpacity(0.96);
    final badgeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, layout.cell * 0.04)
      ..color = cs.onPrimary.withOpacity(0.80);

    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.50)),
      badgeFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.50)),
      badgeStroke,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '${s.no}',
        style: TextStyle(
          fontSize: math.max(10.5, badge.height * 0.58),
          fontWeight: FontWeight.w900,
          color: cs.onPrimary.withOpacity(0.98),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: badge.width);

    tp.paint(
      canvas,
      Offset(
        badge.center.dx - tp.width / 2,
        badge.center.dy - tp.height / 2,
      ),
    );

    if (rect.width >= 34 && rect.height >= 24) {
      final tag = TextPainter(
        text: TextSpan(
          text: '추천',
          style: TextStyle(
            fontSize: math.max(8.0, layout.cell * 0.22),
            fontWeight: FontWeight.w900,
            color: cs.primary.withOpacity(0.98),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: rect.width);

      tag.paint(
        canvas,
        Offset(
          rect.center.dx - tag.width / 2,
          rect.bottom - tag.height - math.max(2.0, layout.cell * 0.08),
        ),
      );
    }
  }

  void _drawChildSlotNumber(Canvas canvas, _GridLayout layout, ChildSlot s) {
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, s.r0, s.r1, s.c0, s.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.18));
    if (rect.width < 12 || rect.height < 12) return;

    final isRecommended =
        recommendedSlotNo != null && recommendedSlotNo == s.no;

    if (isRecommended) {
      final rr = RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.max(6.0, layout.cell * 0.22)),
      );
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = cs.primary.withOpacity(0.18);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, layout.cell * 0.10)
        ..color = cs.primary.withOpacity(0.95);
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = isRecommended
          ? cs.primary.withOpacity(0.95)
          : cs.surface.withOpacity(0.80);

    final bd = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, layout.cell * 0.06)
      ..color = cs.primary.withOpacity(0.85);

    final badgeSize = math.min(rect.width, rect.height) * 0.55;
    final badge = Rect.fromCenter(
      center: rect.center,
      width: badgeSize.clamp(14.0, 30.0),
      height: badgeSize.clamp(14.0, 30.0),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
      bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
      bd,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '${s.no}',
        style: TextStyle(
          fontSize: math.max(10.5, badge.height * 0.55),
          fontWeight: FontWeight.w900,
          color: isRecommended
              ? cs.onPrimary.withOpacity(0.98)
              : cs.primary.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: badge.width);

    tp.paint(
        canvas,
        Offset(
            badge.center.dx - tp.width / 2, badge.center.dy - tp.height / 2));

    if (isRecommended && rect.width >= 34 && rect.height >= 24) {
      final tag = TextPainter(
        text: TextSpan(
          text: '추천',
          style: TextStyle(
            fontSize: math.max(8.0, layout.cell * 0.22),
            fontWeight: FontWeight.w900,
            color: cs.primary.withOpacity(0.98),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: rect.width);

      tag.paint(
        canvas,
        Offset(
          rect.center.dx - tag.width / 2,
          rect.bottom - tag.height - math.max(2.0, layout.cell * 0.08),
        ),
      );
    }
  }

  void _drawBlockedChildSlot(
      Canvas canvas, _GridLayout layout, ChildSlot s, _BlockedSlotKind kind) {
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, s.r0, s.r1, s.c0, s.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.10));
    if (rect.width < 10 || rect.height < 10) return;

    final base = (kind == _BlockedSlotKind.parked)
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    final rr = RRect.fromRectAndRadius(
        rect, Radius.circular(math.max(6.0, layout.cell * 0.22)));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = base.withOpacity(0.10);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, layout.cell * 0.10)
      ..strokeCap = StrokeCap.round
      ..color = base.withOpacity(0.85);

    canvas.drawRRect(rr, fill);
    canvas.drawLine(rect.topLeft, rect.bottomRight, stroke);
    canvas.drawLine(rect.topRight, rect.bottomLeft, stroke);
  }

  Color _slotAccent(_BlockedSlotKind kind) {
    switch (kind) {
      case _BlockedSlotKind.parked:
        return const Color(0xFF2E7D32);
      case _BlockedSlotKind.departureRequest:
        return const Color(0xFFC62828);
    }
  }

  void _drawChildSlotOverlay(
      Canvas canvas, _GridLayout layout, ChildSlot s, _BlockedSlotKind kind) {
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, s.r0, s.r1, s.c0, s.c1);
    if (rectLocal == null) return;

    final rect = rectLocal.deflate(math.max(1.0, layout.cell * 0.12));
    if (rect.width < 10 || rect.height < 10) return;

    final base = _slotAccent(kind);
    final rr = RRect.fromRectAndRadius(
        rect, Radius.circular(math.max(6.0, layout.cell * 0.22)));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = base.withOpacity(0.18);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, layout.cell * 0.08)
      ..strokeCap = StrokeCap.round
      ..color = base.withOpacity(0.88);

    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);
  }

  void _drawRectOverlayBox(
    Canvas canvas,
    _GridLayout layout,
    GridRect rect, {
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
    IconData? icon,
    Color? iconColor,
  }) {
    final r = rect.normalized();
    final rectLocal =
        _rectForGlobalRangeToLocal(layout, r.r0, r.r1, r.c0, r.c1);
    if (rectLocal == null) return;

    final cell = layout.cell;
    final inset = math.max(1.0, cell * 0.06);
    final rr = RRect.fromRectAndRadius(
        rectLocal.deflate(inset), Radius.circular(math.max(6.0, cell * 0.22)));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = strokeColor;

    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);

    if (icon == null) return;
    if (rr.width < 18 || rr.height < 18) return;

    final size = math.max(10.0, math.min(cell * 0.52, 18.0));
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: (iconColor ?? strokeColor).withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    tp.paint(canvas,
        Offset(rr.center.dx - tp.width / 2, rr.center.dy - tp.height / 2));
  }

  void _drawTowerRects(Canvas canvas, _GridLayout layout) {
    if (!showTowers) return;
    if (grid.towerRects.isEmpty) return;

    final cell = layout.cell;
    final fill = cs.tertiaryContainer.withOpacity(0.18);
    final stroke = cs.tertiary.withOpacity(0.92);
    final strokeW = math.max(1.8, cell * 0.08);

    for (final tr in grid.towerRects) {
      _drawRectOverlayBox(
        canvas,
        layout,
        tr,
        fillColor: fill,
        strokeColor: stroke,
        strokeWidth: strokeW,
        icon: Icons.apartment_rounded,
        iconColor: cs.tertiary,
      );

      final r = tr.normalized();
      final rectLocal =
          _rectForGlobalRangeToLocal(layout, r.r0, r.r1, r.c0, r.c1);
      if (rectLocal == null) continue;

      final inset = math.max(2.0, cell * 0.16);
      final inner = rectLocal.deflate(inset);
      if (inner.width < 10 || inner.height < 10) continue;

      final mark = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, cell * 0.05)
        ..strokeCap = StrokeCap.round
        ..color = cs.tertiary.withOpacity(0.65);

      canvas.drawLine(inner.topLeft, inner.bottomRight, mark);
      canvas.drawLine(inner.topRight, inner.bottomLeft, mark);
    }
  }

  void _drawGateRects(
      Canvas canvas, _GridLayout layout, List<GridRect> rects, _GateKind kind) {
    if (!showGates) return;
    if (rects.isEmpty) return;

    final accent = _gateAccent(kind);
    final fill = accent.withOpacity(0.12);
    final stroke = accent.withOpacity(0.92);
    final strokeW = math.max(1.8, layout.cell * 0.08);
    final icon = _gateIcon(kind);

    for (final gr in rects) {
      _drawRectOverlayBox(
        canvas,
        layout,
        gr,
        fillColor: fill,
        strokeColor: stroke,
        strokeWidth: strokeW,
        icon: icon,
        iconColor: accent,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.rows <= 0 || grid.cols <= 0) return;

    final rowsL = _viewRows;
    final colsL = _viewCols;

    final layout = (fixedCellPx == null)
        ? _GridLayout.fit(
            size: size,
            rows: rowsL,
            cols: colsL,
            padding: paddingPx,
            gap: gapPx)
        : _GridLayout.fixed(
            size: size,
            rows: rowsL,
            cols: colsL,
            cell: fixedCellPx!,
            padding: paddingPx,
            gap: gapPx,
          );

    final gridRect = layout.gridRect();

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surfaceContainerLow.withOpacity(0.85);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = cs.outlineVariant.withOpacity(0.95);

    canvas.drawRRect(
        RRect.fromRectAndRadius(gridRect, const Radius.circular(12)), bg);
    canvas.drawRRect(
        RRect.fromRectAndRadius(gridRect, const Radius.circular(12)), border);

    final cellBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = cs.outlineVariant.withOpacity(0.65);

    final road2Set = grid.road2Cells.toSet();
    const road1Stripe = Color(0xFFFFA000);
    const road2Stripe = Color(0xFFFFFFFF);

    for (int r = 0; r < rowsL; r++) {
      for (int c = 0; c < colsL; c++) {
        final rG = viewport.r0 + r;
        final cG = viewport.c0 + c;

        final t = _cellTypeAtGlobal(rG, cG);
        final rect = layout.cellRect(r, c);

        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = _cellColor(t);

        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, cellBorder);

        if (t == ParkingGridCellType.pillar) {
          final center = rect.center;
          final rad = math.max(3.0, layout.cell * 0.18);
          final pFill = Paint()..color = cs.onSurface.withOpacity(0.18);
          final pStroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.1, layout.cell * 0.035)
            ..color = cs.onSurface.withOpacity(0.52);
          canvas.drawCircle(center, rad, pFill);
          canvas.drawCircle(center, rad, pStroke);
        }

        if (t == ParkingGridCellType.road) {
          final idx = rG * grid.cols + cG;
          final isRoad2 = road2Set.contains(idx);
          final stripeColor =
              (isRoad2 ? road2Stripe : road1Stripe).withOpacity(0.85);

          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.2, layout.cell * 0.045)
            ..color = stripeColor;

          final a = Offset(rect.center.dx, rect.top + rect.height * 0.18);
          final b = Offset(rect.center.dx, rect.bottom - rect.height * 0.18);

          final dash = math.max(4.0, layout.cell * 0.12);
          final gap = math.max(3.0, layout.cell * 0.08);

          double t0 = 0;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len > 1e-6) {
            final ux = dx / len;
            final uy = dy / len;
            while (t0 < len) {
              final t1 = math.min(len, t0 + dash);
              canvas.drawLine(
                Offset(a.dx + ux * t0, a.dy + uy * t0),
                Offset(a.dx + ux * t1, a.dy + uy * t1),
                paint,
              );
              t0 = t1 + gap;
            }
          }
        }
      }

      if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
        for (final a in grid.parkingAreas) {
          _drawParkingArea(canvas, layout, a, drawLabel: false);
        }
      }

      _drawTowerRects(canvas, layout);

      final hasGateRectsForPaint =
          grid.entranceRects.isNotEmpty || grid.exitRects.isNotEmpty;
      if (showGates && hasGateRectsForPaint) {
        _drawGateRects(canvas, layout, grid.entranceRects, _GateKind.entrance);
        _drawGateRects(canvas, layout, grid.exitRects, _GateKind.exit);
      }

      if (showChildRegions && childRegions.isNotEmpty) {
        for (final ov in childRegions) {
          _drawChildRegion(canvas, layout, ov);
        }
      }

      if (showChildSlotOverlay &&
          childSlotOverlays.isNotEmpty &&
          recommendedChildKey != null &&
          recommendedSlotNo != null) {
        for (final ov in childSlotOverlays) {
          if (ov.childKey != recommendedChildKey) continue;
          if (ov.slot.no != recommendedSlotNo) continue;
          if (_slotOverlapsGridRects(ov.slot, grid.towerRects)) continue;
          _drawRecommendedChildSlot(canvas, layout, ov.slot);
          break;
        }
      }

      if (showChildSlotOverlay &&
          childSlotOverlays.isNotEmpty &&
          blockedSlotsByChildKey.isNotEmpty) {
        for (final ov in childSlotOverlays) {
          if (_slotOverlapsGridRects(ov.slot, grid.towerRects)) continue;
          final no = ov.slot.no;
          if (no <= 0) continue;
          final kind = blockedSlotsByChildKey[ov.childKey]?[no];
          if (kind == null) continue;
          _drawChildSlotOverlay(canvas, layout, ov.slot, kind);
        }
      }

      if (showWalls && grid.walls.isNotEmpty) {
        final tmp = <EdgePlacement, WallGroupId?>{};
        for (final e in grid.walls.entries) {
          try {
            final edgeG = EdgePlacement.fromKey(e.key);
            if (!isEdgeValid(edgeG, grid.rows, grid.cols)) continue;

            final local = _shiftEdgeToLocalIfVisible(edgeG);
            if (local == null) continue;

            if (!isEdgeValid(local, _viewRows, _viewCols)) continue;

            tmp[edgeG] = e.value;
            final gid = e.value;
            final named = (gid != null) &&
                (grid.wallGroups[gid]?.trim().isNotEmpty ?? false);
            _drawWall(canvas, layout, local, named: named);
          } catch (_) {}
        }

        if (showWallNames && grid.wallGroups.isNotEmpty && tmp.isNotEmpty) {
          final reps = <WallGroupId, EdgePlacement>{};
          for (final entry in tmp.entries) {
            final gid = entry.value;
            if (gid == null) continue;

            final name = grid.wallGroups[gid]?.trim();
            if (name == null || name.isEmpty) continue;

            if (!reps.containsKey(gid)) {
              reps[gid] = entry.key;
            } else {
              final cur = reps[gid]!;
              if (edgeSortKey(entry.key) < edgeSortKey(cur)) {
                reps[gid] = entry.key;
              }
            }
          }

          for (final rep in reps.entries) {
            final name = grid.wallGroups[rep.key]?.trim() ?? '';
            if (name.isEmpty) continue;

            final local = _shiftEdgeToLocalIfVisible(rep.value);
            if (local == null) continue;
            if (!isEdgeValid(local, _viewRows, _viewCols)) continue;

            _drawWallName(canvas, layout, local, name);
          }
        }
      }

      if (showGates) {
        final hasGateRectsForPaint =
            grid.entranceRects.isNotEmpty || grid.exitRects.isNotEmpty;
        if (!hasGateRectsForPaint) {
          final gateSet = <EdgePlacement>{};
          final entrance = grid.entranceGate;
          final exit = grid.exitGate;

          if (entrance != null && isEdgeValid(entrance, grid.rows, grid.cols)) {
            gateSet.add(entrance);
          }
          if (exit != null && isEdgeValid(exit, grid.rows, grid.cols)) {
            gateSet.add(exit);
          }

          for (final g in gateSet) {
            final local = _shiftEdgeToLocalIfVisible(g);
            if (local == null) continue;
            if (!isEdgeValid(local, _viewRows, _viewCols)) continue;
            _drawGate(canvas, layout, local, _gateKindFor(g));
          }
        }
      }

      if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
        for (final a in grid.parkingAreas) {
          _drawParkingArea(canvas, layout, a, drawLabel: showParkingAreaLabels);
        }
      }

      if (showChildSlotNumbers && childSlotsToLabel.isNotEmpty) {
        if (blockedSlotsByNo.isNotEmpty) {
          for (final s in childSlotsToLabel) {
            if (_slotOverlapsGridRects(s, grid.towerRects)) continue;
            final kind = blockedSlotsByNo[s.no];
            if (kind != null) _drawBlockedChildSlot(canvas, layout, s, kind);
          }
        }
        for (final s in childSlotsToLabel) {
          if (_slotOverlapsGridRects(s, grid.towerRects)) continue;
          _drawChildSlotNumber(canvas, layout, s);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParkingGridPainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.viewport != viewport ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.showWalls != showWalls ||
        oldDelegate.showGates != showGates ||
        oldDelegate.showTowers != showTowers ||
        oldDelegate.showWallNames != showWallNames ||
        oldDelegate.showParkingAreas != showParkingAreas ||
        oldDelegate.showParkingAreaLabels != showParkingAreaLabels ||
        oldDelegate.showChildRegions != showChildRegions ||
        oldDelegate.childRegions != childRegions ||
        oldDelegate.showChildRegionLabels != showChildRegionLabels ||
        oldDelegate.showAllChildRegionLabels != showAllChildRegionLabels ||
        oldDelegate.showChildSlotOverlay != showChildSlotOverlay ||
        oldDelegate.childSlotOverlays != childSlotOverlays ||
        oldDelegate.blockedSlotsByChildKey != blockedSlotsByChildKey ||
        oldDelegate.recommendedChildKey != recommendedChildKey ||
        oldDelegate.showChildSlotNumbers != showChildSlotNumbers ||
        oldDelegate.childSlotsToLabel != childSlotsToLabel ||
        oldDelegate.blockedSlotsByNo != blockedSlotsByNo ||
        oldDelegate.recommendedSlotNo != recommendedSlotNo ||
        oldDelegate.paddingPx != paddingPx ||
        oldDelegate.gapPx != gapPx ||
        oldDelegate.fixedCellPx != fixedCellPx;
  }
}
