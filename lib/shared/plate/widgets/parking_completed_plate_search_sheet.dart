import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/mode_double/parking_completed_package/widgets/double_parking_completed_plate_search_results.dart';
import '../../../features/mode_double/parking_completed_package/widgets/double_parking_completed_status_bottom_sheet.dart';
import '../../../features/mode_minor/parking_completed_package/widgets/minor_parking_completed_plate_search_results.dart';
import '../../../features/mode_minor/parking_completed_package/widgets/minor_parking_completed_status_bottom_sheet.dart';
import '../../../features/mode_triple/parking_completed_package/widgets/triple_parking_completed_plate_search_results.dart';
import '../../../features/mode_triple/parking_completed_package/widgets/triple_parking_completed_status_bottom_sheet.dart';
import '../application/common/delete_plate.dart';
import '../application/common/movement_plate.dart';
import '../domain/enums/plate_type.dart';
import '../domain/models/plate_model.dart';
import '../domain/models/plate_out_log_search_result.dart';
import '../domain/repositories/plate_repository.dart';
import 'plate_out_log_search_results.dart';
import 'plate_remove_dialog.dart';
import 'plate_search_mode_switch.dart';

enum ParkingCompletedSearchVariant { minor, double, triple }

class ParkingCompletedPlateSearchSheet extends StatefulWidget {
  final String area;
  final ParkingCompletedSearchVariant variant;
  final void Function(String)? onSearch;

  const ParkingCompletedPlateSearchSheet({
    super.key,
    required this.area,
    required this.variant,
    this.onSearch,
  });

  @override
  State<ParkingCompletedPlateSearchSheet> createState() =>
      _ParkingCompletedPlateSearchSheetState();
}

class _ParkingCompletedPlateSearchSheetState
    extends State<ParkingCompletedPlateSearchSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false;
  PlateSearchMode _searchMode = PlateSearchMode.plates;

  List<PlateModel> _results = [];
  List<PlateOutLogSearchResult> _outLogResults = [];

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
    ).animate(
      CurvedAnimation(parent: _keypadController, curve: Curves.easeOut),
    );
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

  bool _isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value.trim());

  void _completeSearch({
    List<PlateModel>? results,
    List<PlateOutLogSearchResult>? outLogResults,
  }) {
    if (!mounted) return;
    setState(() {
      _results = results ?? <PlateModel>[];
      _outLogResults = outLogResults ?? <PlateOutLogSearchResult>[];
      _hasSearched = true;
      _isLoading = false;
    });
  }

  void _finishLoadingAsSearched() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasSearched = true;
    });
  }

  void _resetSearch() {
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _hasSearched = false;
      _results.clear();
      _outLogResults.clear();
      _navigating = false;
      _isLoading = false;
    });
  }

  void _setSearchMode(PlateSearchMode mode) {
    if (!mounted || _searchMode == mode || _isLoading) return;
    setState(() {
      _searchMode = mode;
      _hasSearched = false;
      _results.clear();
      _outLogResults.clear();
      _navigating = false;
    });
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted || _isLoading) return;

    final q = _controller.text.trim();
    final area = widget.area.trim();
    final mode = _searchMode;

    if (!_isValidPlate(q) || area.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final repository = context.read<PlateRepository>();

      if (mode == PlateSearchMode.plateOutLog) {
        final results = await repository.searchPlateOutLogsByFourDigit(
          plateFourDigit: q,
          area: area,
        );

        if (!mounted) return;
        if (_searchMode != mode) {
          setState(() => _isLoading = false);
          return;
        }

        _completeSearch(outLogResults: results);
        return;
      }

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
      if (_searchMode != mode) {
        setState(() => _isLoading = false);
        return;
      }

      _completeSearch(results: filtered);
    } catch (_) {
      _finishLoadingAsSearched();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('검색 중 오류가 발생했습니다.')),
      );
    }
  }

  Future<bool> _showDeleteDialog(
      BuildContext rootContext,
      PlateModel selected,
      ) async {
    final deleter = rootContext.read<DeletePlate>();

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
      final performedBy = widget.variant == ParkingCompletedSearchVariant.minor
          ? null
          : rootContext.read<UserState>().name;

      if (t == PlateType.parkingRequests) {
        if (performedBy == null) {
          await deleter.deleteFromParkingRequest(
            selected.plateNumber,
            selected.area,
          );
        } else {
          await deleter.deleteFromParkingRequest(
            selected.plateNumber,
            selected.area,
            performedBy: performedBy,
          );
        }
      } else if (t == PlateType.parkingCompleted) {
        if (performedBy == null) {
          await deleter.deleteFromParkingCompleted(
            selected.plateNumber,
            selected.area,
          );
        } else {
          await deleter.deleteFromParkingCompleted(
            selected.plateNumber,
            selected.area,
            performedBy: performedBy,
          );
        }
      } else if (t == PlateType.departureRequests) {
        if (performedBy == null) {
          await deleter.deleteFromDepartureRequest(
            selected.plateNumber,
            selected.area,
          );
        } else {
          await deleter.deleteFromDepartureRequest(
            selected.plateNumber,
            selected.area,
            performedBy: performedBy,
          );
        }
      } else {
        return false;
      }

      await _refreshSearchResults();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openStatusBottomSheet(
      BuildContext rootContext,
      PlateModel selected,
      ) async {
    Future<void> onRequestEntry() async {
      if (selected.typeEnum != PlateType.parkingCompleted) return;

      await rootContext.read<MovementPlate>().goBackToParkingRequest(
        fromType: PlateType.parkingCompleted,
        plateNumber: selected.plateNumber,
        area: selected.area,
        newLocation: '미지정',
      );

      await _refreshSearchResults();
    }

    Future<bool> onDelete() => _showDeleteDialog(rootContext, selected);

    switch (widget.variant) {
      case ParkingCompletedSearchVariant.minor:
        await showMinorParkingCompletedStatusBottomSheet(
          context: rootContext,
          plate: selected,
          onRequestEntry: onRequestEntry,
          onDelete: onDelete,
        );
        return;
      case ParkingCompletedSearchVariant.double:
        await showDoubleParkingCompletedStatusBottomSheet(
          context: rootContext,
          plate: selected,
          onRequestEntry: onRequestEntry,
          onDelete: onDelete,
        );
        return;
      case ParkingCompletedSearchVariant.triple:
        await showTripleParkingCompletedStatusBottomSheet(
          context: rootContext,
          plate: selected,
          onRequestEntry: onRequestEntry,
          onDelete: onDelete,
        );
        return;
    }
  }

  Widget _buildPlateResults(BuildContext rootContext) {
    Future<void> onSelect(PlateModel selected) async {
      if (_navigating) return;
      setState(() => _navigating = true);

      try {
        await _openStatusBottomSheet(rootContext, selected);
      } finally {
        if (!mounted) return;
        setState(() => _navigating = false);
      }
    }

    switch (widget.variant) {
      case ParkingCompletedSearchVariant.minor:
        return MinorParkingCompletedPlateSearchResults(
          results: _results,
          onSelect: onSelect,
        );
      case ParkingCompletedSearchVariant.double:
        return DoubleParkingCompletedPlateSearchResults(
          results: _results,
          onSelect: onSelect,
        );
      case ParkingCompletedSearchVariant.triple:
        return TripleParkingCompletedPlateSearchResults(
          results: _results,
          onSelect: onSelect,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 1.0,
          maxChildSize: 1.0,
          expand: true,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: Column(
                  children: [
                    SizedBox(height: topInset + 10),
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
                          const Expanded(child: _SearchHeader()),
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
                          PlateSearchModeSwitch(
                            value: _searchMode,
                            onChanged: _setSearchMode,
                          ),
                          const SizedBox(height: 12),
                          _CardSection(
                            title: '번호 4자리 입력',
                            subtitle: '예: 1234',
                            child: _PlateNumberDisplay(
                              controller: _controller,
                              isValidPlate: _isValidPlate,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: _buildResultSection(rootContext),
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
                          final valid = _isValidPlate(value.text);
                          return _SearchButton(
                            isValid: valid,
                            isLoading: _isLoading,
                            onPressed: valid
                                ? () async {
                              await _refreshSearchResults();
                              widget.onSearch?.call(value.text.trim());
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
          : _AnimatedSearchKeypad(
        slideAnimation: _slideAnimation,
        fadeAnimation: _fadeAnimation,
        controller: _controller,
        maxLength: 4,
        onComplete: () => setState(() {}),
        onReset: _resetSearch,
      ),
    );
  }

  Widget _buildResultSection(BuildContext rootContext) {
    final cs = Theme.of(context).colorScheme;
    final text = _controller.text.trim();
    final valid = _isValidPlate(text);

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

    if (_searchMode == PlateSearchMode.plateOutLog) {
      if (_outLogResults.isEmpty) {
        return const _EmptyState(
          icon: Icons.search_off,
          title: '검색 결과 없음',
          message: '저장된 출차 로그 문서를 찾지 못했습니다.',
          tone: _EmptyTone.neutral,
        );
      }

      return PlateOutLogSearchResults(results: _outLogResults);
    }

    if (_results.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: '검색 결과 없음',
        message: '해당 4자리 번호판을 찾지 못했습니다.',
        tone: _EmptyTone.neutral,
      );
    }

    return _buildPlateResults(rootContext);
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(Icons.directions_car, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          '번호판 검색',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
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

class _PlateNumberDisplay extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const _PlateNumberDisplay({
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final text = value.text;
        final valid = isValidPlate(text);
        final Color tone = text.isEmpty
            ? cs.onSurfaceVariant
            : (valid ? cs.tertiary : cs.error);
        final Color border = text.isEmpty
            ? cs.outlineVariant.withOpacity(0.70)
            : (valid ? cs.tertiary.withOpacity(0.55) : cs.error.withOpacity(0.55));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(4, (i) {
                final char = (i < text.length) ? text[i] : '';
                final filled = char.isNotEmpty;

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: filled ? cs.surface : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        char.isEmpty ? '•' : char,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: char.isEmpty
                              ? cs.onSurfaceVariant.withOpacity(0.45)
                              : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              opacity: text.isEmpty ? 0.9 : 1,
              duration: const Duration(milliseconds: 180),
              child: Row(
                children: [
                  Icon(
                    text.isEmpty
                        ? Icons.edit
                        : (valid ? Icons.check_circle_outline : Icons.error_outline),
                    size: 16,
                    color: tone,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text.isEmpty
                          ? '숫자 4자리를 입력해주세요.'
                          : (valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.'),
                      style: TextStyle(
                        color: tone,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (text.isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.primary.withOpacity(0.90)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '키패드로 4자리를 입력하면 검색할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary.withOpacity(0.90),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SearchButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SearchButton({
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = isValid && !isLoading;
    final Color bg = enabled ? cs.primary : cs.surfaceContainerHighest;
    final Color fg = enabled ? cs.onPrimary : cs.onSurfaceVariant;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.search, size: 18),
            SizedBox(width: 8),
            Text(
              '검색',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSearchKeypad extends StatelessWidget {
  final Animation<Offset> slideAnimation;
  final Animation<double> fadeAnimation;
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;

  const _AnimatedSearchKeypad({
    required this.slideAnimation,
    required this.fadeAnimation,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SlideTransition(
      position: slideAnimation,
      child: FadeTransition(
        opacity: fadeAnimation,
        child: Material(
          color: cs.surface,
          elevation: 18,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _NumKeypadForPlateSearch(
                controller: controller,
                maxLength: maxLength,
                onComplete: onComplete,
                onReset: onReset,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumKeypadForPlateSearch extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;

  const _NumKeypadForPlateSearch({
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(context, const ['1', '2', '3']),
        const SizedBox(height: 8),
        _buildRow(context, const ['4', '5', '6']),
        const SizedBox(height: 8),
        _buildRow(context, const ['7', '8', '9']),
        const SizedBox(height: 8),
        _buildRow(context, const ['처음', '0', '처음']),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<String> keys) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          Expanded(child: _buildKey(context, keys[i])),
          if (i != keys.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildKey(BuildContext context, String key) {
    final cs = Theme.of(context).colorScheme;
    final reset = key == '처음';

    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: () => _handleKey(key),
        style: ElevatedButton.styleFrom(
          backgroundColor: reset ? cs.surfaceContainerHighest : cs.surface,
          foregroundColor: reset ? cs.onSurfaceVariant : cs.onSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
          ),
        ),
        child: Text(
          key,
          style: TextStyle(
            fontSize: reset ? 14 : 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  void _handleKey(String key) {
    if (key == '처음') {
      controller.clear();
      onReset?.call();
      return;
    }

    if (controller.text.length < maxLength) {
      controller.text += key;
      if (controller.text.length == maxLength) {
        Future.microtask(() => onComplete?.call());
      }
    }
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
