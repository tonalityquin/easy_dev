import 'app_command_definition.dart';

class AppCommandRegistry {
  AppCommandRegistry._();

  static const String basicCategory = '기본';
  static const String developerCategory = '개발자';

  static const List<AppCommandDefinition> commands = <AppCommandDefinition>[
    AppCommandDefinition(
      command: 'quick',
      title: '빠른 실행',
      description: '본사 빠른 실행 핸들을 활성화합니다.',
      category: basicCategory,
      runningMessage: '빠른 실행 환경을 준비 중...',
      successMessage: '[ok] 빠른 실행을 활성화했습니다.',
    ),
    AppCommandDefinition(
      command: 'setting',
      title: '설정 경로',
      description: '설정 경로로 이동합니다.',
      category: basicCategory,
      runningMessage: '설정 경로를 준비 중...',
      successMessage: '[ok] ~/setting',
    ),
    AppCommandDefinition(
      command: 'charge',
      title: '청구',
      description: '청구 집계 화면을 엽니다.',
      category: basicCategory,
      runningMessage: '청구 집계를 준비 중...',
      successMessage: '[ok] 청구 화면을 열었습니다.',
      launchesSurface: true,
    ),
    AppCommandDefinition(
      command: 'about',
      title: '앱 소개',
      description: 'ParkinWorkin 소개 화면을 엽니다.',
      category: basicCategory,
      runningMessage: 'ParkinWorkin 정보를 준비 중...',
      successMessage: '[ok] 앱 소개 화면을 열었습니다.',
      launchesSurface: true,
    ),
    AppCommandDefinition(
      command: 'out',
      title: '터미널 종료',
      description: '현재 ParkinWorkin Terminal을 닫습니다.',
      category: basicCategory,
      runningMessage: 'Terminal session을 정리 중...',
      successMessage: '[ok] Terminal close ready.',
    ),
    AppCommandDefinition(
      command: 'exit',
      title: '앱 종료',
      description: 'ParkinWorkin 앱을 종료합니다.',
      category: basicCategory,
      runningMessage: 'ParkinWorkin 종료를 준비 중...',
      successMessage: '[ok] App exit requested.',
    ),
    AppCommandDefinition(
      command: 'status',
      title: '시스템 상태',
      description: '현재 ParkinWorkin Terminal 상태를 확인합니다.',
      category: basicCategory,
      runningMessage: 'Terminal 상태를 정리 중...',
      successMessage: '[ok] Terminal status ready.',
    ),
    AppCommandDefinition(
      command: 'help',
      title: 'Command Reference',
      description: '지원하는 고정 명령어를 확인합니다.',
      category: basicCategory,
      runningMessage: '지원 명령어를 조회 중...',
      successMessage: '[ok] 지원 명령 목록을 불러왔습니다.',
      visibleInHelp: false,
    ),
    AppCommandDefinition(
      command: 'debug',
      title: 'DEBUG 세션',
      description: 'DEBUG 세션과 개발자 도구를 활성화합니다.',
      category: developerCategory,
      runningMessage: 'DEBUG 세션을 활성화 중...',
      successMessage: '[ok] DEBUG session active.',
    ),
  ];

  static List<AppCommandDefinition> get visibleCommands =>
      List<AppCommandDefinition>.unmodifiable(
        commands.where((definition) => definition.visibleInHelp),
      );

  static String normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static AppCommandDefinition? find(String rawCommand) {
    final normalized = normalize(rawCommand);
    if (normalized.isEmpty) return null;
    final ordered = commands.toList()
      ..sort((a, b) => b.command.length.compareTo(a.command.length));
    for (final definition in ordered) {
      if (definition.command == normalized) return definition;
    }
    return null;
  }

  static List<String> get categories {
    final result = <String>[];
    for (final definition in visibleCommands) {
      if (!result.contains(definition.category)) {
        result.add(definition.category);
      }
    }
    return List<String>.unmodifiable(result);
  }

  static List<AppCommandDefinition> byCategory(String category) {
    return List<AppCommandDefinition>.unmodifiable(
      visibleCommands.where((definition) => definition.category == category),
    );
  }
}
