import 'package:flutter/material.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/plate_number_display.dart';
import 'widgets/plate_search_header.dart';
import 'widgets/plate_search_results.dart';
import 'widgets/search_button.dart';

class PlateSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;

  const PlateSearchBottomSheet({
    super.key,
    required this.onSearch,
  });

  @override
  State<PlateSearchBottomSheet> createState() => _PlateSearchBottomSheetState();

  /// 커스텀 애니메이션으로 표시
  static Future<void> show(BuildContext context, void Function(String) onSearch) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '닫기',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: PlateSearchBottomSheet(onSearch: onSearch),
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

class _PlateSearchBottomSheetState extends State<PlateSearchBottomSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _hasSearched = false;

  late AnimationController _keypadController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  final List<String> _dummyResults = [
    '12가 1234',
    '34나 1234',
    '56다 1234',
  ];

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

    // 키패드 애니메이션 시작
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
                      PlateSearchResults(
                        results: _dummyResults,
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
                          onPressed: () async {
                            setState(() {
                              _isLoading = true;
                            });
                            await Future.delayed(const Duration(milliseconds: 300));
                            widget.onSearch(value.text);
                            setState(() {
                              _hasSearched = true;
                              _isLoading = false;
                            });
                          },
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
                  });
                },
              ),
      ),
    );
  }
}
