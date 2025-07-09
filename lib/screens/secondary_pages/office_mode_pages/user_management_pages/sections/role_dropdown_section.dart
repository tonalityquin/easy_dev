import 'package:flutter/material.dart';
import 'role_type.dart'; // RoleType enum 정의 import

class RoleDropdownSection extends StatelessWidget {
  final RoleType selectedRole;
  final ValueChanged<RoleType> onChanged;

  const RoleDropdownSection({
    super.key,
    required this.selectedRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<RoleType>(
      value: selectedRole,
      decoration: InputDecoration(
        labelText: '권한',
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.green),
          borderRadius: BorderRadius.circular(8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dropdownColor: Colors.white,
      iconEnabledColor: Colors.green,
      items: RoleType.values
          .map(
            (role) => DropdownMenuItem<RoleType>(
              value: role,
              child: Text(
                role.label,
                style: TextStyle(
                  color: role == selectedRole ? Colors.green : Colors.purple,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (role) {
        if (role != null) {
          onChanged(role);
        }
      },
    );
  }
}
