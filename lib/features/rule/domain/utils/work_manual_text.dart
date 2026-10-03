String normalizeWorkManualText(String value) {
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

String normalizeWorkManualForStorage(String value) {
  final normalized = normalizeWorkManualText(value);
  return normalized.trim().isEmpty ? '' : normalized;
}

bool isWorkManualBlank(String value) {
  return normalizeWorkManualText(value).trim().isEmpty;
}

int workManualLineCount(String value) {
  final normalized = normalizeWorkManualText(value);
  if (normalized.isEmpty) return 0;
  return normalized.split('\n').length;
}
