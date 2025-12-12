// lib/screens/head_package/hr_package/mail_recipient_settings.dart
import 'package:flutter/material.dart';

import '../../../utils/api/email_config.dart';
import '../../../utils/snackbar_helper.dart';

/// Gmail 수신자(To) 설정 화면
/// - SharedPreferences 키: 'mail.to'
/// - 여러 수신자: 쉼표(,)로 구분
/// - 유효성 검사: EmailConfig.isValidToList
class MailRecipientSettings extends StatefulWidget {
  const MailRecipientSettings({super.key, this.asBottomSheet = false});

  /// true면 바텀시트 전용 헤더(핸들/닫기/액션)를 사용
  final bool asBottomSheet;

  /// 바텀시트(92% 느낌)로 열기 (루트 네비게이터 사용)
  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _BottomSheetFrame(
            heightFactor: 1,
            child: MailRecipientSettings(asBottomSheet: true),
          ),
        );
      },
    );
  }

  /// 일반 페이지로 열기
  static Future<T?> pushPage<T>(BuildContext context) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => const MailRecipientSettings()),
    );
  }

  @override
  State<MailRecipientSettings> createState() => _MailRecipientSettingsState();
}

class _MailRecipientSettingsState extends State<MailRecipientSettings> {
  // Deep Blue Palette (캘린더 화면과 톤 맞춤)
  static const _base = Color(0xFF0D47A1);
  static const _dark = Color(0xFF09367D);
  static const _light = Color(0xFF5472D3);

  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  String _loaded = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _ctrl.addListener(() => setState(() {}));
  }

  Future<void> _bootstrap() async {
    try {
      final cfg = await EmailConfig.load();
      if (!mounted) return;
      setState(() {
        _loaded = cfg.to.trim();
        _ctrl.text = _loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '수신자 설정을 불러오지 못했습니다: $e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _value => _ctrl.text.trim();

  bool get _isValid {
    final v = _value;
    if (v.isEmpty) return false;
    return EmailConfig.isValidToList(v);
  }

  List<String> get _parsedList {
    final v = _value;
    if (v.isEmpty) return const [];
    return v
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving) return;

    final v = _value;
    if (!EmailConfig.isValidToList(v)) {
      showFailedSnackbar(
        context,
        '수신자(To) 형식이 올바르지 않습니다. 예) a@x.com, b@y.com',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await EmailConfig.save(EmailConfig(to: v));
      if (!mounted) return;
      setState(() {
        _loaded = v;
      });
      _focus.unfocus();
      showSuccessSnackbar(context, '수신자(To)를 저장했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    if (_saving) return;

    setState(() => _saving = true);
    try {
      await EmailConfig.clear();
      if (!mounted) return;
      setState(() {
        _loaded = '';
        _ctrl.text = '';
      });
      _focus.unfocus();
      showSelectedSnackbar(context, '수신자(To)를 초기화했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '초기화 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoCard(loaded: _loaded, base: _base, light: _light),

          const SizedBox(height: 12),

          Card(
            elevation: 1,
            surfaceTintColor: _light,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText: '메일 수신자(To)',
                      hintText: '예) hr@company.com, manager@company.com',
                      helperText: '여러 명은 쉼표(,)로 구분합니다.',
                      isDense: true,
                      filled: true,
                      fillColor: _light.withOpacity(.06),
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      errorText: _value.isEmpty
                          ? null
                          : (_isValid ? null : '이메일 형식을 확인하세요. (쉼표로 구분)'),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _light.withOpacity(.35)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _base, width: 1.6),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_parsedList.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _parsedList
                          .map(
                            (e) => Chip(
                          label: Text(
                            e,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          backgroundColor: _light.withOpacity(.10),
                          side: BorderSide(color: _light.withOpacity(.35)),
                        ),
                      )
                          .toList(growable: false),
                    )
                  else
                    Text(
                      '현재 입력된 수신자가 없습니다.',
                      style: TextStyle(color: Colors.black.withOpacity(.55)),
                    ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _clear,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('초기화'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _dark,
                            side: BorderSide(color: _dark.withOpacity(.55)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_saving || !_isValid) ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.save_rounded),
                          label: const Text('저장'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _base,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          _GuideCard(light: _light),
        ],
      ),
    );

    if (!widget.asBottomSheet) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black87,
          centerTitle: true,
          title: const Text('메일 수신자 설정', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        body: SingleChildScrollView(child: content),
      );
    }

    return _SheetScaffold(
      title: '메일 수신자 설정',
      onClose: () => Navigator.of(context).maybePop(),
      body: SingleChildScrollView(child: content),
      trailingActions: [
        IconButton(
          tooltip: '초기화',
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: _saving ? null : _clear,
        ),
        IconButton(
          tooltip: '저장',
          icon: const Icon(Icons.save_rounded),
          onPressed: (_saving || !_isValid) ? null : _save,
        ),
      ],
    );
  }
}

/// 상단 안내 카드
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.loaded,
    required this.base,
    required this.light,
  });

  final String loaded;
  final Color base;
  final Color light;

  @override
  Widget build(BuildContext context) {
    final has = loaded.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: light.withOpacity(.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: light.withOpacity(.24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: base,
            foregroundColor: Colors.white,
            child: const Icon(Icons.mail_outline_rounded),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              has ? '저장된 수신자(To): $loaded' : '저장된 수신자(To): 없음 (메일 발송 전 반드시 설정)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// 하단 가이드 카드
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.light});

  final Color light;

  @override
  Widget build(BuildContext context) {
    Text t(String s) => Text(
      s,
      style: TextStyle(color: Colors.black.withOpacity(.75)),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: light.withOpacity(.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: light.withOpacity(.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('입력 규칙', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          t('• 여러 명에게 보내려면 쉼표(,)로 구분합니다.'),
          t('• 예) hr@company.com, manager@company.com'),
          const SizedBox(height: 6),
          t('• 저장되면 SharedPreferences 키 mail.to 로 보관됩니다.'),
          t('• 값이 비어 있으면 메일 발송이 차단됩니다.'),
        ],
      ),
    );
  }
}

/// ===== 가변 높이 바텀시트 프레임 =====
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
      widthFactor: 1.0,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 8,
                color: Color(0x33000000),
                offset: Offset(0, 8),
              ),
            ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.white,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 바텀시트 전용 스캐폴드 =====
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
            color: Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
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
