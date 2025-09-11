// lib/screens/dev_package/google_docs_doc_bottom_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/docs/v1.dart' as gdocs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // debugPrint 사용

/// Google Docs(문서) 편집 바텀시트
/// - 서비스계정 인증 (Docs API scope)
/// - 새 문서 생성 / 기존 문서 로딩
/// - 본문 전체를 "플레인 텍스트"로 편집 후 저장
///   (문서 제목 변경은 Drive API가 필요하므로 여기서는 생성 시 제목만 사용)
class GoogleDocsDocBottomSheet extends StatefulWidget {
  const GoogleDocsDocBottomSheet({super.key});

  @override
  State<GoogleDocsDocBottomSheet> createState() => _GoogleDocsDocBottomSheetState();
}

class _GoogleDocsDocBottomSheetState extends State<GoogleDocsDocBottomSheet> {
  static const _prefsDocIdKey = 'dev_google_docs_document_id';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  final _docIdCtrl = TextEditingController();
  final _newTitleCtrl = TextEditingController(text: 'Dev Document');
  final _editorCtrl = TextEditingController();

  bool _busy = false;
  String? _lastMessage;

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

  Future<gdocs.DocsApi> _getDocsApi() async {
    final json = await rootBundle.loadString(_serviceAccountPath);
    final creds = ServiceAccountCredentials.fromJson(json);
    const scopes = [gdocs.DocsApi.documentsScope]; // https://www.googleapis.com/auth/documents
    final client = await clientViaServiceAccount(creds, scopes);
    return gdocs.DocsApi(client);
  }

  /// 새 빈 문서 생성 (본문엔 빈 줄 1개 기본 생성됨)
  Future<void> _createNewDocument() async {
    try {
      setState(() => _busy = true);
      final api = await _getDocsApi();
      final title = '${_newTitleCtrl.text.trim()} - ${DateTime.now().toIso8601String().substring(0, 19)}';

      final created = await api.documents.create(gdocs.Document(title: title));
      final docId = created.documentId ?? '';
      if (docId.isEmpty) {
        throw Exception('문서 ID를 가져오지 못했습니다.');
      }

      setState(() {
        _docIdCtrl.text = docId;
        _editorCtrl.text = ''; // 에디터는 비워둠
        _lastMessage = '새 문서를 생성했습니다: $title';
      });
      await _savePrefs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 구글 독스 문서를 생성했습니다.')),
      );
    } catch (e) {
      setState(() => _lastMessage = '생성 실패: $e');
      // 🔎 디버깅 프린트
      debugPrint('[GoogleDocs] _createNewDocument() 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  /// 문서 불러오기: 본문을 플레인 텍스트로 평탄화
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
        _lastMessage = '로딩 완료: 길이 ${text.length.toString()}자';
      });
      await _savePrefs();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('문서를 불러왔습니다.')));
    } catch (e, st) {
      setState(() => _lastMessage = '로딩 실패: $e');
      // 🔎 디버깅 프린트(에러 + 스택)
      debugPrint('[GoogleDocs] _loadDocument() 실패: $e');
      debugPrint('[GoogleDocs] _loadDocument() stack:\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로딩 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 문서 저장: 기존 본문 삭제 후 index=1 위치에 전체 텍스트 삽입
  Future<void> _saveDocument() async {
    try {
      setState(() => _busy = true);
      final id = _docIdCtrl.text.trim();
      if (id.isEmpty) throw Exception('문서 ID를 입력해주세요.');

      final api = await _getDocsApi();

      // 현재 문서 길이를 알아내기 위해 get
      final doc = await api.documents.get(id);
      final endIndex = _getDocumentEndIndex(doc); // 최소 1 이상
      // Docs API는 마지막 "세그먼트 끝 개행"은 삭제 범위에 포함할 수 없음 → -1
      final deleteEnd = (endIndex - 1).clamp(1, endIndex);
      debugPrint('[GoogleDocs] save: endIndex=$endIndex, deleteEnd=$deleteEnd');

      final newText = _ensureTrailingNewline(_editorCtrl.text);

      final requests = <gdocs.Request>[];

      // 기존 본문 삭제 (본문은 index 1부터 시작, 끝 개행 제외)
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('문서를 저장했습니다.')));
    } catch (e, st) {
      setState(() => _lastMessage = '저장 실패: $e');
      // 🔎 디버깅 프린트(에러 + 스택)
      debugPrint('[GoogleDocs] _saveDocument() 실패: $e');
      debugPrint('[GoogleDocs] _saveDocument() stack:\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== Helpers =====

  /// 본문(Body) 끝 인덱스 계산
  int _getDocumentEndIndex(gdocs.Document doc) {
    final contents = doc.body?.content ?? const <gdocs.StructuralElement>[];
    int maxEnd = 1;
    for (final el in contents) {
      final ei = el.endIndex ?? 1;
      if (ei > maxEnd) maxEnd = ei;
    }
    return maxEnd;
  }

  /// 텍스트 평탄화: Paragraph/TextRun의 content를 이어붙임 + 표는 탭/개행 직렬화
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
    _newTitleCtrl.dispose();
    _editorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 헤더 바
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.black.withOpacity(0.06), width: 1),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.description_rounded),
              const SizedBox(width: 8),
              const Text('구글 독스 · 문서 편집', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // 컨트롤 패널
                Card(
                  elevation: 0,
                  color: Colors.white,
                  surfaceTintColor: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // 1) ID/제목 입력 행
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _docIdCtrl,
                                decoration: const InputDecoration(
                                  labelText: '문서 ID',
                                  hintText: '1A2B3C... (문서 URL의 /d/ 와 /edit 사이)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _newTitleCtrl,
                                decoration: const InputDecoration(
                                  labelText: '새 문서 제목',
                                  hintText: '새 문서 생성 시 사용',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 2) 버튼 모음 + 상태 메시지 (Wrap으로 줄바꿈 허용)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('새 빈 문서'),
                                  onPressed: _busy ? null : _createNewDocument,
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
                              _lastMessage ?? '서비스계정에 문서 편집 권한이 있어야 저장됩니다.',
                              style: TextStyle(color: Colors.black.withOpacity(0.6), fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // 플레인 텍스트 에디터
                Card(
                  elevation: 0,
                  color: Colors.white,
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    height: 460,
                    child: TextField(
                      controller: _editorCtrl,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '여기에 문서 본문을 입력하거나, 불러온 텍스트를 편집하세요.',
                        alignLabelWithHint: true,
                      ),
                      style: const TextStyle(fontSize: 14, height: 1.4),
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
