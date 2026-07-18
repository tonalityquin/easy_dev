import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/di/routes.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/headquarter/application/area/area_master_cache.dart';
import 'prompt_area_picker_sheet.dart';
import '../../../plate/application/double/double_plate_state.dart';

const String _modeKey = 'double';

void doubleAreaPickerBottomSheet({
  required BuildContext context,
  required AreaState areaState,
  required DoublePlateState litePlateState,
  bool usePromptUi = false,
}) {
  final userState = context.read<UserState>();
  final userAreas = userState.session?.areas ?? const <String>[];

  if (userAreas.isEmpty) {
    debugPrint('⚠️ 사용자 소속 지역 없음 (userAreas)');
    return;
  }

  final divisions = userState.session?.divisions ?? const <String>[];
  final userDivision = divisions.isNotEmpty ? divisions.first : '';
  if (userDivision.trim().isEmpty) {
    debugPrint('⚠️ 사용자 소속 회사 없음 (userDivision)');
    return;
  }

  final rootContext = context;
  final Future<AreaMasterSelectableData> future = AreaMasterCache.readSelectableAreas(
    division: userDivision,
    userAreas: userAreas,
    modeKey: _modeKey,
  );

  if (usePromptUi) {
    showPromptAreaPickerSheet(
      context: context,
      future: future,
      currentArea: areaState.currentArea,
      onConfirm: (selected, data) async {
        Navigator.of(context).pop();
        final beforeArea = areaState.currentArea;
        areaState.updateAreaPicker(selected);
        await userState.areaPickerCurrentArea(selected);
        final isHeadquarter = data.isHeadquarterByName[selected] == true;
        if (!rootContext.mounted) return;
        if (isHeadquarter) {
          litePlateState.doubleDisableAll();
          Navigator.pushReplacementNamed(
            rootContext,
            AppRoutes.doubleHeadquarterPage,
          );
        } else {
          litePlateState.doubleEnableForTypePages();
          if (beforeArea != areaState.currentArea) {
            litePlateState.doubleSyncWithAreaState();
          }
          Navigator.pushReplacementNamed(
            rootContext,
            AppRoutes.doubleTypePage,
          );
        }
      },
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      final cs = Theme.of(modalCtx).colorScheme;

      return FractionallySizedBox(
        heightFactor: 1,
        child: DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.3,
          maxChildSize: 1.0,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.14),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      '지역 선택',
                      style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: FutureBuilder<AreaMasterSelectableData>(
                        future: future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                              ),
                            );
                          }

                          if (!snap.hasData) {
                            return Center(
                              child: Text(
                                '지역 목록을 불러오지 못했습니다.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            );
                          }

                          final data = snap.data!;
                          final selectable = data.selectableAreas;

                          if (!data.hasCache) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '지역 마스터가 없습니다.',
                                    style: TextStyle(color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '업무 메뉴에서 지역 마스터 갱신을 먼저 실행하세요.',
                                    style: TextStyle(color: cs.onSurfaceVariant),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 200,
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(sheetCtx).pop(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: cs.onSurface,
                                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text('닫기'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (selectable.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '이 모드에서 선택 가능한 지역이 없습니다.',
                                    style: TextStyle(color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 180,
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(sheetCtx).pop(),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: cs.onSurface,
                                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text('닫기'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          String tempSelected = areaState.currentArea.trim().isNotEmpty
                              ? areaState.currentArea.trim()
                              : selectable.first;

                          if (!selectable.contains(tempSelected)) {
                            tempSelected = selectable.first;
                          }

                          return _PickerWithConfirmButton(
                            selectableAreas: selectable,
                            initialSelected: tempSelected,
                            onConfirm: (selected) async {
                              Navigator.of(sheetCtx).pop();

                              final beforeArea = areaState.currentArea;
                              areaState.updateAreaPicker(selected);
                              await userState.areaPickerCurrentArea(selected);

                              final isHeadquarter = data.isHeadquarterByName[selected] == true;

                              if (!rootContext.mounted) return;

                              if (isHeadquarter) {
                                litePlateState.doubleDisableAll();
                                Navigator.pushReplacementNamed(rootContext, AppRoutes.doubleHeadquarterPage);
                              } else {
                                litePlateState.doubleEnableForTypePages();
                                if (beforeArea != areaState.currentArea) {
                                  litePlateState.doubleSyncWithAreaState();
                                }
                                Navigator.pushReplacementNamed(rootContext, AppRoutes.doubleTypePage);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _PickerWithConfirmButton extends StatefulWidget {
  final List<String> selectableAreas;
  final String initialSelected;
  final Future<void> Function(String selected) onConfirm;

  const _PickerWithConfirmButton({
    required this.selectableAreas,
    required this.initialSelected,
    required this.onConfirm,
  });

  @override
  State<_PickerWithConfirmButton> createState() => _PickerWithConfirmButtonState();
}

class _PickerWithConfirmButtonState extends State<_PickerWithConfirmButton> {
  late String _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.initialSelected;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final initialIndex = widget.selectableAreas.contains(_tempSelected)
        ? widget.selectableAreas.indexOf(_tempSelected)
        : 0;

    return Column(
      children: [
        Expanded(
          child: CupertinoTheme(
            data: CupertinoThemeData(
              primaryColor: cs.primary,
              brightness: cs.brightness,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            child: CupertinoPicker(
              scrollController: FixedExtentScrollController(initialItem: initialIndex),
              itemExtent: 48,
              magnification: 1.05,
              useMagnifier: true,
              squeeze: 1.1,
              onSelectedItemChanged: (index) {
                setState(() => _tempSelected = widget.selectableAreas[index]);
              },
              children: widget.selectableAreas
                  .map(
                    (area) => Center(
                      child: Text(
                        area,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            icon: const Icon(Icons.check_rounded),
            label: const Text('확인'),
            onPressed: () => widget.onConfirm(_tempSelected),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
