import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 입력 포맷터 & MaxLengthEnforcement
import '../../../../../utils/snackbar_helper.dart';
import '../../../../type_package/debugs/firestore_logger.dart';
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
  bool _deleting = false;

  void _validateInput() {
    final input = widget.controller.customStatusController.text.trim();
    setState(() {
      _errorMessage = input.isEmpty ? '⚠ 메모 내용을 입력해주세요.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return KeyedSubtree(
      key: widget.statusSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '추가 상태 메모 (최대 20자)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 접근성 라벨 + 길이 제한 + 문자 필터
          Semantics(
            label: '추가 상태 메모 입력',
            hint: '최대 20자까지 입력할 수 있습니다',
            child: TextField(
              controller: widget.controller.customStatusController,
              maxLength: 20,
              // 🔧 호환성: truncateAfterComposition 미지원 버전용
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              onChanged: (_) => _validateInput(),
              inputFormatters: [
                // 한글/영문/숫자/공백/기본 구두점 허용 (정책에 맞게 조정 가능)
                FilteringTextInputFormatter.allow(
                  RegExp(r"[a-zA-Z0-9가-힣\s\.\,\-\(\)\/]"),
                ),
              ],
              decoration: InputDecoration(
                hintText: '예: 뒷범퍼 손상',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                errorText: _errorMessage,
              ),
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
                      tooltip: '자동 메모 삭제',
                      icon: _deleting
                          ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.error,
                        ),
                      )
                          : const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: _deleting
                          ? null
                          : () async {
                        FocusScope.of(context).unfocus();
                        setState(() => _deleting = true);
                        try {
                          await FirestoreLogger().log(
                            '🗑️ 상태 메모 삭제 시도: ${widget.controller.buildPlateNumber()}',
                            level: 'called',
                          );

                          await widget.controller.deleteCustomStatusFromFirestore(context);
                          await FirestoreLogger().log('✅ 상태 메모 삭제 완료', level: 'success');

                          widget.onDeleted();
                          widget.onStatusCleared();

                          showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                        } catch (e) {
                          await FirestoreLogger().log('❌ 상태 메모 삭제 실패: $e', level: 'error');
                          showFailedSnackbar(context, '삭제 실패. 다시 시도해주세요');
                        } finally {
                          if (mounted) setState(() => _deleting = false);
                        }
                      },
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
