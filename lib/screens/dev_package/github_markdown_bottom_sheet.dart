// File: lib/screens/stub_package/github_markdown_bottom_sheet.dart
//
// Read/Write GitHub repository browser focused on Markdown.
// - Navigate folders (in/out)
// - Open files (renders .md via flutter_markdown, others as read-only text)
// - ✏️ Edit & Commit (Markdown 파일은 편집 후 GitHub에 커밋 가능)
// - 📝 Notes: path-scoped personal memo saved to SharedPreferences
//
// 리팩터링 포인트:
// - github_common.dart의 GhPrefs / GithubTokenStore 사용 (코드 브라우저와 동일 로직)
// - gh_* 공통 키 기반으로 Owner/Repo/Branch/Path 복원/저장 (md_*, code_* 레거시도 자동 호환)
// - 토큰 저장/읽기/삭제: 플랫폼 옵션 + 레거시 fallback까지 동일 동작
// - ✅ Markdown 파일 편집 + PUT /repos/{owner}/{repo}/contents/{path} 커밋 지원

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'github_common.dart';

class GithubMarkdownBottomSheet extends StatefulWidget {
  const GithubMarkdownBottomSheet({
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
  State<GithubMarkdownBottomSheet> createState() => _GithubMarkdownBottomSheetState();
}

class _GithubMarkdownBottomSheetState extends State<GithubMarkdownBottomSheet> {
  // --- Controllers ---
  final _ownerCtrl = TextEditingController(text: 'tonalityquin');
  final _repoCtrl = TextEditingController(text: 'easy_dev');
  final _branchCtrl = TextEditingController(text: 'main');
  final _pathCtrl = TextEditingController(text: ''); // repo root by default

  // 📝 Notes controller
  final _noteCtrl = TextEditingController();

  // ✏️ Edit controller (Markdown)
  final _editCtrl = TextEditingController();
  bool _editMode = false;

  // --- Token key (공통 저장소에서 사용) ---
  static const _kTokenKey = 'gh_token';

  // --- View state ---
  bool _loading = false;
  bool _tokenSaved = false;

  // Directory listing or file content
  List<_Entry>? _dirEntries; // non-null => directory view
  String? _fileContent; // non-null => file view
  String? _filePath; // full path for opened file (for web open)
  String? _fileSha; // 커밋 시 필요한 현재 파일 sha
  bool get _isFileView => _fileContent != null;

  bool _isMarkdownPath(String path) =>
      path.toLowerCase().endsWith('.md') || path.toLowerCase().endsWith('.markdown');

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
    _editCtrl.dispose();
    super.dispose();
  }

  // -------------------- Prefs: 공통 유틸 사용 --------------------

  Future<void> _restorePrefs() async {
    final p = await ghPrefsInstance();
    final d = await GhPrefs.restore(p);
    setState(() {
      _ownerCtrl.text = widget.owner ?? d.owner ?? _ownerCtrl.text;
      _repoCtrl.text = widget.repo ?? d.repo ?? _repoCtrl.text;
      _branchCtrl.text = widget.defaultBranch ?? d.branch ?? _branchCtrl.text;
      _pathCtrl.text = widget.initialPath ?? d.path ?? _pathCtrl.text;
    });
  }

  Future<void> _savePrefs() async {
    final p = await ghPrefsInstance();
    await GhPrefs.save(
      p,
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
      branch: _branchCtrl.text.trim(),
      path: _pathCtrl.text.trim(),
    );
  }

  // ---------- Token helpers (공통 유틸 사용) ----------

  Future<String?> _readToken() async {
    try {
      return await GithubTokenStore.read(key: _kTokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToken(String token) async {
    await GithubTokenStore.write(token, key: _kTokenKey);
  }

  Future<void> _deleteToken() async {
    await GithubTokenStore.delete(key: _kTokenKey);
  }

  Future<void> _checkTokenSaved() async {
    final t = await _readToken();
    if (!mounted) return;
    setState(() => _tokenSaved = (t != null && t.isNotEmpty));
  }

  Future<void> _setTokenDialog() async {
    final tokenCtrl = TextEditingController(text: await _readToken() ?? '');
    final formKey = GlobalKey<FormState>();
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('GitHub Personal Access Token'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: tokenCtrl,
              obscureText: obscure,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Token',
                hintText: 'ghp_xxx (fine-grained 권장)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: obscure ? '표시' : '숨김',
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setLocal(() => obscure = !obscure),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '토큰을 입력하세요' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _deleteToken();
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                setState(() => _tokenSaved = false);
                _toast('토큰이 삭제되었습니다.');
              },
              child: const Text('삭제'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await _writeToken(tokenCtrl.text);
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                setState(() => _tokenSaved = true);
                _toast('토큰이 저장되었습니다.');
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // -------------------- Notes helpers --------------------

  String _contextPath() =>
      _isFileView ? (_filePath ?? _pathCtrl.text.trim()) : _pathCtrl.text.trim();

  // Markdown 전용 메모 키(prefix만 구분)
  String _noteKeyFor(String owner, String repo, String branch, String path) =>
      'md_note|$owner|$repo|$branch|$path';

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

  Uri _putContentUri({
    required String owner,
    required String repo,
    required String path, // file path
  }) {
    final seg = 'contents/$path';
    return Uri.parse('https://api.github.com/repos/$owner/$repo/$seg');
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

  // -------------------- Load (dir/file) --------------------

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
      _fileSha = null;
      _editMode = false;
      _editCtrl.clear();
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
            _fileSha = null;
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
            _fileSha = body['sha'] as String?;
            _dirEntries = null;
            _editMode = false;
            _editCtrl.text = _isMarkdownPath(_filePath ?? '') ? decoded : '';
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
      _fileSha = null;
      _editMode = false;
      _editCtrl.clear();
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
          _fileSha = body['sha'] as String?;
          _dirEntries = null;
          _editMode = false;
          _editCtrl.text = _isMarkdownPath(fullPath) ? decoded : '';
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

  // -------------------- Edit & Commit (Markdown) --------------------

  Future<String?> _promptCommitMessage() async {
    final msgCtrl = TextEditingController(
      text: 'Update ${_filePath ?? _pathCtrl.text.trim()}',
    );
    String? result;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('커밋 메시지'),
        content: TextField(
          controller: msgCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '예) Update README.md',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              final v = msgCtrl.text.trim();
              if (v.isEmpty) return;
              result = v;
              Navigator.pop(ctx);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _commitEdits() async {
    final path = _filePath;
    if (!_isFileView || path == null || !_isMarkdownPath(path)) {
      _toast('Markdown 파일에서만 커밋할 수 있습니다.');
      return;
    }

    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final token = await _readToken();

    if ([owner, repo, branch].any((e) => e.isEmpty)) {
      _toast('owner / repo / branch를 확인하세요.');
      return;
    }
    if (token == null || token.isEmpty) {
      _toast('저장된 GitHub 토큰이 없습니다. 상단 🔑 아이콘으로 설정하세요.');
      return;
    }

    final message = await _promptCommitMessage();
    if (message == null) return;

    final newContent = _editCtrl.text;
    final b64 = base64.encode(utf8.encode(newContent));

    setState(() => _loading = true);

    try {
      final body = jsonEncode({
        'message': message,
        'content': b64,
        if (_fileSha != null) 'sha': _fileSha, // 기존 파일 업데이트 시 필요
        'branch': branch,
      });

      final res = await http.put(
        _putContentUri(owner: owner, repo: repo, path: path),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: body,
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        // 성공: 응답에 content.sha 갱신됨
        final Map<String, dynamic> resp = jsonDecode(res.body);
        final newSha = (resp['content'] is Map && resp['content']['sha'] is String)
            ? resp['content']['sha'] as String
            : null;

        setState(() {
          _fileContent = newContent;
          _fileSha = newSha ?? _fileSha;
          _editMode = false;
        });
        _toast('커밋 완료되었습니다.');
      } else if (res.statusCode == 409) {
        _toast('충돌(409): 원격이 변경되었습니다. 최신 내용을 불러온 뒤 다시 시도하세요.');
      } else if (res.statusCode == 422) {
        _toast('검증 오류(422): 브랜치/경로/sha를 확인하세요.');
      } else if (res.statusCode == 401) {
        _toast('인증 실패(401): 토큰 권한을 확인하세요.');
      } else if (res.statusCode == 403) {
        _toast('권한 거부(403): 저장소에 쓰기 권한이 없습니다.');
      } else {
        _toast('커밋 실패: ${res.statusCode} ${res.reasonPhrase}');
      }
    } catch (e) {
      _toast('커밋 중 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------- External open --------------------

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

    final isMd = _isMarkdownPath(_filePath ?? '');

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
                                const Icon(Icons.description_rounded, size: 18),
                                const SizedBox(width: 8),
                                const Text('GitHub Markdown Viewer',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(width: 10),
                                _tokenSaved
                                    ? const _TokenChip(label: 'Token: saved')
                                    : const _TokenChip(label: 'Token: not set', error: true),
                              ],
                            );

                            IconButton btn({
                              required IconData icon,
                              required VoidCallback onPressed,
                              String? tooltip,
                            }) {
                              return IconButton(
                                tooltip: tooltip,
                                onPressed: onPressed,
                                icon: Icon(icon),
                                padding: EdgeInsets.zero,
                                constraints:
                                const BoxConstraints.tightFor(width: 40, height: 40),
                                visualDensity: VisualDensity.compact,
                              );
                            }

                            final trailing = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isFileView && isMd && !_loading)
                                  btn(
                                    icon: _editMode
                                        ? Icons.visibility_rounded
                                        : Icons.edit_rounded,
                                    onPressed: () {
                                      setState(() => _editMode = !_editMode);
                                      if (_editMode && _fileContent != null) {
                                        _editCtrl.text = _fileContent!;
                                      }
                                    },
                                    tooltip: _editMode ? '미리보기' : '편집',
                                  ),
                                if (_isFileView && isMd && _editMode && !_loading)
                                  btn(
                                    icon: Icons.save_rounded,
                                    onPressed: _commitEdits,
                                    tooltip: '저장/커밋',
                                  ),
                                btn(
                                    icon: Icons.open_in_new_rounded,
                                    onPressed: _openOnGithub,
                                    tooltip: '브라우저로 보기'),
                                btn(
                                    icon: Icons.vpn_key_rounded,
                                    onPressed: _setTokenDialog,
                                    tooltip: '토큰 설정'),
                                btn(
                                    icon: Icons.close_rounded,
                                    onPressed: () => Navigator.pop(context),
                                    tooltip: '닫기'),
                              ],
                            );

                            if (cons.maxWidth < 560) {
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
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Icon(Icons.folder_open_rounded),
                            label: const Text('열기/목록 불러오기'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isFileView
                                ? () => setState(() {
                              _fileContent = null;
                              _filePath = null;
                              _fileSha = null;
                              _editMode = false;
                              _editCtrl.clear();
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
                                ? (_editMode && isMd
                                ? _MarkdownEditor(
                              controller: _editCtrl,
                              path: _filePath ?? '',
                            )
                                : _FileViewer(
                              path: _filePath ?? _pathCtrl.text.trim(),
                              content: _fileContent!,
                              isMarkdown: isMd,
                            ))
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
                        'Tip: Markdown 파일을 열면 상단 ✏️ 아이콘으로 편집, 디스크 아이콘으로 커밋할 수 있습니다.',
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

class _MarkdownEditor extends StatelessWidget {
  final TextEditingController controller;
  final String path;

  const _MarkdownEditor({required this.controller, required this.path});

  @override
  Widget build(BuildContext context) {
    final hint = 'Editing: $path';
    return TextField(
      controller: controller,
      expands: true,
      minLines: null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.all(12),
      ),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.0,
        height: 1.35,
      ),
    );
  }
}
ㅅㄷㅅㄴ