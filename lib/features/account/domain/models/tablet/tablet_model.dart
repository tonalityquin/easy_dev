class TabletModel {
  final String id;
  final List<String> areas;
  final String? currentArea;
  final List<String> divisions;
  final String email;
  final String? englishSelectedAreaName;
  final List<String> fixedHolidays;
  final bool isSaved;
  final bool isWorking;
  final String name;
  final String password;
  final String handle;
  final String? position;
  final String role;
  final String? selectedArea;

  const TabletModel({
    required this.id,
    required this.areas,
    this.currentArea,
    required this.divisions,
    required this.email,
    this.englishSelectedAreaName,
    this.fixedHolidays = const <String>[],
    required this.isSaved,
    required this.isWorking,
    required this.name,
    required this.password,
    required this.handle,
    this.position,
    required this.role,
    this.selectedArea,
  });

  TabletModel copyWith({
    String? id,
    List<String>? areas,
    String? currentArea,
    List<String>? divisions,
    String? email,
    String? englishSelectedAreaName,
    List<String>? fixedHolidays,
    bool? isSaved,
    bool? isWorking,
    String? name,
    String? password,
    String? handle,
    String? position,
    String? role,
    String? selectedArea,
  }) {
    return TabletModel(
      id: id ?? this.id,
      areas: areas ?? this.areas,
      currentArea: currentArea ?? this.currentArea,
      divisions: divisions ?? this.divisions,
      email: email ?? this.email,
      englishSelectedAreaName: englishSelectedAreaName ?? this.englishSelectedAreaName,
      fixedHolidays: fixedHolidays ?? this.fixedHolidays,
      isSaved: isSaved ?? this.isSaved,
      isWorking: isWorking ?? this.isWorking,
      name: name ?? this.name,
      password: password ?? this.password,
      handle: handle ?? this.handle,
      position: position ?? this.position,
      role: role ?? this.role,
      selectedArea: selectedArea ?? this.selectedArea,
    );
  }

  factory TabletModel.fromMap(String id, Map<String, dynamic> data) {
    return TabletModel(
      id: id,
      areas: List<String>.from(data['areas'] ?? const <String>[]),
      currentArea: data['currentArea'],
      divisions: List<String>.from(data['divisions'] ?? const <String>[]),
      email: data['email'] ?? '',
      englishSelectedAreaName: data['englishSelectedAreaName'],
      fixedHolidays: List<String>.from(data['fixedHolidays'] ?? const <String>[]),
      isSaved: data['isSaved'] ?? false,
      isWorking: data['isWorking'] ?? false,
      name: data['name'] ?? '',
      password: data['password'] ?? '',
      handle: data['handle'] ?? data['phone'] ?? '',
      position: data['position'],
      role: data['role'] ?? '',
      selectedArea: data['selectedArea'],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'areas': areas,
      'currentArea': currentArea,
      'divisions': divisions,
      'email': email,
      'englishSelectedAreaName': englishSelectedAreaName,
      'fixedHolidays': fixedHolidays,
      'isSaved': isSaved,
      'isWorking': isWorking,
      'name': name,
      'password': password,
      'handle': handle,
      'position': position,
      'role': role,
      'selectedArea': selectedArea,
    };
  }

  factory TabletModel.fromJson(Map<String, dynamic> json) {
    return TabletModel.fromMap(json['id'] ?? '', json);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      ...toMap(),
    };
  }

  Map<String, dynamic> toMapWithId() => toJson();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TabletModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
