import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../models/plate_model.dart';
import '../../../../../../enums/plate_type.dart';
import '../../../../../../repositories/plate_repo_services/plate_repository.dart';

// ✅ 삭제/복귀용
import '../../../../../../states/plate/delete_plate.dart';
import '../../../../../../states/plate/movement_plate.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import '../../../../../../widgets/dialog/plate_remove_dialog.dart';

// ✅ 기존 상태 바텀시트(새 바텀시트 X)
import '../normal_parking_completed_status_bottom_sheet.dart';

import 'keypad/animated_keypad.dart';
import 'widgets/normal_parking_completed_plate_number_display.dart';
import 'widgets/normal_parking_completed_plate_search_header.dart';
import 'widgets/normal_parking_completed_plate_search_results.dart';
import 'widgets/normal_parking_completed_search_button.dart';

class NormalParkingCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const NormalParkingCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<NormalParkingCompletedSearchBottomSheet> createState() =>
      _NormalParkingCompletedSearchBottomSheetState();
}

class _NormalParkingCompletedSearchBottomSheetState
    extends State<NormalParkingCompletedSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  // ✅ 요청 팔레트 (BlueGrey)
  static const Color _base = Color(0xFF546E7A); // BlueGrey 600
  static const Color _dark = Color(0xFF37474F); // BlueGrey 800

  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false;

  List<PlateModel> _results = [];

  late AnimationController _keypadController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _keypadController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation = CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool isValidPlate(String value) {
    return RegExp(r'^\d{4}$').hasMatch(value);
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final repository = context.read<PlateRepository>();

      // ✅ 기존 signatureQuery(입차완료 고정) → commonQuery(타입 전체)
      final results = await repository.fourDigitCommonQuery(
        plateFourDigit: _controller.text.trim(),
        area: widget.area.trim(),
      );

      // ✅ Normal 모드 요구 범위만: 입차요청 / 입차완료 / 출차요청
      final allowedTypes = <String>{
        PlateType.parkingRequests.firestoreValue,
        PlateType.parkingCompleted.firestoreValue,
        PlateType.departureRequests.firestoreValue,
      };

      final filtered = results.where((p) => allowedTypes.contains(p.type)).toList();

      if (!mounted) return;
      setState(() {
        _results = filtered;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')),
      );
    }
  }

  void _openStatusBottomSheet(BuildContext rootContext, PlateModel selected) {
    // ✅ 기존 상태 바텀시트에 필요한 콜백 구성
    Future<void> onRequestEntry() async {
      // 이 동작은 기존 앱 의미상 parking_completed에서만 유효하므로 그때만 수행
      if (selected.typeEnum != PlateType.parkingCompleted) return;

      final movement = rootContext.read<MovementPlate>();
      await movement.goBackToParkingRequest(
        fromType: PlateType.parkingCompleted,
        plateNumber: selected.plateNumber,
        area: selected.area,
        newLocation: "미지정",
      );
    }

    void onDelete() {
      showDialog(
        context: rootContext,
        builder: (_) => PlateRemoveDialog(
          onConfirm: () {
            final deleter = rootContext.read<DeletePlate>();
            final performedBy = rootContext.read<UserState>().name;
            final t = selected.typeEnum;

            Future<void> f;
            if (t == PlateType.parkingRequests) {
              f = deleter.deleteFromParkingRequest(
                selected.plateNumber,
                selected.area,
                performedBy: performedBy,
              );
            } else if (t == PlateType.parkingCompleted) {
              f = deleter.deleteFromParkingCompleted(
                selected.plateNumber,
                selected.area,
                performedBy: performedBy,
              );
            } else if (t == PlateType.departureRequests) {
              f = deleter.deleteFromDepartureRequest(
                selected.plateNumber,
                selected.area,
                performedBy: performedBy,
              );
            } else {
              showFailedSnackbar(rootContext, '이 상태에서는 삭제할 수 없습니다.');
              return;
            }

            f.then((_) {
              showSuccessSnackbar(rootContext, "삭제 완료: ${selected.plateNumber}");
            }).catchError((e) {
              showFailedSnackbar(rootContext, "삭제 실패: $e");
            });
          },
        ),
      );
    }

    showNormalParkingCompletedStatusBottomSheet(
      context: rootContext,
      plate: selected,
      onRequestEntry: onRequestEntry,
      onDelete: onDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: Colors.transparent,
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 상단 헤더(닫기 버튼 포함)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Expanded(child: NormalParkingCompletedPlateSearchHeader()),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close, color: _dark),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          children: [
                            // 입력 카드
                            _CardSection(
                              title: '번호 4자리 입력',
                              subtitle: '예: 1234',
                              accent: _base,
                              child: NormalParkingCompletedPlateNumberDisplay(
                                // ✅ 프로젝트 실제 시그니처: controller/isValidPlate 필수
                                controller: _controller,
                                isValidPlate: isValidPlate,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // 결과 영역
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: _buildResultSection(rootContext, scrollController),
                            ),

                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                      // 하단 CTA (검색 버튼)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            final valid = isValidPlate(value.text);
                            return NormalParkingCompletedSearchButton(
                              isValid: valid,
                              isLoading: _isLoading,
                              onPressed: valid
                                  ? () async {
                                await _refreshSearchResults();
                                widget.onSearch(value.text);
                              }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // ✅ 키패드(검색 전만 노출) — 프로젝트 AnimatedKeypad 시그니처에 맞춤
        bottomNavigationBar: _hasSearched
            ? const SizedBox.shrink()
            : AnimatedKeypad(
          slideAnimation: _slideAnimation,
          fadeAnimation: _fadeAnimation,
          controller: _controller,
          maxLength: 4,
          enableDigitModeSwitch: false,
          onComplete: () => setState(() {}),
          onReset: () => setState(() {
            _controller.clear();
            _hasSearched = false;
            _results.clear();
          }),
        ),
      ),
    );
  }

  Widget _buildResultSection(BuildContext rootContext, ScrollController scrollController) {
    final text = _controller.text;
    final valid = isValidPlate(text);

    if (!_hasSearched) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!valid) {
      return const _EmptyState(
        icon: Icons.error_outline,
        title: '유효하지 않은 번호 형식',
        message: '숫자 4자리를 입력해주세요.',
        tone: _EmptyTone.danger,
      );
    }

    if (_results.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: '검색 결과 없음',
        message: '해당 4자리 번호판을 찾지 못했습니다.',
        tone: _EmptyTone.neutral,
      );
    }

    return NormalParkingCompletedPlateSearchResults(
      results: _results,
      onSelect: (selected) {
        if (_navigating) return;
        _navigating = true;

        // ✅ 검색 바텀시트 닫고, "기존 상태 바텀시트"를 바로 오픈
        Navigator.pop(context);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openStatusBottomSheet(rootContext, selected);
        });
      },
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;

  const _CardSection({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum _EmptyTone { neutral, danger }

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final _EmptyTone tone;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = (tone == _EmptyTone.danger) ? Colors.redAccent : Colors.black54;
    final Color bg =
    (tone == _EmptyTone.danger) ? Colors.red.withOpacity(0.05) : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: fg.withOpacity(0.85), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
