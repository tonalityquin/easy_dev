import 'package:flutter/material.dart';
import '../../../models/plate_model.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/plate_number_display.dart';
import 'widgets/plate_search_header.dart';
import 'widgets/plate_search_results.dart';
import 'widgets/search_button.dart';

// FirestorePlateRepository import
import '../../../repositories/plate/firestore_plate_repository.dart';

class CommonPlateSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const CommonPlateSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<CommonPlateSearchBottomSheet> createState() => _CommonPlateSearchBottomSheetState();

  static Future<void> show(
    BuildContext context,
    void Function(String) onSearch,
    String area,
  ) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: CommonPlateSearchBottomSheet(
            onSearch: onSearch,
            area: area,
          ),
        );
      },
      transitionBuilder: (_, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuint,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
    );
  }
}

class _CommonPlateSearchBottomSheetState extends State<CommonPlateSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;
  List<PlateModel> _results = [];

  late AnimationController _keypadController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _keypadController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _keypadController,
        curve: Curves.easeOut,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _keypadController,
      curve: Curves.easeIn,
    );

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

  @override
  Widget build(BuildContext context) {
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
                    const PlateSearchHeader(),
                    const SizedBox(height: 24),
                    PlateNumberDisplay(
                      controller: _controller,
                      isValidPlate: isValidPlate,
                    ),
                    const SizedBox(height: 24),
                    if (_hasSearched)
                      _results.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  '유효하지 않은 번호입니다.',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            )
                          : PlateSearchResults(
                              results: _results, // ✅ 그대로 넘기기
                              onSelect: (selected) {
                                Navigator.pop(context);
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
                        return SearchButton(
                          isValid: valid,
                          isLoading: _isLoading,
                          onPressed: valid
                              ? () async {
                                  setState(() {
                                    _isLoading = true;
                                  });

                                  try {
                                    final repository = FirestorePlateRepository();

                                    final results = await repository.fourDigitCommonQuery(
                                      plateFourDigit: value.text,
                                      area: widget.area, // 하드코딩 제거
                                    );

                                    setState(() {
                                      _results = results;
                                      _hasSearched = true;
                                      _isLoading = false;
                                    });

                                    widget.onSearch(value.text);
                                  } catch (e) {
                                    setState(() {
                                      _isLoading = false;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('검색 중 오류가 발생했습니다: $e'),
                                      ),
                                    );
                                  }
                                }
                              : null,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
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
                onComplete: () {
                  setState(() {});
                },
                onReset: () {
                  setState(() {
                    _controller.clear();
                    _hasSearched = false;
                    _results.clear();
                  });
                },
              ),
      ),
    );
  }
}
