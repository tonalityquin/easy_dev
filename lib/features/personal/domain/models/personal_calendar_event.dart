import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class PersonalCalendarEvent {
  const PersonalCalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.plateNumber = '',
    this.note = '',
  });

  final String id;
  final String title;
  final String plateNumber;
  final String note;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get dayOnly => DateTime(date.year, date.month, date.day);

  PersonalCalendarEvent copyWith({
    String? id,
    String? title,
    String? plateNumber,
    String? note,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonalCalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      plateNumber: plateNumber ?? this.plateNumber,
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'plateNumber': plateNumber.trim(),
      'note': note.trim(),
      'date': dayOnly.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PersonalCalendarEvent.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return PersonalCalendarEvent(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      plateNumber: (map['plateNumber'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      date: DateTime.tryParse((map['date'] ?? '').toString()) ?? now,
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()) ?? now,
    );
  }

  String encode() => jsonEncode(toMap());
}
