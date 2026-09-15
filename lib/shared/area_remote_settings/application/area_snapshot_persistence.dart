import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/models/capability.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../features/dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../../features/headquarter/application/snapshot/headquarter_snapshot_repository.dart';
import '../../../features/headquarter/domain/models/headquarter_download_snapshot.dart';
import '../../../features/selector/application/dev_auth.dart';

class AreaSnapshotPersistence {
  AreaSnapshotPersistence._();

  static final List<String> _debugLines = <String>[];

  static List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  static String get debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[AREA_SNAPSHOT] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<HeadquarterSnapshotArea> persistRecord(
    AreaRecord record, {
    String source = '',
  }) async {
    final area = HeadquarterSnapshotArea(
      division: record.division.trim(),
      name: record.name.trim(),
      email: record.email.trim(),
      invite: record.invite.trim(),
      communication: record.communication.trim(),
      workRules: List<String>.unmodifiable(
        record.workRules
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      ),
      modes: Set<String>.unmodifiable(
        record.modes
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet(),
      ),
      capabilities: Set<Capability>.unmodifiable(record.capabilities),
      isHeadquarter: record.isHeadquarter,
      rawJson: record.rawJson,
    );
    _record(
      'persist_start',
      source: source,
      meta: <String, Object?>{
        'division': area.division,
        'area': area.name,
        'emailPresent': area.email.isNotEmpty,
        'invitePresent': area.invite.isNotEmpty,
        'communicationPresent': area.communication.isNotEmpty,
        'workRules': area.workRules.length,
        'modes': area.modes.length,
        'capabilities': area.capabilities.length,
        'isHeadquarter': area.isHeadquarter,
        'rawBytes': area.rawJson.length,
      },
    );
    final stored = await HeadquarterSnapshotRepository.instance.upsertArea(area);
    _record(
      'persist_complete',
      source: source,
      meta: <String, Object?>{
        'division': stored.division,
        'area': stored.name,
        'emailPresent': stored.email.isNotEmpty,
        'workRules': stored.workRules.length,
        'modes': stored.modes.length,
        'capabilities': stored.capabilities.length,
      },
    );
    return stored;
  }

  static Future<void> showDeveloperStatus(
    BuildContext context, {
    required String title,
    required String description,
    bool failure = false,
  }) async {
    if (!context.mounted) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    final copyText = debugPrintCode;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: title,
        description: description,
        copyText: copyText,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
      return;
    }
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: description,
      copyText: copyText,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  static void _record(
    String event, {
    String source = '',
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[AREA_SNAPSHOT]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
      if (source.isNotEmpty) 'source=${jsonEncode(source)}',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${jsonEncode(entry.value)}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > 220) {
      _debugLines.removeRange(0, _debugLines.length - 220);
    }
  }
}
