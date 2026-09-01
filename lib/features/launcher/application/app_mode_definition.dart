class AppModeDefinition {
  const AppModeDefinition({
    required this.id,
    required this.koreanName,
    required this.englishName,
    required this.description,
    required this.aliases,
    required this.postLoginRoute,
  });

  final String id;
  final String koreanName;
  final String englishName;
  final String description;
  final Set<String> aliases;
  final String postLoginRoute;
}
