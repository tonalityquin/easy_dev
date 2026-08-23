import '../../../../shared/area_remote_settings/application/area_snapshot_scope.dart';

const String discordWalkieTutorialDoneKey = 'discord_walkie_tutorial_done';

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
  final area = await AreaSnapshotScope.readCurrentArea();
  return area?.invite.trim() ?? '';
}

Future<String> loadDiscordChannelUrl() async {
  final area = await AreaSnapshotScope.readCurrentArea();
  return area?.communication.trim() ?? '';
}
