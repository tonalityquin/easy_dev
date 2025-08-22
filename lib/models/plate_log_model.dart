class PlateLogModel {
  final String action;
  final String area;
  final String? billingType;
  final String from;
  final String performedBy;
  final String plateNumber;
  final DateTime timestamp;
  final String to;
  final String type;
  final Map<String, dynamic>? updatedFields;

  PlateLogModel({
    required this.action,
    required this.area,
    this.billingType,
    required this.from,
    required this.performedBy,
    required this.plateNumber,
    required this.timestamp,
    required this.to,
    required this.type,
    this.updatedFields,
  });

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> map = {
      'action': action,
      'area': area,
      'from': from,
      'performedBy': performedBy,
      'plateNumber': plateNumber,
      'timestamp': timestamp.toIso8601String(),
      'to': to,
      'type': type,
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
      action: map['action'] ?? '',
      area: map['area'] ?? '',
      billingType: map['billingType'] as String?,
      from: map['from'] ?? '',
      performedBy: map['performedBy'] ?? '',
      plateNumber: map['plateNumber'] ?? '',
      timestamp: parsedTime,
      to: map['to'] ?? '',
      type: map['type'] ?? '',
      updatedFields: parsedUpdatedFields,
    );
  }

  @override
  String toString() {
    return '[$timestamp] $plateNumber moved from "$from" to "$to" '
        'by $performedBy (action: $action${billingType != null ? ', billingType: $billingType' : ''})';
  }
}
