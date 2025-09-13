import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationSettingBottomSheet extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSettingBottomSheet({super.key, required this.onSave});

  @override
  State<LocationSettingBottomSheet> createState() =>
      _LocationSettingBottomSheetState();
}

/// 하위 구역 입력 컨트롤러를 타입 안전하게 보관
class _SubFieldCtrls {
  final TextEditingController name;
  final TextEditingController capacity;

  _SubFieldCtrls(this.name, this.capacity);

  void dispose() {
    name.dispose();
    capacity.dispose();
  }
}

class _LocationSettingBottomSheetState
    extends State<LocationSettingBottomSheet> {
  // 상위(단일/복합 공통)
  final TextEditingController _locationController = TextEditingController();

  // 단일 모드용
  final TextEditingController _capacityController = TextEditingController();

  // 복합 모드용
  final List<_SubFieldCtrls> _subControllers = <_SubFieldCtrls>[];

  String? _errorMessage;
  bool _isSingle = true;

  @override
  void dispose() {
    _locationController.dispose();
    _capacityController.dispose();
    for (final s in _subControllers) {
      s.dispose();
    }
    super.dispose();
  }

  // ---------- 검증/계산 ----------

  bool _validateInput() {
    final parent = _locationController.text.trim();
    if (parent.isEmpty) {
      _setError('구역명을 입력하세요.');
      return false;
    }

    if (_isSingle) {
      final capText = _capacityController.text.trim();
      final cap = int.tryParse(capText);
      if (cap == null || cap <= 0) {
        _setError('1 이상의 유효한 수용 대수를 입력하세요.');
        return false;
      }
      _clearError();
      return true;
    } else {
      // 최소 한 개의 하위 구역: 이름 있고, 수용대수 > 0
      final hasValidSub = _subControllers.any((c) {
        final nameOk = c.name.text.trim().isNotEmpty;
        final cap = int.tryParse(c.capacity.text.trim());
        final capOk = (cap != null && cap > 0);
        return nameOk && capOk;
      });

      if (!hasValidSub) {
        _setError('상위 구역명과 1개 이상 유효한 하위 구역이 필요합니다.');
        return false;
      }
      _clearError();
      return true;
    }
  }

  int _calculateTotalSubCapacity() {
    int total = 0;
    for (final s in _subControllers) {
      final cap = int.tryParse(s.capacity.text.trim()) ?? 0;
      total += cap;
    }
    return total;
  }

  void _setError(String msg) => setState(() => _errorMessage = msg);

  void _clearError() => setState(() => _errorMessage = null);

  // ---------- 하위 구역 편집 ----------

  void _addSubLocation() {
    final name = TextEditingController();
    final capacity = TextEditingController();

    // 입력 시 합계 텍스트 실시간 갱신
    capacity.addListener(() => setState(() {}));

    setState(() {
      _subControllers.add(_SubFieldCtrls(name, capacity));
    });
  }

  void _removeSubLocation(int index) {
    setState(() {
      _subControllers[index].dispose();
      _subControllers.removeAt(index);
    });
  }

  // ---------- 저장 ----------

  void _handleSave() {
    FocusScope.of(context).unfocus();
    if (!_validateInput()) return;

    if (_isSingle) {
      widget.onSave({
        'type': 'single',
        'name': _locationController.text.trim(),
        'capacity': int.parse(_capacityController.text.trim()),
      });
    } else {
      final subs = _subControllers
          .where((c) => c.name.text.trim().isNotEmpty)
          .map((c) {
        final cap = int.tryParse(c.capacity.text.trim()) ?? 0;
        return {
          'name': c.name.text.trim(),
          'capacity': cap,
        };
      }).toList();

      widget.onSave({
        'type': 'composite',
        'parent': _locationController.text.trim(),
        'subs': subs,
        'totalCapacity': _calculateTotalSubCapacity(),
      });
    }

    Navigator.pop(context);
  }

  // ---------- UI ----------

  InputDecoration _inputDecoration(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding:
      const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height; // ✅ 화면 높이

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          // ✅ 키보드 높이를 제외한 영역만큼 최소 높이 확보 → 배경이 최상단까지 꽉 참
          constraints:
          BoxConstraints(minHeight: screenHeight - bottomPadding),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            decoration: const BoxDecoration(
              color:
              Colors.white, // 바텀시트 배경 고정(요구사항에 따라 surface로 변경 가능)
              borderRadius:
              BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                const Text(
                  '주차 구역 설정',
                  style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // 모드 선택
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('단일'),
                      selected: _isSingle,
                      selectedColor: cs.primary,
                      backgroundColor: cs.surfaceVariant,
                      labelStyle: TextStyle(
                          color: _isSingle
                              ? cs.onPrimary
                              : cs.onSurface),
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) setState(() => _isSingle = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('복합'),
                      selected: !_isSingle,
                      selectedColor: cs.primary,
                      backgroundColor: cs.surfaceVariant,
                      labelStyle: TextStyle(
                          color: !_isSingle
                              ? cs.onPrimary
                              : cs.onSurface),
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _isSingle = false;
                            if (_subControllers.isEmpty)
                              _addSubLocation();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 상위 구역명
                TextField(
                  controller: _locationController,
                  onTapOutside: (_) =>
                      FocusScope.of(context).unfocus(),
                  textInputAction: TextInputAction.next,
                  decoration: _inputDecoration(
                      context, _isSingle ? '구역명' : '상위 구역명'),
                  onSubmitted: (_) {
                    if (_isSingle) {
                      // 단일 모드일 때 수용대수로 이동
                      FocusScope.of(context).nextFocus();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // 단일 모드: 수용대수
                if (_isSingle)
                  TextField(
                    controller: _capacityController,
                    onTapOutside: (_) =>
                        FocusScope.of(context).unfocus(),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration:
                    _inputDecoration(context, '수용 가능 차량 수'),
                  ),

                // 복합 모드: 하위 구역 목록
                if (!_isSingle)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('하위 구역',
                          style:
                          TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ..._subControllers
                          .asMap()
                          .entries
                          .map((entry) {
                        final index = entry.key;
                        final sub = entry.value;
                        return Padding(
                          key: ValueKey(sub), // 안정 키
                          padding:
                          const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: sub.name,
                                  onTapOutside: (_) =>
                                      FocusScope.of(context)
                                          .unfocus(),
                                  textInputAction:
                                  TextInputAction.next,
                                  decoration: _inputDecoration(
                                      context, '하위 ${index + 1}'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: sub.capacity,
                                  onTapOutside: (_) =>
                                      FocusScope.of(context)
                                          .unfocus(),
                                  keyboardType:
                                  TextInputType.number,
                                  textInputAction:
                                  TextInputAction.next,
                                  inputFormatters: [
                                    FilteringTextInputFormatter
                                        .digitsOnly,
                                    LengthLimitingTextInputFormatter(
                                        4),
                                  ],
                                  decoration:
                                  _inputDecoration(context, '수용'),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _removeSubLocation(index),
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                tooltip: '하위 구역 삭제',
                              ),
                            ],
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _addSubLocation,
                          icon: const Icon(Icons.add),
                          label: const Text('하위 구역 추가'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                          '총 수용 차량: ${_calculateTotalSubCapacity()}대'),
                    ],
                  ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!,
                      style: TextStyle(color: cs.error)),
                ],

                const SizedBox(height: 24),

                // 하단 액션
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
