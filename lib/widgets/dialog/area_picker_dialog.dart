import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../routes.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart';

void showAreaPickerDialog({
  required BuildContext context,
  required AreaState areaState,
  required PlateState plateState,
}) {
  final userState = context.read<UserState>();

  final userAreas = userState.user?.areas ?? [];

  if (userAreas.isEmpty) {
    debugPrint('⚠️ 사용자 소속 지역 없음 (userAreas)');
  }

  String tempSelected =
  areaState.currentArea.isNotEmpty ? areaState.currentArea : (userAreas.isNotEmpty ? userAreas.first : '');

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "지역 선택",
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
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
                child: userAreas.isEmpty
                    ? const Center(child: Text("표시할 지역이 없습니다"))
                    : CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: userAreas.contains(tempSelected) ? userAreas.indexOf(tempSelected) : 0,
                  ),
                  itemExtent: 50,
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
              Padding(
                padding: const EdgeInsets.only(bottom: 40, top: 20),
                child: Center(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.of(context).pop();
                      areaState.updateArea(tempSelected);

                      await userState.areaPickerCurrentArea(tempSelected);
                      plateState.syncWithAreaState();

                      final userDivision = userState.user?.divisions.first ?? '';
                      final areaDoc = await FirebaseFirestore.instance
                          .collection('areas')
                          .doc('$userDivision-$tempSelected')
                          .get();

                      final data = areaDoc.data();
                      final isHeadquarter = data != null && data['isHeadquarter'] == true;

                      // 디버깅 출력
                      debugPrint('📌 선택된 지역: $tempSelected');
                      debugPrint('📌 조회된 문서 ID: ${areaDoc.id}');
                      debugPrint('📌 isHeadquarter 필드: ${data?['isHeadquarter']}');

                      if (isHeadquarter) {
                        Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
                      } else {
                        Navigator.pushReplacementNamed(context, AppRoutes.typePage);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 50,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.green, width: 2),
                        boxShadow: [
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
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
