import 'package:flutter/material.dart';

enum StatusDialogTone {
  success,
  failure,
}

class StatusDialog {
  const StatusDialog._();

  static const String invalidPlateInput = '번호판 입력을 확인해주세요';
  static const String monthlyDocNotFound = '월정기 문서를 찾을 수 없습니다';
  static const String monthlyDocReadFailed = '월정기 문서 조회 실패';
  static const String monthlyApplyFailed = '월정기 반영 실패';
  static const String duplicateActiveEntry = '이미 입차 중인 번호판입니다';
  static const String loginFailed = '로그인 실패';
  static const String workStartReportSuccess = '업무 시작 보고 완료';
  static const String workEndReportSuccess = '업무 종료 보고 완료';
  static const String userStatementSubmitSuccess = '경위서 보고 완료';
  static const String userStatementSubmitFailed = '경위서 보고 실패';
  static const String leaveApplicationSubmitSuccess = '연차(결근) 지원 신청서 보고 완료';
  static const String leaveApplicationSubmitFailed = '연차(결근) 지원 신청서 보고 실패';
  static const String photoSaveFailed = '사진 저장 실패';
  static const String photoLoadFailed = '사진 불러오기 실패';
  static const String pastEntryLogLoadFailed = '과거 입차 로그 불러오기 실패';
  static const String photoTransferSendSuccess = '사진 전송 완료';
  static const String photoTransferSendFailed = '사진 전송 실패';
  static const String userAccountSaveSuccess = '계정 정보 저장 완료';
  static const String userAccountSaveFailed = '계정 정보 저장 실패';
  static const String gmailRecipientSaveSuccess = '지메일 수신자가 저장되었습니다.';
  static const String savedInviteLinkResetSuccess = '저장된 링크를 초기화했어요';
  static const String inviteLinkCopySuccess = '초대 링크 복사 완료';
  static const String clipboardTextNotFound = '클립보드에 텍스트가 없어요';
  static const String discordInviteUrlInvalid = '디스코드 초대 링크 형태가 아니에요';
  static const String discordInviteUrlSaveSuccess = '초대 링크를 저장했어요';
  static const String discordInviteUrlPasteRequired = '초대 링크를 먼저 붙여넣어 주세요';
  static const String externalLinkOpenFailed = '링크를 열 수 없어요';
  static const String discordInviteUrlRequired = '초대 링크가 필요해요';

  static Future<void> show(
    BuildContext context, {
    required String title,
    required StatusDialogTone tone,
    bool closeCurrentPageAfter = false,
    Duration visibleDuration = const Duration(milliseconds: 1200),
    Duration transitionDuration = const Duration(milliseconds: 180),
    Duration pagePopDelay = const Duration(milliseconds: 80),
    String? barrierLabel,
  }) async {
    if (!context.mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final pageNavigator = Navigator.of(context);

    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierLabel: barrierLabel ?? title,
      barrierColor: Colors.black54,
      transitionDuration: transitionDuration,
      pageBuilder: (dialogContext, _, __) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        final textTheme = theme.textTheme;
        final accentColor = _accentColor(colorScheme, tone);

        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 24,
                      offset: Offset(0, 12),
                      color: Color(0x33000000),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accentColor.withAlpha(31),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _iconFor(tone),
                        size: 32,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
            ),
            child: child,
          ),
        );
      },
    );

    rootNavigator.push<void>(route);

    await Future<void>.delayed(visibleDuration);

    if (rootNavigator.mounted && route.isActive) {
      rootNavigator.removeRoute(route);
    }

    if (!context.mounted) return;

    if (closeCurrentPageAfter) {
      await Future<void>.delayed(pagePopDelay);

      if (pageNavigator.mounted && pageNavigator.canPop()) {
        pageNavigator.pop();
      }
    }
  }

  static Future<void> showSuccess(
    BuildContext context, {
    String title = workStartReportSuccess,
    bool closeCurrentPageAfter = false,
  }) {
    return show(
      context,
      title: title,
      tone: StatusDialogTone.success,
      closeCurrentPageAfter: closeCurrentPageAfter,
    );
  }

  static Future<void> showFailure(
    BuildContext context, {
    String title = loginFailed,
    bool closeCurrentPageAfter = false,
  }) {
    return show(
      context,
      title: title,
      tone: StatusDialogTone.failure,
      closeCurrentPageAfter: closeCurrentPageAfter,
    );
  }

  static IconData _iconFor(StatusDialogTone tone) {
    switch (tone) {
      case StatusDialogTone.success:
        return Icons.check_circle_rounded;
      case StatusDialogTone.failure:
        return Icons.error_outline_rounded;
    }
  }

  static Color _accentColor(ColorScheme colorScheme, StatusDialogTone tone) {
    switch (tone) {
      case StatusDialogTone.success:
        return colorScheme.tertiary;
      case StatusDialogTone.failure:
        return colorScheme.error;
    }
  }
}
