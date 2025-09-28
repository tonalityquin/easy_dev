import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../models/plate_model.dart';
import '../../../../../enums/plate_type.dart';
import '../parking_completed_status_bottom_sheet.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/parking_completed_plate_number_display.dart';
import 'widgets/parking_completed_plate_search_header.dart';
import 'widgets/parking_completed_plate_search_results.dart';
import 'widgets/parking_completed_search_button.dart';
import '../../../../../../repositories/plate_repo_services/firestore_plate_repository.dart';
import '../../../../../../states/plate/movement_plate.dart';
import '../../../../../../states/plate/delete_plate.dart';

class ParkingCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const ParkingCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<ParkingCompletedSearchBottomSheet> createState() => _ParkingCompletedSearchBottomSheetState();
}

class _ParkingCompletedSearchBottomSheetState extends State<ParkingCompletedSearchBottomSheet>
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
    _keypadController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
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
    setState(() {
      _isLoading = true;
    });

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
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')),
      );
    }
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const ParkingCompletedPlateSearchHeader(),
                      const SizedBox(height: 24),
                      ParkingCompletedPlateNumberDisplay(controller: _controller, isValidPlate: isValidPlate),
                      const SizedBox(height: 24),

                      Builder(
                        builder: (_) {
                          final text = _controller.text;
                          final valid = isValidPlate(text);

                          if (!_hasSearched) {
                            return const SizedBox.shrink();
                          }

                          if (_isLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (!valid) {
                            return const _EmptyState(text: '유효하지 않은 번호 형식입니다. (숫자 4자리)');
                          }

                          if (_results.isEmpty) {
                            return const _EmptyState(text: '검색 결과가 없습니다.');
                          }

                          return ParkingCompletedPlateSearchResults(
                            results: _results,
                            onSelect: (selected) {
                              if (_navigating) return;
                              _navigating = true;

                              Navigator.pop(context);

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                showParkingCompletedStatusBottomSheet(
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
                        },
                      ),

                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          final valid = isValidPlate(value.text);
                          return ParkingCompletedSearchButton(
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

                      const SizedBox(height: 16),
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
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
