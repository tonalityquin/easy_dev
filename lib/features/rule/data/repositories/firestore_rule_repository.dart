import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/rule_model.dart';
import '../../domain/repositories/rule_repository.dart';

class FirestoreRuleRepository implements RuleRepository {
  FirestoreRuleRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collectionName = 'rule';

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  @override
  Future<RuleModel?> getRule({
    required String division,
    required String area,
  }) async {
    final identity = _identity(division: division, area: area);
    final id = buildRuleDocumentId(
      division: identity.$1,
      area: identity.$2,
    );
    try {
      final snapshot = await _collection.doc(id).get();
      if (!snapshot.exists || snapshot.data() == null) {
        debugPrint('[RuleRepository] 조회 완료: id=$id found=false');
        return null;
      }
      final rule = RuleModel.fromMap(id, snapshot.data()!);
      _ensureOwnership(rule, identity.$1, identity.$2);
      debugPrint(
        '[RuleRepository] 조회 완료: id=$id found=true todos=${rule.todoItems.length} contentLength=${rule.content.length}',
      );
      return rule;
    } catch (error, stackTrace) {
      debugPrint('[RuleRepository] 조회 실패: id=$id error=$error');
      debugPrint('[RuleRepository] stackTrace=$stackTrace');
      rethrow;
    }
  }

  @override
  Future<RuleModel> createRule({
    required String division,
    required String area,
    required List<RuleTodoItem> todoItems,
    required String content,
  }) async {
    final identity = _identity(division: division, area: area);
    final todos = _validateTodos(todoItems);
    final normalizedContent = _validateContent(content);
    _validateRulePayload(todos: todos, content: normalizedContent);
    final id = buildRuleDocumentId(
      division: identity.$1,
      area: identity.$2,
    );
    final reference = _collection.doc(id);
    final now = DateTime.now();
    try {
      final result = await _firestore.runTransaction<RuleModel>((transaction) async {
        final existing = await transaction.get(reference);
        if (existing.exists) throw const RuleAlreadyExistsException();
        transaction.set(reference, <String, dynamic>{
          'division': identity.$1,
          'area': identity.$2,
          'todoItems': todos.map((item) => item.toMap()).toList(growable: false),
          'content': normalizedContent,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return RuleModel(
          id: id,
          division: identity.$1,
          area: identity.$2,
          todoItems: todos,
          content: normalizedContent,
          createdAt: now,
          updatedAt: now,
        );
      });
      debugPrint(
        '[RuleRepository] 생성 완료: id=$id todos=${todos.length} contentLength=${normalizedContent.length}',
      );
      return result;
    } catch (error, stackTrace) {
      debugPrint('[RuleRepository] 생성 실패: id=$id error=$error');
      debugPrint('[RuleRepository] stackTrace=$stackTrace');
      rethrow;
    }
  }

  @override
  Future<RuleModel> updateRule({
    required String division,
    required String area,
    required List<RuleTodoItem> todoItems,
    required String content,
  }) async {
    final identity = _identity(division: division, area: area);
    final todos = _validateTodos(todoItems);
    final normalizedContent = _validateContent(content);
    _validateRulePayload(todos: todos, content: normalizedContent);
    final id = buildRuleDocumentId(
      division: identity.$1,
      area: identity.$2,
    );
    final reference = _collection.doc(id);
    final now = DateTime.now();
    try {
      final result = await _firestore.runTransaction<RuleModel>((transaction) async {
        final existing = await transaction.get(reference);
        if (!existing.exists || existing.data() == null) {
          throw const RuleNotFoundException();
        }
        final current = RuleModel.fromMap(id, existing.data()!);
        _ensureOwnership(current, identity.$1, identity.$2);
        transaction.update(reference, <String, dynamic>{
          'division': identity.$1,
          'area': identity.$2,
          'todoItems': todos.map((item) => item.toMap()).toList(growable: false),
          'content': normalizedContent,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return RuleModel(
          id: id,
          division: identity.$1,
          area: identity.$2,
          todoItems: todos,
          content: normalizedContent,
          createdAt: current.createdAt,
          updatedAt: now,
        );
      });
      debugPrint(
        '[RuleRepository] 수정 완료: id=$id todos=${todos.length} contentLength=${normalizedContent.length}',
      );
      return result;
    } catch (error, stackTrace) {
      debugPrint('[RuleRepository] 수정 실패: id=$id error=$error');
      debugPrint('[RuleRepository] stackTrace=$stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> deleteRule({
    required String division,
    required String area,
  }) async {
    final identity = _identity(division: division, area: area);
    final id = buildRuleDocumentId(
      division: identity.$1,
      area: identity.$2,
    );
    final reference = _collection.doc(id);
    try {
      await _firestore.runTransaction<void>((transaction) async {
        final existing = await transaction.get(reference);
        if (!existing.exists || existing.data() == null) {
          throw const RuleNotFoundException();
        }
        final current = RuleModel.fromMap(id, existing.data()!);
        _ensureOwnership(current, identity.$1, identity.$2);
        transaction.delete(reference);
      });
      debugPrint('[RuleRepository] 삭제 완료: id=$id');
    } catch (error, stackTrace) {
      debugPrint('[RuleRepository] 삭제 실패: id=$id error=$error');
      debugPrint('[RuleRepository] stackTrace=$stackTrace');
      rethrow;
    }
  }

  (String, String) _identity({
    required String division,
    required String area,
  }) {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    return (normalizedDivision, normalizedArea);
  }

  List<RuleTodoItem> _validateTodos(List<RuleTodoItem> source) {
    if (source.length > 30) {
      throw ArgumentError('Todo 체크리스트에는 최대 30개까지 등록할 수 있습니다.');
    }
    final ids = <String>{};
    final todos = <RuleTodoItem>[];
    for (var index = 0; index < source.length; index += 1) {
      final item = source[index];
      final id = item.id.trim();
      final text = item.text.trim();
      if (id.isEmpty || text.isEmpty) {
        throw ArgumentError('Todo 체크리스트 항목이 비어 있습니다.');
      }
      if (text.length > 120) {
        throw ArgumentError('Todo 체크리스트 항목은 120자 이하로 입력해 주세요.');
      }
      if (!ids.add(id)) {
        throw ArgumentError('Todo 체크리스트에 중복 ID가 있습니다.');
      }
      todos.add(RuleTodoItem(id: id, text: text, order: index));
    }
    return List<RuleTodoItem>.unmodifiable(todos);
  }

  String _validateContent(String content) {
    final normalized = content.trim();
    if (normalized.length > 4000) {
      throw ArgumentError('업무 안내문은 4000자 이하로 입력해 주세요.');
    }
    return normalized;
  }

  void _validateRulePayload({
    required List<RuleTodoItem> todos,
    required String content,
  }) {
    if (todos.isEmpty && content.isEmpty) {
      throw ArgumentError(
        'Todo 체크리스트 또는 업무 안내문 중 하나 이상 입력해야 합니다.',
      );
    }
  }

  void _ensureOwnership(RuleModel rule, String division, String area) {
    if (rule.id != buildRuleDocumentId(division: division, area: area) ||
        rule.division != division ||
        rule.area != area) {
      throw const RuleAreaMismatchException();
    }
  }
}
