const String discordWalkieTutorialDoneKey = 'discord_walkie_tutorial_done';
const String discordWalkieInviteUrlKey = 'discord_walkie_invite_url';

bool isDiscordInviteUrl(String value) {
  final v = value.trim();
  if (v.isEmpty) return false;
  final lower = v.toLowerCase();
  return lower.contains('discord.gg/') || lower.contains('discord.com/invite/');
}
