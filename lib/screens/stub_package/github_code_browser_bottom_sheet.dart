// File: lib/screens/stub_package/github_code_browser_bottom_sheet.dart
//
// Read-only GitHub repository browser for code & markdown.
// - Navigate folders (in/out)
// - Open files (renders .md via flutter_markdown, others as read-only text)
// - No editing/commit (view only)
// - 📝 Notes: path-scoped personal memo saved to SharedPreferences

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GithubCodeBrowserBottomSheet extends StatefulWidget {
  const GithubCodeBrowserBottomSheet({
    super.key,
    this.owner,
    this.repo,
    this.defaultBranch,
    this.initialPath,
  });

  final String? owner;
  final String? repo;
  final String? defaultBranch;

  /// Directory or file path. Empty/null means repo root.
  final String? initialPath;

  @override
  State<GithubCodeBrowserBottomSheet> createState() => _GithubCodeBrowserBottomSheetState();
}

class _GithubCodeBrowserBottomSheetState extends State<GithubCodeBrowserBottomSheet> {
  // --- Controllers ---
  final _ownerCtrl = TextEditingController(text: 'tonalityquin');
  final _repoCtrl = TextEditingController(text: 'easy_dev');
  final _branchCtrl = TextEditingController(text: 'main');
  final _pathCtrl = TextEditingController(text: ''); // repo root by default

  // 📝 Notes controller
  final _noteCtrl = TextEditingController();

  // --- Token storage ---
  static const _kTokenKey = 'gh_token';
  final _storage = const FlutterSecureStorage();

  // --- Prefs keys ---
  static const _kOwner = 'code_owner';
  static const _kRepo = 'code_repo';
  static const _kBranch = 'code_branch';
  static const _kPath = 'code_path';

  // --- View state ---
  bool _loading = false;
  bool _tokenSaved = false;

  // Directory listing or file content
  List<_Entry>? _dirEntries; // non-null => directory view
  String? _fileContent; // non-null => file view
  String? _filePath; // full path for opened file (for web open)
  bool get _isFileView => _fileContent != null;

  bool _isMarkdownPath(String path) => path.toLowerCase().endsWith('.md') || path.toLowerCase().endsWith('.markdown');

  @override
  void initState() {
    super.initState();
    _restorePrefs().then((_) => _checkTokenSaved());
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _branchCtrl.dispose();
    _pathCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _ownerCtrl.text = widget.owner ?? p.getString(_kOwner) ?? _ownerCtrl.text;
      _repoCtrl.text = widget.repo ?? p.getString(_kRepo) ?? _repoCtrl.text;
      _branchCtrl.text = widget.defaultBranch ?? p.getString(_kBranch) ?? _branchCtrl.text;
      _pathCtrl.text = widget.initialPath ?? p.getString(_kPath) ?? _pathCtrl.text;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOwner, _ownerCtrl.text.trim());
    await p.setString(_kRepo, _repoCtrl.text.trim());
    await p.setString(_kBranch, _branchCtrl.text.trim());
    await p.setString(_kPath, _pathCtrl.text.trim());
  }

  Future<void> _checkTokenSaved() async {
    final t = await _storage.read(key: _kTokenKey);
    if (!mounted) return;
    setState(() => _tokenSaved = (t != null && t.isNotEmpty));
  }

  Future<String?> _readToken() => _storage.read(key: _kTokenKey);

  Future<void> _setTokenDialog() async {
    final tokenCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GitHub Personal Access Token'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: tokenCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token',
              hintText: 'ghp_xxx (fine-grained 권장)',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '토큰을 입력하세요' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await _storage.write(key: _kTokenKey, value: tokenCtrl.text.trim());
              if (!mounted) return;
              Navigator.pop(ctx);
              setState(() => _tokenSaved = true);
              _toast('토큰이 저장되었습니다.');
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------- Notes helpers --------------------

  String _contextPath() => _isFileView ? (_filePath ?? _pathCtrl.text.trim()) : _pathCtrl.text.trim();

  String _noteKeyFor(String owner, String repo, String branch, String path) => 'code_note|$owner|$repo|$branch|$path';

  Future<void> _loadNoteForContext() async {
    final p = await SharedPreferences.getInstance();
    final key = _noteKeyFor(
      _ownerCtrl.text.trim(),
      _repoCtrl.text.trim(),
      _branchCtrl.text.trim(),
      _contextPath(),
    );
    setState(() {
      _noteCtrl.text = p.getString(key) ?? '';
    });
  }

  Future<void> _saveNoteForContext() async {
    final p = await SharedPreferences.getInstance();
    final key = _noteKeyFor(
      _ownerCtrl.text.trim(),
      _repoCtrl.text.trim(),
      _branchCtrl.text.trim(),
      _contextPath(),
    );
    final txt = _noteCtrl.text;
    if (txt.trim().isEmpty) {
      await p.remove(key);
      _toast('빈 메모는 삭제되었습니다.');
    } else {
      await p.setString(key, txt);
      _toast('메모를 저장했습니다.');
    }
  }

  Future<void> _clearNoteForContext() async {
    final p = await SharedPreferences.getInstance();
    final key = _noteKeyFor(
      _ownerCtrl.text.trim(),
      _repoCtrl.text.trim(),
      _branchCtrl.text.trim(),
      _contextPath(),
    );
    await p.remove(key);
    setState(() => _noteCtrl.clear());
    _toast('메모를 비웠습니다.');
  }

  // -------------------- GitHub API helpers --------------------

  Uri _contentUri({
    required String owner,
    required String repo,
    required String path, // '' => repo root
    required String branch,
  }) {
    final seg = path.isEmpty ? 'contents' : 'contents/$path';
    return Uri.parse('https://api.github.com/repos/$owner/$repo/$seg?ref=$branch');
  }

  String _githubWebUrl({
    required String owner,
    required String repo,
    required String branch,
    required String path,
    required bool isDir,
  }) {
    if (path.isEmpty && isDir) {
      return 'https://github.com/$owner/$repo/tree/$branch';
    }
    final kind = isDir ? 'tree' : 'blob';
    return 'https://github.com/$owner/$repo/$kind/$branch/$path';
  }

  Future<void> _loadPath() async {
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final path = _pathCtrl.text.trim();

    if ([owner, repo, branch].any((e) => e.isEmpty)) {
      _toast('owner / repo / branch를 입력하세요.');
      return;
    }

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _toast('저장된 GitHub 토큰이 없습니다. 상단 🔑 아이콘으로 설정하세요.');
      return;
    }

    await _savePrefs();

    setState(() {
      _loading = true;
      _dirEntries = null;
      _fileContent = null;
      _filePath = null;
    });

    try {
      final res = await http.get(
        _contentUri(owner: owner, repo: repo, path: path, branch: branch),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);

        if (body is List) {
          final entries = <_Entry>[];
          for (final item in body) {
            if (item is Map<String, dynamic>) {
              entries.add(_Entry(
                name: (item['name'] as String?) ?? '',
                path: (item['path'] as String?) ?? '',
                type: (item['type'] as String?) ?? 'file',
                sha: (item['sha'] as String?) ?? '',
                size: item['size'] is int ? item['size'] as int : null,
              ));
            }
          }
          entries.sort((a, b) {
            if (a.type != b.type) return a.type == 'dir' ? -1 : 1; // dirs first
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          setState(() {
            _dirEntries = entries;
            _fileContent = null;
            _filePath = null;
          });
          await _loadNoteForContext(); // ⬅️ context note
        } else if (body is Map<String, dynamic>) {
          final encoding = (body['encoding'] as String?) ?? 'base64';
          final b64 = (body['content'] as String?)?.replaceAll('\n', '') ?? '';
          if (encoding != 'base64') throw Exception('Unsupported encoding: $encoding');
          final decoded = utf8.decode(base64.decode(b64));
          setState(() {
            _fileContent = decoded;
            _filePath = body['path'] as String? ?? path;
            _dirEntries = null;
          });
          await _loadNoteForContext(); // ⬅️ context note
        } else {
          _toast('알 수 없는 응답 형식입니다.');
        }
      } else if (res.statusCode == 404) {
        _toast('경로를 찾을 수 없습니다 (404).');
      } else if (res.statusCode == 401) {
        _toast('인증 실패(401). 토큰을 확인하세요.');
      } else {
        _toast('로드 실패: ${res.statusCode} ${res.reasonPhrase}');
      }
    } catch (e) {
      _toast('로드 중 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enterDir(String fullPath) async {
    _pathCtrl.text = fullPath;
    await _loadPath();
  }

  Future<void> _goUp() async {
    final p = _pathCtrl.text.trim();
    if (p.isEmpty) return;
    final idx = p.lastIndexOf('/');
    _pathCtrl.text = idx <= 0 ? '' : p.substring(0, idx);
    await _loadPath();
  }

  Future<void> _openFile(String fullPath) async {
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _toast('토큰이 필요합니다.');
      return;
    }

    setState(() {
      _loading = true;
      _fileContent = null;
      _filePath = null;
    });

    try {
      final res = await http.get(
        _contentUri(owner: owner, repo: repo, path: fullPath, branch: branch),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );

      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        final encoding = (body['encoding'] as String?) ?? 'base64';
        final b64 = (body['content'] as String?)?.replaceAll('\n', '') ?? '';
        if (encoding != 'base64') throw Exception('Unsupported encoding: $encoding');
        final decoded = utf8.decode(base64.decode(b64));
        setState(() {
          _fileContent = decoded;
          _filePath = fullPath;
          _dirEntries = null;
        });
        await _loadNoteForContext(); // ⬅️ context note
      } else {
        _toast('파일 열기 실패: ${res.statusCode} ${res.reasonPhrase}');
      }
    } catch (e) {
      _toast('파일 열기 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOnGithub() async {
    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final path = _isFileView ? (_filePath ?? _pathCtrl.text.trim()) : _pathCtrl.text.trim();

    final isDir = !_isFileView;
    final url = _githubWebUrl(
      owner: owner,
      repo: repo,
      branch: branch,
      path: path,
      isDir: isDir,
    );
    if (await canLaunchUrlString(url)) {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } else {
      _toast('브라우저를 열 수 없습니다.');
    }
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  @override
  Widget build(BuildContext context) {
    // 내부 스크롤 박스의 높이(화면 비율 기반, 320~560 범위)
    final h = math.min(560.0, math.max(320.0, MediaQuery.of(context).size.height * 0.5));

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: Colors.white,
          child: DraggableScrollableSheet(
            initialChildSize: 0.92,
            minChildSize: 0.6,
            maxChildSize: 0.98,
            expand: false,
            builder: (context, scrollCtrl) {
              return Stack(
                children: [
                  ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),

                      // Header (responsive)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: LayoutBuilder(
                          builder: (context, cons) {
                            final leading = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 18),
                                const SizedBox(width: 8),
                                const Text('GitHub Code Browser',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 10),
                                _tokenSaved
                                    ? const _TokenChip(label: 'Token: saved')
                                    : const _TokenChip(label: 'Token: not set', error: true),
                              ],
                            );

                            IconButton _btn({
                              required IconData icon,
                              required VoidCallback onPressed,
                              String? tooltip,
                            }) {
                              return IconButton(
                                tooltip: tooltip,
                                onPressed: onPressed,
                                icon: Icon(icon),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                visualDensity: VisualDensity.compact,
                              );
                            }

                            final trailing = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _btn(icon: Icons.open_in_new_rounded, onPressed: _openOnGithub, tooltip: '브라우저로 보기'),
                                _btn(icon: Icons.vpn_key_rounded, onPressed: _setTokenDialog, tooltip: '토큰 설정'),
                                _btn(icon: Icons.close_rounded, onPressed: () => Navigator.pop(context), tooltip: '닫기'),
                              ],
                            );

                            if (cons.maxWidth < 440) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [leading, const SizedBox(height: 8), trailing],
                              );
                            }
                            return Row(children: [leading, const Spacer(), trailing]);
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Owner / Repo
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ownerCtrl,
                              decoration: _dec('Owner', hint: '예: tonalityquin'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _repoCtrl,
                              decoration: _dec('Repo', hint: '예: easy_dev'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Branch / Path (+ Up button)
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _branchCtrl,
                              decoration: _dec('Branch', hint: '예: main'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _pathCtrl,
                              decoration: _dec('Path', hint: '예: (비우면 루트)'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: '상위 폴더',
                            child: IconButton(
                              onPressed: _goUp,
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Actions (read-only)
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _loading ? null : _loadPath,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.folder_open_rounded),
                            label: const Text('열기/목록 불러오기'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isFileView
                                ? () => setState(() {
                                      _fileContent = null;
                                      _filePath = null;
                                      _loadPath();
                                    })
                                : null,
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('목록으로'),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Main area — 내부 전용 스크롤 박스
                      SizedBox(
                        height: h, // 고정 높이(내부만 스크롤)
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _isFileView
                                ? _FileViewer(
                                    path: _filePath ?? _pathCtrl.text.trim(),
                                    content: _fileContent!,
                                    isMarkdown: _isMarkdownPath(_filePath ?? ''),
                                  )
                                : _DirectoryView(
                                    entries: _dirEntries,
                                    onOpenDir: _enterDir,
                                    onOpenFile: _openFile,
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 📝 Notes (path-scoped)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('📝 Notes',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    )),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _contextPath().isEmpty ? '(repo root)' : _contextPath(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: _saveNoteForContext,
                                  icon: const Icon(Icons.save_outlined, size: 18),
                                  label: const Text('저장'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _clearNoteForContext,
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  label: const Text('지우기'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 160,
                              child: TextField(
                                controller: _noteCtrl,
                                expands: true,
                                minLines: null,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                decoration: const InputDecoration(
                                  hintText: '이 경로에 대한 메모를 작성하세요…',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: const TextStyle(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),
                      Text(
                        'Tip: 🔑 토큰을 저장한 뒤 "열기/목록 불러오기"로 탐색하세요. '
                        '폴더 클릭 시 진입, 상단 ⬆️ 버튼으로 상위 폴더로 이동합니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                  if (_loading)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(color: Colors.black.withOpacity(0.03)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// -------------------- Widgets & models --------------------

class _TokenChip extends StatelessWidget {
  final String label;
  final bool error;

  const _TokenChip({required this.label, this.error = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = error ? Colors.red.withOpacity(.08) : cs.primaryContainer.withOpacity(.6);
    final fg = error ? Colors.red : cs.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(.25)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _Entry {
  final String name;
  final String path;
  final String type; // 'file' | 'dir' | others
  final String sha;
  final int? size;

  const _Entry({
    required this.name,
    required this.path,
    required this.type,
    required this.sha,
    this.size,
  });
}

class _DirectoryView extends StatelessWidget {
  final List<_Entry>? entries;
  final ValueChanged<String> onOpenDir;
  final ValueChanged<String> onOpenFile;

  const _DirectoryView({
    required this.entries,
    required this.onOpenDir,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    if (entries == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('좌측 상단 입력 후 "열기/목록 불러오기"를 눌러 주세요.'),
        ),
      );
    }
    if (entries!.isEmpty) {
      return const Center(child: Text('이 폴더는 비어 있습니다.'));
    }
    // 내부 스크롤 사용 (부모는 고정 높이)
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      primary: false,
      shrinkWrap: false,
      physics: const ClampingScrollPhysics(),
      itemCount: entries!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries![i];
        final isDir = e.type == 'dir';
        return ListTile(
          leading: Icon(
            isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            color: isDir ? Colors.amber[700] : Colors.blueGrey,
          ),
          title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: isDir ? const Text('폴더') : Text(e.size == null ? '파일' : '파일 · ${e.size} B'),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => isDir ? onOpenDir(e.path) : onOpenFile(e.path),
        );
      },
    );
  }
}

class _FileViewer extends StatefulWidget {
  final String path;
  final String content;
  final bool isMarkdown;

  const _FileViewer({
    required this.path,
    required this.content,
    required this.isMarkdown,
  });

  @override
  State<_FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<_FileViewer> {
  final ScrollController _vCtrl = ScrollController();

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Markdown 미리보기
    if (widget.isMarkdown) {
      return Scrollbar(
        controller: _vCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _vCtrl,
          // ⬅️ Scrollbar와 동일 컨트롤러
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: md.Markdown(
            data: widget.content,
            selectable: true,
            shrinkWrap: true,
            onTapLink: (text, href, title) {
              if (href != null) launchUrlString(href);
            },
          ),
        ),
      );
    }

    // 코드(텍스트) 뷰 — 세로/가로 스크롤
    return Scrollbar(
      controller: _vCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vCtrl,
        // ⬅️ Scrollbar와 동일 컨트롤러
        primary: false,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 800),
            child: SelectableText(
              widget.content,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
