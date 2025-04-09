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
    super.key,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.access,
    required this.isSelected,
    required this.onTap,
  });

  Widget _buildTextRow(String label, String value) {
    return Text('$label: $value');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextRow('Name', name),
            _buildTextRow('Phone', phone),
            _buildTextRow('Email', email),
            _buildTextRow('Role', role),
            _buildTextRow('Access', access),
          ],
        ),
      ),
    );
  }
}
