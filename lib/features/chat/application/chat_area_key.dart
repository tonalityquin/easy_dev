const String headquarterChatAreaName = '본사';
const String headquarterChatAreaKey = 'headquarters';
const String chatChannelTypeHeadquarter = 'headquarter';
const String chatChannelTypeArea = 'area';

String normalizeChatIdentity(String value) {
  return value.trim();
}

bool sameChatIdentity(String left, String right) {
  final normalizedLeft = normalizeChatIdentity(left);
  final normalizedRight = normalizeChatIdentity(right);
  return normalizedLeft.isNotEmpty &&
      normalizedRight.isNotEmpty &&
      normalizedLeft == normalizedRight;
}

bool isHeadquarterChatAreaName(String areaName) {
  final value = areaName.trim().toLowerCase();
  return value == '본사' ||
      value == 'hq' ||
      value == 'headquarter' ||
      value == 'headquarters';
}

String encodeChatKeyPart(String value) {
  final normalized = normalizeChatIdentity(value);
  if (normalized.isEmpty) return '';
  return Uri.encodeComponent(normalized);
}

String normalizeChatCompanyKey(String division) {
  return encodeChatKeyPart(division);
}

String normalizeChatAreaKey(String areaName) {
  if (isHeadquarterChatAreaName(areaName)) {
    return headquarterChatAreaKey;
  }
  return encodeChatKeyPart(areaName);
}

String buildChatChannelId({
  required String division,
  required String areaName,
  required bool isHeadquarter,
}) {
  final companyKey = normalizeChatCompanyKey(division);
  if (companyKey.isEmpty) return '';
  if (isHeadquarter) {
    return '$companyKey|$chatChannelTypeHeadquarter';
  }
  final areaKey = normalizeChatAreaKey(areaName);
  if (areaKey.isEmpty || areaKey == headquarterChatAreaKey) return '';
  return '$companyKey|$chatChannelTypeArea|$areaKey';
}
