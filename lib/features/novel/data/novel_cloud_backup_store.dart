import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovelCloudBackupMetadata {
  const NovelCloudBackupMetadata({
    required this.projectId,
    required this.path,
    required this.fingerprint,
    required this.sourceUpdatedAt,
    required this.backedUpAt,
    required this.rawBytes,
    required this.compressedBytes,
  });

  final String projectId;
  final String path;
  final String fingerprint;
  final DateTime sourceUpdatedAt;
  final DateTime backedUpAt;
  final int rawBytes;
  final int compressedBytes;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'path': path,
        'fingerprint': fingerprint,
        'sourceUpdatedAt': sourceUpdatedAt.toIso8601String(),
        'backedUpAt': backedUpAt.toIso8601String(),
        'rawBytes': rawBytes,
        'compressedBytes': compressedBytes,
      };

  factory NovelCloudBackupMetadata.fromJson(Map<String, dynamic> json) {
    return NovelCloudBackupMetadata(
      projectId: (json['projectId'] as String?) ?? '',
      path: (json['path'] as String?) ?? '',
      fingerprint: (json['fingerprint'] as String?) ?? '',
      sourceUpdatedAt: DateTime.tryParse(
            (json['sourceUpdatedAt'] as String?) ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      backedUpAt: DateTime.tryParse((json['backedUpAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      rawBytes: _intValue(json['rawBytes']),
      compressedBytes: _intValue(json['compressedBytes']),
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class NovelCloudBackupResult {
  const NovelCloudBackupResult({
    required this.uploaded,
    required this.metadata,
  });

  final bool uploaded;
  final NovelCloudBackupMetadata metadata;
}

class NovelCloudRestoreResult {
  const NovelCloudRestoreResult({
    required this.project,
    required this.metadata,
    required this.schemaVersion,
  });

  final Map<String, dynamic> project;
  final NovelCloudBackupMetadata metadata;
  final int schemaVersion;
}

class NovelCloudBackupStore {
  NovelCloudBackupStore({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  static const int schemaVersion = 2;
  static const int maxDownloadBytes = 64 * 1024 * 1024;
  static const String _root =
      'note_system_backups/headquarter_default/projects';
  static const String _metadataKeyPrefix =
      'notensystem_cloud_backup_metadata_v2_';

  final FirebaseStorage _storage;

  String pathFor(String projectId) =>
      '$_root/${_safeSegment(projectId)}/current.json.gz';

  Future<NovelCloudBackupMetadata?> localMetadata(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_metadataKeyPrefix$projectId');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final metadata = NovelCloudBackupMetadata.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (metadata.projectId != projectId || metadata.fingerprint.isEmpty) {
        return null;
      }
      return metadata;
    } catch (_) {
      return null;
    }
  }

  Future<NovelCloudBackupResult> backup({
    required String projectId,
    required DateTime sourceUpdatedAt,
    required Map<String, dynamic> project,
    bool force = false,
    void Function(String message)? log,
  }) async {
    final fingerprint = fingerprintProject(project);
    final existing = await localMetadata(projectId);
    if (!force && existing != null && existing.fingerprint == fingerprint) {
      log?.call(
        'cloud_backup_skipped_no_changes projectId=$projectId fingerprint=$fingerprint',
      );
      return NovelCloudBackupResult(uploaded: false, metadata: existing);
    }

    if (force) {
      log?.call('cloud_backup_force_upload projectId=$projectId');
    }
    final backedUpAt = DateTime.now();
    final envelope = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'projectId': projectId,
      'sourceUpdatedAt': sourceUpdatedAt.toIso8601String(),
      'backedUpAt': backedUpAt.toIso8601String(),
      'fingerprint': fingerprint,
      'project': project,
    };
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    final compressed = Uint8List.fromList(gzip.encode(raw));
    final path = pathFor(projectId);
    log?.call(
      'cloud_backup_serialized projectId=$projectId rawBytes=${raw.length} compressedBytes=${compressed.length} fingerprint=$fingerprint',
    );
    log?.call('cloud_backup_upload_started path=$path');

    final metadata = SettableMetadata(
      contentType: 'application/gzip',
      customMetadata: <String, String>{
        'schemaVersion': '$schemaVersion',
        'projectId': projectId,
        'sourceUpdatedAt': sourceUpdatedAt.toIso8601String(),
        'backedUpAt': backedUpAt.toIso8601String(),
        'fingerprint': fingerprint,
        'rawBytes': '${raw.length}',
      },
    );
    await _storage.ref(path).putData(compressed, metadata);

    final resultMetadata = NovelCloudBackupMetadata(
      projectId: projectId,
      path: path,
      fingerprint: fingerprint,
      sourceUpdatedAt: sourceUpdatedAt,
      backedUpAt: backedUpAt,
      rawBytes: raw.length,
      compressedBytes: compressed.length,
    );
    await _saveMetadata(resultMetadata);
    log?.call(
      'cloud_backup_success path=$path rawBytes=${raw.length} compressedBytes=${compressed.length}',
    );
    return NovelCloudBackupResult(
      uploaded: true,
      metadata: resultMetadata,
    );
  }

  Future<NovelCloudRestoreResult> restore({
    required String projectId,
    void Function(String message)? log,
  }) async {
    final path = pathFor(projectId);
    log?.call('cloud_restore_download_started path=$path');
    Uint8List? compressed;
    try {
      compressed = await _storage.ref(path).getData(maxDownloadBytes);
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') {
        throw StateError('클라우드 백업이 없습니다. 먼저 클라우드 백업을 실행하세요.');
      }
      rethrow;
    }
    if (compressed == null || compressed.isEmpty) {
      throw StateError('클라우드 백업 파일이 비어 있습니다.');
    }
    log?.call(
      'cloud_restore_downloaded path=$path compressedBytes=${compressed.length}',
    );

    final raw = Uint8List.fromList(gzip.decode(compressed));
    final decoded = jsonDecode(utf8.decode(raw));
    if (decoded is! Map) {
      throw const FormatException('클라우드 백업 형식이 올바르지 않습니다.');
    }
    final envelope = Map<String, dynamic>.from(decoded);
    final version = _intValue(envelope['schemaVersion']);
    if (version != schemaVersion) {
      throw StateError(
        '지원하지 않는 클라우드 백업 버전입니다. schemaVersion=$version',
      );
    }
    final restoredProjectId = (envelope['projectId'] as String?) ?? '';
    if (restoredProjectId != projectId) {
      throw StateError('클라우드 백업의 프로젝트 식별자가 현재 프로젝트와 다릅니다.');
    }
    if (envelope['project'] is! Map) {
      throw const FormatException('클라우드 백업에 프로젝트 데이터가 없습니다.');
    }

    final project = Map<String, dynamic>.from(envelope['project'] as Map);
    final fingerprint = (envelope['fingerprint'] as String?)?.trim().isNotEmpty ==
            true
        ? (envelope['fingerprint'] as String).trim()
        : fingerprintProject(project);
    final sourceUpdatedAt = DateTime.tryParse(
          (envelope['sourceUpdatedAt'] as String?) ?? '',
        ) ??
        DateTime.now();
    final backedUpAt = DateTime.tryParse(
          (envelope['backedUpAt'] as String?) ?? '',
        ) ??
        DateTime.now();
    final calculatedFingerprint = fingerprintProject(project);
    if (calculatedFingerprint != fingerprint) {
      throw const FormatException('클라우드 백업 무결성 검증에 실패했습니다.');
    }

    final resultMetadata = NovelCloudBackupMetadata(
      projectId: projectId,
      path: path,
      fingerprint: fingerprint,
      sourceUpdatedAt: sourceUpdatedAt,
      backedUpAt: backedUpAt,
      rawBytes: raw.length,
      compressedBytes: compressed.length,
    );
    await _saveMetadata(resultMetadata);
    log?.call(
      'cloud_restore_success projectId=$projectId rawBytes=${raw.length} compressedBytes=${compressed.length} fingerprint=$fingerprint',
    );
    return NovelCloudRestoreResult(
      project: project,
      metadata: resultMetadata,
      schemaVersion: version,
    );
  }

  static String fingerprintProject(Map<String, dynamic> project) {
    final normalized = _normalizeForFingerprint(project, isRoot: true);
    final bytes = utf8.encode(jsonEncode(normalized));
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Future<void> _saveMetadata(NovelCloudBackupMetadata metadata) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_metadataKeyPrefix${metadata.projectId}',
      jsonEncode(metadata.toJson()),
    );
  }

  static dynamic _normalizeForFingerprint(
    dynamic value, {
    required bool isRoot,
  }) {
    if (value is Map) {
      final source = Map<String, dynamic>.from(value);
      final keys = source.keys.toList()..sort();
      final result = <String, dynamic>{};
      for (final key in keys) {
        if (key == 'updatedAt') continue;
        if (isRoot && key == 'activeChapterId') continue;
        result[key] = _normalizeForFingerprint(source[key], isRoot: false);
      }
      return result;
    }
    if (value is List) {
      return value
          .map((item) => _normalizeForFingerprint(item, isRoot: false))
          .toList();
    }
    return value;
  }

  static String _safeSegment(String value) {
    final normalized = value.trim().replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        );
    return normalized.isEmpty ? 'default' : normalized;
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
