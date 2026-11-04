import 'user_model.dart';

class UserAccountViewProjection {
  const UserAccountViewProjection._();

  static const List<String> fields = <String>[
    'name',
    'codeNumber',
    'email',
    'role',
    'position',
    'modes',
    'isActive',
    'areas',
    'divisions',
  ];

  static Map<String, dynamic> fromUser(UserModel user) {
    return fromMap(user.toMap());
  }

  static Map<String, dynamic> fromMap(Map<String, dynamic> source) {
    return <String, dynamic>{
      for (final field in fields)
        if (source.containsKey(field)) field: source[field],
    };
  }
}
