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

  static List<MapEntry<String, Map<String, dynamic>>> validatedEntries(
    Map<String, dynamic>? source,
  ) {
    if (source == null) {
      throw StateError('USER_ACCOUNT_VIEW_MISSING');
    }
    if (source['users'] is! Map) {
      throw StateError('USER_ACCOUNT_VIEW_USERS_INVALID');
    }
    return entries(source);
  }

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

  static Map<String, dynamic> deletePayload(String userId) =>
      <String, dynamic>{
        'users': <String, dynamic>{userId: FieldValue.delete()},
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static SetOptions deleteOptions(String userId) => SetOptions(
        mergeFields: <Object>[
          FieldPath(<String>['users', userId]),
          'updatedAt',
        ],
      );

  static Map<String, dynamic> movePayload(
    String oldId,
    String nextId,
    Map<String, dynamic> account,
  ) => <String, dynamic>{
        'users': <String, dynamic>{
          oldId: FieldValue.delete(),
          nextId: account,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static SetOptions moveOptions(String oldId, String nextId) => SetOptions(
        mergeFields: <Object>[
          FieldPath(<String>['users', oldId]),
          FieldPath(<String>['users', nextId]),
          'updatedAt',
        ],
      );

  static Map<String, dynamic> statusPayload(
    String userId,
    bool active,
    Object? disabledAt,
  ) => <String, dynamic>{
        'users': <String, dynamic>{
          userId: <String, dynamic>{
            'isActive': active,
            'updatedAt': FieldValue.serverTimestamp(),
            'disabledAt': active
                ? FieldValue.delete()
                : (disabledAt ?? FieldValue.serverTimestamp()),
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static SetOptions statusOptions(String userId) => SetOptions(
        mergeFields: <Object>[
          FieldPath(<String>['users', userId, 'isActive']),
          FieldPath(<String>['users', userId, 'updatedAt']),
          FieldPath(<String>['users', userId, 'disabledAt']),
          'updatedAt',
        ],
      );

  static Map<String, dynamic> passwordDeletePayload(String userId) =>
      <String, dynamic>{
        'users': <String, dynamic>{
          userId: <String, dynamic>{
            'password': FieldValue.delete(),
          },
        },
      };

  static SetOptions passwordDeleteOptions(String userId) => SetOptions(
        mergeFields: <Object>[
          FieldPath(<String>['users', userId, 'password']),
        ],
      );
}
