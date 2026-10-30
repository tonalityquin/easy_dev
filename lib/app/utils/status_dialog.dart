import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/selector/application/dev_auth.dart';
import 'access_gate_diagnostics.dart';

enum StatusDialogTone {
  success,
  failure,
}

class StatusDialog {
  const StatusDialog._();

  static final List<String> _debugLines = <String>[];
  static String _indexCreationUrl = '';

  static String get indexCreationUrl => _indexCreationUrl;

  static void recordFirestoreIndexError(Object error) {
    if (!DevAuth.devModeEnabled.value || error is! FirebaseException ||
        error.code != 'failed-precondition') return;
    final raw = error.message ?? error.toString();
    final match = RegExp(r'https://console\.firebase\.google\.com/[^\s<>"\]]+')
        .firstMatch(raw);
    if (match == null) return;
    final url = (match.group(0) ?? '')
        .replaceFirst(RegExp(r'[.,;\)]+$'), '');
    if (url.isEmpty) return;
    _indexCreationUrl = url;
    recordDebugOperation(
      'firestore.index', 'missing_composite_index',
      details: <String, Object?>{'indexUrl': url},
    );
  }


  static List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  static String get debugPrintCode => <String>[
        ...AccessGateDiagnostics.lines,
        ..._debugLines,
      ].map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');

  static void _record(
    String event, {
    required String title,
    required StatusDialogTone tone,
    String description = '',
  }) {
    if (!DevAuth.devModeEnabled.value) return;
    final trimmed = description.length > 400
        ? '${description.substring(0, 400)}…'
        : description;
    final line = <String>[
      '[STATUS_DIALOG]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
      'tone=${tone.name}',
      'title=${jsonEncode(title)}',
      if (trimmed.isNotEmpty) 'description=${jsonEncode(trimmed)}',
    ].join(' ');
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > 200) {
      _debugLines.removeRange(0, _debugLines.length - 200);
    }
  }

  static void recordDebugOperation(
    String source,
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!DevAuth.devModeEnabled.value) return;
    final message = jsonEncode(<String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'source': source,
      'event': event,
      ...details,
    }, toEncodable: (Object? value) => value.toString());
    final line = '[FIREBASE_OPT] $message';
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > 200) {
      _debugLines.removeRange(0, _debugLines.length - 200);
    }
  }

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
    bool useCommonUi = false,
    bool awaitManualClose = false,
    bool isolateCopyText = false,
  }) async {
    if (!context.mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final pageNavigator = Navigator.of(context);
    final trimmedDescription = description?.trim() ?? '';
    final trimmedCopyText = copyText?.trim() ?? '';
    final developerMode = DevAuth.devModeEnabled.value;
    if (developerMode) {
      _record(
        'open',
        title: title,
        tone: tone,
        description: trimmedDescription,
      );
    }
    final currentDebugCode = developerMode && !isolateCopyText
        ? debugPrintCode : '';
    final explicitDebugCode = trimmedCopyText.isNotEmpty &&
        (copyButtonLabel == 'debugPrint 코드 복사' ||
            trimmedCopyText.split('\n').every((line) {
              final value = line.trim();
              return value.startsWith('debugPrint(') &&
                  value.endsWith(');');
            }));
    final effectiveCopyText = explicitDebugCode && currentDebugCode.isNotEmpty
        ? <String>{
            ...trimmedCopyText.split('\n'),
            ...currentDebugCode.split('\n'),
          }.where((line) => line.trim().isNotEmpty).join('\n')
        : trimmedCopyText.isEmpty
            ? currentDebugCode
            : trimmedCopyText;
    final debugCopyText = developerMode &&
            !explicitDebugCode &&
            trimmedCopyText.isNotEmpty &&
            currentDebugCode.isNotEmpty &&
            trimmedCopyText != currentDebugCode
        ? currentDebugCode
        : '';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = useCommonUi ? CommonUiTheme.of(context) : null;
    final effectiveTransition =
        reduceMotion ? Duration.zero : transitionDuration;
    final effectiveVisibleDuration = developerMode &&
            effectiveCopyText.isNotEmpty &&
            visibleDuration > Duration.zero &&
            visibleDuration < const Duration(seconds: 10)
        ? const Duration(seconds: 10)
        : visibleDuration;

    final route = RawDialogRoute<void>(
      barrierDismissible: false,
      barrierLabel: barrierLabel ?? title,
      barrierColor: useCommonUi ? tokens!.scrim : Colors.black54,
      transitionDuration: effectiveTransition,
      pageBuilder: (dialogContext, _, __) {
        final content = _StatusDialogSurface(
          title: title,
          tone: tone,
          description: trimmedDescription,
          copyText: effectiveCopyText,
          copyButtonLabel: trimmedCopyText.isEmpty && currentDebugCode.isNotEmpty
              ? 'debugPrint 코드 복사'
              : copyButtonLabel,
          debugCopyText: debugCopyText,
          useCommonUi: useCommonUi,
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

        return useCommonUi
            ? CommonUiScope(child: content)
            : content;
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: CommonUiMotion.enter,
          reverseCurve: CommonUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );

    final routeFuture = rootNavigator.push<void>(route);

    if (effectiveVisibleDuration > Duration.zero) {
      await Future.any<void>(<Future<void>>[
        routeFuture,
        Future<void>.delayed(effectiveVisibleDuration),
      ]);

      if (rootNavigator.mounted && route.isActive) {
        if (route.isCurrent && rootNavigator.canPop()) {
          rootNavigator.pop();
        } else {
          rootNavigator.removeRoute(route);
        }
      }
    } else if (awaitManualClose) {
      await routeFuture;
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
    bool useCommonUi = false,
    bool awaitManualClose = false,
    bool isolateCopyText = false,
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
      useCommonUi: useCommonUi,
      awaitManualClose: awaitManualClose,
      isolateCopyText: isolateCopyText,
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
    bool useCommonUi = false,
    bool awaitManualClose = false,
    bool isolateCopyText = false,
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
      useCommonUi: useCommonUi,
      awaitManualClose: awaitManualClose,
      isolateCopyText: isolateCopyText,
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
    required this.debugCopyText,
    required this.useCommonUi,
    required this.onClose,
  });

  final String title;
  final StatusDialogTone tone;
  final String description;
  final String copyText;
  final String copyButtonLabel;
  final String debugCopyText;
  final bool useCommonUi;
  final VoidCallback onClose;

  @override
  State<_StatusDialogSurface> createState() => _StatusDialogSurfaceState();
}

class _StatusDialogSurfaceState extends State<_StatusDialogSurface> {
  bool _copied = false;
  bool _debugCopied = false;

  Future<void> _copy() async {
    if (widget.copyText.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: widget.copyText));
      if (!mounted) return;
      setState(() => _copied = true);
      StatusDialog._record('copy', title: widget.title, tone: widget.tone);
    } catch (error) {
      debugPrint('[STATUS_DIALOG] copy_failed: $error');
    }
  }

  Future<void> _copyDebug() async {
    if (widget.debugCopyText.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: widget.debugCopyText));
      if (!mounted) return;
      setState(() => _debugCopied = true);
      StatusDialog._record('debug_copy', title: widget.title, tone: widget.tone);
    } catch (error) {
      debugPrint('[STATUS_DIALOG] debug_copy_failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = widget.useCommonUi ? CommonUiTheme.of(context) : null;
    final screenHeight = MediaQuery.of(context).size.height;
    final surface = widget.useCommonUi
        ? tokens!.surfaceRaised
        : colorScheme.surface;
    final border = widget.useCommonUi
        ? tokens!.borderSubtle
        : Colors.transparent;
    final shadow = widget.useCommonUi
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
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.component,
              curve: CommonUiMotion.enter,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: Transform.scale(
                      scale: 0.97 + (0.03 * value),
                      child: child,
                    ),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : CommonUiMotion.component,
                curve: CommonUiMotion.standard,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(
                    widget.useCommonUi
                        ? CommonUiShapes.dialog
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
                  hasDebugCopyText: widget.debugCopyText.isNotEmpty,
                  debugCopied: _debugCopied,
                  onDebugCopy: widget.debugCopyText.isNotEmpty ? _copyDebug : null,
                  copyButtonLabel:
                      _copied ? '복사 완료' : widget.copyButtonLabel,
                  onCopy: widget.copyText.isNotEmpty ? _copy : null,
                  copied: _copied,
                  onClose: widget.onClose,
                  useCommonUi: widget.useCommonUi,
                ),
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
    required this.hasDebugCopyText,
    required this.debugCopied,
    required this.onDebugCopy,
    required this.copyButtonLabel,
    required this.onCopy,
    required this.copied,
    required this.onClose,
    required this.useCommonUi,
  });

  final String title;
  final StatusDialogTone tone;
  final String description;
  final bool hasDescription;
  final bool hasCopyText;
  final bool hasDebugCopyText;
  final bool debugCopied;
  final VoidCallback? onDebugCopy;
  final String copyButtonLabel;
  final VoidCallback? onCopy;
  final bool copied;
  final VoidCallback onClose;
  final bool useCommonUi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final tokens = useCommonUi ? CommonUiTheme.of(context) : null;
    final success = tone == StatusDialogTone.success;
    final accent = useCommonUi
        ? success
            ? tokens!.success
            : tokens!.danger
        : success
            ? colorScheme.tertiary
            : colorScheme.error;
    final accentContainer = useCommonUi
        ? success
            ? tokens!.successContainer
            : tokens!.dangerContainer
        : accent.withAlpha(31);
    final titleColor = useCommonUi ? tokens!.textPrimary : colorScheme.onSurface;
    final descriptionColor = useCommonUi
        ? tokens!.textSecondary
        : colorScheme.onSurfaceVariant;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.88, end: 1),
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.enter,
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
              border: useCommonUi
                  ? Border.all(
                      color: accent.withOpacity(
                        tokens!.isDark ? 0.58 : 0.34,
                      ),
                    )
                  : null,
            ),
            child: AnimatedScale(
              scale: copied ? 1.12 : 1,
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.78, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  copied ? Icons.check_circle_rounded : StatusDialog.iconFor(tone),
                  key: ValueKey<bool>(copied),
                  size: 34,
                  color: accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.enter,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: child,
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
        ),
        if (hasDescription) ...[
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.component,
                curve: CommonUiMotion.enter,
                builder: (context, progress, child) => Opacity(
                  opacity: progress,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - progress)),
                    child: child,
                  ),
                ),
                child: SelectableText(
                  description,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: descriptionColor,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (hasCopyText) ...[
          const SizedBox(height: 18),
          if (useCommonUi)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                AnimatedScale(
                  scale: copied ? 1.025 : 1,
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.enter,
                  child: AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                        child: child,
                      ),
                    ),
                    child: CommonButton(
                      key: ValueKey<String>(copyButtonLabel),
                      label: copyButtonLabel,
                      icon: Icons.copy_rounded,
                      onPressed: onCopy,
                      haptic: CommonHaptic.selection,
                    ),
                  ),
                ),
                if (hasDebugCopyText)
                  AnimatedScale(
                    scale: debugCopied ? 1.025 : 1,
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    curve: CommonUiMotion.enter,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: CommonButton(
                        key: ValueKey<bool>(debugCopied),
                        label: debugCopied ? '복사 완료' : 'debugPrint 코드 복사',
                        icon: debugCopied
                            ? Icons.check_rounded
                            : Icons.code_rounded,
                        onPressed: onDebugCopy,
                        haptic: CommonHaptic.selection,
                      ),
                    ),
                  ),
                CommonButton(
                  label: '닫기',
                  icon: Icons.close_rounded,
                  variant: CommonButtonVariant.tertiary,
                  onPressed: onClose,
                  haptic: CommonHaptic.selection,
                ),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                AnimatedScale(
                  scale: copied ? 1.025 : 1,
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                        child: child,
                      ),
                    ),
                    child: ElevatedButton.icon(
                      key: ValueKey<String>(copyButtonLabel),
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(copyButtonLabel),
                    ),
                  ),
                ),
                if (hasDebugCopyText)
                  AnimatedScale(
                    scale: debugCopied ? 1.025 : 1,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1)
                              .animate(animation),
                          child: child,
                        ),
                      ),
                      child: OutlinedButton.icon(
                        key: ValueKey<bool>(debugCopied),
                        onPressed: onDebugCopy,
                        icon: Icon(
                          debugCopied
                              ? Icons.check_rounded
                              : Icons.code_rounded,
                          size: 18,
                        ),
                        label: Text(
                          debugCopied ? '복사 완료' : 'debugPrint 코드 복사',
                        ),
                      ),
                    ),
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
