import '../../../../../shared/auth/account_code_number.dart';
import '../account_permission_policy.dart';

class TabletModel {
  final String id;
  final String companyId;
  final List<String> permissionKeys;
  final int permissionSchemaVersion;
  final List<String> areas;
  final String? currentArea;
  final List<String> divisions;
  final String email;
  final String? englishSelectedAreaName;
  final List<String> fixedHolidays;
  final bool isSaved;
  final bool isWorking;
  final String name;
  final String? password;
  final String codeNumber;
  final String? position;
  final String? selectedArea;

  const TabletModel({
    required this.id,
    this.companyId = '',
    this.permissionKeys = const <String>[],
    this.permissionSchemaVersion = 1,
    required this.areas,
    this.currentArea,
    required this.divisions,
    this.email = '',
    this.englishSelectedAreaName,
    this.fixedHolidays = const <String>[],
    required this.isSaved,
    required this.isWorking,
    required this.name,
    this.password,
    required this.codeNumber,
    this.position,
    this.selectedArea,
  });

  TabletModel copyWith({
    String? id,
    String? companyId,
    List<String>? permissionKeys,
    int? permissionSchemaVersion,
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
    String? codeNumber,
    String? position,
    String? selectedArea,
  }) {
    return TabletModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      permissionKeys: permissionKeys ?? this.permissionKeys,
      permissionSchemaVersion: permissionSchemaVersion ?? this.permissionSchemaVersion,
      areas: areas ?? this.areas,
      currentArea: currentArea ?? this.currentArea,
      divisions: divisions ?? this.divisions,
      email: email ?? this.email,
      englishSelectedAreaName:
          englishSelectedAreaName ?? this.englishSelectedAreaName,
      fixedHolidays: fixedHolidays ?? this.fixedHolidays,
      isSaved: isSaved ?? this.isSaved,
      isWorking: isWorking ?? this.isWorking,
      name: name ?? this.name,
      password: password ?? this.password,
      codeNumber: codeNumber ?? this.codeNumber,
      position: position ?? this.position,
      selectedArea: selectedArea ?? this.selectedArea,
    );
  }

  factory TabletModel.fromMap(String id, Map<String, dynamic> data) {
    final rawCodeNumber = <Object?>[
      data['codeNumber'],
      data['phone'],
      data['handle'],
    ]
        .map((value) => (value ?? '').toString().trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final normalizedCodeNumber = AccountCodeNumber.normalize(rawCodeNumber);
    return TabletModel(
      id: id,
      companyId: (data['companyId'] ?? '').toString(),
      permissionKeys: AccountPermissionPolicy.sanitize(
        List<String>.from(data['permissionKeys'] ?? const <String>[]),
      ).toList(growable: false),
      permissionSchemaVersion: data['permissionSchemaVersion'] is int
          ? data['permissionSchemaVersion'] as int : 1,
      areas: List<String>.from(data['areas'] ?? const <String>[]),
      currentArea: data['currentArea'],
      divisions: List<String>.from(data['divisions'] ?? const <String>[]),
      email: data['email'] ?? '',
      englishSelectedAreaName: data['englishSelectedAreaName'],
      fixedHolidays:
          List<String>.from(data['fixedHolidays'] ?? const <String>[]),
      isSaved: data['isSaved'] ?? false,
      isWorking: data['isWorking'] ?? false,
      name: data['name'] ?? '',
      password: data['password']?.toString(),
      codeNumber: normalizedCodeNumber,
      position: data['position'],
      selectedArea: data['selectedArea'],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'companyId': companyId.trim(),
      'permissionKeys': permissionKeys,
      'permissionSchemaVersion': permissionSchemaVersion,
      'areas': areas,
      'currentArea': currentArea,
      'divisions': divisions,
      'englishSelectedAreaName': englishSelectedAreaName,
      'fixedHolidays': fixedHolidays,
      'isSaved': isSaved,
      'isWorking': isWorking,
      'name': name,
      'codeNumber': AccountCodeNumber.normalize(codeNumber),
      'email': email.trim(),
      'position': position,
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
