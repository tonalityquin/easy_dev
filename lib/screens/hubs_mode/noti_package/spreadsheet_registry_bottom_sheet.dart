import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../utils/snackbar_helper.dart';
import 'shared_spreadsheet_registry.dart';

class SpreadsheetRegistryBottomSheet extends StatefulWidget {
  const SpreadsheetRegistryBottomSheet({
    super.key,
    required this.feature,
    required this.title,
    this.themeBase = const Color(0xFFF57C00),
    this.themeDark = const Color(0xFFE65100),
    this.themeLight = const Color(0xFFFFE0B2),
    this.asBottomSheet = false,
  });

  final HeadSheetFeature feature;
  final String title;

  final Color themeBase;
  final Color themeDark;
  final Color themeLight;

  final bool asBottomSheet;

  static Future<T?> showAsBottomSheet<T>({
    required BuildContext context,
    required HeadSheetFeature feature,
    required String title,
    Color themeBase = const Color(0xFFF57C00),
    Color themeDark = const Color(0xFFE65100),
    Color themeLight = const Color(0xFFFFE0B2),
  }) {
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
          child: _BottomSheetFrame(
            heightFactor: 0.92,
            child: SpreadsheetRegistryBottomSheet(
              feature: feature,
              title: title,
              themeBase: themeBase,
              themeDark: themeDark,
              themeLight: themeLight,
              asBottomSheet: true,
            ),
          ),
        );
      },
    );
  }

  @override
  State<SpreadsheetRegistryBottomSheet> createState() => _SpreadsheetRegistryBottomSheetState();
}

class _SpreadsheetRegistryBottomSheetState extends State<SpreadsheetRegistryBottomSheet> {
  late final TextEditingController _aliasCtrl = TextEditingController();
  late final TextEditingController _idCtrl = TextEditingController();

  bool _booting = true;
  bool _saving = false;

  String _activeAlias = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await SharedSpreadsheetRegistry.ensureBootstrapped();
    _activeAlias = SharedSpreadsheetRegistry.activeAliasOf(widget.feature);

    if (!mounted) return;
    setState(() => _booting = false);
  }

  void _fillFormFromEntry(SheetAliasEntry e) {
    _aliasCtrl.text = e.alias;
    _idCtrl.text = e.spreadsheetId;
    HapticFeedback.selectionClick();
  }

  Future<void> _setActive(String alias) async {
    await SharedSpreadsheetRegistry.setActiveAlias(widget.feature, alias);
    if (!mounted) return;
    setState(() => _activeAlias = SharedSpreadsheetRegistry.activeAliasOf(widget.feature));
    showSuccessSnackbar(context, '선택 완료: $alias');
  }

  Future<void> _upsert() async {
    if (_saving) return;

    final alias = _aliasCtrl.text.trim();
    final raw = _idCtrl.text.trim();

    if (!SharedSpreadsheetRegistry.isLikelyAlias(alias)) {
      showFailedSnackbar(context, '별명을 입력하세요.');
      return;
    }
    if (!SharedSpreadsheetRegistry.isLikelySpreadsheetIdOrUrl(raw)) {
      showFailedSnackbar(context, '스프레드시트 ID(또는 URL)를 입력하세요.');
      return;
    }

    setState(() => _saving = true);
    try {
      await SharedSpreadsheetRegistry.upsert(
        alias: alias,
        rawIdOrUrl: raw,
        setActiveForNotice: widget.feature == HeadSheetFeature.notice,
        setActiveForChat: widget.feature == HeadSheetFeature.chat,
      );

      if (!mounted) return;

      setState(() => _activeAlias = SharedSpreadsheetRegistry.activeAliasOf(widget.feature));
      _aliasCtrl.clear();
      _idCtrl.clear();
      HapticFeedback.selectionClick();
      showSuccessSnackbar(context, '저장했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String alias) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제'),
        content: Text('“$alias” 항목을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );

    if (ok != true) return;

    await SharedSpreadsheetRegistry.removeAlias(alias);

    if (!mounted) return;
    setState(() => _activeAlias = SharedSpreadsheetRegistry.activeAliasOf(widget.feature));
    showSelectedSnackbar(context, '삭제했습니다.');
  }

  Future<void> _rename(String oldAlias) async {
    final ctrl = TextEditingController(text: oldAlias);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('별명 변경'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '새 별명',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('변경')),
        ],
      ),
    );

    if (ok != true) return;

    final newAlias = ctrl.text.trim();
    if (newAlias.isEmpty) {
      showFailedSnackbar(context, '새 별명을 입력하세요.');
      return;
    }

    try {
      await SharedSpreadsheetRegistry.renameAlias(oldAlias: oldAlias, newAlias: newAlias);
      if (!mounted) return;
      setState(() => _activeAlias = SharedSpreadsheetRegistry.activeAliasOf(widget.feature));
      showSuccessSnackbar(context, '별명을 변경했습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '변경 실패: $e');
    }
  }

  Widget _buildHeader() {
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
              const Icon(Icons.grid_on_outlined, size: 20, color: Colors.black87),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    );
  }

  Widget _buildBody() {
    return ValueListenableBuilder<List<SheetAliasEntry>>(
      valueListenable: SharedSpreadsheetRegistry.entriesNotifier,
      builder: (context, entries, _) {
        final active = _activeAlias.trim();
        final hasEntries = entries.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 1,
                surfaceTintColor: widget.themeLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '현재 선택(활성 별명)',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        active.isEmpty ? '(미선택)' : active,
                        style: TextStyle(color: Colors.black.withOpacity(.70), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (!hasEntries)
                        const Text(
                          '등록된 스프레드시트가 없습니다.\n아래에서 “별명 + ID(URL)”를 추가하세요.',
                          style: TextStyle(fontSize: 13, height: 1.35),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: widget.themeLight.withOpacity(.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black.withOpacity(.06)),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < entries.length; i++) ...[
                                _EntryRow(
                                  entry: entries[i],
                                  selected: entries[i].alias == active,
                                  onSelect: () => _setActive(entries[i].alias),
                                  onFillForm: () => _fillFormFromEntry(entries[i]),
                                  onRename: () => _rename(entries[i].alias),
                                  onRemove: () => _remove(entries[i].alias),
                                ),
                                if (i != entries.length - 1)
                                  Divider(height: 1, color: Colors.black.withOpacity(.06)),
                              ]
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 1,
                surfaceTintColor: widget.themeLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '추가/수정',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _aliasCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '별명',
                          isDense: true,
                          filled: true,
                          fillColor: widget.themeLight.withOpacity(.12),
                          prefixIcon: const Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _idCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '스프레드시트 ID 또는 URL',
                          isDense: true,
                          filled: true,
                          fillColor: widget.themeLight.withOpacity(.12),
                          prefixIcon: const Icon(Icons.link_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _upsert,
                        icon: _saving
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Icon(Icons.save_rounded),
                        label: const Text('저장(레지스트리에 반영)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.themeBase,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '공유 키: $kHeadSpreadsheetAliasRegistryKey\n'
                            '선택 키(공지): $kHeadActiveSheetAliasNoticeKey\n'
                            '선택 키(채팅): $kHeadActiveSheetAliasChatKey',
                        style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.55), height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _booting
        ? const Center(child: CircularProgressIndicator())
        : Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 6),
        const Divider(height: 1, thickness: 1, color: Color(0xFFEAEAEA)),
        Expanded(child: _buildBody()),
      ],
    );

    if (!widget.asBottomSheet) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        backgroundColor: const Color(0xFFF6F7F9),
        body: SafeArea(child: content),
      );
    }

    return content;
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onSelect,
    required this.onFillForm,
    required this.onRename,
    required this.onRemove,
  });

  final SheetAliasEntry entry;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onFillForm;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? cs.primary : Colors.black38,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.alias,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.spreadsheetId,
                    style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.55)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '폼에 불러오기',
              onPressed: onFillForm,
              icon: const Icon(Icons.edit_note_rounded),
            ),
            IconButton(
              tooltip: '별명 변경',
              onPressed: onRename,
              icon: const Icon(Icons.drive_file_rename_outline),
            ),
            IconButton(
              tooltip: '삭제',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
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
