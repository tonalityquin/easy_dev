class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String password;
  final String area;
  final String division; // ✅ 추가
  final bool isSelected;
  final bool isWorking;
  final bool isSaved;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.password,
    required this.area,
    required this.division, // ✅ 추가
    required this.isSelected,
    required this.isWorking,
    required this.isSaved,
  });

  /// ✅ 복사
  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? password,
    String? area,
    String? division, // ✅ 추가
    bool? isSelected,
    bool? isWorking,
    bool? isSaved,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      password: password ?? this.password,
      area: area ?? this.area,
      division: division ?? this.division, // ✅ 추가
      isSelected: isSelected ?? this.isSelected,
      isWorking: isWorking ?? this.isWorking,
      isSaved: isSaved ?? this.isSaved,
    );
  }

  /// ✅ Firestore에서 불러오기 (id는 문서 ID로 전달됨)
  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      password: data['password'] ?? '',
      area: data['area'] ?? '',
      division: data['division'] ?? '', // ✅ 추가
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      isSaved: data['isSaved'] ?? false,
    );
  }

  /// ✅ Firestore 저장용 (id 제외)
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'area': area,
      'division': division, // ✅ 추가
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
    };
  }

  /// ✅ SharedPreferences에서 복원용 (id 포함)
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      password: json['password'] ?? '',
      area: json['area'] ?? '',
      division: json['division'] ?? '', // ✅ 추가
      isSelected: json['isSelected'] ?? false,
      isWorking: json['isWorking'] ?? false,
      isSaved: json['isSaved'] ?? false,
    );
  }

  /// ✅ SharedPreferences 저장용 (id 포함)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'area': area,
      'division': division, // ✅ 추가
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
    };
  }
}
