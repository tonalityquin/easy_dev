import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showRegionPickerDialog({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  String tempSelected = selectedRegion;

  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "지역 선택",
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              const Text(
                '지역 선택',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: regions.indexOf(selectedRegion),
                  ),
                  itemExtent: 48,
                  onSelectedItemChanged: (index) {
                    tempSelected = regions[index];
                  },
                  children: regions
                      .map((region) => Center(
                            child: Text(
                              region,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 12),
                child: Center(
                  child: CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onConfirm(tempSelected);
                    },
                    child: const Text(
                      '확인',
                      style: TextStyle(fontSize: 16),
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
