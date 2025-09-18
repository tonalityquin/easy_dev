import 'package:shared_preferences/shared_preferences.dart';

class TtsUserFilters {
  final bool parking; // 입차 요청
  final bool departure; // 출차 요청
  final bool completed; // 출차 완료
  final bool chat; // ✅ 채팅 읽어주기

  const TtsUserFilters({
    required this.parking,
    required this.departure,
    required this.completed,
    required this.chat,
  });

  factory TtsUserFilters.defaults() => const TtsUserFilters(
        parking: true,
        departure: true,
        completed: true,
        chat: true, // ✅ 기본값: 켜짐
      );

  TtsUserFilters copyWith({
    bool? parking,
    bool? departure,
    bool? completed,
    bool? chat,
  }) {
    return TtsUserFilters(
      parking: parking ?? this.parking,
      departure: departure ?? this.departure,
      completed: completed ?? this.completed,
      chat: chat ?? this.chat,
    );
  }

  Map<String, dynamic> toMap() => {
        'parking': parking,
        'departure': departure,
        'completed': completed,
        'chat': chat,
      };

  factory TtsUserFilters.fromMap(Map? m) {
    if (m == null) return TtsUserFilters.defaults();
    return TtsUserFilters(
      parking: (m['parking'] ?? true) as bool,
      departure: (m['departure'] ?? true) as bool,
      completed: (m['completed'] ?? true) as bool,
      chat: (m['chat'] ?? true) as bool, // ✅ 신규 키, 없으면 기본 true
    );
  }

  static const _kParking = 'tts.parking';
  static const _kDeparture = 'tts.departure';
  static const _kCompleted = 'tts.completed';
  static const _kChat = 'tts.chat'; // ✅ 신규

  static Future<TtsUserFilters> load() async {
    final prefs = await SharedPreferences.getInstance();
    final hasAny = prefs.containsKey(_kParking) ||
        prefs.containsKey(_kDeparture) ||
        prefs.containsKey(_kCompleted) ||
        prefs.containsKey(_kChat);
    if (!hasAny) return TtsUserFilters.defaults();
    return TtsUserFilters(
      parking: prefs.getBool(_kParking) ?? true,
      departure: prefs.getBool(_kDeparture) ?? true,
      completed: prefs.getBool(_kCompleted) ?? true,
      chat: prefs.getBool(_kChat) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kParking, parking);
    await prefs.setBool(_kDeparture, departure);
    await prefs.setBool(_kCompleted, completed);
    await prefs.setBool(_kChat, chat); // ✅ 저장
  }
}
