import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../controllers/monthly_plate_controller.dart';

const _memoInk = Color(0xFF101828);
const _memoMuted = Color(0xFF667085);
const _memoPanel = Color(0xFFFFFFFF);
const _memoLine = Color(0xFFD8DEE8);
const _memoBlue = Color(0xFF2563EB);
const _memoRed = Color(0xFFDC2626);

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
  bool _deleting = false;

  InputDecoration _inputDecoration() {
    return InputDecoration(
      hintText: '예: 뒷범퍼 손상, 장기 미출차',
      hintStyle: const TextStyle(color: _memoMuted, fontWeight: FontWeight.w700),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _memoLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _memoBlue, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      counterStyle: const TextStyle(color: _memoMuted, fontWeight: FontWeight.w800, fontSize: 11),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: widget.statusSectionKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _memoPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _memoLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sticky_note_2_outlined, color: _memoBlue, size: 19),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운영 메모',
                        style: TextStyle(color: _memoInk, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '현장 인수인계용 짧은 상태 메모입니다.',
                        style: TextStyle(color: _memoMuted, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Text(
                  '20자',
                  style: TextStyle(color: _memoMuted, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.controller.customStatusController,
              maxLength: 20,
              maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
              style: const TextStyle(color: _memoInk, fontWeight: FontWeight.w800),
              decoration: _inputDecoration(),
            ),
            if (widget.fetchedCustomStatus != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '자동 저장된 메모: ${widget.fetchedCustomStatus}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _memoInk, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _deleting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _memoRed),
                          )
                        : IconButton(
                            tooltip: '자동 메모 삭제',
                            onPressed: () async {
                              FocusScope.of(context).unfocus();
                              setState(() => _deleting = true);
                              try {
                                await widget.controller.deleteCustomStatusFromFirestore(context);
                                widget.onDeleted();
                                widget.onStatusCleared();
                              } catch (_) {
                              } finally {
                                if (mounted) setState(() => _deleting = false);
                              }
                            },
                            icon: const Icon(Icons.delete_outline, color: _memoRed),
                          ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
