import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UserInputSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;

  final FocusNode nameFocus;
  final FocusNode phoneFocus;
  final FocusNode emailFocus;

  final String? errorMessage;

  const UserInputSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.nameFocus,
    required this.phoneFocus,
    required this.emailFocus,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(phoneFocus),
          decoration: InputDecoration(
            labelText: '이름',
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            errorText: errorMessage == '이름을 다시 입력하세요' ? errorMessage : null,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          focusNode: phoneFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).requestFocus(emailFocus),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: '전화번호',
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            errorText: errorMessage == '전화번호를 다시 입력하세요' ? errorMessage : null,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: emailController,
                focusNode: emailFocus,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: '이메일(구글)',
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  errorText: errorMessage == '이메일을 입력하세요' ? errorMessage : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              flex: 2,
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    '@gmail.com',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
