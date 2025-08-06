import 'package:flutter/material.dart';
import '../../../../type_pages/debugs/firestore_logger.dart';
import '../monthly_plate_controller.dart';

class MonthlyCustomStatusSection extends StatefulWidget {
  final MonthlyPlateController controller;
  final String? fetchedCustomStatus;
  final VoidCallback onDeleted;
  final VoidCallback onStatusCleared;
  final Key statusSectionKey;

  const MonthlyCustomStatusSection({
    super.key,
    required this.controller,
    required this.fetchedCustomStatus,
    required this.onDeleted,
    required this.onStatusCleared,
    required this.statusSectionKey,
  });

  @override
  State<MonthlyCustomStatusSection> createState() => _MonthlyCustomStatusSectionState();
}

class _MonthlyCustomStatusSectionState extends State<MonthlyCustomStatusSection> {
  String? _errorMessage;

  void _validateInput() {
    final input = widget.controller.customStatusController.text.trim();
    setState(() {
      _errorMessage = input.isEmpty ? '⚠ 메모 내용을 입력해주세요.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('추가 상태 메모 (최대 20자)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller.customStatusController,
          maxLength: 20,
          onChanged: (_) => _validateInput(),
          decoration: InputDecoration(
            hintText: '예: 뒷범퍼 손상',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            errorText: _errorMessage,
          ),
        ),
        if (widget.fetchedCustomStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '자동 저장된 메모: "${widget.fetchedCustomStatus}"',
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      try {
                        await FirestoreLogger().log(
                          '🗑️ 상태 메모 삭제 시도: ${widget.controller.buildPlateNumber()}',
                          level: 'called',
                        );
                        await widget.controller.deleteCustomStatusFromFirestore(context);
                        await FirestoreLogger().log('✅ 상태 메모 삭제 완료', level: 'success');

                        widget.onDeleted();
                        widget.onStatusCleared();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('자동 메모가 삭제되었습니다')),
                        );
                      } catch (e) {
                        await FirestoreLogger().log('❌ 상태 메모 삭제 실패: $e', level: 'error');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('삭제 실패. 다시 시도해주세요')),
                        );
                      }
                    },
                  )
                ],
              ),
            ),
          )
      ],
    );
  }
}
