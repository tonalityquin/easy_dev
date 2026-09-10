import 'package:cloud_firestore/cloud_firestore.dart';

String buildRuleDocumentId({
  required String division,
  required String area,
}) {
  final normalizedDivision = division.trim();
  final normalizedArea = area.trim();
  if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
    throw StateError('업무 규칙 지역 식별값이 비어 있습니다.');
  }
  return '$normalizedDivision-$normalizedArea';
}

class RuleAlreadyExistsException implements Exception {
  const RuleAlreadyExistsException();

  @override
  String toString() => '현재 지역에는 이미 업무 규칙이 등록되어 있습니다.';
}

class RuleNotFoundException implements Exception {
  const RuleNotFoundException();

  @override
  String toString() => '현재 지역의 업무 규칙을 찾을 수 없습니다.';
}

class RuleAreaMismatchException implements Exception {
  const RuleAreaMismatchException();

  @override
  String toString() => '현재 지역에 속한 업무 규칙이 아닙니다.';
}

class RuleTodoItem {
  const RuleTodoItem({
    required this.id,
    required this.text,
    required this.order,
  });

  final String id;
  final String text;
  final int order;

  factory RuleTodoItem.fromMap(Map<String, dynamic> data) {
    return RuleTodoItem(
      id: (data['id'] ?? '').toString().trim(),
      text: (data['text'] ?? '').toString().trim(),
      order: (data['order'] as num?)?.toInt() ?? 0,
    );
  }

  RuleTodoItem copyWith({
    String? id,
    String? text,
    int? order,
  }) {
    return RuleTodoItem(
      id: id ?? this.id,
      text: text ?? this.text,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'text': text,
      'order': order,
    };
  }
}

class RuleModel {
  const RuleModel({
    required this.id,
    required this.division,
    required this.area,
    required this.todoItems,
    required this.content,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String division;
  final String area;
  final List<RuleTodoItem> todoItems;
  final String content;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory RuleModel.fromMap(String id, Map<String, dynamic> data) {
    final rawTodos = data['todoItems'];
    final todos = <RuleTodoItem>[];
    if (rawTodos is Iterable) {
      for (final raw in rawTodos) {
        if (raw is! Map) continue;
        final todo = RuleTodoItem.fromMap(Map<String, dynamic>.from(raw));
        if (todo.id.isEmpty || todo.text.isEmpty) continue;
        todos.add(todo);
      }
    }
    todos.sort((a, b) {
      final orderCompare = a.order.compareTo(b.order);
      if (orderCompare != 0) return orderCompare;
      return a.id.compareTo(b.id);
    });
    return RuleModel(
      id: id.trim(),
      division: (data['division'] ?? '').toString().trim(),
      area: (data['area'] ?? '').toString().trim(),
      todoItems: List<RuleTodoItem>.unmodifiable(todos),
      content: (data['content'] ?? '').toString().trim(),
      createdAt: _readDateTime(data['createdAt']),
      updatedAt: _readDateTime(data['updatedAt']),
    );
  }

  factory RuleModel.fromCacheMap(Map<String, dynamic> data) {
    return RuleModel.fromMap((data['id'] ?? '').toString(), data);
  }

  RuleModel copyWith({
    String? id,
    String? division,
    String? area,
    List<RuleTodoItem>? todoItems,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RuleModel(
      id: id ?? this.id,
      division: division ?? this.division,
      area: area ?? this.area,
      todoItems: List<RuleTodoItem>.unmodifiable(todoItems ?? this.todoItems),
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return <String, dynamic>{
      'id': id,
      'division': division,
      'area': area,
      'todoItems': todoItems.map((item) => item.toMap()).toList(growable: false),
      'content': content,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }
}
