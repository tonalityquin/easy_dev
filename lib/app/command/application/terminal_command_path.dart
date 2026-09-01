enum TerminalCommandPath {
  root,
  setting,
  settingEmailEdit,
}

extension TerminalCommandPathX on TerminalCommandPath {
  String get promptPath => switch (this) {
        TerminalCommandPath.root => '~',
        TerminalCommandPath.setting => '~/setting',
        TerminalCommandPath.settingEmailEdit => '~/setting/email',
      };

  bool get isRoot => this == TerminalCommandPath.root;
  bool get isSetting => this != TerminalCommandPath.root;
  bool get isEmailEdit => this == TerminalCommandPath.settingEmailEdit;
}
