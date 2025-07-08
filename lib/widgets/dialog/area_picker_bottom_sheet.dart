import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';

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

  final rootContext = context; // ✅ 외부 context 저장
  String tempSelected = areaState.currentArea.isNotEmpty
      ? areaState.currentArea
      : userAreas.first;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  '지역 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: userAreas.contains(tempSelected)
                          ? userAreas.indexOf(tempSelected)
                          : 0,
                    ),
                    itemExtent: 48,
                    onSelectedItemChanged: (index) {
                      tempSelected = userAreas[index];
                    },
                    children: userAreas
                        .map((area) => Center(
                      child: Text(
                        area,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ))
                        .toList(),
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    Navigator.of(context).pop(); // ✅ bottom sheet 닫기

                    areaState.updateAreaPicker(tempSelected);
                    await userState.areaPickerCurrentArea(tempSelected);
                    plateState.syncWithAreaState();

                    final userDivision = userState.user?.divisions.first ?? '';
                    final areaDoc = await FirebaseFirestore.instance
                        .collection('areas')
                        .doc('$userDivision-$tempSelected')
                        .get();

                    final data = areaDoc.data();
                    final isHeadquarter =
                        data != null && data['isHeadquarter'] == true;

                    debugPrint('📌 선택된 지역: $tempSelected');
                    debugPrint('📌 조회된 문서 ID: ${areaDoc.id}');
                    debugPrint('📌 isHeadquarter 필드: ${data?['isHeadquarter']}');

                    // ✅ context가 dispose되지 않았는지 체크
                    if (!rootContext.mounted) return;

                    if (isHeadquarter) {
                      Navigator.pushReplacementNamed(
                          rootContext, AppRoutes.headquarterPage);
                    } else {
                      Navigator.pushReplacementNamed(
                          rootContext, AppRoutes.typePage);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 50, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.green, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      );
    },
  );
}
