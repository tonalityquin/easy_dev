import 'package:flutter/material.dart';
import 'keypad/num_keypad.dart'; // NumKeypad 경로에 맞게 수정

class PlateSearchDialog extends StatefulWidget {
  final void Function(String) onSearch;

  const PlateSearchDialog({
    super.key,
    required this.onSearch,
  });

  @override
  State<PlateSearchDialog> createState() => _PlateSearchDialogState();

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
          child: PlateSearchDialog(onSearch: onSearch),
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

class _PlateSearchDialogState extends State<PlateSearchDialog> with SingleTickerProviderStateMixin {
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
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

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
                    Row(
                      children: [
                        Icon(Icons.directions_car, color: primary),
                        const SizedBox(width: 8),
                        const Text(
                          '번호판 검색',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, child) {
                        final valid = isValidPlate(value.text);
                        return AnimatedOpacity(
                          opacity: value.text.isEmpty ? 0.4 : 1,
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            value.text.isEmpty ? '번호 입력 대기 중' : value.text,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w500,
                              color: valid ? Colors.black : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, child) {
                        final valid = isValidPlate(value.text);
                        if (value.text.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.',
                          style: TextStyle(
                            color: valid ? Colors.green : Colors.red,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    if (_hasSearched) ...[
                      const Text(
                        '검색 결과',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _dummyResults.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          return ListTile(
                            leading: const Icon(Icons.directions_car),
                            title: Text(_dummyResults[index]),
                            onTap: () {
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
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
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: valid && !_isLoading
                                ? () async {
                              setState(() {
                                _isLoading = true;
                              });
                              await Future.delayed(const Duration(milliseconds: 300));
                              widget.onSearch(value.text);
                              setState(() {
                                _hasSearched = true;
                                _isLoading = false;
                              });
                            }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: valid ? primary : Colors.grey.shade300,
                              foregroundColor: valid ? onPrimary : Colors.black45,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                                : const Text(
                              '검색',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ),
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
            : FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: NumKeypad(
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
          ),
        ),
      ),
    );
  }
}
