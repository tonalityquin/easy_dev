import '../../../app/config/email_config.dart';
import '../../../features/community/application/discord/discord_config.dart';
import '../../../features/headquarter/application/snapshot/headquarter_snapshot_repository.dart';

typedef AreaRemoteSettingsLog = void Function(
  String message, {
  double? progress,
});

class AreaRemoteSettingsSyncResult {
  const AreaRemoteSettingsSyncResult({
    required this.area,
    required this.emailAvailable,
    required this.inviteAvailable,
    required this.communicationAvailable,
  });

  final String area;
  final bool emailAvailable;
  final bool inviteAvailable;
  final bool communicationAvailable;

  int get availableCount => <bool>[
        emailAvailable,
        inviteAvailable,
        communicationAvailable,
      ].where((value) => value).length;

  String get summary {
    final items = <String>[
      emailAvailable ? 'email 있음' : 'email 없음',
      inviteAvailable ? 'invite 있음' : 'invite 없음',
      communicationAvailable ? 'communication 있음' : 'communication 없음',
    ];
    return items.join(' · ');
  }
}

class AreaRemoteSettingsSync {
  const AreaRemoteSettingsSync._();

  static Future<AreaRemoteSettingsSyncResult> sync({
    required String division,
    required String area,
    AreaRemoteSettingsLog? onLog,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty) {
      throw StateError('회사 정보가 없어 SQLite Snapshot을 확인할 수 없습니다.');
    }
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없어 SQLite Snapshot을 확인할 수 없습니다.');
    }

    final start = progressStart.clamp(0.0, 1.0).toDouble();
    final end = progressEnd.clamp(start, 1.0).toDouble();

    void log(String message, double relativeProgress) {
      final relative = relativeProgress.clamp(0.0, 1.0).toDouble();
      final progress = start + ((end - start) * relative);
      onLog?.call(message, progress: progress);
    }

    log(
      'SQLite Snapshot 연결 데이터 조회를 시작합니다: division=$normalizedDivision, area=$normalizedArea',
      0.08,
    );

    final snapshotArea = await HeadquarterSnapshotRepository.instance.readArea(
      division: normalizedDivision,
      area: normalizedArea,
    );
    if (snapshotArea == null) {
      throw StateError(
        '현재 지역의 본사 다운로드 SQLite Snapshot이 없습니다: division=$normalizedDivision, area=$normalizedArea',
      );
    }

    final email = snapshotArea.email.trim();
    final invite = snapshotArea.invite.trim();
    final communication = snapshotArea.communication.trim();

    if (email.isNotEmpty && !EmailConfig.isValidToList(email)) {
      throw FormatException('SQLite Snapshot의 email 필드가 유효하지 않습니다.');
    }
    if (invite.isNotEmpty && !isDiscordInviteUrl(invite)) {
      throw FormatException('SQLite Snapshot의 invite 필드가 유효하지 않습니다.');
    }
    if (communication.isNotEmpty && !isDiscordChannelUrl(communication)) {
      throw FormatException('SQLite Snapshot의 communication 필드가 유효하지 않습니다.');
    }

    final emailAvailable = email.isNotEmpty;
    final inviteAvailable = invite.isNotEmpty;
    final communicationAvailable = communication.isNotEmpty;

    log(
      'SQLite Snapshot 연결 데이터 검증을 완료했습니다: emailAvailable=$emailAvailable inviteAvailable=$inviteAvailable communicationAvailable=$communicationAvailable',
      1,
    );

    return AreaRemoteSettingsSyncResult(
      area: normalizedArea,
      emailAvailable: emailAvailable,
      inviteAvailable: inviteAvailable,
      communicationAvailable: communicationAvailable,
    );
  }
}
