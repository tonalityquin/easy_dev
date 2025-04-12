class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String password;
  final String area;
  final String division;
  final String? currentArea; // ✅ 현재 근무 중인 지역
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
    required this.division,
    this.currentArea, // ✅ nullable
    required this.isSelected,
    required this.isWorking,
    required this.isSaved,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? role,
    String? password,
    String? area,
    String? division,
    String? currentArea, // ✅ 추가
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
      division: division ?? this.division,
      currentArea: currentArea ?? this.currentArea, // ✅ 반영
      isSelected: isSelected ?? this.isSelected,
      isWorking: isWorking ?? this.isWorking,
      isSaved: isSaved ?? this.isSaved,
    );
  }

  factory UserModel.fromMap(String id, Map<String, dynamic> data) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
      password: data['password'] ?? '',
      area: data['area'] ?? '',
      division: data['division'] ?? '',
      currentArea: data['currentArea'], // ✅ nullable 처리
      isSelected: data['isSelected'] ?? false,
      isWorking: data['isWorking'] ?? false,
      isSaved: data['isSaved'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'area': area,
      'division': division,
      'currentArea': currentArea, // ✅ 저장 시 포함
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      password: json['password'] ?? '',
      area: json['area'] ?? '',
      division: json['division'] ?? '',
      currentArea: json['currentArea'], // ✅ 추가
      isSelected: json['isSelected'] ?? false,
      isWorking: json['isWorking'] ?? false,
      isSaved: json['isSaved'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'password': password,
      'area': area,
      'division': division,
      'currentArea': currentArea, // ✅ 추가
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
    };
  }
}
