import 'package:flutter/material.dart';

import '../../../../shared/plate/data/repositories/firestore_plate_repository.dart';
import '../widgets/keypad/personal_animated_keypad.dart';
import '../widgets/personal_plate_number_display_section.dart';
import '../widgets/personal_plate_search_header_section.dart';
import '../dialogs/personal_plate_search_dialog.dart';

class PersonalSearchPanel extends StatefulWidget {
  final String area;

  const PersonalSearchPanel({
    super.key,
    required this.area,
  });

  @override
  State<PersonalSearchPanel> createState() => _PersonalSearchPanelState();
}

class _PersonalSearchPanelState extends State<PersonalSearchPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _dialogOpen = false;

  late final AnimationController _keypadController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

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
    _fadeAnimation = CurvedAnimation(
      parent: _keypadController,
      curve: Curves.easeIn,
    );
    _keypadController.forward();
  }

  @override
  void didUpdateWidget(covariant PersonalSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) {
      _resetToInitial();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool _isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  void _resetToInitial() {
    setState(() {
      _controller.clear();
      _isLoading = false;
    });
    _keypadController.forward(from: 0);
  }

  void _onKeypadComplete() {
    final input = _controller.text;
    if (_isValidPlate(input)) {
      _refreshSearchResults();
    }
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted || _isLoading || _dialogOpen) return;

    final area = widget.area.trim();
    if (area.isEmpty) {
      _showSnack('지역 정보가 없어 검색할 수 없습니다.', success: false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = FirestorePlateRepository();
      final input = _controller.text;

      final results = await repository.fourDigitForTabletQuery(
        plateFourDigit: input,
        area: area,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      _dialogOpen = true;
      final closeReason = await showPersonalPlateSearchDialog(
        context: context,
        results: results,
        input: input,
      );
      _dialogOpen = false;

      if (!mounted) return;
      if (closeReason == null ||
          closeReason == PersonalPlateSearchDialogCloseReason.reset ||
          closeReason == PersonalPlateSearchDialogCloseReason.cancelled ||
          closeReason == PersonalPlateSearchDialogCloseReason.confirmed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _resetToInitial();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _dialogOpen = false;
      _showSnack('검색 중 오류가 발생했습니다.', success: false);
      debugPrint('개인형 검색 중 오류가 발생했습니다: $e');
    }
  }

  void _showSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Widget _panelCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildHeaderCard({required EdgeInsets padding}) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: padding,
      child: _panelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PersonalPlateSearchHeaderSection(),
            const SizedBox(height: 16),
            PersonalPlateNumberDisplaySection(
              controller: _controller,
              isValidPlate: _isValidPlate,
            ),
            const SizedBox(height: 16),
            _buildSearchProgressBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchProgressBar(ColorScheme cs) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _isLoading
          ? ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 3,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                backgroundColor: cs.outlineVariant.withOpacity(.35),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _keypadWrapper({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHeaderCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: true,
                child: _keypadWrapper(
                  child: PersonalAnimatedKeypad(
                    slideAnimation: _slideAnimation,
                    fadeAnimation: _fadeAnimation,
                    controller: _controller,
                    maxLength: 4,
                    enableDigitModeSwitch: false,
                    onComplete: _onKeypadComplete,
                    onReset: _resetToInitial,
                    fullHeight: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
