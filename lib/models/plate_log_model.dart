class PlateLogModel {
  final String plateNumber;
  final String type;
  final String area;
  final String from;
  final String to;
  final String action;
  final String performedBy;
  final DateTime timestamp;
  final String? billingType;
  final Map<String, dynamic>? updatedFields;

  PlateLogModel({
    required this.plateNumber,
    required this.type,
    required this.area,
    required this.from,
    required this.to,
    required this.action,
    required this.performedBy,
    required this.timestamp,
    this.billingType,
    this.updatedFields,
  });

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'plateNumber': plateNumber,
      'type': type,
      'area': area,
      'from': from,
      'to': to,
      'action': action,
      'performedBy': performedBy,
      'timestamp': timestamp.toIso8601String(),
    };

    final cleanBillingType = billingType?.trim();
    if (cleanBillingType != null && cleanBillingType.isNotEmpty) {
      map['billingType'] = cleanBillingType;
    }

    if (updatedFields != null && updatedFields!.isNotEmpty) {
      map['updatedFields'] = updatedFields;
    }

    return map;
  }

  factory PlateLogModel.fromMap(Map<String, dynamic> map) {
    DateTime parsedTime;

    if (map['timestamp'] is String) {
      parsedTime = DateTime.tryParse(map['timestamp']) ?? DateTime.now();
    } else if (map['timestamp'] is int) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(map['timestamp']);
    } else {
      parsedTime = DateTime.now();
    }

    Map<String, dynamic>? parsedUpdatedFields;
    final rawUpdatedFields = map['updatedFields'];

    if (rawUpdatedFields is Map) {
      try {
        parsedUpdatedFields = rawUpdatedFields.map((key, value) {
          if (value is Map) {
            return MapEntry(key, Map<String, dynamic>.from(value));
          } else {
            return MapEntry(key, {'value': value});
          }
        });
      } catch (_) {
        parsedUpdatedFields = null;
      }
    }

    return PlateLogModel(
      plateNumber: map['plateNumber'] ?? '',
      type: map['type'] ?? '',
      area: map['area'] ?? '',
      from: map['from'] ?? '',
      to: map['to'] ?? '',
      action: map['action'] ?? '',
      performedBy: map['performedBy'] ?? '',
      timestamp: parsedTime,
      billingType: map['billingType'] as String?,
      updatedFields: parsedUpdatedFields,
    );
  }

  @override
  String toString() {
    return '[$timestamp] $plateNumber moved from "$from" to "$to" '
        'by $performedBy (action: $action${billingType != null ? ', billingType: $billingType' : ''})';
  }
}
