import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/snackbar_helper.dart';

class ChatPanel extends StatefulWidget {
  final String roomId;

  const ChatPanel({super.key, required this.roomId});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  static const int _maxShortcuts = 20;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<DocumentSnapshot>? _chatSubscription;

  String latestMessage = '';
  Timestamp? latestTimestamp;
  bool _hasPendingWrites = false;

  List<String> _shortcuts = [];
  bool _canSend = false;

  // 멀티선택
  bool _isMultiSelect = false;
  final Set<int> _selectedShortcutIdx = {};

  String get _prefsKey => 'chat_shortcuts_${widget.roomId}';

  @override
  void initState() {
    super.initState();
    _listenToLatestMessage();
    _loadShortcuts();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _chatSubscription?.cancel();
      _listenToLatestMessage();
      _loadShortcuts();
      _controller.clear(); // 방 변경 시 혼동 방지
      _exitMultiSelectIfNeeded();
    }
  }

  void _handleTextChanged() {
    final enabled = _controller.text.trim().isNotEmpty;
    if (_canSend != enabled) {
      setState(() => _canSend = enabled);
    }
  }

  void _listenToLatestMessage() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.roomId)
        .collection('state')
        .doc('latest_message')
        .snapshots(includeMetadataChanges: true)
        .listen((docSnapshot) {
      final data = docSnapshot.data();
      if (!mounted) return;

      setState(() {
        _hasPendingWrites = docSnapshot.metadata.hasPendingWrites;
        if (data == null) {
          latestMessage = '';
          latestTimestamp = null;
          return;
        }
        final msg = data['message'];
        latestMessage = (msg is String) ? msg : '';
        final ts = data['timestamp'];
        latestTimestamp = ts is Timestamp ? ts : null;
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.roomId)
          .collection('state')
          .doc('latest_message')
          .set({
        'message': text,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _controller.clear();
      _focusNode.requestFocus();
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('sendMessage error: $e\n$st');
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
      // 노치/상단 안전영역
      backgroundColor: Colors.white,
      // 시트 배경 흰색
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          // 화면 최상단까지
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
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, // 키보드 패딩
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '쇼트컷 추가',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                            helperText: isDuplicate ? '이미 같은 쇼트컷이 있습니다.' : '최대 80자',
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
        _shortcuts.removeAt(0); // FIFO
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

  // ── 커서 위치/선택영역 삽입 & 공백 보정
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

    final toInsert = '${needsSpaceBefore ? ' ' : ''}$insert${needsSpaceAfter ? ' ' : ''}';

    final newText = '$before$toInsert$after';
    final newOffset = before.length + toInsert.length;

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );
    _focusNode.requestFocus();
  }

  // 입력창 한 번에 지우기
  void _clearInput() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    // listener에서 _canSend=false로 반영됨
    _focusNode.requestFocus();
  }

  // 멀티선택 모드 토글
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
    _toggleMultiSelect(); // 삽입 후 종료
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String timeText = '';
    final ts = latestTimestamp;
    if (ts != null) {
      try {
        final dt = ts.toDate();
        if (dt.millisecondsSinceEpoch > 0) {
          timeText = DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
        }
      } catch (_) {}
    }

    final subtitle = _hasPendingWrites || ts == null ? '동기화 중...' : (timeText.isNotEmpty ? '🕒 $timeText' : '');

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        // 상단 액션 바
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
                  onPressed: _selectedShortcutIdx.isNotEmpty ? _insertSelectedShortcuts : null,
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
            TextButton.icon(
              onPressed: _addShortcut,
              icon: const Icon(Icons.add),
              label: const Text('쇼트컷 추가'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 최근 메시지 + 쇼트컷
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('[익명]', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(latestMessage),
                      const SizedBox(height: 8),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
                if (_shortcuts.isNotEmpty) ...[
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
                              onLongPress: !_isMultiSelect ? () => _removeShortcut(s) : null,
                              child: FilterChip(
                                selected: selected,
                                label: Text(s, overflow: TextOverflow.ellipsis),
                                onSelected: (val) {
                                  if (_isMultiSelect) {
                                    _toggleShortcutSelection(i);
                                  } else {
                                    _insertAtCursor(s); // 즉시 삽입
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

        // 입력 + 지우기 + 전송
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  // ✅ 입력 전체 지우기 버튼
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
  }
}
