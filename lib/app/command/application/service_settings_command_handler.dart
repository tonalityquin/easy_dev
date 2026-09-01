import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/auth/gmail_sender_auth.dart';
import '../../../app/auth/gmail_sender_diagnostics.dart';
import '../../../app/config/email_config.dart';
import '../../../app/config/gmail_sender_config.dart';
import '../../../app/config/overlay_edge_side_config.dart';
import '../../../app/config/overlay_mode_config.dart';
import '../../../app/theme/brand_theme.dart';
import '../../../app/theme/theme_prefs_controller.dart';
import '../../../features/dev/application/debug_session_controller.dart';
import '../../../features/selector/application/dev_auth.dart';
import 'terminal_command_path.dart';

class ServiceSettingsCommandResult {
  const ServiceSettingsCommandResult.success(
    this.lines, {
    this.nextPath,
  }) : succeeded = true;

  const ServiceSettingsCommandResult.failure(
    this.lines, {
    this.nextPath,
  }) : succeeded = false;

  final bool succeeded;
  final List<String> lines;
  final TerminalCommandPath? nextPath;
}

class ServiceSettingsCommandHandler {
  ServiceSettingsCommandHandler._();

  static const String _kbPresetId = 'kb';
  static const String _defaultIndependentPresetId = 'soft_linen';
  static const Set<String> _kbThemeAllowedAreas = <String>{
    'KB라이프타워',
    'KB라이프역삼',
  };

  static Future<ServiceSettingsCommandResult> execute(
    BuildContext context,
    String rawCommand, {
    required String source,
  }) async {
    final normalized = _normalize(rawCommand);
    final args = normalized.isEmpty ? <String>[] : normalized.split(' ');
    final prefs = await SharedPreferences.getInstance();
    final selectedArea = (prefs.getString('selectedArea') ?? '').trim();
    final singleMode =
        (prefs.getString('mode') ?? '').trim().toLowerCase() == 'single';
    final debugEnabled = await DevAuth.isDevModeEnabled();
    if (!context.mounted) {
      return const ServiceSettingsCommandResult.failure(<String>[
        '[error] Terminal context가 종료되었습니다.',
      ]);
    }
    final themeController = context.read<ThemePrefsController>();
    if (!themeController.loaded) {
      await themeController.load();
    }
    await _ensurePresetAllowed(
      themeController,
      selectedArea: selectedArea,
    );

    DebugSessionController.record(
      'service_setting_command_start',
      source: source,
      meta: <String, Object?>{
        'command': normalized,
        'debug': debugEnabled,
      },
    );

    final result = await _executeArgs(
      args,
      themeController: themeController,
      selectedArea: selectedArea,
      singleMode: singleMode,
      debugEnabled: debugEnabled,
    );

    DebugSessionController.record(
      result.succeeded
          ? 'service_setting_command_complete'
          : 'service_setting_command_rejected',
      source: source,
      meta: <String, Object?>{
        'command': normalized,
        'debug': debugEnabled,
        'lines': result.lines.length,
      },
    );
    return result;
  }

  static Future<ServiceSettingsCommandResult> _executeArgs(
    List<String> args, {
    required ThemePrefsController themeController,
    required String selectedArea,
    required bool singleMode,
    required bool debugEnabled,
  }) async {
    if (args.isEmpty) {
      return _help(
        const <String>[],
        themeController: themeController,
        selectedArea: selectedArea,
        debugEnabled: debugEnabled,
        singleMode: singleMode,
      );
    }

    switch (args.first) {
      case 'help':
        return _help(
          args.skip(1).toList(),
          themeController: themeController,
          selectedArea: selectedArea,
          debugEnabled: debugEnabled,
          singleMode: singleMode,
        );
      case 'theme':
        return _theme(args.skip(1).toList(), themeController, selectedArea);
      case 'color':
        return _color(args.skip(1).toList(), themeController, selectedArea);
      case 'edge':
        return _edge(args.skip(1).toList());
      case 'email':
        return _email(args.skip(1).toList());
      case 'edit':
        if (args.length == 2 && args[1] == 'email') {
          return _beginEmailEdit();
        }
        return const ServiceSettingsCommandResult.failure(<String>[
          '[error] edit',
          'edit email',
        ]);
      case 'overlay':
        if (!debugEnabled) return _debugRequired('overlay');
        return _overlay(args.skip(1).toList(), singleMode: singleMode);
      case 'recipient':
        if (!debugEnabled) return _debugRequired('recipient');
        return _recipient(args.skip(1).toList());
      default:
        return ServiceSettingsCommandResult.failure(<String>[
          '[error] command: ${args.first}',
          'help',
        ]);
    }
  }

  static Future<ServiceSettingsCommandResult> _help(
    List<String> args, {
    required ThemePrefsController themeController,
    required String selectedArea,
    required bool debugEnabled,
    required bool singleMode,
  }) async {
    if (args.length > 1) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] help',
        ..._helpTopicLines(debugEnabled: debugEnabled),
      ]);
    }

    if (args.isNotEmpty) {
      switch (args.first) {
        case 'theme':
          return ServiceSettingsCommandResult.success(
            _themeHelpLines(themeController),
          );
        case 'color':
          return ServiceSettingsCommandResult.success(
            _colorHelpLines(
              themeController,
              selectedArea: selectedArea,
            ),
          );
        case 'edge':
          return ServiceSettingsCommandResult.success(
            await _edgeHelpLines(),
          );
        case 'email':
          return ServiceSettingsCommandResult.success(
            await _emailHelpLines(),
          );
        case 'overlay':
          if (!debugEnabled) return _debugRequired('overlay');
          return ServiceSettingsCommandResult.success(
            await _overlayHelpLines(singleMode: singleMode),
          );
        case 'recipient':
          if (!debugEnabled) return _debugRequired('recipient');
          return const ServiceSettingsCommandResult.success(<String>[
            'RECIPIENT',
            'recipient       현재 수신자',
            'recipient copy  클립보드 복사',
            '',
            'COMMAND',
            'recipient',
            'recipient copy',
          ]);
        default:
          return ServiceSettingsCommandResult.failure(<String>[
            '[error] help ${args.first}',
            ..._helpTopicLines(debugEnabled: debugEnabled),
          ]);
      }
    }

    final edge = await OverlayEdgeSideConfig.getSide();
    final lines = <String>[
      'CURRENT',
      'theme       ${themeController.themeModeId}',
      'color       ${themeController.presetId}',
      'edge        ${_edgeId(edge)}',
    ];
    if (debugEnabled) {
      final storedOverlay = await OverlayModeConfig.getMode();
      final effectiveOverlay = _effectiveOverlayMode(
        storedOverlay,
        singleMode: singleMode,
      );
      lines.add('overlay     ${_overlayId(effectiveOverlay)}');
    }
    lines.addAll(<String>[
      '',
      ..._themeHelpLines(themeController, includeCurrent: false),
      '',
      ..._colorHelpLines(
        themeController,
        selectedArea: selectedArea,
        includeCurrent: false,
      ),
      '',
      ...await _edgeHelpLines(includeCurrent: false),
      '',
      ...await _emailHelpLines(includeCurrent: false),
    ]);
    if (debugEnabled) {
      lines.addAll(<String>[
        '',
        ...await _overlayHelpLines(
          singleMode: singleMode,
          includeCurrent: false,
        ),
        '',
        'RECIPIENT',
        'recipient       현재 수신자',
        'recipient copy  클립보드 복사',
        '',
        'COMMAND',
        'recipient',
        'recipient copy',
      ]);
    }
    lines.addAll(<String>[
      '',
      'HELP',
      'help',
      'help theme',
      'help color',
      'help edge',
      'help email',
      if (debugEnabled) 'help overlay',
      if (debugEnabled) 'help recipient',
      '',
      'NAVIGATION',
      'cd ..',
    ]);
    return ServiceSettingsCommandResult.success(lines);
  }

  static List<String> _themeHelpLines(
    ThemePrefsController themeController, {
    bool includeCurrent = true,
  }) {
    final specs = themeModeSpecs();
    return <String>[
      'THEME',
      if (includeCurrent) 'current     ${themeController.themeModeId}',
      for (final spec in specs) '${spec.id.padRight(12)}${spec.label}',
      '',
      'COMMAND',
      'theme',
      for (final spec in specs) 'theme ${spec.id}',
    ];
  }

  static List<String> _colorHelpLines(
    ThemePrefsController themeController, {
    required String selectedArea,
    bool includeCurrent = true,
  }) {
    final available = _allowedPresets(
      themeController.themeModeId,
      selectedArea: selectedArea,
    );
    return <String>[
      'COLOR',
      if (includeCurrent) 'current     ${themeController.presetId}',
      'theme       ${themeController.themeModeId}',
      for (final preset in available) '${preset.id.padRight(16)}${preset.label}',
      '',
      'COMMAND',
      'color',
      'color list',
      for (final preset in available) 'color ${preset.id}',
    ];
  }

  static Future<List<String>> _edgeHelpLines({
    bool includeCurrent = true,
  }) async {
    final current = await OverlayEdgeSideConfig.getSide();
    return <String>[
      'EDGE',
      if (includeCurrent) 'current     ${_edgeId(current)}',
      'left        왼쪽',
      'right       오른쪽',
      '',
      'COMMAND',
      'edge',
      'edge left',
      'edge right',
    ];
  }

  static Future<List<String>> _emailHelpLines({
    bool includeCurrent = true,
  }) async {
    final status = await GmailSenderAuth.status();
    return <String>[
      'EMAIL',
      if (includeCurrent) ...status.statusLines,
      'local-part only  ${GmailSenderConfig.suffix}',
      '',
      'COMMAND',
      'email',
      'edit email',
    ];
  }

  static Future<ServiceSettingsCommandResult> _email(List<String> args) async {
    if (args.isNotEmpty) {
      return const ServiceSettingsCommandResult.failure(<String>[
        '[error] email',
        'email',
        'edit email',
      ]);
    }
    final status = await GmailSenderAuth.status();
    GmailSenderDiagnostics.record(
      'terminal_status',
      meta: <String, Object?>{
        'configured': status.configuredEmail.isEmpty ? '-' : status.configuredEmail,
        'authenticated': status.authenticatedEmail.isEmpty ? '-' : status.authenticatedEmail,
        'state': status.state,
      },
    );
    return ServiceSettingsCommandResult.success(<String>[
      'EMAIL STATUS',
      '────────────────────────────────',
      ...status.statusLines,
      '────────────────────────────────',
      '',
      '수정하려면:',
      'edit email',
    ]);
  }

  static ServiceSettingsCommandResult _beginEmailEdit() {
    GmailSenderDiagnostics.record('terminal_edit_begin');
    return const ServiceSettingsCommandResult.success(
      <String>[
        'EMAIL EDIT',
        '────────────────────────────────',
        'Gmail 앞자리만 입력하세요.',
        'domain          @gmail.com',
        'cancel로 취소할 수 있습니다.',
        '────────────────────────────────',
      ],
      nextPath: TerminalCommandPath.settingEmailEdit,
    );
  }

  static Future<ServiceSettingsCommandResult> submitEmailEdit(
    String rawLocalPart, {
    required String source,
  }) async {
    final localPart = GmailSenderConfig.normalizeLocalPart(rawLocalPart);
    GmailSenderDiagnostics.record(
      'terminal_edit_submit',
      meta: <String, Object?>{
        'source': source,
        'length': localPart.length,
      },
    );
    if (!GmailSenderConfig.isValidLocalPart(localPart)) {
      return const ServiceSettingsCommandResult.failure(<String>[
        '[error] Gmail 앞자리를 확인하세요.',
        '영문 소문자, 숫자, 마침표만 사용할 수 있습니다.',
        '마침표는 처음·끝·연속으로 사용할 수 없습니다.',
      ]);
    }
    final before = await GmailSenderConfig.readEmail() ?? '-';
    try {
      final status = await GmailSenderAuth.authenticateAndSetLocalPart(localPart);
      return ServiceSettingsCommandResult.success(
        <String>[
          'email: $before -> ${status.configuredEmail}',
          'oauth: ${status.state}',
          '[ok] Gmail 발신 계정 준비 완료',
        ],
        nextPath: TerminalCommandPath.setting,
      );
    } catch (error, stackTrace) {
      GmailSenderDiagnostics.record(
        'terminal_edit_failed',
        meta: <String, Object?>{
          'source': source,
          'error': error,
        },
      );
      debugPrint('[GMAIL_SENDER] terminal edit failed error=$error');
      debugPrint(stackTrace.toString());
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] Gmail 계정 인증을 완료하지 못했습니다.',
        'configured     $before',
        'requested      ${GmailSenderConfig.emailForLocalPart(localPart)}',
        'email',
      ]);
    }
  }

  static Future<List<String>> _overlayHelpLines({
    required bool singleMode,
    bool includeCurrent = true,
  }) async {
    final stored = await OverlayModeConfig.getMode();
    final current = _effectiveOverlayMode(
      stored,
      singleMode: singleMode,
    );
    return <String>[
      'OVERLAY',
      if (includeCurrent) 'current     ${_overlayId(current)}',
      'bubble      플로팅 버블',
      if (!singleMode) 'top         상단 포그라운드',
      '',
      'COMMAND',
      'overlay',
      'overlay bubble',
      if (!singleMode) 'overlay top',
    ];
  }

  static List<String> _helpTopicLines({required bool debugEnabled}) {
    return <String>[
      'help theme',
      'help color',
      'help edge',
      'help email',
      if (debugEnabled) 'help overlay',
      if (debugEnabled) 'help recipient',
    ];
  }

  static Future<ServiceSettingsCommandResult> _theme(
    List<String> args,
    ThemePrefsController themeController,
    String selectedArea,
  ) async {
    final specs = themeModeSpecs();
    if (args.isEmpty) {
      return ServiceSettingsCommandResult.success(
        _themeHelpLines(themeController),
      );
    }
    if (args.length != 1) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] theme',
        for (final spec in specs) 'theme ${spec.id}',
      ]);
    }
    final value = args.first;
    if (!specs.any((spec) => spec.id == value)) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] theme $value',
        for (final spec in specs) 'theme ${spec.id}',
      ]);
    }
    final beforeTheme = themeController.themeModeId;
    final beforePreset = themeController.presetId;
    await themeController.setThemeModeId(value);
    await _ensurePresetAllowed(themeController, selectedArea: selectedArea);
    return ServiceSettingsCommandResult.success(<String>[
      'theme: $beforeTheme -> ${themeController.themeModeId}',
      if (beforePreset != themeController.presetId)
        'color: $beforePreset -> ${themeController.presetId}',
    ]);
  }

  static Future<ServiceSettingsCommandResult> _color(
    List<String> args,
    ThemePrefsController themeController,
    String selectedArea,
  ) async {
    final available = _allowedPresets(
      themeController.themeModeId,
      selectedArea: selectedArea,
    );
    if (args.isEmpty) {
      return ServiceSettingsCommandResult.success(
        _colorHelpLines(
          themeController,
          selectedArea: selectedArea,
        ),
      );
    }
    if (args.length == 1 && args.first == 'list') {
      return ServiceSettingsCommandResult.success(<String>[
        'COLOR',
        'current     ${themeController.presetId}',
        'theme       ${themeController.themeModeId}',
        for (final preset in available)
          '${preset.id.padRight(16)}${preset.label}',
      ]);
    }
    if (args.length != 1) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] color',
        for (final preset in available) 'color ${preset.id}',
      ]);
    }
    final value = args.first;
    final match = available.where((preset) => preset.id == value).toList();
    if (match.isEmpty) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] color $value',
        for (final preset in available) 'color ${preset.id}',
      ]);
    }
    final before = themeController.presetId;
    await themeController.setPresetId(value);
    return ServiceSettingsCommandResult.success(<String>[
      'color: $before -> ${themeController.presetId}',
    ]);
  }

  static Future<ServiceSettingsCommandResult> _edge(List<String> args) async {
    final current = await OverlayEdgeSideConfig.getSide();
    if (args.isEmpty) {
      return ServiceSettingsCommandResult.success(
        await _edgeHelpLines(),
      );
    }
    if (args.length != 1 ||
        !const <String>{'left', 'right'}.contains(args.first)) {
      return const ServiceSettingsCommandResult.failure(<String>[
        '[error] edge',
        'edge left',
        'edge right',
      ]);
    }
    final next =
        args.first == 'right' ? OverlayEdgeSide.right : OverlayEdgeSide.left;
    await OverlayEdgeSideConfig.setSide(next);
    var overlayClosed = false;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        overlayClosed = true;
      }
    } catch (error, stackTrace) {
      debugPrint('[SERVICE_SETTING] edge overlay close failure error=$error');
      debugPrint(stackTrace.toString());
    }
    return ServiceSettingsCommandResult.success(<String>[
      'edge: ${_edgeId(current)} -> ${_edgeId(next)}',
      if (overlayClosed) 'overlay closed',
    ]);
  }

  static Future<ServiceSettingsCommandResult> _overlay(
    List<String> args, {
    required bool singleMode,
  }) async {
    final current = await OverlayModeConfig.getMode();
    if (args.isEmpty) {
      return ServiceSettingsCommandResult.success(
        await _overlayHelpLines(singleMode: singleMode),
      );
    }
    if (args.length != 1 ||
        !const <String>{'bubble', 'top'}.contains(args.first)) {
      return ServiceSettingsCommandResult.failure(<String>[
        '[error] overlay',
        'overlay bubble',
        if (!singleMode) 'overlay top',
      ]);
    }
    final wantsTop = args.first == 'top';
    if (singleMode && wantsTop) {
      if (current != OverlayMode.bubble) {
        await OverlayModeConfig.setMode(OverlayMode.bubble);
      }
      return const ServiceSettingsCommandResult.failure(<String>[
        '[blocked] overlay top',
        'overlay bubble',
      ]);
    }
    final next = wantsTop ? OverlayMode.topHalf : OverlayMode.bubble;
    await OverlayModeConfig.setMode(next);
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData(
          next == OverlayMode.topHalf ? '__mode:topHalf__' : '__mode:bubble__',
        );
        await FlutterOverlayWindow.shareData('__collapse__');
      }
    } catch (error, stackTrace) {
      debugPrint('[SERVICE_SETTING] overlay live sync failure error=$error');
      debugPrint(stackTrace.toString());
    }
    return ServiceSettingsCommandResult.success(<String>[
      'overlay: ${_overlayId(current)} -> ${_overlayId(next)}',
    ]);
  }

  static Future<ServiceSettingsCommandResult> _recipient(
    List<String> args,
  ) async {
    final config = await EmailConfig.load();
    final recipient = config.to.trim();
    if (args.isEmpty) {
      return ServiceSettingsCommandResult.success(<String>[
        'recipient=${recipient.isEmpty ? '-' : recipient}',
        'recipient copy',
      ]);
    }
    if (args.length == 1 && args.first == 'copy') {
      if (recipient.isEmpty) {
        return const ServiceSettingsCommandResult.failure(<String>[
          '[error] recipient',
        ]);
      }
      await Clipboard.setData(ClipboardData(text: recipient));
      return const ServiceSettingsCommandResult.success(<String>[
        '[ok] recipient copied',
      ]);
    }
    return const ServiceSettingsCommandResult.failure(<String>[
      '[blocked] recipient',
      'recipient',
      'recipient copy',
    ]);
  }

  static ServiceSettingsCommandResult _debugRequired(String item) {
    return ServiceSettingsCommandResult.failure(<String>[
      '[denied] $item',
      'cd ..',
      'debug',
      'setting',
    ]);
  }

  static Future<void> _ensurePresetAllowed(
    ThemePrefsController themeController, {
    required String selectedArea,
  }) async {
    final current = brandPresets()
        .where((preset) => preset.id == themeController.presetId)
        .toList();
    final allowed = _allowedPresets(
      themeController.themeModeId,
      selectedArea: selectedArea,
    );
    if (current.isNotEmpty &&
        allowed.any((preset) => preset.id == current.first.id)) {
      return;
    }
    final fallback = _fallbackPreset(
      themeController.themeModeId,
      selectedArea: selectedArea,
    );
    await themeController.setPresetId(fallback.id);
  }

  static List<BrandPresetSpec> _allowedPresets(
    String themeModeId, {
    required String selectedArea,
  }) {
    return brandPresetsForThemeMode(themeModeId)
        .where(
          (preset) =>
              preset.id != _kbPresetId ||
              _kbThemeAllowedAreas.contains(selectedArea),
        )
        .toList(growable: false);
  }

  static BrandPresetSpec _fallbackPreset(
    String themeModeId, {
    required String selectedArea,
  }) {
    final candidates = _allowedPresets(
      themeModeId,
      selectedArea: selectedArea,
    );
    if (candidates.isEmpty) return presetById('system');
    if (themeModeId == 'independent') {
      final preferred = candidates
          .where((preset) => preset.id == _defaultIndependentPresetId)
          .toList();
      if (preferred.isNotEmpty) return preferred.first;
    }
    final system = candidates.where((preset) => preset.id == 'system').toList();
    if (system.isNotEmpty) return system.first;
    return candidates.first;
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _edgeId(OverlayEdgeSide side) {
    return side == OverlayEdgeSide.right ? 'right' : 'left';
  }

  static OverlayMode _effectiveOverlayMode(
    OverlayMode stored, {
    required bool singleMode,
  }) {
    return singleMode ? OverlayMode.bubble : stored;
  }

  static String _overlayId(OverlayMode mode) {
    return mode == OverlayMode.topHalf ? 'top' : 'bubble';
  }
}
