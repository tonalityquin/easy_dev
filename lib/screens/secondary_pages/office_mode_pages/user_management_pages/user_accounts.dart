import 'package:flutter/material.dart';

class UserAccounts extends StatefulWidget {
  final Function(String name, String phone, String email, String role, String access) onSave;
  final String areaValue; // TopNavigation에서 전달받은 지역 값

  const UserAccounts({Key? key, required this.onSave, required this.areaValue}) : super(key: key);

  @override
  State<UserAccounts> createState() => _UserAccountsState();
}

class _UserAccountsState extends State<UserAccounts> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  String _selectedRole = 'Dev'; // 초기값 설정

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Accounts'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Role 필드: 드롭다운으로 변경
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: ['Dev', 'Admin', 'User']
                  .map((role) => DropdownMenuItem(
                value: role,
                child: Text(role),
              ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRole = value!; // 선택한 값으로 업데이트
                });
              },
            ),
            const SizedBox(height: 16),
            // Area 필드: 유저 수정 불가능
            Text(
              'Area: ${widget.areaValue}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.onSave(
                      _nameController.text,
                      _phoneController.text,
                      _emailController.text,
                      _selectedRole, // 드롭다운에서 선택한 값 전달
                      widget.areaValue, // Area 값 고정 전달
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
