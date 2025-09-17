// lib/screens/secondary_package/office_mode_package/location_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
import 'location_management_package/location_setting.dart';
import '../../../states/location/location_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/location_model.dart';

/// Service 카드 팔레트 반영 🎨
const serviceCardBase  = Color(0xFF0D47A1);
const serviceCardDark  = Color(0xFF09367D);
const serviceCardLight = Color(0xFF5472D3);
const serviceCardFg    = Colors.white; // 아이콘/버튼 전경
const serviceCardBg    = Colors.white; // 카드/바탕

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  // ▼ FAB 위치/간격 조절
  static const double _fabBottomGap = 48.0; // 하단에서 띄우기
  static const double _fabSpacing = 10.0; // 버튼 간 간격

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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final currentArea = context.read<AreaState>().currentArea;

        // 전체 높이로 채우기
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            onSave: (location) {
              if (location is! Map<String, dynamic>) {
                showFailedSnackbar(context, '❗ 알 수 없는 형식의 주차 구역 데이터입니다.');
                return;
              }

              final type = location['type'];
              if (type == 'single') {
                final name = location['name']?.toString() ?? '';
                final capacity = (location['capacity'] as int?) ?? 0;

                locationState
                    .addSingleLocation(
                  name,
                  currentArea,
                  capacity: capacity,
                  onError: (error) => showFailedSnackbar(
                    context,
                    '🚨 주차 구역 추가 실패: $error',
                  ),
                )
                    .then((_) => showSuccessSnackbar(context, '✅ 주차 구역이 추가되었습니다.'));
              } else if (type == 'composite') {
                final parent = location['parent']?.toString() ?? '';
                final rawSubs = location['subs'];

                final subs = (rawSubs is List)
                    ? rawSubs
                    .map<Map<String, dynamic>>(
                      (sub) => {
                    'name': sub['name']?.toString() ?? '',
                    'capacity': sub['capacity'] ?? 0,
                  },
                )
                    .toList()
                    : <Map<String, dynamic>>[];

                locationState
                    .addCompositeLocation(
                  parent,
                  subs,
                  currentArea,
                  onError: (error) => showFailedSnackbar(
                    context,
                    '🚨 복합 주차 구역 추가 실패: $error',
                  ),
                )
                    .then((_) => showSuccessSnackbar(context, '✅ 복합 주차 구역이 추가되었습니다.'));
              } else {
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

    final ok = await _confirmDelete(context);
    if (!ok) return;

    await locationState.deleteLocations(
      [selectedId],
      onError: (error) => showFailedSnackbar(context, '🚨 주차 구역 삭제 실패: $error'),
    );
    if (!mounted) return;
    showSuccessSnackbar(context, '✅ 삭제되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea;

    final allLocations =
    locationState.locations.where((location) => location.area == currentArea).toList();

    final singles = allLocations.where((loc) => loc.type == 'single').toList();
    final composites = allLocations.where((loc) => loc.type == 'composite').toList();

    final Map<String, List<LocationModel>> grouped = {};
    for (final loc in composites) {
      final parent = loc.parent ?? '기타';
      grouped.putIfAbsent(parent, () => []).add(loc);
    }

    final hasSelection = locationState.selectedLocationId != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: serviceCardBg,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '주차구역',
          style: const TextStyle(fontWeight: FontWeight.bold).copyWith(color: serviceCardDark),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: serviceCardLight.withOpacity(.18)),
        ),
      ),
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator())
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
                  cs: cs,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '단일',
                  selected: _filter == 'single',
                  onSelected: () => setState(() => _filter = 'single'),
                  cs: cs,
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: '복합',
                  selected: _filter == 'composite',
                  onSelected: () => setState(() => _filter = 'composite'),
                  cs: cs,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _filter == 'single'
                ? _buildSimpleList(singles, locationState, colorScheme: cs)
                : _filter == 'composite'
                ? _buildGroupedList(grouped, locationState, colorScheme: cs)
                : _buildAllListView(
              singles: singles,
              grouped: grouped,
              state: locationState,
              colorScheme: cs,
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
        cs: cs,
      ),
    );
  }

  /// ‘전체’ 탭은 하나의 ListView로 합쳐 스크롤러를 1개만 유지(오버플로우/중첩 스크롤 방지)
  Widget _buildAllListView({
    required List<LocationModel> singles,
    required Map<String, List<LocationModel>> grouped,
    required LocationState state,
    required ColorScheme colorScheme,
  }) {
    final tiles = <Widget>[];

    if (singles.isNotEmpty) {
      tiles.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '단일 주차 구역',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: serviceCardDark,
          ),
        ),
      ));
      tiles.addAll(_buildSimpleTiles(singles, state, colorScheme));
    }

    if (singles.isNotEmpty && grouped.isNotEmpty) {
      tiles.add(Divider(color: serviceCardLight.withOpacity(.30)));
    }

    if (grouped.isNotEmpty) {
      tiles.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          '복합 주차 구역',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: serviceCardDark,
          ),
        ),
      ));
      tiles.addAll(_buildGroupedTiles(grouped, state, colorScheme));
    }

    return ListView(children: tiles);
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
        color: serviceCardBg,
        elevation: isSelected ? 3 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected
                ? serviceCardBase
                : serviceCardLight.withOpacity(.28),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          title: Text(
            loc.locationName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: serviceCardLight.withOpacity(.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
              color: serviceCardBase,
              size: 20,
            ),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle, color: serviceCardBase)
              : Icon(Icons.chevron_right, color: cs.outline),
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
      ) {
    return grouped.entries.map((entry) {
      final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: serviceCardLight.withOpacity(.28)),
        ),
        color: serviceCardBg,
        elevation: 1,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            expansionTileTheme: ExpansionTileThemeData(
              iconColor: serviceCardBase,
              collapsedIconColor: cs.onSurfaceVariant,
              textColor: cs.onSurface,
              collapsedTextColor: cs.onSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          child: ExpansionTile(
            title: Text(
              '상위 구역: ${entry.key} (공간 $totalCapacity대)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: entry.value.map((loc) {
              final isSelected = state.selectedLocationId == loc.id;

              return ListTile(
                title: Text(loc.locationName),
                subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
                leading: Icon(Icons.subdirectory_arrow_right, color: cs.onSurfaceVariant),
                trailing:
                isSelected ? const Icon(Icons.check_circle, color: serviceCardBase) : null,
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
      }) {
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final loc = list[index];
        final isSelected = state.selectedLocationId == loc.id;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: serviceCardBg,
          elevation: isSelected ? 3 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected
                  ? serviceCardBase
                  : serviceCardLight.withOpacity(.28),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            title: Text(
              loc.locationName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: serviceCardLight.withOpacity(.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
                color: serviceCardBase,
                size: 20,
              ),
            ),
            trailing: isSelected ? const Icon(Icons.check_circle, color: serviceCardBase) : null,
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
      }) {
    return ListView(
      children: grouped.entries.map((entry) {
        final totalCapacity =
        entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: serviceCardBg,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: serviceCardLight.withOpacity(.28)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              expansionTileTheme: ExpansionTileThemeData(
                iconColor: serviceCardBase,
                collapsedIconColor: colorScheme.onSurfaceVariant,
                textColor: colorScheme.onSurface,
                collapsedTextColor: colorScheme.onSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                collapsedShape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            child: ExpansionTile(
              title: Text(
                '상위 구역: ${entry.key} (공간 $totalCapacity대)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: entry.value.map((loc) {
                final isSelected = state.selectedLocationId == loc.id;

                return ListTile(
                  title: Text(loc.locationName),
                  subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
                  leading:
                  Icon(Icons.subdirectory_arrow_right, color: colorScheme.onSurfaceVariant),
                  trailing:
                  isSelected ? const Icon(Icons.check_circle, color: serviceCardBase) : null,
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
    required this.cs,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback? onDelete;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: serviceCardBase,
      foregroundColor: serviceCardFg,
      elevation: 3,
      shadowColor: cs.shadow.withOpacity(0.25),
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
        // 항상 ‘추가’ 노출
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
        SizedBox(height: bottomGap), // 하단 여백으로 버튼 위치 올리기
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

  // ✅ const 생성자 대신 factory로 위임하여 상수 제약(Invalid constant value) 회피
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
    required this.cs,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? serviceCardBase : cs.onSurfaceVariant,
      ),
      selectedColor: serviceCardLight.withOpacity(.22),
      backgroundColor: serviceCardLight.withOpacity(.10),
      side: BorderSide(
        color: selected ? serviceCardBase : cs.outlineVariant.withOpacity(.6),
      ),
      onSelected: (_) => onSelected(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
