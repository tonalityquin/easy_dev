import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../rule/applications/work_rule_report_loader.dart';
import '../../rule/domain/models/rule_model.dart';
import 'single_inside_diagnostics.dart';

class SingleAreaWorkRulesResult {
  const SingleAreaWorkRulesResult({
    required this.division,
    required this.area,
    required this.rule,
  });

  final String division;
  final String area;
  final RuleModel? rule;
}

class SingleAreaWorkRulesLoader {
  SingleAreaWorkRulesLoader._();

  static Future<SingleAreaWorkRulesResult> load({
    required OperationalLocalRepository localRepository,
    required String division,
    required String area,
  }) async {
    final result = await WorkRuleReportLoader.load(
      localRepository: localRepository,
      division: division,
      area: area,
      onDebug: (message) => SingleInsideDiagnostics.log('rules', message),
    );
    return SingleAreaWorkRulesResult(
      division: result.division,
      area: result.area,
      rule: result.rule,
    );
  }
}
