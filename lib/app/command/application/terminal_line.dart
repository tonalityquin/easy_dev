enum TerminalLineType {
  command,
  running,
  output,
  success,
  error,
  system,
}

enum TerminalCadence {
  automatic,
  instant,
  thinking,
  preparing,
  configuring,
  responding,
  emphasis,
  error,
}

class TerminalLine {
  const TerminalLine({
    required this.id,
    required this.type,
    required this.text,
    this.cadence = TerminalCadence.automatic,
    this.promptPath = '~',
  });

  final int id;
  final TerminalLineType type;
  final String text;
  final TerminalCadence cadence;
  final String promptPath;

  TerminalLine copyWith({
    TerminalLineType? type,
    String? text,
    TerminalCadence? cadence,
    String? promptPath,
  }) {
    return TerminalLine(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
      cadence: cadence ?? this.cadence,
      promptPath: promptPath ?? this.promptPath,
    );
  }
}
