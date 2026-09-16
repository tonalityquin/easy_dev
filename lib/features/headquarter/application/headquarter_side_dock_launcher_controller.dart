import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';

@immutable
class HeadquarterSideDockLauncherSnapshot {
  const HeadquarterSideDockLauncherSnapshot({
    required this.enabled,
    required this.eligible,
    required this.surfaceVisible,
    required this.dockOpen,
    required this.openCount,
    required this.blockedCount,
    required this.lastOpenSource,
    required this.lastOpenAt,
    required this.lastCloseAt,
    required this.lastAction,
  });

  const HeadquarterSideDockLauncherSnapshot.initial()
      : enabled = false,
        eligible = false,
        surfaceVisible = false,
        dockOpen = false,
        openCount = 0,
        blockedCount = 0,
        lastOpenSource = '-',
        lastOpenAt = null,
        lastCloseAt = null,
        lastAction = 'initial';

  final bool enabled;
  final bool eligible;
  final bool surfaceVisible;
  final bool dockOpen;
  final int openCount;
  final int blockedCount;
  final String lastOpenSource;
  final DateTime? lastOpenAt;
  final DateTime? lastCloseAt;
  final String lastAction;

  HeadquarterSideDockLauncherSnapshot copyWith({
    bool? enabled,
    bool? eligible,
    bool? surfaceVisible,
    bool? dockOpen,
    int? openCount,
    int? blockedCount,
    String? lastOpenSource,
    DateTime? lastOpenAt,
    DateTime? lastCloseAt,
    String? lastAction,
  }) {
    return HeadquarterSideDockLauncherSnapshot(
      enabled: enabled ?? this.enabled,
      eligible: eligible ?? this.eligible,
      surfaceVisible: surfaceVisible ?? this.surfaceVisible,
      dockOpen: dockOpen ?? this.dockOpen,
      openCount: openCount ?? this.openCount,
      blockedCount: blockedCount ?? this.blockedCount,
      lastOpenSource: lastOpenSource ?? this.lastOpenSource,
      lastOpenAt: lastOpenAt ?? this.lastOpenAt,
      lastCloseAt: lastCloseAt ?? this.lastCloseAt,
      lastAction: lastAction ?? this.lastAction,
    );
  }
}

class HeadquarterSideDockLauncherController {
  HeadquarterSideDockLauncherController._();

  static const String enabledKey =
      'headquarter_side_dock_launcher_enabled_v1';
  static const String dockKind = 'headquarter_quick_actions';
  static const String dockDesign = 'legacy_head_hub_actions_v1519';
  static const String dockSide = 'left';
  static const String launcherSide = 'left';
  static const int maxDebugLines = 240;

  static final ValueNotifier<HeadquarterSideDockLauncherSnapshot> status =
      ValueNotifier<HeadquarterSideDockLauncherSnapshot>(
    const HeadquarterSideDockLauncherSnapshot.initial(),
  );
  static final List<String> _debugLines = <String>[];

  static bool _initialized = false;

  static String get debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[HQ_DOCK_LAUNCHER] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final enabled = prefs.getBool(enabledKey) ?? false;
    _initialized = true;
    _publish(
      status.value.copyWith(
        enabled: enabled,
        lastAction: 'initialized',
      ),
    );
    _log('initialized enabled=$enabled');
  }

  static Future<void> setEnabled(
    bool value, {
    String source = 'unknown',
  }) async {
    if (!_initialized) await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    final current = status.value;
    _publish(
      current.copyWith(
        enabled: value,
        surfaceVisible: value && current.eligible && !current.dockOpen,
        lastAction: value ? 'enabled' : 'disabled',
      ),
    );
    _log('enabled_changed value=$value source=$source');
  }

  static Future<void> resetForLogout({
    String source = 'logout',
  }) async {
    if (!_initialized) await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, false);
    _publish(
      status.value.copyWith(
        enabled: false,
        eligible: false,
        surfaceVisible: false,
        dockOpen: false,
        lastAction: 'logout_reset',
      ),
    );
    _log('logout_reset source=$source');
  }

  static void updateSurfaceState({
    required bool eligible,
    required bool visible,
    String source = 'edge_handle',
  }) {
    final current = status.value;
    if (current.eligible == eligible && current.surfaceVisible == visible) {
      return;
    }
    _publish(
      current.copyWith(
        eligible: eligible,
        surfaceVisible: visible,
        lastAction: visible ? 'surface_visible' : 'surface_hidden',
      ),
    );
    _log(
      'surface_state eligible=$eligible visible=$visible enabled=${current.enabled} dockOpen=${current.dockOpen} source=$source',
    );
  }

  static void recordOpenRequested({
    required String source,
  }) {
    _publish(
      status.value.copyWith(
        lastOpenSource: source,
        lastAction: 'open_requested',
      ),
    );
    _log(
      'open_requested source=$source dock=$dockKind dockDesign=$dockDesign dockSide=$dockSide launcherSide=$launcherSide',
    );
  }

  static void recordOpenBlocked({
    required String source,
    required String reason,
  }) {
    final current = status.value;
    _publish(
      current.copyWith(
        blockedCount: current.blockedCount + 1,
        lastOpenSource: source,
        lastAction: 'open_blocked_$reason',
      ),
    );
    _log('open_blocked source=$source reason=$reason');
  }

  static void recordOpenError({
    required String source,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final current = status.value;
    _publish(
      current.copyWith(
        blockedCount: current.blockedCount + 1,
        lastOpenSource: source,
        lastAction: 'open_error',
      ),
    );
    _log('open_error source=$source error=$error');
    _log('open_error_stack source=$source stack=$stackTrace');
  }

  static void recordOpened({
    required String source,
  }) {
    final current = status.value;
    final now = DateTime.now();
    _publish(
      current.copyWith(
        dockOpen: true,
        surfaceVisible: false,
        openCount: current.openCount + 1,
        lastOpenSource: source,
        lastOpenAt: now,
        lastAction: 'dock_opened',
      ),
    );
    _log(
      'dock_opened source=$source openCount=${current.openCount + 1} at=${now.toIso8601String()}',
    );
  }

  static void recordClosed({
    required String source,
  }) {
    final current = status.value;
    final now = DateTime.now();
    _publish(
      current.copyWith(
        dockOpen: false,
        surfaceVisible: current.enabled && current.eligible,
        lastOpenSource: source,
        lastCloseAt: now,
        lastAction: 'dock_closed',
      ),
    );
    _log('dock_closed source=$source at=${now.toIso8601String()}');
  }

  static Future<void> showDeveloperStatus(BuildContext context) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;

    final current = status.value;
    _log(
      'developer_status_open enabled=${current.enabled} eligible=${current.eligible} visible=${current.surfaceVisible} dockOpen=${current.dockOpen} dock=$dockKind dockDesign=$dockDesign dockSide=$dockSide launcherSide=$launcherSide',
    );
    await HapticFeedback.mediumImpact();
    if (!context.mounted) return;

    final description = <String>[
      'enabled=${current.enabled}',
      'eligible=${current.eligible}',
      'surfaceVisible=${current.surfaceVisible}',
      'dockOpen=${current.dockOpen}',
      'dockKind=$dockKind',
      'dockDesign=$dockDesign',
      'dockSide=$dockSide',
      'launcherSide=$launcherSide',
      'openCount=${current.openCount}',
      'blockedCount=${current.blockedCount}',
      'lastOpenSource=${current.lastOpenSource}',
      'lastOpenAt=${current.lastOpenAt?.toIso8601String() ?? '-'}',
      'lastCloseAt=${current.lastCloseAt?.toIso8601String() ?? '-'}',
      'lastAction=${current.lastAction}',
      'preferenceKey=$enabledKey',
      'logs=${_debugLines.length}',
    ].join('\n');

    await StatusDialog.showSuccess(
      context,
      title: '본사 빠른 실행 Side Dock 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  static void recordDebug(String message) {
    _log(message);
  }

  static void _publish(HeadquarterSideDockLauncherSnapshot next) {
    status.value = next;
  }

  static void _log(String message) {
    final line =
        '[HQ_DOCK_LAUNCHER][${DateTime.now().toIso8601String()}] $message';
    _debugLines.add(line);
    if (_debugLines.length > maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - maxDebugLines);
    }
    debugPrint(line);
  }
}
