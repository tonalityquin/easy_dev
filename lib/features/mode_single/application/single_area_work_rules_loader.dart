import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
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
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    SingleInsideDiagnostics.log(
      'rules',
      'load_start division=$normalizedDivision area=$normalizedArea source=operational_sqlite remoteRead=0 remoteWrite=0',
    );
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      SingleInsideDiagnostics.log(
        'rules',
        'load_skipped division=$normalizedDivision area=$normalizedArea reason=identity_empty remoteRead=0 remoteWrite=0',
      );
      return SingleAreaWorkRulesResult(
        division: normalizedDivision,
        area: normalizedArea,
        rule: null,
      );
    }
    final rule = await localRepository.readRule(
      division: normalizedDivision,
      area: normalizedArea,
    );
    SingleInsideDiagnostics.log(
      'rules',
      'load_complete division=$normalizedDivision area=$normalizedArea found=${rule != null} todos=${rule?.todoItems.length ?? 0} contentLength=${rule?.content.length ?? 0} source=operational_sqlite remoteRead=0 remoteWrite=0',
    );
    return SingleAreaWorkRulesResult(
      division: normalizedDivision,
      area: normalizedArea,
      rule: rule,
    );
  }
}
