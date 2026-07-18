import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../design_system/prompt_ui/prompt_ui_theme.dart';

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
    String? description,
    String? copyText,
    String copyButtonLabel = '전문 복사',
    bool usePromptUi = false,
  }) async {
    if (!context.mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final pageNavigator = Navigator.of(context);
    final trimmedDescription = description?.trim() ?? '';
    final trimmedCopyText = copyText?.trim() ?? '';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = usePromptUi ? PromptUiTheme.of(context) : null;
    final effectiveTransition =
        reduceMotion ? Duration.zero : transitionDuration;

    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierLabel: barrierLabel ?? title,
      barrierColor: usePromptUi ? tokens!.scrim : Colors.black54,
      transitionDuration: effectiveTransition,
      pageBuilder: (dialogContext, _, __) {
        final content = _StatusDialogSurface(
          title: title,
          tone: tone,
          description: trimmedDescription,
          copyText: trimmedCopyText,
          copyButtonLabel: copyButtonLabel,
          usePromptUi: usePromptUi,
          onClose: () {
            final navigator = Navigator.of(
              dialogContext,
              rootNavigator: true,
            );
            if (navigator.canPop()) {
              navigator.pop();
            }
          },
        );

        return usePromptUi
            ? PromptUiScope(child: content)
            : content;
      },
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: PromptUiMotion.enter,
                reverseCurve: PromptUiMotion.exit,
              ),
            ),
            child: child,
          ),
        );
      },
    );

    rootNavigator.push<void>(route);

    if (visibleDuration > Duration.zero) {
      await Future<void>.delayed(visibleDuration);

      if (rootNavigator.mounted && route.isActive) {
        if (route.isCurrent && rootNavigator.canPop()) {
          rootNavigator.pop();
        } else {
          rootNavigator.removeRoute(route);
        }
      }
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
    String? description,
    String? copyText,
    String copyButtonLabel = '전문 복사',
    Duration? visibleDuration,
    bool usePromptUi = false,
  }) {
    final hasCopyText = copyText != null && copyText.trim().isNotEmpty;

    return show(
      context,
      title: title,
      tone: StatusDialogTone.success,
      closeCurrentPageAfter: closeCurrentPageAfter,
      description: description,
      copyText: copyText,
      copyButtonLabel: copyButtonLabel,
      visibleDuration: visibleDuration ??
          (hasCopyText
              ? const Duration(seconds: 30)
              : description == null || description.trim().isEmpty
                  ? const Duration(milliseconds: 1200)
                  : const Duration(milliseconds: 2600)),
      usePromptUi: usePromptUi,
    );
  }

  static Future<void> showFailure(
    BuildContext context, {
    String title = loginFailed,
    bool closeCurrentPageAfter = false,
    String? description,
    String? copyText,
    String copyButtonLabel = '전문 복사',
    Duration? visibleDuration,
    bool usePromptUi = false,
  }) {
    final hasCopyText = copyText != null && copyText.trim().isNotEmpty;

    return show(
      context,
      title: title,
      tone: StatusDialogTone.failure,
      closeCurrentPageAfter: closeCurrentPageAfter,
      description: description,
      copyText: copyText,
      copyButtonLabel: copyButtonLabel,
      visibleDuration: visibleDuration ??
          (hasCopyText
              ? const Duration(seconds: 45)
              : description == null || description.trim().isEmpty
                  ? const Duration(milliseconds: 1200)
                  : const Duration(milliseconds: 3200)),
      usePromptUi: usePromptUi,
    );
  }

  static IconData iconFor(StatusDialogTone tone) {
    switch (tone) {
      case StatusDialogTone.success:
        return Icons.check_circle_rounded;
      case StatusDialogTone.failure:
        return Icons.error_outline_rounded;
    }
  }
}

class _StatusDialogSurface extends StatefulWidget {
  const _StatusDialogSurface({
    required this.title,
    required this.tone,
    required this.description,
    required this.copyText,
    required this.copyButtonLabel,
    required this.usePromptUi,
    required this.onClose,
  });

  final String title;
  final StatusDialogTone tone;
  final String description;
  final String copyText;
  final String copyButtonLabel;
  final bool usePromptUi;
  final VoidCallback onClose;

  @override
  State<_StatusDialogSurface> createState() => _StatusDialogSurfaceState();
}

class _StatusDialogSurfaceState extends State<_StatusDialogSurface> {
  bool _copied = false;

  Future<void> _copy() async {
    if (widget.copyText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.copyText));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = widget.usePromptUi ? PromptUiTheme.of(context) : null;
    final screenHeight = MediaQuery.of(context).size.height;
    final surface = widget.usePromptUi
        ? tokens!.surfaceRaised
        : colorScheme.surface;
    final border = widget.usePromptUi
        ? tokens!.borderSubtle
        : Colors.transparent;
    final shadow = widget.usePromptUi
        ? tokens!.shadow
        : const Color(0x33000000);

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 380,
              maxHeight: screenHeight * 0.84,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 22,
              ),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(
                  widget.usePromptUi
                      ? PromptUiShapes.dialog
                      : 20,
                ),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                    color: shadow,
                  ),
                ],
              ),
              child: _StatusDialogContent(
                title: widget.title,
                tone: widget.tone,
                description: widget.description,
                hasDescription: widget.description.isNotEmpty,
                hasCopyText: widget.copyText.isNotEmpty,
                copyButtonLabel:
                    _copied ? '복사 완료' : widget.copyButtonLabel,
                onCopy: widget.copyText.isNotEmpty ? _copy : null,
                onClose: widget.onClose,
                usePromptUi: widget.usePromptUi,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDialogContent extends StatelessWidget {
  const _StatusDialogContent({
    required this.title,
    required this.tone,
    required this.description,
    required this.hasDescription,
    required this.hasCopyText,
    required this.copyButtonLabel,
    required this.onCopy,
    required this.onClose,
    required this.usePromptUi,
  });

  final String title;
  final StatusDialogTone tone;
  final String description;
  final bool hasDescription;
  final bool hasCopyText;
  final String copyButtonLabel;
  final VoidCallback? onCopy;
  final VoidCallback onClose;
  final bool usePromptUi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final tokens = usePromptUi ? PromptUiTheme.of(context) : null;
    final success = tone == StatusDialogTone.success;
    final accent = usePromptUi
        ? success
            ? tokens!.success
            : tokens!.danger
        : success
            ? colorScheme.tertiary
            : colorScheme.error;
    final accentContainer = usePromptUi
        ? success
            ? tokens!.successContainer
            : tokens!.dangerContainer
        : accent.withAlpha(31);
    final titleColor = usePromptUi ? tokens!.textPrimary : colorScheme.onSurface;
    final descriptionColor = usePromptUi
        ? tokens!.textSecondary
        : colorScheme.onSurfaceVariant;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.88, end: 1),
          duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
          curve: PromptUiMotion.enter,
          builder: (context, value, child) {
            return Transform.scale(scale: value, child: child);
          },
          child: Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentContainer,
              shape: BoxShape.circle,
              border: usePromptUi
                  ? Border.all(
                      color: accent.withOpacity(
                        tokens!.isDark ? 0.58 : 0.34,
                      ),
                    )
                  : null,
            ),
            child: Icon(
              StatusDialog.iconFor(tone),
              size: 34,
              color: accent,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: titleColor,
          ),
        ),
        if (hasDescription) ...[
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                description,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: descriptionColor,
                ),
              ),
            ),
          ),
        ],
        if (hasCopyText) ...[
          const SizedBox(height: 18),
          if (usePromptUi)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                PromptButton(
                  label: copyButtonLabel,
                  icon: Icons.copy_rounded,
                  onPressed: onCopy,
                  haptic: PromptHaptic.selection,
                ),
                PromptButton(
                  label: '닫기',
                  icon: Icons.close_rounded,
                  variant: PromptButtonVariant.tertiary,
                  onPressed: onClose,
                  haptic: PromptHaptic.selection,
                ),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(copyButtonLabel),
                ),
                TextButton(
                  onPressed: onClose,
                  child: const Text('닫기'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
