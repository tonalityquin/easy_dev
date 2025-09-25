// lib/widgets/dialog/area_picker_bottom_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';

import '../../utils/usage_reporter.dart';

// ── Deep Blue Palette
const base = Color(0xFF0D47A1); // primary
const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
const light = Color(0xFF5472D3); // 톤 변형/보더
const fg = Color(0xFFFFFFFF); // onPrimary

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

  // pop 이후 push 시 안전하게 쓰기 위한 루트 컨텍스트
  final rootContext = context;

  String tempSelected = areaState.currentArea.isNotEmpty ? areaState.currentArea : userAreas.first;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // ⬅️ 최상단까지 확장
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return FractionallySizedBox(
        heightFactor: 1, // ⬅️ 화면 100%
        child: DraggableScrollableSheet(
          initialChildSize: 1.0, // ⬅️ 시작부터 최대
          minChildSize: 0.3,
          maxChildSize: 1.0,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              top: false, // ⬅️ 상단 라운드 유지
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
                    // 그립바
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

                    // 내용
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: userAreas.contains(tempSelected) ? userAreas.indexOf(tempSelected) : 0,
                        ),
                        itemExtent: 48,
                        magnification: 1.05,
                        useMagnifier: true,
                        squeeze: 1.1,
                        onSelectedItemChanged: (index) {
                          tempSelected = userAreas[index];
                        },
                        children: userAreas
                            .map((area) => Center(
                          child: Text(
                            area,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ))
                            .toList(),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Divider(height: 1, color: light.withOpacity(.35)),
                    const SizedBox(height: 16),

                    // 확인 버튼 (팔레트 적용)
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
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();

                          // 지역 상태/유저 상태 업데이트 (구독 판단 전 선반영)
                          final __beforeArea = areaState.currentArea; // 👈 변경 전 지역 기록(가드)
                          areaState.updateAreaPicker(tempSelected);
                          await userState.areaPickerCurrentArea(tempSelected);

                          final userDivision = userState.user?.divisions.first ?? '';
                          try {
                            final areaDoc = await FirebaseFirestore.instance
                                .collection('areas')
                                .doc('$userDivision-$tempSelected')
                                .get();

                            // 🔎 UsageReporter: Firestore READ 1건 계측
                            UsageReporter.instance.report(
                              area: tempSelected,
                              action: 'read',
                              n: 1,
                              source: 'AreaPickerBottomSheet.getAreaDoc',
                            );

                            final data = areaDoc.data();
                            final isHeadquarter = data != null && data['isHeadquarter'] == true;

                            debugPrint('📌 선택된 지역: $tempSelected');
                            debugPrint('📌 조회된 문서 ID: ${areaDoc.id}');
                            debugPrint('📌 isHeadquarter 필드: ${data?['isHeadquarter']}');

                            if (!rootContext.mounted) return;

                            if (isHeadquarter) {
                              // ✅ HQ 전환: 모든 구독 해제 → HQ 페이지로
                              plateState.disableAll();
                              Navigator.pushReplacementNamed(rootContext, AppRoutes.headquarterPage);
                            } else {
                              // ✅ 필드 전환: 구독 활성화(최초 진입) + [지역 변경 시에만] 동기화 → 필드 페이지
                              plateState.enableForTypePages();
                              if (__beforeArea != areaState.currentArea) {
                                plateState.syncWithAreaState(); // 👈 실제 변경된 경우에만 재구독
                              }
                              Navigator.pushReplacementNamed(rootContext, AppRoutes.typePage);
                            }
                          } catch (e, st) {
                            // (읽기 실패 시에도 READ 시도 자체는 1건으로 간주할 수 있으나,
                            // 실패 시점에 중복 계측을 피하기 위해 위에서만 기록)
                            debugPrint('❌ areas 문서 조회 실패: $e\n$st');
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
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
