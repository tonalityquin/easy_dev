class Todo {
  String title;
  bool isDone;
  DateTime? dueDate;

  Todo({
    required this.title,
    this.isDone = false,
    this.dueDate,
  });

  // ✅ JSON 변환
  Map<String, dynamic> toJson() => {
    'title': title,
    'isDone': isDone,
    'dueDate': dueDate?.toIso8601String(),
  };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
    title: json['title'],
    isDone: json['isDone'] ?? false,
    dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
  );

  // ✅ 복사본 생성용 copyWith 메서드 추가
  Todo copyWith({
    String? title,
    bool? isDone,
    DateTime? dueDate,
  }) {
    return Todo(
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      dueDate: dueDate ?? this.dueDate,
    );
  }
}
