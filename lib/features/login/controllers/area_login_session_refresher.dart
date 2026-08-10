import 'package:flutter/material.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../dev/application/area_state.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';

class AreaLoginSessionRefresher {
  const AreaLoginSessionRefresher._();

  static Future<AreaRecord> refresh({
    required BuildContext context,
    required AreaState areaState,
    required String division,
    required String area,
    required String operationLabel,
  }) async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: 'Area 세션 동기화',
      initialMessage: '$operationLabel 로그인 Area 세션 최신화를 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: Firebase 서버 조회와 캐시 갱신 과정을 Status Dialog에 표시합니다.',
      standardModeMessage:
          '개발자 모드 OFF: Firebase 서버 조회와 캐시 갱신 로그만 출력합니다.',
    );

    try {
      trace.log(
        '로그인 캐시 폐기 후 서버 전용 AreaRecord 조회를 요청합니다: division=${division.trim()}, area=${area.trim()}',
        progress: 0.08,
      );
      final record = await areaState.refreshAreaForLogin(
        division: division,
        area: area,
        onLog: trace.log,
      );
      await trace.succeed(
        'Area 세션 동기화가 완료되었습니다: division=${record.division}, area=${record.name}, isHeadquarter=${record.isHeadquarter}',
      );
      return record;
    } catch (error, stackTrace) {
      await trace.fail(
        'Area 세션 동기화에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
