class ParkingSlotPreferenceKey {
  static const String compact = 'compact';
  static const String standard = 'standard';
  static const String extended = 'extended';
  static const String extendedA = 'extendedA';
  static const String extendedB = 'extendedB';
  static const String evCompact = 'evCompact';
  static const String evStandard = 'evStandard';
  static const String evExtended = 'evExtended';
  static const String evExtendedA = 'evExtendedA';
  static const String evExtendedB = 'evExtendedB';
  static const String pregnantExtended = 'pregnantExtended';
  static const String pregnantExtendedA = 'pregnantExtendedA';
  static const String pregnantExtendedB = 'pregnantExtendedB';
  static const String disabledStandard = 'disabledStandard';
  static const String disabledExtended = 'disabledExtended';
  static const String disabledExtendedA = 'disabledExtendedA';
  static const String disabledExtendedB = 'disabledExtendedB';

  static const Set<String> values = <String>{
    compact,
    standard,
    extended,
    extendedA,
    extendedB,
    evCompact,
    evStandard,
    evExtended,
    evExtendedA,
    evExtendedB,
    pregnantExtended,
    pregnantExtendedA,
    pregnantExtendedB,
    disabledStandard,
    disabledExtended,
    disabledExtendedA,
    disabledExtendedB,
  };

  static String normalize(String raw) {
    final v = raw.trim();
    final n = v.toLowerCase().replaceAll('×', 'x').replaceAll(RegExp(r'\s+'), '');
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
      case evCompact:
      case '전기차 경형':
      case 'EV 경형':
      case 'EV경':
        return evCompact;
      case evStandard:
      case '전기차 일반형':
      case 'EV 일반형':
      case 'EV일반':
      case 'EV일':
        return evStandard;
      case evExtended:
      case '전기차 확장형':
      case 'EV 확장형':
      case 'EV확장':
        return evExtended;
      case evExtendedA:
      case '전기차 확장형 A':
      case 'EV 확장형 A':
      case 'EV확A':
        return evExtendedA;
      case evExtendedB:
      case '전기차 확장형 B':
      case 'EV 확장형 B':
      case 'EV확B':
        return evExtendedB;
      case pregnantExtended:
      case '임산부 배려 확장형':
      case '임산부 확장형':
      case '임산부':
        return pregnantExtended;
      case pregnantExtendedA:
      case '임산부 배려 확장형 A':
      case '임산부 확장형 A':
      case '임A':
        return pregnantExtendedA;
      case pregnantExtendedB:
      case '임산부 배려 확장형 B':
      case '임산부 확장형 B':
      case '임B':
        return pregnantExtendedB;
      case disabledStandard:
      case '장애인 일반형':
      case '장애인 일반':
      case '장일':
        return disabledStandard;
      case disabledExtended:
      case '장애인 확장형':
      case '장애인 확장':
        return disabledExtended;
      case disabledExtendedA:
      case '장애인 확장형 A':
      case '장애인 확장 A':
      case '장확A':
        return disabledExtendedA;
      case disabledExtendedB:
      case '장애인 확장형 B':
      case '장애인 확장 B':
      case '장확B':
        return disabledExtendedB;
      default:
        if (n.contains('전기차') || n.contains('전기') || n.contains('ev') || n.contains('electric')) {
          if (n.contains('확장형b') || n.contains('확장b') || n.contains('extendedb')) return evExtendedB;
          if (n.contains('확장형a') || n.contains('확장a') || n.contains('extendeda')) return evExtendedA;
          if (n.contains('확장형') || n.contains('확장') || n.contains('extended') || n.contains('expand')) return evExtended;
          if (n.contains('일반형') || n.contains('일반') || n.contains('standard') || n.contains('normal') || n.contains('general')) return evStandard;
          if (n.contains('경형') || n.contains('경차') || n.contains('compact') || n.contains('light') || n.contains('small')) return evCompact;
        }
        if (n.contains('임산부') || n.contains('pregnant') || n.contains('maternity')) {
          if (n.contains('확장형b') || n.contains('확장b') || n.contains('extendedb')) return pregnantExtendedB;
          if (n.contains('확장형a') || n.contains('확장a') || n.contains('extendeda')) return pregnantExtendedA;
          if (n.contains('확장형') || n.contains('확장') || n.contains('extended') || n.contains('expand')) return pregnantExtended;
        }
        if (n.contains('장애인') || n.contains('disabled') || n.contains('accessible') || n.contains('handicap')) {
          if (n.contains('확장형b') || n.contains('확장b') || n.contains('extendedb')) return disabledExtendedB;
          if (n.contains('확장형a') || n.contains('확장a') || n.contains('extendeda')) return disabledExtendedA;
          if (n.contains('확장형') || n.contains('확장') || n.contains('extended') || n.contains('expand')) return disabledExtended;
          if (n.contains('일반형') || n.contains('일반') || n.contains('standard') || n.contains('normal') || n.contains('general')) return disabledStandard;
        }
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
      case evCompact:
        return '전기차 경형';
      case evStandard:
        return '전기차 일반형';
      case evExtended:
        return '전기차 확장형';
      case evExtendedA:
        return '전기차 확장형 A';
      case evExtendedB:
        return '전기차 확장형 B';
      case pregnantExtended:
        return '임산부 배려 확장형';
      case pregnantExtendedA:
        return '임산부 배려 확장형 A';
      case pregnantExtendedB:
        return '임산부 배려 확장형 B';
      case disabledStandard:
        return '장애인 일반형';
      case disabledExtended:
        return '장애인 확장형';
      case disabledExtendedA:
        return '장애인 확장형 A';
      case disabledExtendedB:
        return '장애인 확장형 B';
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
    if (pref == evExtended) {
      return slot == evExtendedA || slot == evExtendedB || slot == evExtended;
    }
    if (pref == pregnantExtended) {
      return slot == pregnantExtendedA || slot == pregnantExtendedB || slot == pregnantExtended;
    }
    if (pref == disabledExtended) {
      return slot == disabledExtendedA || slot == disabledExtendedB || slot == disabledExtended;
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
