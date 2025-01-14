import 'package:flutter/material.dart';

class UserContainer extends StatelessWidget {
  final String name;
  final String phone;
  final String email;
  final String role;
  final String access;
  final bool isSelected;
  final VoidCallback onTap;

  const UserContainer({
    Key? key,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.access,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 클릭 이벤트
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white, // 배경색
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: $name'),
            Text('Phone: $phone'),
            Text('Email: $email'),
            Text('Role: $role'),
            Text('Access: $access'),
          ],
        ),
      ),
    );
  }
}
