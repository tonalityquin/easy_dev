import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/config/email_config.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

class MailRecipientSettings extends StatefulWidget {
  const MailRecipientSettings({
    super.key,
    this.asBottomSheet = false,
    this.useCommonUi = false,
  });

  final bool asBottomSheet;
  final bool useCommonUi;

  static Future<T?> showAsBottomSheet<T>(
    BuildContext context, {
    bool useCommonUi = false,
  }) {
    Widget buildSheet(BuildContext sheetContext) {
      final insets = MediaQuery.of(sheetContext).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: _BottomSheetFrame(
          heightFactor: 1,
          child: MailRecipientSettings(
            asBottomSheet: true,
            useCommonUi: useCommonUi,
          ),
        ),
      );
    }

    if (useCommonUi) {
      return showCommonOverlayBottomSheet<T>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: buildSheet,
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: buildSheet,
    );
  }

  static Future<T?> pushPage<T>(BuildContext context) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => const MailRecipientSettings()),
    );
  }

  @override
  State<MailRecipientSettings> createState() => _MailRecipientSettingsState();
}

class _MailRecipientSettingsState extends State<MailRecipientSettings> {
  String _loaded = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cfg = await EmailConfig.load();
      if (!mounted) return;
      setState(() {
        _loaded = cfg.to.trim();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = '';
        _loading = false;
      });
    }
  }

  Future<void> _copy() async {
    final value = _loaded.trim();
    if (value.isEmpty) return;
    HapticFeedback.selectionClick();
    await Clipboard.setData(ClipboardData(text: value));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final loadedBody = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _loaded.isEmpty
                        ? tokens.surfaceDisabled
                        : tokens.accentContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: _loaded.isEmpty
                        ? tokens.textDisabled
                        : tokens.onAccentContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SQLite 다운로드 Snapshot',
                        style: text.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _loaded.isEmpty
                            ? '현재 지역의 저장된 수신자 이메일이 없습니다.'
                            : _loaded,
                        style: text.bodyMedium?.copyWith(
                          color: _loaded.isEmpty
                              ? tokens.textSecondary
                              : tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Text(
              '메일 수신자는 본사 내려받기에서 저장된 현재 지역 SQLite Snapshot만 사용합니다. 이 화면에서는 값을 수정하거나 초기화하지 않습니다.',
              style: text.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loaded.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_rounded),
            label: const Text('수신자 복사'),
          ),
        ],
      ),
    );

    final content = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .025),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _loading
          ? const Padding(
              key: ValueKey<String>('loading'),
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('loaded'),
              child: loadedBody,
            ),
    );

    if (!widget.asBottomSheet) {
      return Scaffold(
        backgroundColor: tokens.canvas,
        appBar: AppBar(
          backgroundColor: tokens.canvas,
          surfaceTintColor: tokens.transparent,
          elevation: 0,
          foregroundColor: tokens.textPrimary,
          centerTitle: true,
          title: const Text(
            '메일 수신자',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        body: SingleChildScrollView(child: content),
      );
    }

    return _SheetScaffold(
      title: '메일 수신자',
      onClose: () => Navigator.of(context).maybePop(),
      body: SingleChildScrollView(child: content),
      trailingActions: [
        IconButton(
          tooltip: '새로 읽기',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading
              ? null
              : () {
                  setState(() => _loading = true);
                  _bootstrap();
                },
        ),
      ],
    );
  }
}

class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({
    required this.child,
    this.heightFactor = 1,
  });

  final Widget child;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: heightFactor,
      widthFactor: 1,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 8,
                  color: CommonUiTheme.of(context).shadow,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: CommonUiTheme.of(context).surfaceRaised,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.onClose,
    required this.body,
    this.trailingActions,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget>? trailingActions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: CommonUiTheme.of(context).handle,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailingActions != null) ...trailingActions!,
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }
}
