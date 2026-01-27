import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../models/plate_model.dart';
import '../../../../../../enums/plate_type.dart';
import '../double_parking_completed_status_bottom_sheet.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/double_parking_completed_plate_number_display.dart';
import 'widgets/double_parking_completed_plate_search_header.dart';
import 'widgets/double_parking_completed_plate_search_results.dart';
import 'widgets/double_parking_completed_search_button.dart';
import '../../../../../../repositories/plate_repo_services/firestore_plate_repository.dart';
import '../../../../../../states/plate/movement_plate.dart';
import '../../../../../../states/plate/delete_plate.dart';

class DoubleParkingCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const DoubleParkingCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<DoubleParkingCompletedSearchBottomSheet> createState() =>
      _DoubleParkingCompletedSearchBottomSheetState();
}

class _DoubleParkingCompletedSearchBottomSheetState
    extends State<DoubleParkingCompletedSearchBottomSheet>
    with SingleTickerProviderStateMixin {
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
      final repository = FirestorePlateRepository();

      final results = await repository.fourDigitSignatureQuery(
        plateFourDigit: _controller.text,
        area: widget.area,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                            color: cs.outlineVariant.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Expanded(child: DoubleParkingCompletedPlateSearchHeader()),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close, color: cs.onSurface),
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
                            _CardSection(
                              title: '번호 4자리 입력',
                              subtitle: '예: 1234',
                              child: DoubleParkingCompletedPlateNumberDisplay(
                                controller: _controller,
                                isValidPlate: isValidPlate,
                              ),
                            ),
                            const SizedBox(height: 12),
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

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            final valid = isValidPlate(value.text);
                            return DoubleParkingCompletedSearchButton(
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
    final cs = Theme.of(context).colorScheme;
    final text = _controller.text;
    final valid = isValidPlate(text);

    if (!_hasSearched) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
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

    return DoubleParkingCompletedPlateSearchResults(
      results: _results,
      onSelect: (selected) {
        if (_navigating) return;
        _navigating = true;

        Navigator.pop(context);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDoubleParkingCompletedStatusBottomSheet(
            context: rootContext,
            plate: selected,
            onRequestEntry: () async {
              await rootContext.read<MovementPlate>().goBackToParkingRequest(
                fromType: PlateType.parkingCompleted,
                plateNumber: selected.plateNumber,
                area: selected.area,
                newLocation: "미지정",
              );
              await _refreshSearchResults();
            },
            onDelete: () async {
              await rootContext.read<DeletePlate>().deleteFromParkingCompleted(
                selected.plateNumber,
                selected.area,
              );
              await _refreshSearchResults();
            },
          );
        });
      },
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _CardSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
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
                decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
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
    final cs = Theme.of(context).colorScheme;

    final Color fg = (tone == _EmptyTone.danger) ? cs.error : cs.onSurfaceVariant;
    final Color bg = (tone == _EmptyTone.danger) ? cs.errorContainer.withOpacity(0.6) : cs.surfaceContainerLow;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(color: fg.withOpacity(0.9), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
