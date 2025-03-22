// lib/widgets/dialog/region_picker_dialog.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showRegionPickerDialog({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  String tempSelected = selectedRegion;

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.only(top: 12, left: 8, right: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SizedBox(
          height: 230,
          child: Column(
            children: [
              const Text('지역 선택', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: regions.indexOf(selectedRegion),
                  ),
                  itemExtent: 36,
                  onSelectedItemChanged: (index) {
                    tempSelected = regions[index];
                  },
                  children: regions.map((region) => Center(child: Text(region))).toList(),
                ),
              ),
              const Divider(height: 0),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onConfirm(tempSelected);
                },
                child: const Text('확인', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
