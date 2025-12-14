import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
class GhKeys {
  // Common keys
  static const ghOwner  = 'gh_owner';
  static const ghRepo   = 'gh_repo';
  static const ghBranch = 'gh_branch';
  static const ghPath   = 'gh_path';

  // Markdown-specific (legacy)
  static const mdOwner  = 'md_owner';
  static const mdRepo   = 'md_repo';
  static const mdBranch = 'md_branch';
  static const mdPath   = 'md_path';

  // Code-specific (legacy)
  static const codeOwner  = 'code_owner';
  static const codeRepo   = 'code_repo';
  static const codeBranch = 'code_branch';
  static const codePath   = 'code_path';
}

class GhPrefData {
  final String? owner;
  final String? repo;
  final String? branch;
  final String? path;

  const GhPrefData({this.owner, this.repo, this.branch, this.path});
}

class GhPrefs {
  static String? _readPref(SharedPreferences p, List<String> keys) {
    for (final k in keys) {
      final v = p.getString(k);
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static Future<GhPrefData> restore(SharedPreferences p) async {
    final owner = _readPref(p, [GhKeys.ghOwner, GhKeys.mdOwner, GhKeys.codeOwner]);
    final repo  = _readPref(p, [GhKeys.ghRepo,  GhKeys.mdRepo,  GhKeys.codeRepo ]);
    final branch= _readPref(p, [GhKeys.ghBranch,GhKeys.mdBranch,GhKeys.codeBranch]);
    final path  = _readPref(p, [GhKeys.ghPath,  GhKeys.mdPath,  GhKeys.codePath ]);
    return GhPrefData(owner: owner, repo: repo, branch: branch, path: path);
  }

  static Future<void> save(SharedPreferences p, {
    required String owner, required String repo, required String branch, required String path
  }) async {
    final pairs = <String, String>{
      GhKeys.ghOwner: owner, GhKeys.mdOwner: owner, GhKeys.codeOwner: owner,
      GhKeys.ghRepo: repo,   GhKeys.mdRepo: repo,   GhKeys.codeRepo: repo,
      GhKeys.ghBranch: branch, GhKeys.mdBranch: branch, GhKeys.codeBranch: branch,
      GhKeys.ghPath: path,   GhKeys.mdPath: path,   GhKeys.codePath: path,
    };
    for (final e in pairs.entries) {
      await p.setString(e.key, e.value.trim());
    }
  }
}

class GithubTokenStore {
  // Caller may use any token key; default provided for convenience
  static const defaultKey = 'github_token';
  static const _storage = FlutterSecureStorage();
  static const _aOpts = AndroidOptions(encryptedSharedPreferences: true);
  static const _iOpts = IOSOptions(accessibility: KeychainAccessibility.first_unlock);

  static Future<String?> read({String key = defaultKey}) async {
    try {
      String? t = await _storage.read(key: key, aOptions: _aOpts, iOptions: _iOpts);
      if (t != null && t.isNotEmpty) return t;
      // Legacy fallback (no options)
      t = await _storage.read(key: key);
      return t;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> write(String token, {String key = defaultKey}) async {
    try {
      final v = token.trim();
      await _storage.write(key: key, value: v, aOptions: _aOpts, iOptions: _iOpts);
      // Write legacy too for compatibility
      await _storage.write(key: key, value: v);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete({String key = defaultKey}) async {
    try {
      await _storage.delete(key: key, aOptions: _aOpts, iOptions: _iOpts);
    } finally {
      // Ensure legacy is cleaned up too
      await _storage.delete(key: key);
    }
  }
}

Future<SharedPreferences> ghPrefsInstance() => SharedPreferences.getInstance();
