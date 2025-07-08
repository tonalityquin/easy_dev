import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/bill/bill_state.dart';

class ModifyBillSection extends StatelessWidget {
  final String? selectedBill;
  final ValueChanged<String?> onChanged;

  const ModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final billState = context.watch<BillState>();
    final billList = billState.bills;
    final isLoading = billState.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (billList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                '설정된 정산 유형이 없어 무료입니다.',
                style: TextStyle(color: Colors.green),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              side: const BorderSide(color: Colors.black),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) {
                  return DraggableScrollableSheet(
                    initialChildSize: 0.4,
                    minChildSize: 0.3,
                    maxChildSize: 0.9,
                    builder: (context, scrollController) {
                      return Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                              '정산 유형 선택',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                controller: scrollController,
                                itemCount: billList.length,
                                itemBuilder: (context, index) {
                                  final type = billList[index].countType;
                                  return ListTile(
                                    title: Text(type),
                                    trailing: type == selectedBill
                                        ? const Icon(Icons.check, color: Colors.green)
                                        : null,
                                    onTap: () {
                                      Navigator.pop(context);
                                      onChanged(type);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(selectedBill ?? '정산 유형 선택'),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
      ],
    );
  }
}
