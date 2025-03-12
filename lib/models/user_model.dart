class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String password;
  final String area;
  final bool isSelected;
  final bool isWorking;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.password,
    required this.area,
    required this.isSelected,
    required this.isWorking,
  });

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      password: data['password'] ?? '',
      // ✅ password가 올바르게 매핑되었는지 확인
      area: data['area'] ?? '',
      // ✅ area가 올바르게 매핑되었는지 확인
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password, // ✅ Firestore에 올바른 값 저장
      'area': area, // ✅ Firestore에 올바른 값 저장
      'isSelected': isSelected,
      'isWorking': isWorking,
    };
  }
}
