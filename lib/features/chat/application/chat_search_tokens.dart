String normalizeChatSearchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^0-9a-z가-힣]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> chatSearchTerms(String value) {
  final normalized = normalizeChatSearchText(value);
  if (normalized.isEmpty) return const <String>[];
  return normalized
      .split(' ')
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
}

List<String> buildCompactChatSearchTokens({
  required String text,
  required String senderName,
  required String senderIdentity,
}) {
  final source = normalizeChatSearchText(
    '$senderName $senderIdentity $text',
  );
  if (source.isEmpty) return const <String>[];

  final words = source
      .split(' ')
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  final tokens = <String>{};

  for (final word in words) {
    tokens.add(word);
    final digits = word.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) {
      tokens.add(digits.substring(digits.length - 4));
    }
    if (tokens.length >= 32) {
      return tokens.take(32).toList(growable: false);
    }
  }

  for (final word in words) {
    final maxPrefixLength = word.length > 8 ? 8 : word.length;
    for (var length = 2; length <= maxPrefixLength; length += 1) {
      tokens.add(word.substring(0, length));
      if (tokens.length >= 32) {
        return tokens.take(32).toList(growable: false);
      }
    }
  }

  return tokens.toList(growable: false);
}

String chatServerSearchToken(String query) {
  final terms = chatSearchTerms(query);
  if (terms.isEmpty) return '';
  final candidates = terms.where((term) => term.length >= 2).toList();
  if (candidates.isEmpty) return '';
  candidates.sort((a, b) => b.length.compareTo(a.length));
  return candidates.first;
}
