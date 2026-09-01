class AppCommandDefinition {
  const AppCommandDefinition({
    required this.command,
    required this.title,
    required this.description,
    required this.category,
    required this.runningMessage,
    required this.successMessage,
    this.launchesSurface = false,
    this.visibleInHelp = true,
  });

  final String command;
  final String title;
  final String description;
  final String category;
  final String runningMessage;
  final String successMessage;
  final bool launchesSurface;
  final bool visibleInHelp;
}
