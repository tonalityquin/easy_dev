import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../features/account/applications/user_state.dart';
import '../../../../../../shared/plate/application/common/delete_plate.dart';
import '../../../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../../../shared/plate/widgets/plate_remove_dialog.dart';
import  '../triple_parking_completed_status_bottom_sheet.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/triple_parking_completed_plate_number_display.dart';
import 'widgets/triple_parking_completed_plate_search_header.dart';
import 'widgets/triple_parking_completed_plate_search_results.dart';
import 'widgets/triple_parking_completed_search_button.dart';

class TripleParkingCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const TripleParkingCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<TripleParkingCompletedSearchBottomSheet> createState() =>
      _TripleParkingCompletedSearchBottomSheetState();
}

class _TripleParkingCompletedSearchBottomSheetState
    extends State<TripleParkingCompletedSearchBottomSheet>
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
    _keypadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation =
        CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value.trim());

  void _resetSearch() {
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _hasSearched = false;
      _results.clear();
      _navigating = false;
      _isLoading = false;
    });
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted) return;
    if (_isLoading) return;

    final q = _controller.text.trim();
    final area = widget.area.trim();

    if (!isValidPlate(q)) {
      return;
    }

    if (area.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = context.read<PlateRepository>();

      final results = await repository.fourDigitCommonQuery(
        plateFourDigit: q,
        area: area,
      );

      final allowedTypes = <String>{
        PlateType.parkingRequests.firestoreValue,
        PlateType.parkingCompleted.firestoreValue,
        PlateType.departureRequests.firestoreValue,
      };

      final filtered =
      results.where((p) => allowedTypes.contains(p.type)).toList();

      if (!mounted) return;
      setState(() {
        _results = filtered;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showDeleteDialog(
      BuildContext rootContext,
      PlateModel selected,
      ) async {
    final deleter = rootContext.read<DeletePlate>();
    final performedBy = rootContext.read<UserState>().name;

    final confirmed = await showDialog<bool>(
      context: rootContext,
      useRootNavigator: true,
      builder: (dialogContext) => PlateRemoveDialog(
        onConfirm: () {
          Navigator.of(dialogContext).pop(true);
        },
      ),
    ) ??
        false;

    if (!confirmed) return false;

    try {
      final t = selected.typeEnum;

      if (t == PlateType.parkingRequests) {
        await deleter.deleteFromParkingRequest(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      } else if (t == PlateType.parkingCompleted) {
        await deleter.deleteFromParkingCompleted(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      } else if (t == PlateType.departureRequests) {
        await deleter.deleteFromDepartureRequest(
          selected.plateNumber,
          selected.area,
          performedBy: performedBy,
        );
      } else {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _openStatusBottomSheet(
      BuildContext rootContext,
      PlateModel selected,
      ) async {
    Future<void> onRequestEntry() async {
      if (selected.typeEnum != PlateType.parkingCompleted) {
        return;
      }

      await rootContext.read<MovementPlate>().goBackToParkingRequest(
        fromType: PlateType.parkingCompleted,
        plateNumber: selected.plateNumber,
        area: selected.area,
        newLocation: '미지정',
      );

      await _refreshSearchResults();
    }

    Future<bool> onDelete() async {
      final deleted = await _showDeleteDialog(rootContext, selected);
      if (deleted) {
        await _refreshSearchResults();
      }
      return deleted;
    }

    await showTripleParkingCompletedStatusBottomSheet(
      context: rootContext,
      plate: selected,
      onRequestEntry: onRequestEntry,
      onDelete: onDelete,
    );
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
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                child: ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Expanded(
                              child: TripleParkingCompletedPlateSearchHeader(),
                            ),
                            if (_hasSearched)
                              TextButton.icon(
                                onPressed: _isLoading ? null : _resetSearch,
                                icon: Icon(Icons.refresh, color: cs.primary),
                                label: Text(
                                  '다시 검색',
                                  style: TextStyle(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
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
                              child: TripleParkingCompletedPlateNumberDisplay(
                                controller: _controller,
                                isValidPlate: isValidPlate,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: _buildResultSection(
                                rootContext,
                                scrollController,
                              ),
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
                            return TripleParkingCompletedSearchButton(
                              isValid: valid,
                              isLoading: _isLoading,
                              onPressed: valid
                                  ? () async {
                                await _refreshSearchResults();
                                widget.onSearch(value.text.trim());
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
          onReset: _resetSearch,
        ),
      ),
    );
  }

  Widget _buildResultSection(
      BuildContext rootContext,
      ScrollController scrollController,
      ) {
    final cs = Theme.of(context).colorScheme;
    final text = _controller.text.trim();
    final valid = isValidPlate(text);

    if (!_hasSearched) return const SizedBox.shrink();

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

    return TripleParkingCompletedPlateSearchResults(
      results: _results,
      onSelect: (selected) async {
        if (_navigating) return;
        setState(() => _navigating = true);

        try {
          await _openStatusBottomSheet(rootContext, selected);
        } finally {
          if (!mounted) return;
          setState(() => _navigating = false);
        }
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
                decoration:
                BoxDecoration(color: cs.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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

    final Color fg =
    (tone == _EmptyTone.danger) ? cs.error : cs.onSurfaceVariant;
    final Color bg = (tone == _EmptyTone.danger)
        ? cs.errorContainer.withOpacity(0.6)
        : cs.surfaceContainerLow;

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
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: fg.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
