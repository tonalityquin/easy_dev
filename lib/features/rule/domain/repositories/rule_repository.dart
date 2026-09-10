import '../models/rule_model.dart';

abstract class RuleRepository {
  Future<RuleModel?> getRule({
    required String division,
    required String area,
  });

  Future<RuleModel> createRule({
    required String division,
    required String area,
    required List<RuleTodoItem> todoItems,
    required String content,
  });

  Future<RuleModel> updateRule({
    required String division,
    required String area,
    required List<RuleTodoItem> todoItems,
    required String content,
  });

  Future<void> deleteRule({
    required String division,
    required String area,
  });
}
