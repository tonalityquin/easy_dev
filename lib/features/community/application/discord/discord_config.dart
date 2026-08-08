import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String discordWalkieTutorialDoneKey = 'discord_walkie_tutorial_done';
const String discordWalkieInviteUrlKey = 'discord_walkie_invite_url';
const String discordWalkieChannelUrlKey = 'discord_walkie_channel_url';

bool isDiscordInviteUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  final lower = v.toLowerCase();
  return lower.contains('discord.gg/') || lower.contains('discord.com/invite/');
}

bool isDiscordChannelUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
  final host = uri.host.toLowerCase();
  if (host != 'discord.com' && host != 'www.discord.com') return false;
  final segments = uri.pathSegments;
  if (segments.length != 3 || segments.first.toLowerCase() != 'channels') {
    return false;
  }
  final snowflake = RegExp(r'^\d+$');
  return snowflake.hasMatch(segments[1]) && snowflake.hasMatch(segments[2]);
}

String? discordChannelDeepLink(String value) {
  if (!isDiscordChannelUrl(value)) return null;
  final uri = Uri.parse(value.trim());
  final segments = uri.pathSegments;
  return 'discord:///channels/${segments[1]}/${segments[2]}';
}

Future<String> loadDiscordInviteUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getString(discordWalkieInviteUrlKey) ?? '').trim();
}

Future<String> loadDiscordChannelUrl() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getString(discordWalkieChannelUrlKey) ?? '').trim();
}

Future<void> replaceDiscordInviteUrl(String value) {
  return _replaceDiscordValue(
    key: discordWalkieInviteUrlKey,
    value: value,
    validator: isDiscordInviteUrl,
    label: 'invite',
  );
}

Future<void> replaceDiscordChannelUrl(String value) {
  return _replaceDiscordValue(
    key: discordWalkieChannelUrlKey,
    value: value,
    validator: isDiscordChannelUrl,
    label: 'communication',
  );
}

Future<void> restoreDiscordInviteUrl(String value) {
  return _restoreDiscordValue(
    key: discordWalkieInviteUrlKey,
    value: value,
    label: 'invite',
  );
}

Future<void> restoreDiscordChannelUrl(String value) {
  return _restoreDiscordValue(
    key: discordWalkieChannelUrlKey,
    value: value,
    label: 'communication',
  );
}

Future<void> _restoreDiscordValue({
  required String key,
  required String value,
  required String label,
}) async {
  final normalized = value.trim();
  final prefs = await SharedPreferences.getInstance();

  if (normalized.isEmpty) {
    await prefs.remove(key);
  } else {
    final saved = await prefs.setString(key, normalized);
    if (!saved) {
      throw StateError('Discord $label 롤백 저장 실패');
    }
  }

  await prefs.reload();
  final verified = (prefs.getString(key) ?? '').trim();
  if (verified != normalized) {
    throw StateError('Discord $label 롤백 검증 실패');
  }

  debugPrint(
    '[DiscordConfig] $label 롤백 값 복원 완료: restoredPresent=${normalized.isNotEmpty} restoredLength=${normalized.length}',
  );
}

Future<void> _replaceDiscordValue({
  required String key,
  required String value,
  required bool Function(String) validator,
  required String label,
}) async {
  final normalized = value.trim();
  if (!validator(normalized)) {
    throw FormatException('유효하지 않은 Discord $label 값입니다.');
  }

  final prefs = await SharedPreferences.getInstance();
  final previous = (prefs.getString(key) ?? '').trim();

  debugPrint(
    '[DiscordConfig] $label 교체 시작: previousPresent=${previous.isNotEmpty} previousLength=${previous.length} nextLength=${normalized.length}',
  );

  try {
    final removed = await prefs.remove(key);
    await prefs.reload();

    if (prefs.containsKey(key)) {
      throw StateError('기존 Discord $label 로컬값 삭제 검증 실패');
    }

    debugPrint(
      '[DiscordConfig] 기존 $label 삭제 완료: removed=$removed',
    );

    final saved = await prefs.setString(key, normalized);
    if (!saved) {
      throw StateError('새 Discord $label 로컬 저장 실패');
    }

    await prefs.reload();
    final verified = (prefs.getString(key) ?? '').trim();
    if (verified != normalized) {
      throw StateError('새 Discord $label 로컬 저장 검증 실패');
    }

    debugPrint(
      '[DiscordConfig] 새 $label 저장 및 검증 완료: length=${verified.length}',
    );
  } catch (error) {
    try {
      if (previous.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, previous);
      }
      await prefs.reload();
      final rollbackValue = (prefs.getString(key) ?? '').trim();
      if (rollbackValue != previous) {
        throw StateError('Discord $label 롤백 검증 실패');
      }
      debugPrint(
        '[DiscordConfig] $label 교체 실패로 기존 값 복구 완료: restoredPresent=${previous.isNotEmpty} restoredLength=${previous.length}',
      );
    } catch (rollbackError) {
      debugPrint(
        '[DiscordConfig] $label 교체 롤백 실패: $rollbackError',
      );
    }
    rethrow;
  }
}
