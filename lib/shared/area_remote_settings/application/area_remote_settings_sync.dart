import '../../../app/config/email_config.dart';
import '../../../features/community/application/discord/discord_config.dart';
import '../../../features/dev/domain/repositories/area_repo_package/area_repository.dart';

typedef AreaRemoteSettingsLog = void Function(
  String message, {
  double? progress,
});

class AreaRemoteSettingsSyncResult {
  const AreaRemoteSettingsSyncResult({
    required this.area,
    required this.emailSynced,
    required this.inviteSynced,
    required this.communicationSynced,
  });

  final String area;
  final bool emailSynced;
  final bool inviteSynced;
  final bool communicationSynced;

  int get syncedCount => <bool>[
        emailSynced,
        inviteSynced,
        communicationSynced,
      ].where((value) => value).length;

  String get summary {
    final items = <String>[
      emailSynced ? 'email 갱신' : 'email 유지',
      inviteSynced ? 'invite 갱신' : 'invite 유지',
      communicationSynced ? 'communication 갱신' : 'communication 유지',
    ];
    return items.join(' · ');
  }
}

class AreaRemoteSettingsSync {
  const AreaRemoteSettingsSync._();

  static Future<AreaRemoteSettingsSyncResult> sync({
    required AreaRepository repository,
    required String division,
    required String area,
    AreaRemoteSettingsLog? onLog,
    double progressStart = 0,
    double progressEnd = 1,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    final start = progressStart.clamp(0.0, 1.0).toDouble();
    final end = progressEnd.clamp(start, 1.0).toDouble();

    void log(String message, double relativeProgress) {
      final relative = relativeProgress.clamp(0.0, 1.0).toDouble();
      final progress = start + ((end - start) * relative);
      onLog?.call(message, progress: progress);
    }

    if (normalizedDivision.isEmpty) {
      throw StateError('회사 정보가 없어 연결 데이터를 동기화할 수 없습니다.');
    }
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없어 연결 데이터를 동기화할 수 없습니다.');
    }

    log(
      '현재 지역 연결 데이터 조회를 시작합니다: division=$normalizedDivision, area=$normalizedArea',
      0.04,
    );
    log(
      'lightweightPolicy=single_area_document email+invite+communication only areaMasterRefresh=false',
      0.08,
    );

    final record = await repository.getAreaByName(
      normalizedArea,
      division: normalizedDivision,
    );
    if (record == null) {
      throw StateError(
        '현재 지역과 일치하는 areas 문서를 찾을 수 없습니다: division=$normalizedDivision, area=$normalizedArea',
      );
    }

    final email = record.email.trim();
    final invite = record.invite.trim();
    final communication = record.communication.trim();

    log(
      '서버 연결 필드를 읽었습니다: emailPresent=${email.isNotEmpty}, invitePresent=${invite.isNotEmpty}, inviteLength=${invite.length}, communicationPresent=${communication.isNotEmpty}, communicationLength=${communication.length}',
      0.18,
    );

    if (email.isNotEmpty && !EmailConfig.isValidToList(email)) {
      throw FormatException('현재 지역의 email 필드가 유효하지 않습니다.');
    }
    if (invite.isNotEmpty && !isDiscordInviteUrl(invite)) {
      throw FormatException(
        '현재 지역의 invite 필드가 유효한 Discord 초대 링크가 아닙니다.',
      );
    }
    if (communication.isNotEmpty && !isDiscordChannelUrl(communication)) {
      throw FormatException(
        '현재 지역의 communication 필드가 유효한 Discord 채널 링크가 아닙니다.',
      );
    }

    log('email, invite, communication 선검증을 완료했습니다.', 0.28);
    log(
      'replacePolicy=remove_reload_verify_set_reload_verify globalRollback=all_three_fields',
      0.31,
    );

    final previousEmail = (await EmailConfig.load()).to.trim();
    final previousInvite = await loadDiscordInviteUrl();
    final previousCommunication = await loadDiscordChannelUrl();

    log(
      '기존 로컬값 스냅샷을 확보했습니다: emailPresent=${previousEmail.isNotEmpty}, invitePresent=${previousInvite.isNotEmpty}, inviteLength=${previousInvite.length}, communicationPresent=${previousCommunication.isNotEmpty}, communicationLength=${previousCommunication.length}',
      0.36,
    );

    var emailSynced = false;
    var inviteSynced = false;
    var communicationSynced = false;

    try {
      if (email.isEmpty) {
        log('서버 email 값이 비어 있어 기존 로컬 수신자 이메일을 유지합니다.', 0.46);
      } else {
        log('기존 로컬 수신자 이메일을 삭제한 뒤 서버 email 값으로 교체합니다.', 0.43);
        await EmailConfig.replaceRecipient(email);
        final verifiedEmail = (await EmailConfig.load()).to.trim();
        if (verifiedEmail != email) {
          throw StateError('수신자 이메일 최종 저장 검증에 실패했습니다.');
        }
        emailSynced = true;
        log('수신자 이메일 교체 및 검증을 완료했습니다.', 0.55);
      }

      if (invite.isEmpty) {
        log('서버 invite 값이 비어 있어 기존 Discord 초대 링크를 유지합니다.', 0.65);
      } else {
        log(
          '기존 Discord 초대 링크를 삭제한 뒤 서버 invite 값으로 교체합니다: nextLength=${invite.length}',
          0.61,
        );
        await replaceDiscordInviteUrl(invite);
        final verifiedInvite = await loadDiscordInviteUrl();
        if (verifiedInvite != invite) {
          throw StateError('Discord 초대 링크 최종 저장 검증에 실패했습니다.');
        }
        inviteSynced = true;
        log(
          'Discord 초대 링크 교체 및 검증을 완료했습니다: length=${verifiedInvite.length}',
          0.72,
        );
      }

      if (communication.isEmpty) {
        log(
          '서버 communication 값이 비어 있어 기존 Discord 채널 링크를 유지합니다.',
          0.82,
        );
      } else {
        log(
          '기존 Discord 채널 링크를 삭제한 뒤 서버 communication 값으로 교체합니다: nextLength=${communication.length}',
          0.78,
        );
        await replaceDiscordChannelUrl(communication);
        final verifiedCommunication = await loadDiscordChannelUrl();
        if (verifiedCommunication != communication) {
          throw StateError('Discord 채널 링크 최종 저장 검증에 실패했습니다.');
        }
        communicationSynced = true;
        log(
          'Discord 채널 링크 교체 및 검증을 완료했습니다: length=${verifiedCommunication.length}',
          0.88,
        );
      }

      final finalEmail = (await EmailConfig.load()).to.trim();
      final finalInvite = await loadDiscordInviteUrl();
      final finalCommunication = await loadDiscordChannelUrl();
      final expectedEmail = email.isEmpty ? previousEmail : email;
      final expectedInvite = invite.isEmpty ? previousInvite : invite;
      final expectedCommunication = communication.isEmpty
          ? previousCommunication
          : communication;

      if (finalEmail != expectedEmail ||
          finalInvite != expectedInvite ||
          finalCommunication != expectedCommunication) {
        throw StateError('연결 데이터 전체 최종 검증에 실패했습니다.');
      }

      log(
        '연결 데이터 전체 최종 검증을 완료했습니다: emailSynced=$emailSynced, inviteSynced=$inviteSynced, communicationSynced=$communicationSynced',
        1,
      );

      return AreaRemoteSettingsSyncResult(
        area: normalizedArea,
        emailSynced: emailSynced,
        inviteSynced: inviteSynced,
        communicationSynced: communicationSynced,
      );
    } catch (error, stackTrace) {
      log('연결 데이터 동기화 실패를 감지해 전체 로컬값 롤백을 시작합니다.', 0.93);
      final rollbackErrors = <String>[];

      try {
        await EmailConfig.restoreRecipient(previousEmail);
      } catch (rollbackError) {
        rollbackErrors.add('email=$rollbackError');
      }
      try {
        await restoreDiscordInviteUrl(previousInvite);
      } catch (rollbackError) {
        rollbackErrors.add('invite=$rollbackError');
      }
      try {
        await restoreDiscordChannelUrl(previousCommunication);
      } catch (rollbackError) {
        rollbackErrors.add('communication=$rollbackError');
      }

      try {
        final rollbackEmail = (await EmailConfig.load()).to.trim();
        final rollbackInvite = await loadDiscordInviteUrl();
        final rollbackCommunication = await loadDiscordChannelUrl();

        if (rollbackEmail != previousEmail) {
          rollbackErrors.add('email_verify_failed');
        }
        if (rollbackInvite != previousInvite) {
          rollbackErrors.add('invite_verify_failed');
        }
        if (rollbackCommunication != previousCommunication) {
          rollbackErrors.add('communication_verify_failed');
        }
      } catch (rollbackVerifyError) {
        rollbackErrors.add('verify=$rollbackVerifyError');
      }

      if (rollbackErrors.isNotEmpty) {
        throw StateError(
          '연결 데이터 동기화 실패 후 전체 롤백에 실패했습니다: syncError=$error rollbackErrors=${rollbackErrors.join(' | ')}',
        );
      }

      log('연결 데이터 전체 로컬값 롤백 및 검증을 완료했습니다.', 1);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
