import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../states/secondary/secondary_mode.dart';

void secondaryPickerBottomSheet({
  required BuildContext context,
  required SecondaryMode manageState,
  required String currentStatus,
  required List<String> availableStatus,
}) {
  String tempSelected = currentStatus;
  int outsideTapCount = 0;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              outsideTapCount++;
              if (outsideTapCount >= 10) {
                tempSelected = "Dev Mode";
                manageState.updateManage(tempSelected);
                Navigator.of(context).pop();
              }
            },
            child: DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.4,
              maxChildSize: 0.9,
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
                        '모드 선택',
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
                            initialItem: availableStatus.indexOf(currentStatus),
                          ),
                          itemExtent: 48,
                          onSelectedItemChanged: (index) {
                            tempSelected = availableStatus[index];
                          },
                          children: availableStatus.map((mode) {
                            return Center(
                              child: Text(
                                mode,
                                style: const TextStyle(fontSize: 18),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          manageState.updateManage(tempSelected);
                          Navigator.of(context).pop();
                        },
                        onTapDown: (_) {
                          outsideTapCount = 0;
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
            ),
          );
        },
      );
    },
  );
}
