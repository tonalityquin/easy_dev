enum TerminalLineType {
  command,
  running,
  output,
  success,
  error,
  system,
}

class TerminalLine {
  const TerminalLine({
    required this.id,
    required this.type,
    required this.text,
  });

  final int id;
  final TerminalLineType type;
  final String text;

  TerminalLine copyWith({
    TerminalLineType? type,
    String? text,
  }) {
    return TerminalLine(
      id: id,
      type: type ?? this.type,
      text: text ?? this.text,
    );
  }
}
