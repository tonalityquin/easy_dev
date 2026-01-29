import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LocationSettingBottomSheet extends StatefulWidget {
  final Function(dynamic location) onSave;

  const LocationSettingBottomSheet({super.key, required this.onSave});

  @override
  State<LocationSettingBottomSheet> createState() => _LocationSettingBottomSheetState();
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

class _LocationSettingBottomSheetState extends State<LocationSettingBottomSheet> {
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

  // ---------- 11시 라벨 ----------
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        // 제스처 간섭 방지
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: location setting',
              child: Text('location setting', style: style),
            ),
          ),
        ),
      ),
    );
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
      final subs = _subControllers.where((c) => c.name.text.trim().isNotEmpty).map((c) {
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

  InputDecoration _inputDecoration(
      BuildContext context,
      String label, {
        required ColorScheme cs,
      }) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.45),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 1.6),
        borderRadius: BorderRadius.circular(10),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.error.withOpacity(.60)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.error, width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              // 키보드 높이를 제외한 영역만큼 최소 높이 확보 → 배경이 최상단까지 꽉 참
              constraints: BoxConstraints(minHeight: screenHeight - bottomPadding),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
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
                          color: cs.outlineVariant.withOpacity(.65),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      '주차 구역 설정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 모드 선택
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ModeChip(
                          label: '단일',
                          selected: _isSingle,
                          onTap: () => setState(() => _isSingle = true),
                        ),
                        const SizedBox(width: 8),
                        _ModeChip(
                          label: '복합',
                          selected: !_isSingle,
                          onTap: () {
                            setState(() {
                              _isSingle = false;
                              if (_subControllers.isEmpty) _addSubLocation();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 상위 구역명
                    TextField(
                      controller: _locationController,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      textInputAction: TextInputAction.next,
                      style: TextStyle(color: cs.onSurface),
                      decoration: _inputDecoration(
                        context,
                        _isSingle ? '구역명' : '상위 구역명',
                        cs: cs,
                      ),
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
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: TextStyle(color: cs.onSurface),
                        decoration: _inputDecoration(
                          context,
                          '수용 가능 차량 수',
                          cs: cs,
                        ),
                      ),

                    // 복합 모드: 하위 구역 목록
                    if (!_isSingle)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '하위 구역',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._subControllers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final sub = entry.value;
                            return Padding(
                              key: ValueKey(sub), // 안정 키
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: sub.name,
                                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                                      textInputAction: TextInputAction.next,
                                      style: TextStyle(color: cs.onSurface),
                                      decoration: _inputDecoration(
                                        context,
                                        '하위 ${index + 1}',
                                        cs: cs,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: TextField(
                                      controller: sub.capacity,
                                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.next,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(4),
                                      ],
                                      style: TextStyle(color: cs.onSurface),
                                      decoration: _inputDecoration(
                                        context,
                                        '수용',
                                        cs: cs,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _removeSubLocation(index),
                                    icon: Icon(Icons.delete, color: cs.error),
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
                              icon: Icon(Icons.add, color: cs.primary),
                              label: Text(
                                '하위 구역 추가',
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '총 수용 차량: ${_calculateTotalSubCapacity()}대',
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withOpacity(.85),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 하단 액션
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cs.onSurface,
                              side: BorderSide(color: cs.outlineVariant.withOpacity(.75), width: 1.2),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const StadiumBorder(),
                            ),
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: const StadiumBorder(),
                              elevation: 2,
                              shadowColor: cs.primary.withOpacity(.25),
                            ),
                            child: const Text(
                              '저장',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ◀️ 11시 라벨
          _buildScreenTag(context),
        ],
      ),
    );
  }
}

/// 모드 토글 칩 (브랜드테마 반영)
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? cs.onPrimary : cs.onSurface,
        ),
      ),
      selected: selected,
      selectedColor: cs.primary,
      backgroundColor: cs.surfaceVariant.withOpacity(.45),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withOpacity(.65),
      ),
      showCheckmark: false,
      onSelected: (_) => onTap(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
