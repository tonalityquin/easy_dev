import '../../command/application/terminal_line.dart';

class TerminalOutputPacing {
  const TerminalOutputPacing._();

  static TerminalCadence cadenceFor(TerminalLine line) {
    if (line.cadence != TerminalCadence.automatic) return line.cadence;
    if (line.type == TerminalLineType.command) return TerminalCadence.instant;
    if (line.type == TerminalLineType.error) return TerminalCadence.error;
    if (line.type == TerminalLineType.success) return TerminalCadence.emphasis;
    if (line.type == TerminalLineType.running) return TerminalCadence.thinking;
    if (_isDivider(line.text)) return TerminalCadence.instant;
    final normalized = line.text.toLowerCase();
    if (normalized.contains('checking') ||
        normalized.contains('authenticating') ||
        normalized.contains('session') ||
        normalized.contains('조회') ||
        normalized.contains('확인')) {
      return TerminalCadence.thinking;
    }
    if (normalized.contains('preparing') ||
        normalized.contains('opening') ||
        normalized.contains('loading') ||
        normalized.contains('준비') ||
        normalized.contains('불러')) {
      return TerminalCadence.preparing;
    }
    if (normalized.contains('storage db') ||
        normalized.contains('live db') ||
        normalized.contains('notifications') ||
        normalized.contains('foreground') ||
        normalized.contains('config') ||
        normalized.contains('설정')) {
      return TerminalCadence.configuring;
    }
    return TerminalCadence.responding;
  }

  static Duration characterDelay(
    TerminalLine line,
    int index, {
    required bool reduceMotion,
  }) {
    if (reduceMotion) return const Duration(milliseconds: 2);
    if (line.type == TerminalLineType.command) return Duration.zero;
    if (_isDivider(line.text)) {
      return Duration(milliseconds: 4 + _jitter(line, index, 3));
    }
    final cadence = cadenceFor(line);
    final bounds = switch (cadence) {
      TerminalCadence.instant => (10, 16),
      TerminalCadence.thinking => (29, 44),
      TerminalCadence.preparing => (27, 42),
      TerminalCadence.configuring => (25, 39),
      TerminalCadence.responding => (26, 41),
      TerminalCadence.emphasis => (31, 48),
      TerminalCadence.error => (18, 29),
      TerminalCadence.automatic => (26, 41),
    };
    var delay = bounds.$1 + _jitter(line, index, bounds.$2 - bounds.$1 + 1);
    final char = line.text[index];
    if (char == ' ') {
      delay = (delay * .68).round();
    } else if (char == ',' || char == ':' || char == ';') {
      delay += 34;
    } else if (char == '.') {
      delay += 52;
    } else if (char == '?' || char == '!') {
      delay += 62;
    }
    return Duration(milliseconds: delay);
  }

  static Duration postLineDelay(
    TerminalLine line, {
    required bool reduceMotion,
  }) {
    if (reduceMotion) {
      return Duration(milliseconds: 10 + _jitter(line, line.text.length, 12));
    }
    if (line.type == TerminalLineType.command) {
      return Duration(milliseconds: 42 + _jitter(line, 1, 28));
    }
    if (_isDivider(line.text)) {
      return Duration(milliseconds: 72 + _jitter(line, 2, 38));
    }
    final cadence = cadenceFor(line);
    final bounds = switch (cadence) {
      TerminalCadence.instant => (72, 118),
      TerminalCadence.thinking => (205, 315),
      TerminalCadence.preparing => (175, 275),
      TerminalCadence.configuring => (165, 255),
      TerminalCadence.responding => (145, 235),
      TerminalCadence.emphasis => (230, 345),
      TerminalCadence.error => (96, 155),
      TerminalCadence.automatic => (145, 235),
    };
    return Duration(
      milliseconds: bounds.$1 +
          _jitter(line, line.text.length + line.id, bounds.$2 - bounds.$1 + 1),
    );
  }

  static Duration initialBreath({required bool reduceMotion}) {
    return reduceMotion
        ? const Duration(milliseconds: 12)
        : const Duration(milliseconds: 135);
  }

  static int _jitter(TerminalLine line, int salt, int range) {
    if (range <= 1) return 0;
    var hash = line.id * 1103515245 + salt * 12345 + line.type.index * 7919;
    for (final unit in line.text.codeUnits.take(16)) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash.abs() % range;
  }

  static bool _isDivider(String text) {
    if (text.length < 4) return false;
    return text.runes.every((rune) => rune == 0x2500 || rune == 0x2D);
  }
}
