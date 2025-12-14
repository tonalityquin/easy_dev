import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ 입력 포맷터 & MaxLengthEnforcement
import '../../../../../../utils/snackbar_helper.dart';
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
    final textTheme = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: widget.statusSectionKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 타이틀
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 18,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '추가 상태 메모',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '최대 20자',
                style: textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 접근성 라벨 + 길이 제한 + 문자 필터
          Semantics(
            label: '추가 상태 메모 입력',
            hint: '최대 20자까지 입력할 수 있습니다',
            child: TextField(
              controller: widget.controller.customStatusController,
              maxLength: 20,
              // ✅ 한글 조합 친화: 조합 종료 후 길이 잘라내기
              //    (Flutter 버전이 지원하지 않으면 MaxLengthEnforcement.none + onChanged 트리밍으로 대체)
              maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
              onChanged: (_) => _validateInput(),
              inputFormatters: [
                // ✅ 허용 문자 확장: 한글/영문/숫자/공백/기본 구두점 + ! ? : ; ' "
                FilteringTextInputFormatter.allow(
                  RegExp("[a-zA-Z0-9가-힣\\s.,()/!?;:'\\\"-]"),
                ),
              ],
              style: const TextStyle(fontSize: 14.5),
              decoration: InputDecoration(
                hintText: '예: 뒷범퍼 손상',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                filled: true,
                fillColor: cs.surface,
                // ✅ 톤 맞춤
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.primary, width: 1.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                errorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.error, width: 1.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: cs.error, width: 1.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                counterStyle: TextStyle(
                  color: _errorMessage != null ? cs.error : cs.onSurface.withOpacity(.54),
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
                errorText: _errorMessage,
              ),
            ),
          ),

          // 자동 저장된 메모 뱃지/카드
          if (widget.fetchedCustomStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.secondaryContainer, // ✅ 토널 배경
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '자동 저장된 메모: "${widget.fetchedCustomStatus}"',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _deleting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(cs.error),
                            ),
                          )
                        : IconButton(
                            tooltip: '자동 메모 삭제',
                            splashRadius: 20,
                            icon: Icon(Icons.delete_outline, color: cs.error),
                            onPressed: () async {
                              FocusScope.of(context).unfocus();
                              setState(() => _deleting = true);
                              try {
                                await widget.controller.deleteCustomStatusFromFirestore(context);

                                widget.onDeleted();
                                widget.onStatusCleared();

                                showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                              } catch (e) {
                                showFailedSnackbar(context, '삭제 실패. 다시 시도해주세요');
                              } finally {
                                if (mounted) {
                                  setState(() => _deleting = false);
                                }
                              }
                            },
                          ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
