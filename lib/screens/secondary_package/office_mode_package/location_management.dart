// lib/screens/secondary_package/office_mode_package/location_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/snackbar_helper.dart';
// import '../../../widgets/navigation/secondary_mini_navigation.dart'; // ❌ 미사용
import 'location_management_package/location_setting.dart';
import '../../../states/location/location_state.dart';
import '../../../states/area/area_state.dart';
import '../../../models/location_model.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  // ▼ FAB 위치/간격 조절
  static const double _fabBottomGap = 48.0; // 하단에서 띄우기
  static const double _fabSpacing = 10.0;   // 버튼 간 간격

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
                    .map<Map<String, dynamic>>((sub) => {
                  'name': sub['name']?.toString() ?? '',
                  'capacity': sub['capacity'] ?? 0,
                })
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
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('주차구역', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: locationState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : allLocations.isEmpty
          ? const Center(child: Text('현재 지역에 주차 구역이 없습니다.'))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('전체'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('단일'),
                  selected: _filter == 'single',
                  onSelected: (_) => setState(() => _filter = 'single'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('복합'),
                  selected: _filter == 'composite',
                  onSelected: (_) => setState(() => _filter = 'composite'),
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
      tiles.add(const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('단일 주차 구역'),
      ));
      tiles.addAll(_buildSimpleTiles(singles, state, colorScheme));
    }

    if (singles.isNotEmpty && grouped.isNotEmpty) {
      tiles.add(const Divider());
    }

    if (grouped.isNotEmpty) {
      tiles.add(const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('복합 주차 구역'),
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

      return ListTile(
        title: Text(loc.locationName),
        subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
        leading: Icon(
          loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
          color: cs.onSurfaceVariant,
        ),
        trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
        selected: isSelected,
        onTap: () => state.toggleLocationSelection(loc.id),
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

      return ExpansionTile(
        title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
        children: entry.value.map((loc) {
          final isSelected = state.selectedLocationId == loc.id;

          return ListTile(
            title: Text(loc.locationName),
            subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
            leading: const Icon(Icons.subdirectory_arrow_right),
            trailing: isSelected ? Icon(Icons.check_circle, color: cs.primary) : null,
            selected: isSelected,
            onTap: () => state.toggleLocationSelection(loc.id),
          );
        }).toList(),
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

        return ListTile(
          title: Text(loc.locationName),
          subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
          leading: Icon(
            loc.type == 'single' ? Icons.location_on : Icons.maps_home_work,
            color: colorScheme.onSurfaceVariant,
          ),
          trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
          selected: isSelected,
          onTap: () => state.toggleLocationSelection(loc.id),
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
        final totalCapacity = entry.value.fold<int>(0, (sum, loc) => sum + loc.capacity);

        return ExpansionTile(
          title: Text('상위 구역: ${entry.key} (공간 $totalCapacity대)'),
          children: entry.value.map((loc) {
            final isSelected = state.selectedLocationId == loc.id;

            return ListTile(
              title: Text(loc.locationName),
              subtitle: loc.capacity > 0 ? Text('공간 ${loc.capacity}대') : null,
              leading: const Icon(Icons.subdirectory_arrow_right),
              trailing: isSelected ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
              selected: isSelected,
              onTap: () => state.toggleLocationSelection(loc.id),
            );
          }).toList(),
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
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
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
      mainAxisSize: MainAxisSize.min, // ✅ 소문자 min
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
