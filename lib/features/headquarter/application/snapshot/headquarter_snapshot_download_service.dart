import '../../../../app/models/capability.dart';
import '../../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../data/local/headquarter_snapshot_database.dart';
import '../../domain/models/headquarter_download_snapshot.dart';

typedef HeadquarterSnapshotDownloadLog = void Function(
  String message, {
  double? progress,
});

class HeadquarterSnapshotDownloadService {
  HeadquarterSnapshotDownloadService();

  Future<HeadquarterDownloadSnapshot> download({
    required AreaRepository areaRepository,
    required String division,
    String requiredArea = '',
    HeadquarterSnapshotDownloadLog? onLog,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final normalizedDivision = division.trim();
    if (normalizedDivision.isEmpty) {
      throw ArgumentError('division is empty');
    }

    final start = progressStart.clamp(0.0, 1.0).toDouble();
    final end = progressEnd.clamp(start, 1.0).toDouble();

    void log(String message, double relativeProgress) {
      final relative = relativeProgress.clamp(0.0, 1.0).toDouble();
      final progress = start + ((end - start) * relative);
      onLog?.call(message, progress: progress);
    }

    log('지역 문서 다운로드를 시작합니다.', 0.08);
    final records = await areaRepository.getAreasByDivision(
      normalizedDivision,
      serverOnly: true,
    );
    if (records.isEmpty) {
      throw StateError('다운로드할 지역 정보가 없습니다.');
    }
    log('지역 문서 ${records.length}개를 내려받았습니다.', 0.5);

    final areas = records
        .map(
          (record) => HeadquarterSnapshotArea(
            division: normalizedDivision,
            name: record.name.trim(),
            email: record.email.trim(),
            invite: record.invite.trim(),
            communication: record.communication.trim(),
            modes: Set<String>.unmodifiable(
              record.modes
                  .map((mode) => mode.trim().toLowerCase())
                  .where((mode) => mode.isNotEmpty)
                  .toSet(),
            ),
            capabilities: Set<Capability>.unmodifiable(record.capabilities),
            isHeadquarter: record.isHeadquarter,
          ),
        )
        .where((area) => area.name.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    final areaNames = <String>{};
    for (final area in areas) {
      if (!areaNames.add(area.name)) {
        throw StateError('중복 지역 정보가 포함되어 있습니다: ${area.name}');
      }
      _validateAreaConnectionFields(area);
    }

    final normalizedRequiredArea = requiredArea.trim();
    if (normalizedRequiredArea.isNotEmpty &&
        !areaNames.contains(normalizedRequiredArea)) {
      throw StateError(
        '다운로드한 지역 정보에서 현재 지역을 찾을 수 없습니다: $normalizedRequiredArea',
      );
    }
    log('지역 데이터 구조와 연결 필드 검증을 완료했습니다.', 0.66);

    final snapshot = HeadquarterDownloadSnapshot(
      division: normalizedDivision,
      downloadedAtIso: DateTime.now().toIso8601String(),
      areas: List<HeadquarterSnapshotArea>.unmodifiable(areas),
    );

    log('SQLite 기존 Snapshot row 전량 삭제와 신규 전량 INSERT transaction을 시작합니다.', 0.74);
    await HeadquarterSnapshotDatabase.instance.replaceSnapshot(snapshot);
    log('SQLite 기존 row 0건 검증, 신규 row 검증, transaction commit을 완료했습니다.', 1);
    return snapshot;
  }

  void _validateAreaConnectionFields(HeadquarterSnapshotArea area) {
    final email = area.email.trim();
    final invite = area.invite.trim();
    final communication = area.communication.trim();

    if (email.isNotEmpty && !_isValidEmailList(email)) {
      throw FormatException('${area.name}의 email 필드가 유효하지 않습니다.');
    }
    if (invite.isNotEmpty && !_isDiscordInviteUrl(invite)) {
      throw FormatException('${area.name}의 invite 필드가 유효하지 않습니다.');
    }
    if (communication.isNotEmpty && !_isDiscordChannelUrl(communication)) {
      throw FormatException('${area.name}의 communication 필드가 유효하지 않습니다.');
    }
  }

  bool _isValidEmailList(String csv) {
    final list = csv
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    if (list.isEmpty) return false;
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return list.every(regex.hasMatch);
  }

  bool _isDiscordInviteUrl(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('discord.gg/') ||
        lower.contains('discord.com/invite/');
  }

  bool _isDiscordChannelUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host != 'discord.com' && host != 'www.discord.com') return false;
    final segments = uri.pathSegments;
    if (segments.length != 3 || segments.first.toLowerCase() != 'channels') {
      return false;
    }
    final snowflake = RegExp(r'^\d+$');
    return snowflake.hasMatch(segments[1]) && snowflake.hasMatch(segments[2]);
  }
}
