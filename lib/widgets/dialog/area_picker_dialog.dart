import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ✅ 추가

import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../../states/user/user_state.dart'; // ✅ 추가

void showAreaPickerDialog({
  required BuildContext context,
  required AreaState areaState,
  required PlateState plateState,
}) {
  final areas = areaState.availableAreas;
  String tempSelected = areaState.currentArea;

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
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: areas.indexOf(areaState.currentArea),
                  ),
                  itemExtent: 50,
                  onSelectedItemChanged: (index) {
                    tempSelected = areas[index];
                  },
                  children: areas
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
                    onTap: () {
                      Navigator.of(context).pop();

                      areaState.updateArea(tempSelected);
                      plateState.syncWithAreaState();

                      // ✅ 사용자 상태에도 currentArea 반영 (Firestore 포함)
                      final userState = context.read<UserState>();
                      userState.updateCurrentArea(tempSelected);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
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
