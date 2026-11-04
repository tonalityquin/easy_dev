import 'package:cloud_firestore/cloud_firestore.dart';

class UserAccountShowMap {
  const UserAccountShowMap._();

  static Map<String, dynamic> users(Map<String, dynamic>? source) {
    final raw = source?['users'];
    if (raw == null) return <String, dynamic>{};
    if (raw is! Map) throw StateError('SHOW_USERS_MAP_INVALID');
    return Map<String, dynamic>.from(raw);
  }

  static Map<String, dynamic>? account(
    Map<String, dynamic>? source,
    String userId,
  ) {
    final raw = users(source)[userId];
    if (raw == null) return null;
    if (raw is! Map) throw StateError('SHOW_USER_ENTRY_INVALID');
    return Map<String, dynamic>.from(raw);
  }

  static List<MapEntry<String, Map<String, dynamic>>> entries(
    Map<String, dynamic>? source,
  ) {
    final result = <MapEntry<String, Map<String, dynamic>>>[];
    for (final entry in users(source).entries) {
      if (entry.value is! Map) throw StateError('SHOW_USER_ENTRY_INVALID');
      result.add(MapEntry(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      ));
    }
    return result;
  }

  static bool isComplete(Map<String, dynamic>? source) =>
      source?['usersMapComplete'] == true;

  static Map<String, dynamic> putPayload(
    String userId,
    Map<String, dynamic> account,
  ) => <String, dynamic>{
    'users': <String, dynamic>{userId: account},
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static SetOptions putOptions(String userId) => SetOptions(
    mergeFields: <Object>[
      FieldPath(<String>['users', userId]),
      'updatedAt',
    ],
  );

  static Map<Object, Object?> deletePayload(String userId) =>
      <Object, Object?>{
        FieldPath(<String>['users', userId]): FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<Object, Object?> statusPayload(
    String userId,
    bool active,
    Object? disabledAt,
  ) => <Object, Object?>{
    FieldPath(<String>['users', userId, 'isActive']): active,
    FieldPath(<String>['users', userId, 'updatedAt']):
        FieldValue.serverTimestamp(),
    FieldPath(<String>['users', userId, 'disabledAt']): active
        ? FieldValue.delete()
        : (disabledAt ?? FieldValue.serverTimestamp()),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
