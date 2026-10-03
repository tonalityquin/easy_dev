import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../domain/models/rule_model.dart';
import '../domain/utils/work_manual_text.dart';

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

  bool get ruleFound => rule != null;

  String get content => rule?.content.trim() ?? '';

  bool get contentAvailable => content.isNotEmpty;

  String get responseManual =>
      normalizeWorkManualText(rule?.responseManual ?? '');

  List<RuleManualPage> get responseManualPages =>
      rule?.responseManualPages ?? const <RuleManualPage>[];

  bool get responseManualAvailable => responseManualPages.isNotEmpty;

  DateTime? get updatedAt => rule?.updatedAt;
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
    final result = WorkRuleReportResult(
      division: normalizedDivision,
      area: normalizedArea,
      rule: rule,
      source: 'operational_sqlite',
    );
    onDebug?.call(
      'work_rule_report=load_complete division=$normalizedDivision area=$normalizedArea ruleFound=${result.ruleFound} contentAvailable=${result.contentAvailable} contentLength=${result.content.length} responseManualAvailable=${result.responseManualAvailable} responseManualLength=${result.responseManual.length} responseManualPageCount=${result.responseManualPages.length} legacyFallback=${result.rule?.responseManualUsesLegacyFallback ?? false} updatedAt=${result.updatedAt?.toIso8601String() ?? '-'} source=${result.source} remoteRead=0 remoteWrite=0',
    );
    return result;
  }
}
