import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;

import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/google_auth_session.dart';
import 'shared_spreadsheet_registry.dart';
import 'spreadsheet_registry_bottom_sheet.dart';

/// ✅ (중요) 공지 시트명 고정: noti
const String kNoticeSheetName = 'noti';

/// ✅ (중요) 공지 Range (noti 시트 A열 1~50행)
const String kNoticeSpreadsheetRange = '$kNoticeSheetName!A1:A50';

/// ✅ 공지 고정 행 수
const int kNoticeMaxRows = 50;

Future<sheets.SheetsApi> _sheetsApi() async {
  final client = await GoogleAuthSession.instance.safeClient();
  return sheets.SheetsApi(client);
}

/// 공지 작성/수정 바텀시트
/// - 레지스트리에서 "활성 별명(공지)"의 spreadsheetId를 사용
/// - 별명 드롭다운으로 대상 시트를 바꿔가며 수정 가능
class NoticeEditorBottomSheet extends StatefulWidget {
  const NoticeEditorBottomSheet({super.key});

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
            child: NoticeEditorBottomSheet(),
          ),
        );
      },
    );
  }

  @override
  State<NoticeEditorBottomSheet> createState() => _NoticeEditorBottomSheetState();
}

class _NoticeEditorBottomSheetState extends State<NoticeEditorBottomSheet> {
  static const _base = Color(0xFFF57C00);
  static const _dark = Color(0xFFE65100);
  static const _light = Color(0xFFFFE0B2);

  bool _loading = false;
  bool _saving = false;

  String _activeAlias = '';
  String _sheetId = '';
  String? _error;

  final ScrollController _scroll = ScrollController();

  late final List<TextEditingController> _controllers =
  List.generate(kNoticeMaxRows, (_) => TextEditingController());

  @override
  void initState() {
    super.initState();
    _init();

    SharedSpreadsheetRegistry.entriesNotifier.addListener(_syncSelectionAndMaybeLoad);
    SharedSpreadsheetRegistry.activeNoticeAliasNotifier.addListener(_syncSelectionAndMaybeLoad);
  }

  @override
  void dispose() {
    SharedSpreadsheetRegistry.entriesNotifier.removeListener(_syncSelectionAndMaybeLoad);
    SharedSpreadsheetRegistry.activeNoticeAliasNotifier.removeListener(_syncSelectionAndMaybeLoad);

    for (final c in _controllers) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await SharedSpreadsheetRegistry.ensureBootstrapped();
    _syncSelectionAndMaybeLoad(force: true);
  }

  void _syncSelectionAndMaybeLoad({bool force = false}) {
    if (!mounted) return;

    final alias = SharedSpreadsheetRegistry.activeAliasOf(HeadSheetFeature.notice);
    final id = SharedSpreadsheetRegistry.activeSpreadsheetIdOf(HeadSheetFeature.notice) ?? '';

    final changed = (alias != _activeAlias) || (id != _sheetId);

    if (!force && !changed) return;

    setState(() {
      _activeAlias = alias;
      _sheetId = id;
      _error = null;
      for (final c in _controllers) {
        c.text = '';
      }
    });

    if (_sheetId.isNotEmpty) {
      _load();
    }
  }

  Future<void> _openRegistrySettings() async {
    await SpreadsheetRegistryBottomSheet.showAsBottomSheet(
      context: context,
      feature: HeadSheetFeature.notice,
      title: '공지 스프레드시트 목록/선택',
      themeBase: _base,
      themeDark: _dark,
      themeLight: _light,
    );
    // 저장/선택 이후 notifier 변화로 자동 로드됩니다.
  }

  Future<void> _load() async {
    final id = _sheetId.trim();
    if (id.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = await _sheetsApi();
      final resp = await api.spreadsheets.values.get(id, kNoticeSpreadsheetRange);
      final values = resp.values ?? const [];

      for (final c in _controllers) {
        c.text = '';
      }

      for (int i = 0; i < values.length && i < kNoticeMaxRows; i++) {
        final row = values[i];
        final rowStrings = row.map((c) => (c ?? '').toString().trim()).toList();
        final joined = rowStrings.where((s) => s.isNotEmpty).join(' ');
        _controllers[i].text = joined;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      final msg = GoogleAuthSession.isInvalidTokenError(e)
          ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
          : '공지 불러오기 실패: $e';

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;

    final id = _sheetId.trim();
    if (id.isEmpty) {
      showFailedSnackbar(context, '공지 대상 스프레드시트가 선택되어 있지 않습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final api = await _sheetsApi();

      final values = List<List<Object?>>.generate(
        kNoticeMaxRows,
            (i) => <Object?>[_controllers[i].text.trim()],
      );

      final body = sheets.ValueRange(values: values);

      await api.spreadsheets.values.update(
        body,
        id,
        kNoticeSpreadsheetRange,
        valueInputOption: 'RAW',
      );

      if (!mounted) return;
      HapticFeedback.selectionClick();
      showSuccessSnackbar(context, '공지를 저장했습니다.');
      SharedSpreadsheetRegistry.bumpNoticeRevision();
    } catch (e) {
      final msg = GoogleAuthSession.isInvalidTokenError(e)
          ? '구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.'
          : '공지 저장 실패: $e';

      if (!mounted) return;
      setState(() => _error = msg);
      showFailedSnackbar(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearAll() async {
    if (_saving) return;

    for (final c in _controllers) {
      c.text = '';
    }
    HapticFeedback.selectionClick();
    showSelectedSnackbar(context, '모든 공지 내용을 비웠습니다. 저장을 눌러 반영하세요.');
  }

  List<String> _previewLines() {
    final lines = <String>[];
    for (final c in _controllers) {
      final t = c.text.trim();
      if (t.isNotEmpty) lines.add(t);
    }
    return lines;
  }

  Widget _aliasDropdown() {
    return ValueListenableBuilder<List<SheetAliasEntry>>(
      valueListenable: SharedSpreadsheetRegistry.entriesNotifier,
      builder: (context, entries, _) {
        if (entries.isEmpty) {
          return const Text('(미등록)', style: TextStyle(fontSize: 12, color: Colors.black54));
        }

        final value = _activeAlias.isEmpty ? entries.first.alias : _activeAlias;

        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            items: [
              for (final e in entries)
                DropdownMenuItem<String>(
                  value: e.alias,
                  child: Text(
                    e.alias,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              await SharedSpreadsheetRegistry.setActiveAlias(HeadSheetFeature.notice, v);
            },
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Padding(
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
              const Text(
                '공지 편집',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _light.withOpacity(.22),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black.withOpacity(.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.label_rounded, size: 16, color: Colors.black54),
                        const SizedBox(width: 6),
                        Flexible(child: _aliasDropdown()),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '목록/선택',
                onPressed: _openRegistrySettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                tooltip: '새로고침',
                onPressed: (_sheetId.isEmpty || _loading) ? null : _load,
                icon: _loading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Card(
        elevation: 1,
        surfaceTintColor: _light,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '공지 대상 스프레드시트가 없습니다.',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                '먼저 “별명 + 스프레드시트 ID(URL)”를 등록하고 선택하세요.\n'
                    '공지 내용은 “$kNoticeSheetName” 시트의 A열($kNoticeSpreadsheetRange)을 사용합니다.',
                style: TextStyle(fontSize: 13, color: Colors.black.withOpacity(.80), height: 1.35),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _base,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _openRegistrySettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('공지 스프레드시트 목록/선택 열기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Expanded(
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.25)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.25),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _light.withOpacity(.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black.withOpacity(.06)),
                      ),
                      child: const TabBar(
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: '미리보기'),
                          Tab(text: '편집'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Card(
                            elevation: 0,
                            color: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                              child: Builder(
                                builder: (_) {
                                  final lines = _previewLines();
                                  if (lines.isEmpty) {
                                    return const Text(
                                      '공지 내용이 없습니다.\n편집 탭에서 내용을 입력하세요.',
                                      style: TextStyle(fontSize: 13, height: 1.35),
                                    );
                                  }
                                  return Scrollbar(
                                    controller: _scroll,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      controller: _scroll,
                                      child: Text(
                                        lines.map((e) => '• $e').join('\n'),
                                        style: const TextStyle(fontSize: 13, height: 1.35),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: kNoticeMaxRows,
                          itemBuilder: (context, i) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: TextField(
                                controller: _controllers[i],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: '공지 ${i + 1}',
                                  isDense: true,
                                  filled: true,
                                  fillColor: _light.withOpacity(.12),
                                  prefixIcon: const Icon(Icons.edit_note_rounded),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _clearAll,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('비우기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dark,
                      side: BorderSide(color: _base.withOpacity(.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.save_rounded),
                    label: const Text('저장'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _base,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        const SizedBox(height: 6),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEAEAEA)),
        if (_sheetId.trim().isEmpty) _buildNoSelection() else _buildEditor(),
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
