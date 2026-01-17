import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> tripleModifyRegionPickerBottomSheet({
  required BuildContext context,
  required String selectedRegion,
  required List<String> regions,
  required Function(String selected) onConfirm,
}) async {
  String tempSelected = selectedRegion;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
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
                  '지역 선택',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),

                const SizedBox(height: 16),

                Expanded(
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: regions.indexOf(selectedRegion),
                    ),
                    itemExtent: 48,
                    onSelectedItemChanged: (index) {
                      tempSelected = regions[index];
                    },
                    children: regions.map((region) {
                      return Center(
                        child: Text(
                          region,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const Divider(height: 1),

                const SizedBox(height: 12),

                CupertinoButton.filled(
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

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      );
    },
  );
}
