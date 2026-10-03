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
    required List<RuleManualPage> responseManualPages,
  });

  Future<RuleModel> updateRule({
    required String division,
    required String area,
    required List<RuleTodoItem> todoItems,
    required String content,
    required List<RuleManualPage> responseManualPages,
  });

  Future<void> deleteRule({
    required String division,
    required String area,
  });
}
