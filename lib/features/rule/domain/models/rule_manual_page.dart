import '../utils/work_manual_text.dart';

class RuleManualPage {
  const RuleManualPage({
    required this.id,
    required this.content,
    required this.order,
  });

  final String id;
  final String content;
  final int order;

  factory RuleManualPage.fromMap(
    Map<String, dynamic> data, {
    required int fallbackOrder,
  }) {
    final rawId = (data['id'] ?? '').toString().trim();
    return RuleManualPage(
      id: rawId.isEmpty ? 'manual_page_${fallbackOrder + 1}' : rawId,
      content: normalizeWorkManualForStorage(
        (data['content'] ?? '').toString(),
      ),
      order: (data['order'] as num?)?.toInt() ?? fallbackOrder,
    );
  }

  RuleManualPage copyWith({
    String? id,
    String? content,
    int? order,
  }) {
    return RuleManualPage(
      id: id ?? this.id,
      content: content ?? this.content,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'content': content,
      'order': order,
    };
  }
}

List<RuleManualPage> normalizeRuleManualPagesForStorage(
  List<RuleManualPage> source,
) {
  final result = <RuleManualPage>[];
  final usedIds = <String>{};
  for (var index = 0; index < source.length; index += 1) {
    final page = source[index];
    final content = normalizeWorkManualForStorage(page.content);
    if (isWorkManualBlank(content)) continue;
    var id = page.id.trim();
    if (id.isEmpty || usedIds.contains(id)) {
      id = 'manual_page_${index + 1}';
      var suffix = 1;
      while (usedIds.contains(id)) {
        id = 'manual_page_${index + 1}_$suffix';
        suffix += 1;
      }
    }
    usedIds.add(id);
    result.add(
      RuleManualPage(
        id: id,
        content: content,
        order: result.length,
      ),
    );
  }
  return List<RuleManualPage>.unmodifiable(result);
}

String flattenRuleManualPages(List<RuleManualPage> pages) {
  final normalized = normalizeRuleManualPagesForStorage(pages);
  return normalized.map((page) => page.content).join('\n\n');
}

int ruleManualPageContentLength(List<RuleManualPage> pages) {
  var length = 0;
  for (final page in normalizeRuleManualPagesForStorage(pages)) {
    length += page.content.length;
  }
  return length;
}

bool sameRuleManualPages(
  List<RuleManualPage> left,
  List<RuleManualPage> right,
) {
  final a = normalizeRuleManualPagesForStorage(left);
  final b = normalizeRuleManualPagesForStorage(right);
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index].id != b[index].id ||
        a[index].content != b[index].content ||
        a[index].order != b[index].order) {
      return false;
    }
  }
  return true;
}

bool isLegacyRuleManualPageId(String id) {
  return id.startsWith('manual_legacy_');
}
