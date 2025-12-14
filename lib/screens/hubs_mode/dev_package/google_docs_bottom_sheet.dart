// lib/screens/dev_package/google_docs_doc_bottom_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, HapticFeedback;
import 'package:googleapis/docs/v1.dart' as gdocs;
import 'package:shared_preferences/shared_preferences.dart';

// ✅ 중앙 인증 세션만 사용 (google_sign_in v7 대응)
//    - 이 파일에서는 OAuth 호출(authenticate/authorizeScopes 등) 금지
//    - 모든 Google API는 공통 세션에서 받은 AuthClient로만 생성
import 'package:easydev/utils/google_auth_session.dart';

import '../../../utils/app_navigator.dart'; // navigatorKey 사용

/// 드래그 가능한 플로팅 버블 + 풀높이 바텀시트 UI로
/// Google Docs 문서를 "플레인 텍스트"로 불러오고/저장하는 패널.
/// - 문서 생성 ❌ (기존 문서만 사용)
/// - 문서 ID는 SharedPreferences에 저장/복원
/// - ✅ 인증 방식: 중앙 세션(OAuth) 재사용
class GoogleDocsDocPanel {
  GoogleDocsDocPanel._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 플로팅 버블 on/off
  static final enabled = ValueNotifier<bool>(false);

  static OverlayEntry? _entry;
  static bool _isPanelOpen = false;
  static Future<void>? _panelFuture;

  /// 앱 시작 시 한 번 호출(선택)
  static Future<void> init() async {
    enabled.addListener(() {
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  /// 첫 프레임 이후 부착 필요 시 호출
  static void mountIfNeeded() {
    if (enabled.value) _showOverlay();
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(builder: (_) => const _GDocBubble());
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  /// 외부에서 호출할 토글 API
  static Future<void> togglePanel() async {
    final ctx = navigatorKey.currentState?.overlay?.context ??
        navigatorKey.currentState?.context;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => togglePanel());
      return;
    }
    if (_isPanelOpen) {
      Navigator.of(ctx).maybePop();
      return;
    }
    if (_panelFuture != null) return;

    _isPanelOpen = true;
    _panelFuture = showModalBottomSheet(
      context: ctx,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GoogleDocsDocBottomSheet(),
    ).whenComplete(() {
      _isPanelOpen = false;
      _panelFuture = null;
    });

    await _panelFuture;
  }
}

/// 드래그 가능한 플로팅 버블
class _GDocBubble extends StatefulWidget {
  const _GDocBubble();

  @override
  State<_GDocBubble> createState() => _GDocBubbleState();
}

class _GDocBubbleState extends State<_GDocBubble> {
  static const double _bubbleSize = 56;
  Offset _pos = const Offset(12, 200);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _pos = Offset(
              (_pos.dx + d.delta.dx).clamp(0.0, screen.width - _bubbleSize),
              (_pos.dy + d.delta.dy)
                  .clamp(0.0, screen.height - _bubbleSize - bottomInset),
            );
          });
        },
        onPanEnd: (_) {
          final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
              ? 8.0
              : screen.width - _bubbleSize - 8.0;
          setState(() => _pos = Offset(snapX, _pos.dy));
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: GoogleDocsDocPanel.togglePanel,
            customBorder: const CircleBorder(),
            child: Container(
              width: _bubbleSize,
              height: _bubbleSize,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: cs.onSurface.withOpacity(.08)),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.description_rounded,
                  color: Colors.white.withOpacity(0.95)),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= Docs API 핸들러 =======================

/// 중앙 세션에서 AuthClient를 받아 Docs API 생성
Future<gdocs.DocsApi> _getDocsApi() async {
  final client = await GoogleAuthSession.instance.safeClient();
  return gdocs.DocsApi(client);
}

// ==============================================================

/// 풀높이 바텀시트 본문
class _GoogleDocsDocBottomSheet extends StatefulWidget {
  const _GoogleDocsDocBottomSheet();

  @override
  State<_GoogleDocsDocBottomSheet> createState() =>
      _GoogleDocsDocBottomSheetState();
}

class _GoogleDocsDocBottomSheetState
    extends State<_GoogleDocsDocBottomSheet> {
  static const _prefsDocIdKey = 'dev_google_docs_document_id';

  final _docIdCtrl = TextEditingController();
  final _editorCtrl = TextEditingController();

  bool _busy = false;
  String? _lastMessage;

  /// ✅ 문서 ID 잠금 상태(기본 true)
  bool _idLocked = true;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_prefsDocIdKey) ?? '';
    setState(() => _docIdCtrl.text = id);
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsDocIdKey, _docIdCtrl.text.trim());
  }

  /// 문서 불러오기(기존 문서만)
  Future<void> _loadDocument() async {
    try {
      setState(() => _busy = true);
      final id = _docIdCtrl.text.trim();
      if (id.isEmpty) throw Exception('문서 ID를 입력해주세요.');

      final api = await _getDocsApi();
      final doc = await api.documents.get(id);

      final text = _flattenPlainText(doc);
      setState(() {
        _editorCtrl.text = text;
        _lastMessage = '로딩 완료: 길이 ${text.length}자';
      });
      await _savePrefs();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('문서를 불러왔습니다.')));
      HapticFeedback.selectionClick();
    } catch (e, st) {
      setState(() => _lastMessage = '로딩 실패: $e');
      debugPrint('[GoogleDocs] _loadDocument() 실패: $e');
      debugPrint('[GoogleDocs] _loadDocument() stack:\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('로딩 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 문서 저장(본문 전체 교체)
  Future<void> _saveDocument() async {
    try {
      setState(() => _busy = true);
      final id = _docIdCtrl.text.trim();
      if (id.isEmpty) throw Exception('문서 ID를 입력해주세요.');

      final api = await _getDocsApi();

      // 현재 문서 길이를 알아내기 위해 get
      final doc = await api.documents.get(id);
      final endIndex = _getDocumentEndIndex(doc); // 최소 1 이상
      // 마지막 세그먼트 개행은 삭제 범위에서 제외 → -1
      final deleteEnd = (endIndex - 1).clamp(1, endIndex);

      final newText = _ensureTrailingNewline(_editorCtrl.text);

      final requests = <gdocs.Request>[];

      // 기존 본문 삭제 (본문은 index 1부터 시작)
      if (deleteEnd > 1) {
        requests.add(
          gdocs.Request(
            deleteContentRange: gdocs.DeleteContentRangeRequest(
              range: gdocs.Range(startIndex: 1, endIndex: deleteEnd),
            ),
          ),
        );
      }

      // 새로운 텍스트 삽입
      requests.add(
        gdocs.Request(
          insertText: gdocs.InsertTextRequest(
            text: newText,
            location: gdocs.Location(index: 1),
          ),
        ),
      );

      await api.documents.batchUpdate(
        gdocs.BatchUpdateDocumentRequest(requests: requests),
        id,
      );

      setState(() => _lastMessage = '저장 완료: ${newText.length}자');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('문서를 저장했습니다.')));
      HapticFeedback.lightImpact();
    } catch (e, st) {
      setState(() => _lastMessage = '저장 실패: $e');
      debugPrint('[GoogleDocs] _saveDocument() 실패: $e');
      debugPrint('[GoogleDocs] _saveDocument() stack:\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== Helpers =====

  int _getDocumentEndIndex(gdocs.Document doc) {
    final contents = doc.body?.content ?? const <gdocs.StructuralElement>[];
    int maxEnd = 1;
    for (final el in contents) {
      final ei = el.endIndex ?? 1;
      if (ei > maxEnd) maxEnd = ei;
    }
    return maxEnd;
  }

  String _flattenPlainText(gdocs.Document doc) {
    final buffer = StringBuffer();
    final contents = doc.body?.content ?? const <gdocs.StructuralElement>[];

    for (final el in contents) {
      final para = el.paragraph;
      if (para != null) {
        for (final ce in para.elements ?? const <gdocs.ParagraphElement>[]) {
          final tr = ce.textRun;
          if (tr?.content != null) buffer.write(tr!.content);
        }
        final str = buffer.toString();
        if (str.isNotEmpty && !str.endsWith('\n')) buffer.write('\n');
      }
      final table = el.table;
      if (table != null) {
        for (final row in table.tableRows ?? const <gdocs.TableRow>[]) {
          for (final cell in row.tableCells ?? const <gdocs.TableCell>[]) {
            final cellTexts = <String>[];
            for (final cse in cell.content ?? const <gdocs.StructuralElement>[]) {
              final p = cse.paragraph;
              if (p != null) {
                for (final ce in p.elements ?? const <gdocs.ParagraphElement>[]) {
                  final tr = ce.textRun;
                  if (tr?.content != null) cellTexts.add(tr!.content!);
                }
              }
            }
            buffer.write(cellTexts.join());
            buffer.write('\t');
          }
          buffer.write('\n');
        }
      }
    }
    return buffer.toString();
  }

  String _ensureTrailingNewline(String s) {
    if (s.isEmpty) return '\n';
    return s.endsWith('\n') ? s : '$s\n';
  }

  @override
  void dispose() {
    _docIdCtrl.dispose();
    _editorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return FractionallySizedBox(
      heightFactor: 1.0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _DragHandle(),
                  const SizedBox(height: 12),

                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.description_rounded, color: cs.primary),
                        const SizedBox(width: 8),
                        const Text('구글 독스 · 문서 편집',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 20)),
                        const Spacer(),
                        ValueListenableBuilder<bool>(
                          valueListenable: GoogleDocsDocPanel.enabled,
                          builder: (_, on, __) => Row(
                            children: [
                              Text(on ? 'On' : 'Off',
                                  style: TextStyle(
                                      color:
                                      Theme.of(context).colorScheme.outline,
                                      fontSize: 12)),
                              const SizedBox(width: 6),
                              Switch(
                                  value: on,
                                  onChanged: (v) =>
                                  GoogleDocsDocPanel.enabled.value = v),
                            ],
                          ),
                        ),
                        if (_busy)
                          const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        IconButton(
                          tooltip: '닫기',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),

                  // 컨트롤 카드
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Card(
                      elevation: 0,
                      color: Colors.white,
                      surfaceTintColor: cs.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ID 입력 (+ 잠금)
                            TextField(
                              controller: _docIdCtrl,
                              readOnly: _idLocked,
                              decoration: InputDecoration(
                                labelText: '문서 ID',
                                hintText:
                                '1A2B3C... (문서 URL의 /d/ 와 /edit 사이)',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  tooltip: _idLocked ? 'ID 잠금 해제' : 'ID 잠금',
                                  icon: Icon(_idLocked
                                      ? Icons.lock
                                      : Icons.lock_open),
                                  onPressed: () =>
                                      setState(() => _idLocked = !_idLocked),
                                ),
                              ),
                              onSubmitted: (_) async {
                                if (_idLocked) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('잠금을 해제한 뒤 ID를 수정하세요.')));
                                  return;
                                }
                                await _savePrefs();
                                HapticFeedback.selectionClick();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('문서 ID를 저장했습니다.')));
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Tooltip(
                                  message: _idLocked
                                      ? '잠금 해제 후 붙여넣기 가능'
                                      : '클립보드에서 붙여넣기',
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.paste_rounded),
                                    label: const Text('붙여넣기'),
                                    onPressed: (_busy || _idLocked)
                                        ? null
                                        : () async {
                                      final data = await Clipboard.getData(
                                          'text/plain');
                                      final pasted =
                                      (data?.text ?? '').trim();
                                      if (pasted.isNotEmpty) {
                                        _docIdCtrl.text = pasted;
                                        await _savePrefs();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      '문서 ID를 저장했습니다.')));
                                        }
                                      }
                                    },
                                  ),
                                ),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.download_rounded),
                                  label: const Text('불러오기'),
                                  onPressed: _busy ? null : _loadDocument,
                                ),
                                FilledButton.icon(
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text('저장'),
                                  onPressed: _busy ? null : _saveDocument,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _lastMessage ??
                                  '현재 로그인한 Google 계정이 문서에 접근/편집 권한을 가지고 있어야 합니다.',
                              style: TextStyle(
                                  color: Colors.black.withOpacity(0.6),
                                  fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 에디터
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Stack(
                        children: [
                          TextField(
                            controller: _editorCtrl,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              hintText:
                              '문서 본문을 입력하거나, 불러온 텍스트를 편집하세요.',
                              border: OutlineInputBorder(),
                              contentPadding:
                              EdgeInsets.fromLTRB(12, 12, 12, 16),
                            ),
                            style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                fontFamily: 'monospace'),
                          ),
                          if (_busy)
                            Positioned.fill(
                              child: Container(
                                alignment: Alignment.center,
                                color: Colors.white.withOpacity(.5),
                                child: const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                  CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 5,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
