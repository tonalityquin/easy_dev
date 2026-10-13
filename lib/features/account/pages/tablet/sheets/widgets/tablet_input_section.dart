import 'package:flutter/material.dart';

import '../../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../../shared/auth/account_code_number.dart';

class TabletInputSection extends StatelessWidget {
  const TabletInputSection({
    super.key,
    required this.nameController,
    required this.codeNumberController,
    required this.nameFocus,
    required this.codeNumberFocus,
    required this.errorMessage,
    this.onEdited,
    this.isEditMode = false,
  });

  final TextEditingController nameController;
  final TextEditingController codeNumberController;
  final FocusNode nameFocus;
  final FocusNode codeNumberFocus;
  final String? errorMessage;
  final VoidCallback? onEdited;
  final bool isEditMode;

  bool _isNameOk(String value) => value.trim().isNotEmpty;

  bool _isCodeNumberOk(String value) =>
      AccountCodeNumber.isGeneratedCode(value);

  InputDecoration _decoration(
    BuildContext context, {
    required ColorScheme colorScheme,
    required String label,
    String? errorText,
    IconData? prefixIcon,
    bool done = false,
  }) {
    return InputDecoration(
      labelText: label,
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      prefixIconColor: colorScheme.onSurfaceVariant,
      suffixIcon: Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withOpacity(.55),
      ),
      filled: true,
      fillColor: colorScheme.surfaceVariant.withOpacity(.45),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(.75),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.error.withOpacity(.60)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.error, width: 1.3),
      ),
      errorText: errorText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final nameError =
        errorMessage == '태블릿 이름을 입력하세요.' ? errorMessage : null;
    final codeNumberError = errorMessage == '코드번호를 다시 확인하세요.'
        ? errorMessage
        : null;

    return Column(
      children: [
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          style: TextStyle(color: colorScheme.onSurface),
          decoration: _decoration(
            context,
            colorScheme: colorScheme,
            label: '태블릿 이름',
            errorText: nameError,
            prefixIcon: Icons.tablet_mac_rounded,
            done: _isNameOk(nameController.text),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: TextField(
            key: ValueKey<String>(codeNumberController.text),
            controller: codeNumberController,
            focusNode: codeNumberFocus,
            readOnly: true,
            enableInteractiveSelection: true,
            textInputAction: TextInputAction.done,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: _decoration(
              context,
              colorScheme: colorScheme,
              label: '코드번호',
              errorText: codeNumberError,
              prefixIcon: Icons.tag_rounded,
              done: _isCodeNumberOk(codeNumberController.text),
            ),
          ),
        ),
      ],
    );
  }
}
