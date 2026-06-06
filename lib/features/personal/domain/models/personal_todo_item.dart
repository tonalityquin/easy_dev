import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class PersonalTodoItem {
  const PersonalTodoItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.plateNumber = '',
    this.dueDate,
    this.done = false,
  });

  final String id;
  final String title;
  final String plateNumber;
  final DateTime? dueDate;
  final bool done;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonalTodoItem copyWith({
    String? id,
    String? title,
    String? plateNumber,
    DateTime? dueDate,
    bool? done,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDueDate = false,
  }) {
    return PersonalTodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      plateNumber: plateNumber ?? this.plateNumber,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      done: done ?? this.done,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'plateNumber': plateNumber.trim(),
      'done': done,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
    };
  }

  factory PersonalTodoItem.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return PersonalTodoItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      plateNumber: (map['plateNumber'] ?? '').toString(),
      done: (map['done'] as bool?) ?? false,
      dueDate: DateTime.tryParse((map['dueDate'] ?? '').toString()),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()) ?? now,
    );
  }

  String encode() => jsonEncode(toMap());
}
