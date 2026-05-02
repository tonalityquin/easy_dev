class ParkingSlotPreferenceKey {
  static const String compact = 'compact';
  static const String standard = 'standard';
  static const String extended = 'extended';
  static const String extendedA = 'extendedA';
  static const String extendedB = 'extendedB';

  static const Set<String> values = <String>{
    compact,
    standard,
    extended,
    extendedA,
    extendedB,
  };

  static String normalize(String raw) {
    final v = raw.trim();
    switch (v) {
      case compact:
      case '경형':
      case '경':
        return compact;
      case standard:
      case '일반형':
      case '일반':
      case '일':
        return standard;
      case extended:
      case '확장형':
      case '확장':
        return extended;
      case extendedA:
      case '확장형 A':
      case '확장 A':
      case '확A':
        return extendedA;
      case extendedB:
      case '확장형 B':
      case '확장 B':
      case '확B':
        return extendedB;
      default:
        return v;
    }
  }

  static bool isValid(String raw) => values.contains(normalize(raw));

  static String label(String key) {
    switch (normalize(key)) {
      case compact:
        return '경형';
      case standard:
        return '일반형';
      case extended:
        return '확장형';
      case extendedA:
        return '확장형 A';
      case extendedB:
        return '확장형 B';
      default:
        return key.trim();
    }
  }

  static bool matchesCategory({
    required String preferenceKey,
    required String slotCategory,
  }) {
    final pref = normalize(preferenceKey);
    final slot = normalize(slotCategory);
    if (pref == extended) {
      return slot == extendedA || slot == extendedB || slot == extended;
    }
    return pref == slot;
  }
}

class VehicleParkingPreference {
  final int? id;
  final String manufacturerName;
  final String modelName;
  final String priority1SlotKey;
  final String? priority2SlotKey;
  final String? priority3SlotKey;
  final int createdAt;
  final int updatedAt;

  const VehicleParkingPreference({
    this.id,
    required this.manufacturerName,
    required this.modelName,
    required this.priority1SlotKey,
    this.priority2SlotKey,
    this.priority3SlotKey,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleParkingPreference.fromMap(Map<String, Object?> map) {
    final p1 = (map['priority_1_slot_key'] ?? map['priority_1_area'] ?? '')
        .toString();
    final p2 = map['priority_2_slot_key'] ?? map['priority_2_area'];
    final p3 = map['priority_3_slot_key'] ?? map['priority_3_area'];

    return VehicleParkingPreference(
      id: map['id'] as int?,
      manufacturerName: (map['manufacturer_name'] as String?) ?? '',
      modelName: (map['model_name'] as String?) ?? '',
      priority1SlotKey: ParkingSlotPreferenceKey.normalize(p1),
      priority2SlotKey: p2 == null
          ? null
          : ParkingSlotPreferenceKey.normalize(p2.toString()),
      priority3SlotKey: p3 == null
          ? null
          : ParkingSlotPreferenceKey.normalize(p3.toString()),
      createdAt: (map['created_at'] as int?) ?? 0,
      updatedAt: (map['updated_at'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'manufacturer_name': manufacturerName,
      'model_name': modelName,
      'priority_1_slot_key': ParkingSlotPreferenceKey.normalize(priority1SlotKey),
      'priority_2_slot_key': priority2SlotKey == null
          ? null
          : ParkingSlotPreferenceKey.normalize(priority2SlotKey!),
      'priority_3_slot_key': priority3SlotKey == null
          ? null
          : ParkingSlotPreferenceKey.normalize(priority3SlotKey!),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  List<String> get prioritySlotKeys {
    return <String>[
      priority1SlotKey,
      if (priority2SlotKey != null && priority2SlotKey!.trim().isNotEmpty)
        priority2SlotKey!,
      if (priority3SlotKey != null && priority3SlotKey!.trim().isNotEmpty)
        priority3SlotKey!,
    ].map(ParkingSlotPreferenceKey.normalize).where(ParkingSlotPreferenceKey.isValid).toList(growable: false);
  }

  String get priority1Area => ParkingSlotPreferenceKey.label(priority1SlotKey);

  String? get priority2Area => priority2SlotKey == null || priority2SlotKey!.trim().isEmpty
      ? null
      : ParkingSlotPreferenceKey.label(priority2SlotKey!);

  String? get priority3Area => priority3SlotKey == null || priority3SlotKey!.trim().isEmpty
      ? null
      : ParkingSlotPreferenceKey.label(priority3SlotKey!);

  List<String> get priorities => prioritySlotKeys;
}
