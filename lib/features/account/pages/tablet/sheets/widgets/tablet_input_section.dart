import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../shared/auth/tablet_phone.dart';

class TabletInputSection extends StatelessWidget {
  const TabletInputSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.nameFocus,
    required this.phoneFocus,
    required this.errorMessage,
    this.onEdited,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final FocusNode nameFocus;
  final FocusNode phoneFocus;
  final String? errorMessage;
  final VoidCallback? onEdited;

  bool _isNameOk(String value) => value.trim().isNotEmpty;

  bool _isPhoneOk(String value) => TabletPhone.isValid(value);

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

  void _formatPhone(String value) {
    final formatted = TabletPhone.format(value);
    if (formatted == value) return;
    phoneController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nameError =
        errorMessage == '태블릿 이름을 입력하세요.' ? errorMessage : null;
    final phoneError = errorMessage == '전화번호를 다시 확인하세요.'
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
        TextField(
          controller: phoneController,
          focusNode: phoneFocus,
          onChanged: (value) {
            _formatPhone(value);
            onEdited?.call();
          },
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.phone,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
            LengthLimitingTextInputFormatter(13),
          ],
          style: TextStyle(color: colorScheme.onSurface),
          decoration: _decoration(
            context,
            colorScheme: colorScheme,
            label: '전화번호',
            errorText: phoneError,
            prefixIcon: Icons.phone_rounded,
            done: _isPhoneOk(phoneController.text),
          ),
        ),
      ],
    );
  }
}
