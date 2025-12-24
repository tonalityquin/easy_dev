import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../utils/snackbar_helper.dart';
import '../noti_package/shared_spreadsheet_registry.dart';
import 'spreadsheet_registry_bottom_sheet.dart';

/// ✅ (NoticeEditor와 동일 값으로 유지 권장)
const String kNoticeSheetName = 'noti';
const String kNoticeSpreadsheetRange = '$kNoticeSheetName!A1:A50';

class NoticeSettingsBottomSheet extends StatefulWidget {
  const NoticeSettingsBottomSheet({super.key, this.asBottomSheet = false});

  final bool asBottomSheet;

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
            heightFactor: 0.92,
            child: NoticeSettingsBottomSheet(asBottomSheet: true),
          ),
        );
      },
    );
  }

  @override
  State<NoticeSettingsBottomSheet> createState() =>
      _NoticeSettingsBottomSheetState();
}

class _NoticeSettingsBottomSheetState extends State<NoticeSettingsBottomSheet> {
  static const _base = Color(0xFFF57C00);
  static const _dark = Color(0xFFE65100);
  static const _light = Color(0xFFFFE0B2);

  bool _booting = true;
  bool _saving = false;

  final TextEditingController _aliasCtrl = TextEditingController();
  final TextEditingController _idCtrl = TextEditingController();
  final FocusNode _focusAlias = FocusNode();
  final FocusNode _focusId = FocusNode();

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _aliasCtrl.addListener(() => setState(() {}));
    _idCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _idCtrl.dispose();
    _focusAlias.dispose();
    _focusId.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await SharedSpreadsheetRegistry.ensureBootstrapped();
      if (!mounted) return;
      setState(() => _booting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _booting = false);
      showFailedSnackbar(context, '초기화 실패: $e');
    }
  }

  String get _alias => _aliasCtrl.text.trim();
  String get _rawIdOrUrl => _idCtrl.text.trim();

  bool get _canSave {
    return _alias.isNotEmpty && _rawIdOrUrl.trim().length >= 10;
  }

  Future<void> _openRegistryManager() async {
    await SpreadsheetRegistryBottomSheet.showAsBottomSheet(
      context: context,
      feature: HeadSheetFeature.notice,
      title: '공지 스프레드시트 목록/선택',
      themeBase: _base,
      themeDark: _dark,
      themeLight: _light,
    );
  }

  Future<void> _saveQuick() async {
    if (_saving) return;

    final a = _alias;
    final raw = _rawIdOrUrl;
    if (a.isEmpty || raw.isEmpty || raw.length < 10) {
      showFailedSnackbar(context, '별명과 스프레드시트 ID(URL)를 입력하세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      await SharedSpreadsheetRegistry.upsert(
        alias: a,
        rawIdOrUrl: raw,
        setActiveForNotice: true,
      );

      if (!mounted) return;
      HapticFeedback.selectionClick();
      _focusAlias.unfocus();
      _focusId.unfocus();
      showSuccessSnackbar(context, '공지 스프레드시트를 저장하고 활성화했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeActive() async {
    if (_saving) return;

    final active = SharedSpreadsheetRegistry.activeAliasOf(HeadSheetFeature.notice);
    if (active.isEmpty) {
      showSelectedSnackbar(context, '삭제할 활성 항목이 없습니다.');
      return;
    }

    setState(() => _saving = true);
    try {
      await SharedSpreadsheetRegistry.removeAlias(active);

      if (!mounted) return;
      HapticFeedback.selectionClick();
      showSelectedSnackbar(context, '활성 공지 항목을 삭제했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildBody() {
    if (_booting) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: SharedSpreadsheetRegistry.activeNoticeAliasNotifier,
            builder: (context, activeAlias, _) {
              final id =
                  SharedSpreadsheetRegistry.activeSpreadsheetIdOf(HeadSheetFeature.notice) ??
                      '';
              final showAlias = activeAlias.trim().isEmpty ? '(미선택)' : activeAlias.trim();
              final showId = id.trim().isEmpty ? '(미설정)' : id.trim();

              return Card(
                elevation: 1,
                surfaceTintColor: _light,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '공지 스프레드시트 설정(공용 레지스트리)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '현재 활성(공지): $showAlias',
                        style: TextStyle(color: Colors.black.withOpacity(.70), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spreadsheet ID: $showId',
                        style: TextStyle(color: Colors.black.withOpacity(.65), fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '공지 내용은 “$kNoticeSheetName” 시트의 A열($kNoticeSpreadsheetRange)을 사용합니다.',
                        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(.70)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : _removeActive,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('활성 항목 삭제'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _dark,
                                side: BorderSide(color: _base.withOpacity(.5)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _openRegistryManager,
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('목록/선택'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _base,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '빠른 추가/갱신',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _aliasCtrl,
                    focusNode: _focusAlias,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: '별명',
                      hintText: '예: 본사-공지, A팀-공지',
                      isDense: true,
                      filled: true,
                      fillColor: _light.withOpacity(.12),
                      prefixIcon: const Icon(Icons.label_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _focusId.requestFocus(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _idCtrl,
                    focusNode: _focusId,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Spreadsheet ID 또는 URL',
                      hintText: '예) https://docs.google.com/spreadsheets/d/<ID>/edit',
                      isDense: true,
                      filled: true,
                      fillColor: _light.withOpacity(.12),
                      prefixIcon: const Icon(Icons.grid_on_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onSubmitted: (_) => _canSave ? _saveQuick() : null,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: (_saving || !_canSave) ? null : _saveQuick,
                    icon: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.save_rounded),
                    label: const Text('저장 후 활성화'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _base,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (!widget.asBottomSheet) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('공지 설정'),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        backgroundColor: const Color(0xFFF6F7F9),
        body: SafeArea(child: body),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const SizedBox(width: 4),
                  const Icon(Icons.campaign_rounded, size: 20, color: Colors.black87),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '공지 설정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEAEAEA)),
        Expanded(child: body),
      ],
    );
  }
}

/// 공용 바텀시트 프레임(92%)
class _BottomSheetFrame extends StatelessWidget {
  final Widget child;
  final double heightFactor;

  const _BottomSheetFrame({
    required this.child,
    this.heightFactor = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: size.height * heightFactor,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: child,
        ),
      ),
    );
  }
}
