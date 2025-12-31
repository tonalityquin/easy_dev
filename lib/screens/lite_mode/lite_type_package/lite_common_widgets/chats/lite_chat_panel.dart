import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/snackbar_helper.dart';
import '../../../../../services/sheet_chat_service.dart';

class LiteChatPanel extends StatefulWidget {
  /// 영역 전환 감지/쇼트컷 키 구분용 (시트 내부 roomId는 사용하지 않음)
  final String scopeKey;

  const LiteChatPanel({super.key, required this.scopeKey});

  @override
  State<LiteChatPanel> createState() => _LiteChatPanelState();
}

class _LiteChatPanelState extends State<LiteChatPanel> {
  static const int _maxShortcuts = 20;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<String> _shortcuts = [];
  bool _canSend = false;

  // 멀티선택
  bool _isMultiSelect = false;
  final Set<int> _selectedShortcutIdx = {};

  String get _prefsKey => 'chat_shortcuts_${widget.scopeKey}';

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      await SheetChatService.instance.sendMessage(text);
      _controller.clear();
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '전송 실패: $e');
    }
  }

  Future<void> _loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _shortcuts = prefs.getStringList(_prefsKey) ?? [];
    });
  }

  Future<void> _saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _shortcuts);
  }

  Future<void> _addShortcut() async {
    final textCtrl = TextEditingController();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          maxChildSize: 1.0,
          minChildSize: 0.4,
          builder: (ctx, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setLocal) {
                final value = textCtrl.text.trim();
                const maxLen = 80;
                final isDuplicate = _shortcuts.contains(value);
                final overLimit = value.length > maxLen;
                final isValid = value.isNotEmpty && !isDuplicate && !overLimit;

                void submitIfValid() {
                  final v = textCtrl.text.trim();
                  if (v.isEmpty) return;
                  Navigator.pop(ctx, v);
                }

                return SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 20,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '쇼트컷 추가',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: textCtrl,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 6,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setLocal(() {}),
                          onSubmitted: (_) => submitIfValid(),
                          decoration: InputDecoration(
                            hintText: '자주 쓰는 문구를 입력하세요',
                            border: const OutlineInputBorder(),
                            helperText:
                            isDuplicate ? '이미 같은 쇼트컷이 있습니다.' : '최대 80자',
                            errorText: overLimit ? '최대 80자까지 입력 가능합니다.' : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('취소'),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              onPressed: isValid ? submitIfValid : null,
                              label: const Text('추가'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    final value = (result ?? '').trim();
    if (value.isEmpty) return;

    if (_shortcuts.contains(value)) {
      if (!mounted) return;
      showFailedSnackbar(context, '이미 같은 쇼트컷이 있습니다.');
      return;
    }

    setState(() {
      _shortcuts.add(value);
      if (_shortcuts.length > _maxShortcuts) {
        _shortcuts.removeAt(0);
      }
    });
    await _saveShortcuts();
  }

  Future<void> _removeShortcut(String value) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('삭제 확인'),
        content: Text('"$value" 쇼트컷을 삭제하시겠어요?'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _shortcuts.remove(value));
    await _saveShortcuts();
  }

  void _handleTextChanged() {
    final enabled = _controller.text.trim().isNotEmpty;
    if (_canSend != enabled) {
      setState(() => _canSend = enabled);
    }
  }

  void _insertAtCursor(String insert) {
    final text = _controller.text;
    final sel = _controller.selection;

    final hasSel = sel.isValid;
    final start = hasSel ? sel.start : text.length;
    final end = hasSel ? sel.end : text.length;

    final before = text.substring(0, start);
    final after = text.substring(end);

    final needsSpaceBefore = before.isNotEmpty && !before.endsWith(' ');
    final needsSpaceAfter = after.isNotEmpty && !insert.endsWith(' ');

    final toInsert =
        '${needsSpaceBefore ? ' ' : ''}$insert${needsSpaceAfter ? ' ' : ''}';

    final newText = '$before$toInsert$after';
    final newOffset = before.length + toInsert.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
    _focusNode.requestFocus();
  }

  void _clearInput() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _toggleMultiSelect() {
    setState(() {
      _isMultiSelect = !_isMultiSelect;
      if (!_isMultiSelect) _selectedShortcutIdx.clear();
    });
  }

  void _exitMultiSelectIfNeeded() {
    if (_isMultiSelect) {
      setState(() {
        _isMultiSelect = false;
        _selectedShortcutIdx.clear();
      });
    }
  }

  void _toggleShortcutSelection(int idx) {
    setState(() {
      if (_selectedShortcutIdx.contains(idx)) {
        _selectedShortcutIdx.remove(idx);
      } else {
        _selectedShortcutIdx.add(idx);
      }
    });
  }

  void _insertSelectedShortcuts() {
    if (_selectedShortcutIdx.isEmpty) return;
    final parts = _selectedShortcutIdx.toList()..sort();
    final text = parts.map((i) => _shortcuts[i]).join(' ');
    _insertAtCursor(text);
    _toggleMultiSelect();
  }

  @override
  void initState() {
    super.initState();
    SheetChatService.instance.start(widget.scopeKey);
    _loadShortcuts();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant LiteChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      SheetChatService.instance.start(widget.scopeKey);
      _loadShortcuts();
      _controller.clear();
      _exitMultiSelectIfNeeded();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SheetChatState>(
      valueListenable: SheetChatService.instance.state,
      builder: (context, st, _) {
        final messages = st.messages;

        return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              children: [
                if (_shortcuts.isNotEmpty) ...[
                  if (!_isMultiSelect)
                    TextButton.icon(
                      onPressed: _toggleMultiSelect,
                      icon: const Icon(Icons.select_all),
                      label: const Text('선택'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _selectedShortcutIdx.isNotEmpty
                          ? _insertSelectedShortcuts
                          : null,
                      icon: const Icon(Icons.input),
                      label: Text('삽입(${_selectedShortcutIdx.length})'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _toggleMultiSelect,
                      child: const Text('취소'),
                    ),
                  ],
                  const Spacer(),
                ] else
                  const Spacer(),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: () =>
                      SheetChatService.instance.start(widget.scopeKey),
                  icon: st.loading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _addShortcut,
                  icon: const Icon(Icons.add),
                  label: const Text('쇼트컷 추가'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (st.error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Text(
                  st.error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (messages.isEmpty && !st.loading && st.error == null)
                      Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '아직 메시지가 없습니다.',
                          style: TextStyle(fontSize: 13),
                        ),
                      )
                    else
                      ...messages.map((m) {
                        String timeText = '';
                        final t = m.time;
                        if (t != null) {
                          try {
                            timeText =
                                DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());
                          } catch (_) {}
                        }

                        final subtitle = timeText.isNotEmpty ? '🕒 $timeText' : '';

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('[익명]',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(m.text),
                              const SizedBox(height: 8),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                            ],
                          ),
                        );
                      }),

                    if (_shortcuts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: List.generate(_shortcuts.length, (i) {
                              final s = _shortcuts[i];
                              final selected = _selectedShortcutIdx.contains(i);

                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onLongPress:
                                  !_isMultiSelect ? () => _removeShortcut(s) : null,
                                  child: FilterChip(
                                    selected: selected,
                                    label: Text(s, overflow: TextOverflow.ellipsis),
                                    onSelected: (_) {
                                      if (_isMultiSelect) {
                                        _toggleShortcutSelection(i);
                                      } else {
                                        _insertAtCursor(s);
                                      }
                                    },
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _canSend ? _sendMessage() : null,
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        tooltip: '입력 지우기',
                        icon: const Icon(Icons.clear),
                        onPressed: _controller.text.isNotEmpty ? _clearInput : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: '메시지 보내기',
                  child: Container(
                    decoration: BoxDecoration(
                      color: _canSend ? Colors.blue : Colors.blue.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _canSend ? _sendMessage : null,
                      tooltip: '보내기',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
