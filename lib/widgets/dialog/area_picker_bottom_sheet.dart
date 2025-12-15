import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';

// ── Deep Blue Palette
const base = Color(0xFF0D47A1); // primary
const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
const light = Color(0xFF5472D3); // 톤 변형/보더
const fg = Color(0xFFFFFFFF); // onPrimary

const String _modeKey = 'service'; // ✅ 서비스 시트는 service 포함 지역만 노출

class _AreaPickData {
  final List<String> selectableAreas; // userAreas 순서 기반 필터 결과
  final Map<String, bool> isHeadquarterByName; // name -> isHeadquarter
  const _AreaPickData({
    required this.selectableAreas,
    required this.isHeadquarterByName,
  });
}

Future<_AreaPickData> _fetchSelectableAreasForMode({
  required String userDivision,
  required List<String> userAreas,
  required String modeKey,
}) async {
  // ✅ division 기준으로 areas 문서들을 가져온 뒤, modes 필드를 클라이언트에서 필터링
  final qs = await FirebaseFirestore.instance
      .collection('areas')
      .where('division', isEqualTo: userDivision)
      .get(const GetOptions(source: Source.serverAndCache));

  // ✅ modes가 "없는" 지역은 불러오지 못하도록: modesByName에는 modes가 있는 문서만 적재
  final Map<String, List<String>> modesByName = {};
  final Map<String, bool> isHQByName = {};

  for (final doc in qs.docs) {
    final data = doc.data();
    final name = (data['name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;

    final dynamic modesRaw = data['modes'];
    if (modesRaw is! List) {
      // ✅ modes 필드가 없거나 List가 아니면 제외
      continue;
    }

    final modes = modesRaw
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (modes.isEmpty) {
      // ✅ 빈 리스트도 제외
      continue;
    }

    modesByName[name] = modes;
    isHQByName[name] = (data['isHeadquarter'] == true);
  }

  // userState.user.areas는 사용자가 접근 가능한 후보 리스트
  // 그 중에서 "문서가 존재하고 + modes가 있고 + modeKey 포함"만 노출
  final List<String> filtered = [];
  for (final a in userAreas) {
    final name = a.trim();
    if (name.isEmpty) continue;

    final modes = modesByName[name];
    if (modes == null) {
      // ✅ modes가 없는 지역은 불러오지 못하도록 제외
      continue;
    }

    if (modes.contains(modeKey)) {
      filtered.add(name);
    }
  }

  return _AreaPickData(
    selectableAreas: filtered,
    isHeadquarterByName: isHQByName,
  );
}

void areaPickerBottomSheet({
  required BuildContext context,
  required AreaState areaState,
  required PlateState plateState,
}) {
  final userState = context.read<UserState>();
  final userAreas = userState.user?.areas ?? [];

  if (userAreas.isEmpty) {
    debugPrint('⚠️ 사용자 소속 지역 없음 (userAreas)');
    return;
  }

  final userDivision = userState.user?.divisions.first ?? '';
  if (userDivision.trim().isEmpty) {
    debugPrint('⚠️ 사용자 소속 회사 없음 (userDivision)');
    return;
  }

  // pop 이후 push 시 안전하게 쓰기 위한 루트 컨텍스트
  final rootContext = context;

  final Future<_AreaPickData> future = _fetchSelectableAreasForMode(
    userDivision: userDivision,
    userAreas: userAreas,
    modeKey: _modeKey,
  );

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
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
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: light.withOpacity(.35)),
                  boxShadow: [
                    BoxShadow(
                      color: base.withOpacity(.06),
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
                        color: light.withOpacity(.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      '지역 선택',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ).copyWith(color: dark),
                    ),
                    const SizedBox(height: 16),

                    Expanded(
                      child: FutureBuilder<_AreaPickData>(
                        future: future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snap.hasData) {
                            return const Center(child: Text('지역 목록을 불러오지 못했습니다.'));
                          }

                          final data = snap.data!;
                          final selectable = data.selectableAreas;

                          if (selectable.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('이 모드에서 선택 가능한 지역이 없습니다.'),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: 180,
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.of(sheetCtx).pop(),
                                      child: const Text('닫기'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // 현재 선택값이 목록에 없으면 첫 항목으로 보정
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

                              // 지역 상태/유저 상태 업데이트 (구독 판단 전 선반영)
                              final beforeArea = areaState.currentArea;
                              areaState.updateAreaPicker(selected);
                              await userState.areaPickerCurrentArea(selected);

                              // ✅ HQ 판정: 미리 로드한 map 사용
                              bool isHeadquarter = data.isHeadquarterByName[selected] == true;

                              // 안전망(정상이라면 여기로 오지 않음): 맵에 없는 경우만 1회 조회
                              if (!data.isHeadquarterByName.containsKey(selected)) {
                                try {
                                  final areaDoc = await FirebaseFirestore.instance
                                      .collection('areas')
                                      .doc('$userDivision-$selected')
                                      .get();
                                  final docData = areaDoc.data();
                                  isHeadquarter = docData != null && docData['isHeadquarter'] == true;
                                } catch (_) {
                                  isHeadquarter = false;
                                }
                              }

                              if (!rootContext.mounted) return;

                              if (isHeadquarter) {
                                plateState.disableAll();
                                Navigator.pushReplacementNamed(rootContext, AppRoutes.headquarterPage);
                              } else {
                                plateState.enableForTypePages();
                                if (beforeArea != areaState.currentArea) {
                                  plateState.syncWithAreaState();
                                }
                                Navigator.pushReplacementNamed(rootContext, AppRoutes.typePage);
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
    final initialIndex = widget.selectableAreas.contains(_tempSelected)
        ? widget.selectableAreas.indexOf(_tempSelected)
        : 0;

    return Column(
      children: [
        Expanded(
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: light.withOpacity(.35)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: base,
              foregroundColor: fg,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
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
