import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../utils/snackbar_helper.dart';
import 'location_management_package/location_setting.dart';
import 'location_management_package/location_draft.dart';
import '../../../../states/location/location_state.dart';
import '../../../../states/area/area_state.dart';
import '../../../../models/location_model.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  // ✅ 이름 정규화(상태 레이어와 동일 규칙): trim + 다중 공백 축약 + 소문자 비교
  static String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  // ▼ FAB 위치/간격 조절
  static const double _fabBottomGap = 48.0; // 하단에서 띄우기
  static const double _fabSpacing = 10.0; // 버튼 간 간격

  // 11시 라벨
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: location management',
              child: Text('location management', style: style),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('선택한 주차 구역을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// 추가(보텀시트)
  Future<void> _handleAdd(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final currentArea = context.read<AreaState>().currentArea;

    // ✅ 빠른 UX용(로컬) 중복 체크 기준: 현재 area에 로드된 locationName 집합
    // - 최종 중복/정합성 검증은 LocationState가 Firestore 기준으로 다시 확인
    final existingNameKeysInArea = locationState.locations
        .where((loc) => loc.area == currentArea)
        .map((loc) => _nameKey(loc.locationName))
        .toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        // 전체 높이로 채우기
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            existingNameKeysInArea: existingNameKeysInArea,
            onSave: (draft) async {
              final area = context.read<AreaState>().currentArea;

              if (draft is SingleLocationDraft) {
                String? err;
                final ok = await locationState.addSingleLocation(
                  draft.name,
                  area,
                  capacity: draft.capacity,
                  onError: (e) => err = e,
                );

                if (!mounted) return;
                if (!ok) {
                  showFailedSnackbar(context, err ?? '🚨 주차 구역 추가 실패');
                  return;
                }
                showSuccessSnackbar(context, '✅ 주차 구역이 추가되었습니다.');
              } else if (draft is CompositeLocationDraft) {
                final subs = draft.subs
                    .map<Map<String, dynamic>>(
                      (s) => {'name': s.name, 'capacity': s.capacity},
                )
                    .toList();

                String? err;
                final ok = await locationState.addCompositeLocation(
                  draft.parent,
                  subs,
                  area,
                  onError: (e) => err = e,
                );

                if (!mounted) return;
                if (!ok) {
                  showFailedSnackbar(context, err ?? '🚨 복합 주차 구역 추가 실패');
                  return;
                }
                showSuccessSnackbar(context, '✅ 복합 주차 구역이 추가되었습니다.');
              } else {
                if (!mounted) return;
                showFailedSnackbar(context, '❗ 알 수 없는 주차 구역 유형입니다.');
              }
            },
          ),
        );
      },
    );
  }

  /// 삭제
  Future<void> _handleDelete(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final selectedId = locationState.selectedLocationId;

    if (selectedId == null) {
      showFailedSnackbar(context, '⚠️ 삭제할 항목을 선택하세요.');
      return;
    }

    final confirmed = await _confirmDelete(context);
    if (!confirmed) return;

    String? err;
    final ok = await locationState.deleteLocations(
      [selectedId],
      onError: (e) => err = e,
    );

    if (!mounted) return;
    if (!ok) {
      showFailedSnackbar(context, err ?? '🚨 주차 구역 삭제 실패');
      return;
    }
    showSuccessSnackbar(context, '✅ 삭제되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea;

    // ✅ PageStorageKey 충돌 방지용 prefix
    // - Area별로 스크롤/확장 상태가 섞이지 않게 currentArea를 prefix에 포함
    // - toString()이 안정적이지 않다면 (ex. 인스턴스 주소) area id/name 같은 고유값으로 바꾸는 걸 권장
    final storageKeyPrefix = 'location_management_${currentArea.toString()}';

    final allLocations = locationState.locations.where((location) => location.area == currentArea).toList();

    final singles = allLocations.where((loc) => loc.type == 'single').toList();
    final composites = allLocations.where((loc) => loc.type == 'composite').toList();

    final Map<String, List<LocationModel>> grouped = {};
    for (final loc in composites) {
      final parent = loc.parent ?? '기타';
      grouped.putIfAbsent(parent, () => []).add(loc);
    }

    final hasSelection = locationState.selectedLocationId != null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: _buildScreenTag(context), // ◀️ 11시 라벨
        title: Text(
          '주차구역',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
      ),
      body: locationState.isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      )
          : allLocations.isEmpty
          ? const Center(child: Text('현재 지역에 주차 구역이 없습니다.'))
          : Column(
        children: [
          // 필터 칩 영역
          Container(
            width: double.infinity,
            color: cs.surface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FilterChip(
                  label: '전체',
                  selected: _filter == 'all',
                  onSelected: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '단일',
                  selected: _filter == 'single',
                  onSelected: () => setState(() => _filter = 'single'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '복합',
                  selected: _filter == 'composite',
                  onSelected: () => setState(() => _filter = 'composite'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.75)),
          Expanded(
            child: _filter == 'single'
                ? _buildSimpleList(
              singles,
              locationState,
              colorScheme: cs,
              storageKeyPrefix: storageKeyPrefix,
            )
                : _filter == 'composite'
                ? _buildGroupedList(
              grouped,
              locationState,
              colorScheme: cs,
              storageKeyPrefix: storageKeyPrefix,
            )
                : _buildAllListView(
              singles: singles,
              grouped: grouped,
              state: locationState,
              colorScheme: cs,
              storageKeyPrefix: storageKeyPrefix,
            ),
          ),
        ],
      ),

      // ▼ FAB 세트(현대적 알약형 버튼 + 하단 여백으로 위치 조절)
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onAdd: () => _handleAdd(context),
        onDelete: hasSelection ? () => _handleDelete(context) : null,
      ),
    );
  }

  /// ‘전체’ 탭은 하나의 ListView로 합쳐 스크롤러를 1개만 유지(오버플로우/중첩 스크롤 방지)
  Widget _buildAllListView({
    required List<LocationModel> singles,
    required Map<String, List<LocationModel>> grouped,
    required LocationState state,
    required ColorScheme colorScheme,
    required String storageKeyPrefix,
  }) {
    final cs = colorScheme;
    final tiles = <Widget>[];

    if (singles.isNotEmpty) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '단일 주차 구역',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
      );
      tiles.addAll(_buildSimpleTiles(singles, state, cs));
    }

    if (singles.isNotEmpty && grouped.isNotEmpty) {
      tiles.add(Divider(color: cs.outlineVariant.withOpacity(.55)));
    }

    if (grouped.isNotEmpty) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '복합 주차 구역',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
      );
      tiles.addAll(_buildGroupedTiles(grouped, state, cs, storageKeyPrefix));
    }

    // ✅ 핵심 수정 1) ListView에 고유 PageStorageKey 부여
    // - ScrollPosition.restoreScrollOffset()이 읽는 값(double?)이
    //   ExpansionTile의 상태(bool)와 같은 슬롯을 공유하지 않도록 분리
    return ListView(
      key: PageStorageKey<String>('${storageKeyPrefix}_all_list'),
      children: tiles,
    );
  }

  List<Widget> _buildSimpleTiles(
      List<LocationModel> list,
      LocationState state,
      ColorScheme cs,
      ) {
    return List<Widget>.generate(list.length, (index) {
      final loc = list[index];
      final isSelected = state.selectedLocationId == loc.id;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: cs.surface,
        elevation: isSelected ? 3 : 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outlineVariant.withOpacity(.65),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          title: const Text(' ', style: TextStyle(fontSize: 0)),
          subtitle: DefaultTextStyle(
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.locationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (loc.capacity > 0) Text('공간 ${loc.capacity}대'),
              ],
            ),
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
            ),
            child: Icon(
              loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
              color: cs.primary,
              size: 20,
            ),
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: cs.primary)
              : Icon(Icons.chevron_right, color: cs.onSurfaceVariant.withOpacity(.75)),
          selected: isSelected,
          onTap: () => state.toggleLocationSelection(loc.id),
        ),
      );
    });
  }

  List<Widget> _buildGroupedTiles(
      Map<String, List<LocationModel>> grouped,
      LocationState state,
      ColorScheme cs,
      String storageKeyPrefix,
      ) {
    return grouped.entries.map((entry) {
      final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
        ),
        color: cs.surface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            expansionTileTheme: ExpansionTileThemeData(
              iconColor: cs.primary,
              collapsedIconColor: cs.onSurfaceVariant,
              textColor: cs.onSurface,
              collapsedTextColor: cs.onSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          // ✅ 핵심 수정 2) ExpansionTile에도 고유 PageStorageKey 부여
          // - ExpansionTile은 펼침 상태를 PageStorage에 bool로 저장
          // - ListView 스크롤 오프셋(double?) 저장 슬롯과 분리해야 함
          child: ExpansionTile(
            key: PageStorageKey<String>('${storageKeyPrefix}_exp_all_${entry.key}'),
            title: Text(
              '상위 구역: ${entry.key} (공간 $totalCapacity대)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: entry.value.map((loc) {
              final isSelected = state.selectedLocationId == loc.id;

              return ListTile(
                title: Text(
                  loc.locationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                subtitle: loc.capacity > 0
                    ? Text(
                  '공간 ${loc.capacity}대',
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
                    : null,
                leading: Icon(Icons.subdirectory_arrow_right, color: cs.onSurfaceVariant),
                trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
                selected: isSelected,
                onTap: () => state.toggleLocationSelection(loc.id),
              );
            }).toList(),
          ),
        ),
      );
    }).toList();
  }

  /// 단일 탭 전용 리스트
  Widget _buildSimpleList(
      List<LocationModel> list,
      LocationState state, {
        required ColorScheme colorScheme,
        required String storageKeyPrefix,
      }) {
    final cs = colorScheme;

    // ✅ 핵심 수정 1) ListView.builder에도 고유 PageStorageKey 부여
    return ListView.builder(
      key: PageStorageKey<String>('${storageKeyPrefix}_single_list'),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final loc = list[index];
        final isSelected = state.selectedLocationId == loc.id;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: cs.surface,
          elevation: isSelected ? 3 : 1,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? cs.primary : cs.outlineVariant.withOpacity(.65),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            title: Text(
              loc.locationName,
              style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
            ),
            subtitle: loc.capacity > 0
                ? Text(
              '공간 ${loc.capacity}대',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
                : null,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
              ),
              child: Icon(
                loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
                color: cs.primary,
                size: 20,
              ),
            ),
            trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
            selected: isSelected,
            onTap: () => state.toggleLocationSelection(loc.id),
          ),
        );
      },
    );
  }

  /// 복합 탭 전용 리스트
  Widget _buildGroupedList(
      Map<String, List<LocationModel>> grouped,
      LocationState state, {
        required ColorScheme colorScheme,
        required String storageKeyPrefix,
      }) {
    final cs = colorScheme;

    // ✅ 핵심 수정 1) ListView에도 고유 PageStorageKey 부여
    return ListView(
      key: PageStorageKey<String>('${storageKeyPrefix}_composite_list'),
      children: grouped.entries.map((entry) {
        final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: cs.surface,
          elevation: 1,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              expansionTileTheme: ExpansionTileThemeData(
                iconColor: cs.primary,
                collapsedIconColor: cs.onSurfaceVariant,
                textColor: cs.onSurface,
                collapsedTextColor: cs.onSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            // ✅ 핵심 수정 2) ExpansionTile 고유 PageStorageKey 부여
            child: ExpansionTile(
              key: PageStorageKey<String>('${storageKeyPrefix}_exp_composite_${entry.key}'),
              title: Text(
                '상위 구역: ${entry.key} (공간 $totalCapacity대)',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: entry.value.map((loc) {
                final isSelected = state.selectedLocationId == loc.id;

                return ListTile(
                  title: Text(
                    loc.locationName,
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
                  ),
                  subtitle: loc.capacity > 0
                      ? Text(
                    '공간 ${loc.capacity}대',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )
                      : null,
                  leading: Icon(Icons.subdirectory_arrow_right, color: cs.onSurfaceVariant),
                  trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
                  selected: isSelected,
                  onTap: () => state.toggleLocationSelection(loc.id),
                );
              }).toList(),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 현대적인 FAB 세트(라운드 필 버튼 + 하단 spacer로 위치 조절)
class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onAdd,
    required this.onDelete,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.primary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ElevatedPillButton.icon(
          icon: Icons.add,
          label: '추가',
          style: primaryStyle,
          onPressed: onAdd,
        ),
        if (hasSelection) ...[
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ],
        SizedBox(height: bottomGap),
      ],
    );
  }
}

/// 둥근 알약 형태의 현대적 버튼 래퍼 (ElevatedButton 기반)
class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
    Key? key,
  }) {
    return _ElevatedPillButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

/// 아이콘 + 라벨(간격/정렬 최적화)
class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label, Key? key}) : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected ? cs.onPrimary : cs.onSurfaceVariant,
      ),
      selectedColor: cs.primary,
      backgroundColor: cs.surface,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withOpacity(.6),
      ),
      onSelected: (_) => onSelected(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
