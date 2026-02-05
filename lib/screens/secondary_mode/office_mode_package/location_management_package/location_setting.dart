import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'location_draft.dart';

class LocationSettingBottomSheet extends StatefulWidget {
  final ValueChanged<LocationDraft> onSave;

  /// ✅ 현재 area에서 이미 사용 중인 주차 구역명(단일 + 복합 자식)을
  /// 정규화하여(lowercase + trim + 다중 공백 축약) 보관한 집합
  /// - 빠른 UX용(로컬) 검증
  /// - 최종 검증은 LocationState가 Firestore 기준으로 다시 수행
  final Set<String> existingNameKeysInArea;

  const LocationSettingBottomSheet({
    super.key,
    required this.onSave,
    required this.existingNameKeysInArea,
  });

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

  // ✅ 이름 정규화 규칙(상태 레이어와 동일)
  String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

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

  // ---------- 검증/파싱 ----------

  void _setError(String msg) => setState(() => _errorMessage = msg);

  void _clearError() => setState(() => _errorMessage = null);

  /// ✅ 현재 입력값을 기반으로 "저장 가능한 draft"를 만들고,
  /// 실패 시 에러 메시지를 세팅한 뒤 null 반환.
  LocationDraft? _tryBuildDraft() {
    final parent = _normalizeName(_locationController.text);
    final parentKey = _nameKey(parent);

    if (parent.isEmpty) {
      _setError('구역명을 입력하세요.');
      return null;
    }

    if (_isSingle) {
      final capText = _capacityController.text.trim();
      final cap = int.tryParse(capText);

      if (cap == null || cap <= 0) {
        _setError('1 이상의 유효한 수용 대수를 입력하세요.');
        return null;
      }

      if (widget.existingNameKeysInArea.contains(parentKey)) {
        _setError('이미 사용 중인 주차 구역명입니다: "$parent"');
        return null;
      }

      _clearError();
      return SingleLocationDraft(name: parent, capacity: cap);
    }

    // ---------------- 복합 모드 ----------------
    // 규칙:
    // - 완전히 빈 줄(name/cap 모두 빈값)은 무시
    // - name 또는 cap 둘 중 하나만 입력된 줄은 오류
    // - cap은 1 이상
    // - 하위 이름 중복 금지(대소문자/공백 차이 무시)
    final subs = <CompositeSubDraft>[];
    final seen = <String>{};

    for (final c in _subControllers) {
      final rawName = c.name.text;
      final rawCap = c.capacity.text.trim();

      final name = _normalizeName(rawName);
      final hasAnyInput = name.isNotEmpty || rawCap.isNotEmpty;

      if (!hasAnyInput) continue;

      if (name.isEmpty) {
        _setError('하위 구역명을 입력하세요.');
        return null;
      }

      final cap = int.tryParse(rawCap);
      if (cap == null || cap <= 0) {
        _setError('하위 구역 "$name"의 수용 대수는 1 이상이어야 합니다.');
        return null;
      }

      final key = _nameKey(name);
      if (seen.contains(key)) {
        _setError('하위 구역명 "$name"이(가) 중복되어 있습니다.');
        return null;
      }
      seen.add(key);

      subs.add(CompositeSubDraft(name: name, capacity: cap));
    }

    if (subs.isEmpty) {
      _setError('상위 구역명과 1개 이상 유효한 하위 구역이 필요합니다.');
      return null;
    }

    if (seen.contains(parentKey)) {
      _setError('상위 구역명 "$parent"은 하위 구역명과 같을 수 없습니다.');
      return null;
    }

    // ✅ 기존 데이터와 중복(단일 + 복합 자식) 금지
    final conflicts = <String>[];
    if (widget.existingNameKeysInArea.contains(parentKey)) {
      conflicts.add(parent);
    }
    for (final s in subs) {
      if (widget.existingNameKeysInArea.contains(_nameKey(s.name))) {
        conflicts.add(s.name);
      }
    }
    if (conflicts.isNotEmpty) {
      final uniq = conflicts.toSet().toList();
      _setError('이미 사용 중인 주차 구역명이 있습니다: ${uniq.join(', ')}');
      return null;
    }

    _clearError();
    return CompositeLocationDraft(parent: parent, subs: subs);
  }

  int _previewTotalSubCapacity() {
    int total = 0;
    for (final c in _subControllers) {
      final name = _normalizeName(c.name.text);
      final cap = int.tryParse(c.capacity.text.trim());
      if (name.isEmpty || cap == null || cap <= 0) continue;
      total += cap;
    }
    return total;
  }

  // ---------- 하위 구역 편집 ----------

  void _addSubLocation() {
    final name = TextEditingController();
    final capacity = TextEditingController();

    // 입력 시 합계/검증 UI 실시간 갱신
    name.addListener(() => setState(() {}));
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

    final draft = _tryBuildDraft();
    if (draft == null) return;

    widget.onSave(draft);
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
                            '총 수용 차량: ${_previewTotalSubCapacity()}대',
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
