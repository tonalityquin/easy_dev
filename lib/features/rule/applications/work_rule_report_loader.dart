import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../domain/models/rule_model.dart';

class WorkRuleReportResult {
  const WorkRuleReportResult({
    required this.division,
    required this.area,
    required this.rule,
    required this.source,
  });

  final String division;
  final String area;
  final RuleModel? rule;
  final String source;
}

class WorkRuleReportLoader {
  WorkRuleReportLoader._();

  static Future<WorkRuleReportResult> load({
    required OperationalLocalRepository localRepository,
    required String division,
    required String area,
    void Function(String message)? onDebug,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    onDebug?.call(
      'work_rule_report=load_start division=$normalizedDivision area=$normalizedArea source=operational_sqlite remoteRead=0 remoteWrite=0',
    );
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) {
      onDebug?.call(
        'work_rule_report=load_skipped division=$normalizedDivision area=$normalizedArea reason=identity_empty source=operational_sqlite remoteRead=0 remoteWrite=0',
      );
      return WorkRuleReportResult(
        division: normalizedDivision,
        area: normalizedArea,
        rule: null,
        source: 'operational_sqlite',
      );
    }

    final rule = await localRepository.readRule(
      division: normalizedDivision,
      area: normalizedArea,
    );
    onDebug?.call(
      'work_rule_report=load_complete division=$normalizedDivision area=$normalizedArea found=${rule != null} todoCount=${rule?.todoItems.length ?? 0} contentLength=${rule?.content.length ?? 0} updatedAt=${rule?.updatedAt?.toIso8601String() ?? '-'} source=operational_sqlite remoteRead=0 remoteWrite=0',
    );
    return WorkRuleReportResult(
      division: normalizedDivision,
      area: normalizedArea,
      rule: rule,
      source: 'operational_sqlite',
    );
  }
}
