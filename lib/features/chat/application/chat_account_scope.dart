import '../../account/domain/models/session_account.dart';
import 'chat_area_key.dart';

class ChatAccountScope {
  const ChatAccountScope({
    required this.userId,
    required this.division,
    required this.selectedArea,
    required this.isWorking,
  });

  final String userId;
  final String division;
  final String selectedArea;
  final bool isWorking;

  bool get isValid =>
      userId.isNotEmpty && division.isNotEmpty && selectedArea.isNotEmpty;

  bool get isHeadquarter => sameChatIdentity(division, selectedArea);

  String get key => <String>[
        userId,
        division,
        selectedArea,
        isHeadquarter ? '1' : '0',
        isWorking ? '1' : '0',
      ].join('\u0001');

  bool canAccessChannel({
    required String areaName,
    required bool isHeadquarterChannel,
  }) {
    if (!isValid) return false;
    if (isHeadquarterChannel) return isHeadquarter;
    if (isHeadquarter) return areaName.trim().isNotEmpty;
    return sameChatIdentity(areaName, selectedArea);
  }

  String channelIdFor({
    required String areaName,
    required bool isHeadquarterChannel,
  }) {
    if (!canAccessChannel(
      areaName: areaName,
      isHeadquarterChannel: isHeadquarterChannel,
    )) {
      return '';
    }
    return buildChatChannelId(
      division: division,
      areaName: areaName,
      isHeadquarter: isHeadquarterChannel,
    );
  }

  factory ChatAccountScope.fromSession(SessionAccount? session) {
    if (session == null) {
      return const ChatAccountScope(
        userId: '',
        division: '',
        selectedArea: '',
        isWorking: false,
      );
    }
    return ChatAccountScope(
      userId: session.id.trim(),
      division: _firstNonEmpty(session.divisions),
      selectedArea: session.selectedArea.trim(),
      isWorking: session.isWorking,
    );
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final clean = value.trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }
}
