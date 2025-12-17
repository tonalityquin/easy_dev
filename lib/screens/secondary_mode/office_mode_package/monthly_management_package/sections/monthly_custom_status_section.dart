import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../monthly_plate_controller.dart';

class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

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

  InputDecoration _svcInputDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: '예: 뒷범퍼 손상',
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: _SvcColors.light.withOpacity(.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.error, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.error, width: 1.6),
        borderRadius: BorderRadius.circular(12),
      ),
      counterStyle: TextStyle(
        color: _errorMessage != null ? cs.error : cs.onSurface.withOpacity(.54),
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
      ),
      errorText: _errorMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: widget.statusSectionKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _SvcColors.light.withOpacity(.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _SvcColors.light.withOpacity(.40)),
                  ),
                  child: const Icon(Icons.sticky_note_2_outlined, color: _SvcColors.dark, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '추가 상태 메모',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: _SvcColors.dark,
                    ),
                  ),
                ),
                Text(
                  '최대 20자',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 입력
            Semantics(
              label: '추가 상태 메모 입력',
              hint: '최대 20자까지 입력할 수 있습니다',
              child: TextField(
                controller: widget.controller.customStatusController,
                maxLength: 20,
                maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
                onChanged: (_) => _validateInput(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp("[a-zA-Z0-9가-힣\\s.,()/!?;:'\\\"-]"),
                  ),
                ],
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                decoration: _svcInputDecoration(context),
              ),
            ),

            // 자동 저장된 메모 카드
            if (widget.fetchedCustomStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: _SvcColors.light.withOpacity(.10),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 20, color: _SvcColors.dark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '자동 저장된 메모: "${widget.fetchedCustomStatus}"',
                          style: const TextStyle(
                            fontSize: 14,
                            color: _SvcColors.dark,
                            fontWeight: FontWeight.w700,
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
      ),
    );
  }
}
