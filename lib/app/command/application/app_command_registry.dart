import 'app_command_definition.dart';

class AppCommandRegistry {
  AppCommandRegistry._();

  static const String basicCategory = '기본';
  static const String developerCategory = '개발자';

  static const List<AppCommandDefinition> commands = <AppCommandDefinition>[
    AppCommandDefinition(
      command: 'quick button',
      title: '빠른 실행',
      description: '본사 빠른 실행 핸들을 활성화합니다.',
      category: basicCategory,
      runningMessage: '빠른 실행 환경을 준비 중...',
      successMessage: '[ok] 빠른 실행을 활성화했습니다.',
    ),
    AppCommandDefinition(
      command: 'setting',
      title: '서비스 설정',
      description: '서비스 설정 화면을 엽니다.',
      category: basicCategory,
      runningMessage: '서비스 설정을 열람 중...',
      successMessage: '[ok] 서비스 설정 화면을 열었습니다.',
      launchesSurface: true,
    ),
    AppCommandDefinition(
      command: 'help',
      title: 'Command Reference',
      description: '지원하는 고정 명령어를 확인합니다.',
      category: basicCategory,
      runningMessage: '지원 명령어를 조회 중...',
      successMessage: '[ok] 지원 명령 목록을 불러왔습니다.',
    ),
    AppCommandDefinition(
      command: 'debug',
      title: '개발자 모드',
      description: '개발자 모드를 활성화합니다.',
      category: developerCategory,
      runningMessage: '개발자 환경을 활성화 중...',
      successMessage: '[ok] developer mode enabled.',
    ),
  ];

  static String normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static AppCommandDefinition? find(String rawCommand) {
    final normalized = normalize(rawCommand);
    if (normalized.isEmpty) return null;
    for (final definition in commands) {
      if (definition.command == normalized) return definition;
    }
    return null;
  }

  static List<String> get categories {
    final result = <String>[];
    for (final definition in commands) {
      if (!result.contains(definition.category)) {
        result.add(definition.category);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static List<AppCommandDefinition> byCategory(String category) {
    return List<AppCommandDefinition>.unmodifiable(
      commands.where((definition) => definition.category == category),
    );
  }
}
