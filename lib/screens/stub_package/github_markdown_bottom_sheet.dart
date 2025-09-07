// File: lib/screens/stub_package/github_markdown_bottom_sheet.dart
//
// Bottom sheet for browsing/editing/previewing/committing Markdown (*.md)
// in a GitHub repo via REST API v3.
//
// Requires (pubspec):
//   http, flutter_secure_storage, shared_preferences, url_launcher,
//   flutter_markdown
//
// Usage:
// showModalBottomSheet(
//   context: context,
//   isScrollControlled: true,
//   backgroundColor: Colors.transparent,
//   builder: (_) => const GithubMarkdownBottomSheet(
//     owner: 'tonalityquin',
//     repo: 'side_project',
//     defaultBranch: 'main',   // optional
//     // initialPath: 'README.md', // optional
//   ),
// );

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage, AndroidOptions, IOSOptions, KeychainAccessibility;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';

class GithubMarkdownBottomSheet extends StatefulWidget {
  const GithubMarkdownBottomSheet({
    super.key,
    this.owner,
    this.repo,
    this.defaultBranch,
    this.initialPath,
  });

  /// Optional overrides (take precedence over saved prefs)
  final String? owner;
  final String? repo;
  final String? defaultBranch;
  final String? initialPath;

  @override
  State<GithubMarkdownBottomSheet> createState() => _GithubMarkdownBottomSheetState();
}

class _GithubMarkdownBottomSheetState extends State<GithubMarkdownBottomSheet> {
  // --- Controllers ---
  final _ownerCtrl = TextEditingController(text: 'tonalityquin');
  final _repoCtrl = TextEditingController(text: 'side_project');
  final _branchCtrl = TextEditingController(text: 'main');
  final _pathCtrl = TextEditingController(text: 'README.md');
  final _commitMsgCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  // --- State ---
  String? _currentSha; // required for updates (PUT)
  bool _loading = false;
  bool _saving = false;
  bool _preview = true;
  bool _hasToken = false; // 토큰 저장 여부 표시용

  // secure storage (플랫폼 옵션 명시)
  static const _kTokenKey = 'gh_token';
  final _storage = const FlutterSecureStorage();

  AndroidOptions get _aOpts => const AndroidOptions(
        encryptedSharedPreferences: true,
        // preferencesKey: 'easydev.secure.prefs', // 필요 시 커스텀
      );

  IOSOptions get _iOpts => const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      );

  // prefs keys
  static const _kOwner = 'md_owner';
  static const _kRepo = 'md_repo';
  static const _kBranch = 'md_branch';
  static const _kPath = 'md_path';

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    _refreshTokenStatus();
  }

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _branchCtrl.dispose();
    _pathCtrl.dispose();
    _commitMsgCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      final savedOwner = p.getString(_kOwner);
      final savedRepo = p.getString(_kRepo);
      final savedBranch = p.getString(_kBranch);
      final savedPath = p.getString(_kPath);

      _ownerCtrl.text = widget.owner ?? savedOwner ?? _ownerCtrl.text;
      _repoCtrl.text = widget.repo ?? savedRepo ?? _repoCtrl.text;
      _branchCtrl.text = widget.defaultBranch ?? savedBranch ?? _branchCtrl.text;
      _pathCtrl.text = widget.initialPath ?? savedPath ?? _pathCtrl.text;
    });
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOwner, _ownerCtrl.text.trim());
    await p.setString(_kRepo, _repoCtrl.text.trim());
    await p.setString(_kBranch, _branchCtrl.text.trim());
    await p.setString(_kPath, _pathCtrl.text.trim());
  }

  Future<String?> _readToken() async {
    try {
      return await _storage.read(
        key: _kTokenKey,
        aOptions: _aOpts,
        iOptions: _iOpts,
      );
    } catch (e) {
      _toast('토큰 읽기 오류: $e');
      return null;
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await _storage.write(
        key: _kTokenKey,
        value: token.trim(),
        aOptions: _aOpts,
        iOptions: _iOpts,
      );
    } catch (e) {
      _toast('토큰 저장 오류: $e');
    } finally {
      _refreshTokenStatus();
    }
  }

  Future<void> _deleteToken() async {
    try {
      await _storage.delete(
        key: _kTokenKey,
        aOptions: _aOpts,
        iOptions: _iOpts,
      );
      _toast('토큰이 삭제되었습니다.');
    } catch (e) {
      _toast('토큰 삭제 오류: $e');
    } finally {
      _refreshTokenStatus();
    }
  }

  Future<void> _refreshTokenStatus() async {
    final t = await _readToken();
    if (!mounted) return;
    setState(() => _hasToken = (t != null && t.isNotEmpty));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _isMdPath {
    final path = _pathCtrl.text.trim().toLowerCase();
    return path.endsWith('.md');
  }

  Uri _contentUri({
    required String owner,
    required String repo,
    required String path,
    required String branch,
  }) =>
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/contents/$path?ref=$branch',
      );

  String _githubWebUrl({
    required String owner,
    required String repo,
    required String branch,
    required String path,
  }) =>
      'https://github.com/$owner/$repo/blob/$branch/$path';

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
                hintText: 'ghp_xxx 또는 classic token',
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
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('삭제'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await _writeToken(tokenCtrl.text);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _toast('토큰이 저장되었습니다.');
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadFile() async {
    if (!_isMdPath) {
      _toast('경로가 .md 파일이 아닙니다.');
      return;
    }

    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final path = _pathCtrl.text.trim();

    if (owner.isEmpty || repo.isEmpty || branch.isEmpty || path.isEmpty) {
      _toast('owner, repo, branch, path를 입력하세요.');
      return;
    }

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _toast('저장된 GitHub 토큰이 없습니다. 우측 상단 열쇠 아이콘으로 설정하세요.');
      return;
    }

    await _savePrefs();

    setState(() {
      _loading = true;
      _currentSha = null;
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
        final Map<String, dynamic> body = jsonDecode(res.body);
        final String b64 = (body['content'] as String?)?.replaceAll('\n', '') ?? '';
        final String encoding = (body['encoding'] as String?) ?? 'base64';
        final String sha = (body['sha'] as String?) ?? '';
        if (encoding != 'base64') {
          throw Exception('지원하지 않는 인코딩: $encoding');
        }
        final decoded = utf8.decode(base64.decode(b64));
        setState(() {
          _contentCtrl.text = decoded;
          _currentSha = sha;
        });
        _toast('파일을 불러왔습니다.');
      } else if (res.statusCode == 404) {
        _toast('파일을 찾을 수 없습니다 (404). 경로/브랜치를 확인하세요.');
      } else if (res.statusCode == 401) {
        _toast('인증 실패(401). 토큰을 확인하세요.');
      } else {
        _toast('로드 실패: ${res.statusCode} ${res.reasonPhrase}');
      }
    } catch (e) {
      _toast('로드 중 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveFile() async {
    if (!_isMdPath) {
      _toast('.md 파일만 저장할 수 있습니다.');
      return;
    }

    final owner = _ownerCtrl.text.trim();
    final repo = _repoCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final path = _pathCtrl.text.trim();

    if (owner.isEmpty || repo.isEmpty || branch.isEmpty || path.isEmpty) {
      _toast('owner, repo, branch, path를 입력하세요.');
      return;
    }

    final token = await _readToken();
    if (token == null || token.isEmpty) {
      _toast('저장된 GitHub 토큰이 없습니다. 우측 상단 열쇠 아이콘으로 설정하세요.');
      return;
    }

    final content = _contentCtrl.text;
    final enc = base64.encode(utf8.encode(content));

    setState(() => _saving = true);

    try {
      final payload = <String, dynamic>{
        'message': _commitMsgCtrl.text.trim().isEmpty ? 'Update $path from app' : _commitMsgCtrl.text.trim(),
        'content': enc,
        'branch': branch,
        if (_currentSha != null) 'sha': _currentSha,
        'committer': {
          'name': 'EasyDev App',
          'email': 'noreply@example.com',
        },
      };

      final res = await http.put(
        _contentUri(owner: owner, repo: repo, path: path, branch: branch),
        headers: {
          'Accept': 'application/vnd.github+json',
          'Authorization': 'Bearer $token',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        final Map<String, dynamic>? contentObj = body['content'] is Map<String, dynamic> ? body['content'] : null;
        final newSha = contentObj?['sha'] as String?;
        setState(() {
          _currentSha = newSha ?? _currentSha;
        });
        _toast('커밋 완료 (${res.statusCode}).');
      } else if (res.statusCode == 409) {
        _toast('충돌(409): 최신 내용을 다시 불러온 뒤 저장하세요.');
      } else if (res.statusCode == 422) {
        _toast('유효성 오류(422): 브랜치/경로/권한을 확인하세요.');
      } else {
        _toast('저장 실패: ${res.statusCode} ${res.reasonPhrase}');
      }
    } catch (e) {
      _toast('저장 중 오류: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openOnGithub() async {
    final url = _githubWebUrl(
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
      branch: _branchCtrl.text.trim(),
      path: _pathCtrl.text.trim(),
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
    final cs = Theme.of(context).colorScheme;

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
                      // Handle
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

                      // ▶ 반응형 헤더
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: LayoutBuilder(
                          builder: (context, cons) {
                            final leading = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.description, size: 18),
                                const SizedBox(width: 8),
                                const Text(
                                  'GitHub Markdown',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // ▼ 토큰 상태 Chip
                                Chip(
                                  label: Text(_hasToken ? 'Token: saved' : 'No token'),
                                  avatar: Icon(
                                    _hasToken ? Icons.lock_rounded : Icons.lock_open_rounded,
                                    size: 16,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ],
                            );

                            IconButton _btn({
                              required VoidCallback onPressed,
                              required IconData icon,
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
                                const Text('Preview', style: TextStyle(fontSize: 12)),
                                Switch(
                                  value: _preview,
                                  onChanged: (v) => setState(() => _preview = v),
                                ),
                                _btn(
                                  tooltip: '브라우저로 보기',
                                  onPressed: _openOnGithub,
                                  icon: Icons.open_in_new_rounded,
                                ),
                                _btn(
                                  tooltip: '토큰 설정',
                                  onPressed: () async {
                                    await _setTokenDialog();
                                    if (!mounted) return;
                                    await _refreshTokenStatus();
                                  },
                                  icon: Icons.vpn_key_rounded,
                                ),
                                _btn(
                                  tooltip: '닫기',
                                  onPressed: () => Navigator.pop(context),
                                  icon: Icons.close_rounded,
                                ),
                              ],
                            );

                            if (cons.maxWidth < 420) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  leading,
                                  const SizedBox(height: 8),
                                  trailing,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                leading,
                                const Spacer(),
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: trailing,
                                  ),
                                ),
                              ],
                            );
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
                              decoration: _dec('Repo', hint: '예: side_project'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Branch / Path
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
                              decoration: _dec('Path', hint: '예: README.md'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Actions
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _loading ? null : _loadFile,
                            icon: _loading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.download_rounded),
                            label: const Text('불러오기'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: cs.secondaryContainer,
                              foregroundColor: cs.onSecondaryContainer,
                            ),
                            onPressed: (_saving || !_isMdPath) ? null : _saveFile,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.upload_rounded),
                            label: const Text('저장(커밋)'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _commitMsgCtrl,
                              decoration: _dec('커밋 메시지', hint: 'Update <path> from app'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Editor / Preview
                      Container(
                        height: 420,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _preview
                            ? Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: md.Markdown(
                                  data: _contentCtrl.text,
                                  selectable: true,
                                  shrinkWrap: true,
                                  onTapLink: (text, href, title) {
                                    if (href != null) launchUrlString(href);
                                  },
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: TextField(
                                  controller: _contentCtrl,
                                  expands: true,
                                  minLines: null,
                                  maxLines: null,
                                  keyboardType: TextInputType.multiline,
                                  style: const TextStyle(fontFamily: 'monospace'),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '여기에 Markdown을 입력하거나, 파일을 불러오세요…',
                                  ),
                                ),
                              ),
                      ),

                      const SizedBox(height: 12),
                      Text(
                        'Tip: 우측 상단 🔑 아이콘으로 토큰을 저장하세요. 불러오기 후 저장(커밋) 시에는 최신 sha가 자동 반영됩니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                  // Loading veil (optional subtle)
                  if (_loading || _saving)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          color: Colors.black.withOpacity(0.03),
                        ),
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
