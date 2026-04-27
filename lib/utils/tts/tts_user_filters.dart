import 'package:shared_preferences/shared_preferences.dart';

class TtsUserFilters {
  final bool parking; 
  final bool departure; 
  final bool completed; 

  const TtsUserFilters({
    required this.parking,
    required this.departure,
    required this.completed,
  });

  factory TtsUserFilters.defaults() => const TtsUserFilters(
    parking: true,
    departure: true,
    completed: true,
  );

  TtsUserFilters copyWith({
    bool? parking,
    bool? departure,
    bool? completed,
  }) {
    return TtsUserFilters(
      parking: parking ?? this.parking,
      departure: departure ?? this.departure,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toMap() => {
    'parking': parking,
    'departure': departure,
    'completed': completed,
  };

  factory TtsUserFilters.fromMap(Map? m) {
    if (m == null) return TtsUserFilters.defaults();
    return TtsUserFilters(
      parking: (m['parking'] ?? true) as bool,
      departure: (m['departure'] ?? true) as bool,
      completed: (m['completed'] ?? true) as bool,
    );
  }

  static const _kParking = 'tts.parking';
  static const _kDeparture = 'tts.departure';
  static const _kCompleted = 'tts.completed';

  static Future<TtsUserFilters> load() async {
    final prefs = await SharedPreferences.getInstance();

    final hasAny =
        prefs.containsKey(_kParking) || prefs.containsKey(_kDeparture) || prefs.containsKey(_kCompleted);

    if (!hasAny) return TtsUserFilters.defaults();

    return TtsUserFilters(
      parking: prefs.getBool(_kParking) ?? true,
      departure: prefs.getBool(_kDeparture) ?? true,
      completed: prefs.getBool(_kCompleted) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kParking, parking);
    await prefs.setBool(_kDeparture, departure);
    await prefs.setBool(_kCompleted, completed);
  }
}
