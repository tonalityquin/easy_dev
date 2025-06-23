class UserModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String role;
  final String password;

  final List<String> areas;      // ✅ 복수 지역
  final List<String> divisions;  // ✅ 복수 부서

  final String? currentArea;            // ✅ 현재 근무 지역
  final String? selectedArea;           // ✅ 선택된 지역
  final String? englishSelectedAreaName; // ✅ 선택된 지역의 영어 이름

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
    required this.areas,
    required this.divisions,
    this.currentArea,
    this.selectedArea,
    this.englishSelectedAreaName, // ✅ 추가
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
    List<String>? areas,
    List<String>? divisions,
    String? currentArea,
    String? selectedArea,
    String? englishSelectedAreaName, // ✅ 추가
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
      areas: areas ?? this.areas,
      divisions: divisions ?? this.divisions,
      currentArea: currentArea ?? this.currentArea,
      selectedArea: selectedArea ?? this.selectedArea,
      englishSelectedAreaName: englishSelectedAreaName ?? this.englishSelectedAreaName, // ✅ 추가
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
      areas: List<String>.from(data['areas'] ?? []),
      divisions: List<String>.from(data['divisions'] ?? []),
      currentArea: data['currentArea'],
      selectedArea: data['selectedArea'],
      englishSelectedAreaName: data['englishSelectedAreaName'], // ✅ 추가
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
      'areas': areas,
      'divisions': divisions,
      'currentArea': currentArea,
      'selectedArea': selectedArea,
      'englishSelectedAreaName': englishSelectedAreaName, // ✅ 추가
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
      areas: List<String>.from(json['areas'] ?? []),
      divisions: List<String>.from(json['divisions'] ?? []),
      currentArea: json['currentArea'],
      selectedArea: json['selectedArea'],
      englishSelectedAreaName: json['englishSelectedAreaName'], // ✅ 추가
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
      'areas': areas,
      'divisions': divisions,
      'currentArea': currentArea,
      'selectedArea': selectedArea,
      'englishSelectedAreaName': englishSelectedAreaName, // ✅ 추가
      'isSelected': isSelected,
      'isWorking': isWorking,
      'isSaved': isSaved,
    };
  }
}
