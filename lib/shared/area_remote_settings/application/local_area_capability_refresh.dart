import 'package:flutter/foundation.dart';

import '../../../app/models/capability.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/headquarter/application/snapshot/headquarter_snapshot_repository.dart';

typedef LocalAreaCapabilityRefreshLog = void Function(
  String message, {
  double? progress,
});

class LocalAreaCapabilityRefreshResult {
  const LocalAreaCapabilityRefreshResult({
    required this.snapshotFound,
    required this.applied,
    required this.changed,
    required this.before,
    required this.snapshotCapabilities,
    required this.after,
  });

  final bool snapshotFound;
  final bool applied;
  final bool changed;
  final CapSet before;
  final CapSet snapshotCapabilities;
  final CapSet after;

  String get beforeKeys => LocalAreaCapabilityRefresh.keys(before);
  String get snapshotKeys =>
      LocalAreaCapabilityRefresh.keys(snapshotCapabilities);
  String get afterKeys => LocalAreaCapabilityRefresh.keys(after);
}

class LocalAreaCapabilityRefresh {
  const LocalAreaCapabilityRefresh._();

  static String keys(CapSet capabilities) {
    final values = capabilities.map((value) => value.key).toList()..sort();
    return values.isEmpty ? 'none' : values.join(',');
  }

  static Future<LocalAreaCapabilityRefreshResult> refresh({
    required AreaState areaState,
    required String division,
    required String area,
    String source = 'local_capability_refresh',
    LocalAreaCapabilityRefreshLog? onLog,
    double progressStart = 0,
    double progressEnd = 1,
    bool requireSnapshot = false,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty) {
      throw StateError('회사 정보가 없어 로컬 capability를 확인할 수 없습니다.');
    }
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없어 로컬 capability를 확인할 수 없습니다.');
    }

    final start = progressStart.clamp(0.0, 1.0).toDouble();
    final end = progressEnd.clamp(start, 1.0).toDouble();

    void log(String message, double relativeProgress) {
      final relative = relativeProgress.clamp(0.0, 1.0).toDouble();
      final progress = start + ((end - start) * relative);
      final callback = onLog;
      if (callback != null) {
        callback(message, progress: progress);
      } else {
        debugPrint(message);
      }
    }

    final before = Set<Capability>.unmodifiable(
      areaState.capabilitiesOfCurrentArea,
    );
    log(
      'local_capability_refresh_start source=$source division=$normalizedDivision area=$normalizedArea areaStateBefore=${keys(before)} remoteRead=0 remoteWrite=0',
      0.08,
    );

    final snapshotArea =
        await HeadquarterSnapshotRepository.instance.readArea(
      division: normalizedDivision,
      area: normalizedArea,
    );

    if (snapshotArea == null) {
      final message =
          'local_capability_snapshot_missing source=$source division=$normalizedDivision area=$normalizedArea areaStateRetained=${keys(before)} remoteRead=0 remoteWrite=0';
      log(message, 1);
      if (requireSnapshot) {
        throw StateError(
          '현재 지역의 본사 다운로드 SQLite Snapshot이 없습니다: division=$normalizedDivision, area=$normalizedArea',
        );
      }
      return LocalAreaCapabilityRefreshResult(
        snapshotFound: false,
        applied: false,
        changed: false,
        before: before,
        snapshotCapabilities: const <Capability>{},
        after: before,
      );
    }

    final snapshotCapabilities = Set<Capability>.unmodifiable(
      snapshotArea.capabilities,
    );
    log(
      'local_capability_snapshot_loaded source=$source division=$normalizedDivision area=$normalizedArea snapshotCapabilities=${keys(snapshotCapabilities)} remoteRead=0 remoteWrite=0',
      0.48,
    );

    final applied = areaState.applyLocalAreaCapabilities(
      division: normalizedDivision,
      area: normalizedArea,
      capabilities: snapshotCapabilities,
      source: source,
    );
    if (!applied) {
      throw StateError(
        '현재 AreaState와 SQLite Snapshot 지역이 일치하지 않아 capability를 적용하지 못했습니다: division=$normalizedDivision, area=$normalizedArea',
      );
    }
    final after = Set<Capability>.unmodifiable(
      areaState.capabilitiesOfCurrentArea,
    );
    final changed = before.length != after.length || !before.containsAll(after);

    if (applied &&
        (after.length != snapshotCapabilities.length ||
            !after.containsAll(snapshotCapabilities))) {
      throw StateError(
        '로컬 capability 적용 검증에 실패했습니다: snapshot=${keys(snapshotCapabilities)} areaState=${keys(after)}',
      );
    }

    log(
      'local_capability_refresh_complete source=$source division=$normalizedDivision area=$normalizedArea applied=$applied changed=$changed before=${keys(before)} snapshot=${keys(snapshotCapabilities)} after=${keys(after)} remoteRead=0 remoteWrite=0',
      1,
    );

    return LocalAreaCapabilityRefreshResult(
      snapshotFound: true,
      applied: applied,
      changed: changed,
      before: before,
      snapshotCapabilities: snapshotCapabilities,
      after: after,
    );
  }
}
