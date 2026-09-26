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
    this.terminalPath = '~',
  });

  final int id;
  final TerminalLineType type;
  final String text;
  final TerminalCadence cadence;
  final String terminalPath;

  TerminalLine copyWith({
    TerminalLineType? type,
    String? text,
    TerminalCadence? cadence,
    String? terminalPath,
  }) {
    return TerminalLine(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
      cadence: cadence ?? this.cadence,
      terminalPath: terminalPath ?? this.terminalPath,
    );
  }
}
