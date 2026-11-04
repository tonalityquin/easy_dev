import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

class FirebaseActivityJournalExport {
  const FirebaseActivityJournalExport({
    required this.lines,
    required this.totalLines,
    required this.sessionCount,
    required this.droppedEvents,
    required this.droppedFiles,
    required this.writeErrors,
    required this.available,
  });

  final List<String> lines;
  final int totalLines;
  final int sessionCount;
  final int droppedEvents;
  final int droppedFiles;
  final int writeErrors;
  final bool available;
}

class FirebaseActivityJournalFileWindow {
  const FirebaseActivityJournalFileWindow(this.path, this.length, this.session);

  final String path;
  final int length;
  final String session;
}

class FirebaseActivityJournalCursor {
  const FirebaseActivityJournalCursor({
    required this.files,
    required this.index,
    required this.offset,
    required this.service,
    required this.sinceMs,
  });

  final List<FirebaseActivityJournalFileWindow> files;
  final int index;
  final int offset;
  final String? service;
  final int? sinceMs;
}

class FirebaseActivityJournalPage {
  const FirebaseActivityJournalPage({
    required this.lines,
    required this.startCursor,
    required this.nextCursor,
    required this.sessionCount,
    required this.droppedEvents,
    required this.droppedFiles,
    required this.writeErrors,
    required this.available,
  });

  final List<String> lines;
  final FirebaseActivityJournalCursor? startCursor;
  final FirebaseActivityJournalCursor? nextCursor;
  final int sessionCount;
  final int droppedEvents;
  final int droppedFiles;
  final int writeErrors;
  final bool available;

  bool get hasMore => nextCursor != null;
}

class FirebaseActivityJournalCost {
  const FirebaseActivityJournalCost({
    required this.sessionCount,
    required this.totalEvents,
    required this.legacyEvents,
    required this.read,
    required this.write,
    required this.delete,
    required this.snap,
    required this.listenStarts,
    required this.listenCancels,
    required this.storage,
    required this.aggregation,
    required this.transaction,
    required this.batch,
    required this.errors,
    required this.uploadBytes,
    required this.downloadBytes,
    required this.resultDocuments,
    required this.cacheResults,
    required this.serverResults,
    required this.committedWrites,
    required this.committedDeletes,
    required this.droppedEvents,
    required this.droppedFiles,
    required this.writeErrors,
    required this.available,
  });

  final int sessionCount;
  final int totalEvents;
  final int legacyEvents;
  final int read;
  final int write;
  final int delete;
  final int snap;
  final int listenStarts;
  final int listenCancels;
  final int storage;
  final int aggregation;
  final int transaction;
  final int batch;
  final int errors;
  final int uploadBytes;
  final int downloadBytes;
  final int resultDocuments;
  final int cacheResults;
  final int serverResults;
  final int committedWrites;
  final int committedDeletes;
  final int droppedEvents;
  final int droppedFiles;
  final int writeErrors;
  final bool available;

  bool get incomplete => legacyEvents > 0 || droppedEvents > 0 ||
      droppedFiles > 0 || writeErrors > 0 || !available;
}

class _JournalReverseLine {
  const _JournalReverseLine(this.value, this.startOffset);

  final String value;
  final int startOffset;
}

class FirebaseActivityJournal {
  FirebaseActivityJournal(this.sessionId);

  static const int maxPendingEvents = 4096;
  static const int maxStorageBytes = 20 * 1024 * 1024;
  static const int maxSegmentBytes = 2 * 1024 * 1024;
  static const Duration retention = Duration(days: 7);

  final String sessionId;
  final Queue<String> _pending = Queue<String>();
  Directory? _directory;
  Future<void>? _initializing;
  Future<void>? _draining;
  Timer? _retryTimer;
  int _retryCount = 0;
  int _part = 0;
  int _segmentBytes = 0;
  int _writtenSinceCleanup = 0;
  int _inFlightCount = 0;
  int droppedEvents = 0;
  int droppedFiles = 0;
  int writeErrors = 0;
  final List<String> previousUncleanSessions = <String>[];
  final List<String> previousUnknownSessions = <String>[];
  bool _available = false;

  bool get available => _available;
  int get pendingEvents => _pending.length;
  int get retryCount => _retryCount;
  String get state => _available ? 'READY' :
      _retryTimer != null ? 'RETRYING' :
      _initializing != null ? 'INITIALIZING' : 'DEGRADED';

  void append({
    required DateTime time,
    required String eventId,
    required String eventSessionId,
    required String service,
    required String operation,
    required String result,
    required String line,
    int? documents,
    int? bytes,
    bool? fromCache,
    int committedWrites = 0,
    int committedDeletes = 0,
  }) {
    final encoded = jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'timeMs': time.millisecondsSinceEpoch,
      'eventId': eventId,
      'sessionId': eventSessionId,
      'service': service,
      'operation': operation,
      'result': result,
      'documents': documents,
      'bytes': bytes,
      'fromCache': fromCache,
      'committedWrites': committedWrites,
      'committedDeletes': committedDeletes,
      'line': line,
    });
    if (_pending.length >= maxPendingEvents) {
      if (_inFlightCount >= _pending.length) {
        droppedEvents++;
        return;
      }
      if (_inFlightCount == 0) {
        _pending.removeFirst();
      } else {
        final retained = _pending.toList();
        retained.removeAt(_inFlightCount);
        _pending
          ..clear()
          ..addAll(retained);
      }
      droppedEvents++;
    }
    _pending.addLast('$encoded\n');
    if (_available) {
      _scheduleDrain();
    } else if (_initializing == null) {
      _scheduleRetry();
    }
  }

  Future<void> initialize() {
    if (_available) return Future<void>.value();
    final ongoing = _initializing;
    if (ongoing != null) return ongoing;
    final running = _initialize();
    _initializing = running;
    unawaited(running.whenComplete(() => _initializing = null));
    return running;
  }

  Future<void> _initialize() async {
    try {
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}${Platform.pathSeparator}firebase_activity');
      await directory.create(recursive: true);
      _directory = directory;
      final segments = await _segments();
      _part = 0;
      _segmentBytes = 0;
      final lastParts = <String, File>{};
      for (final file in segments) {
        final fileSession = _sessionOf(file);
        if (fileSession == sessionId) {
          final part = _partOf(file);
          if (part >= _part) {
            _part = part;
            _segmentBytes = await file.length();
          }
        } else {
          lastParts[fileSession] = file;
        }
      }
      previousUncleanSessions.clear();
      previousUnknownSessions.clear();
      final previousEntries = lastParts.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));
      for (final entry in previousEntries.take(1)) {
        try {
          String? lastOperation;
          await for (final raw in entry.value.openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            try {
              final item = jsonDecode(raw);
              if (item is Map<String, dynamic>) {
                final operation = (item['operation'] ?? '').toString();
                if (operation == 'SESSION_EXIT_REQUESTED' ||
                    operation == 'SESSION_RESTART_REQUESTED' ||
                    operation == 'SESSION_EXIT_PREPARED' ||
                    operation == 'SESSION_RESTART_PREPARED' ||
                    operation == 'SESSION_EXIT_FAILED' ||
                    operation == 'SESSION_RESTART_FAILED' ||
                    operation == 'SESSION_END') {
                  lastOperation = operation;
                }
              }
            } catch (_) {
              writeErrors++;
            }
          }
          if (lastOperation == 'SESSION_EXIT_PREPARED' ||
              lastOperation == 'SESSION_RESTART_PREPARED' ||
              lastOperation == 'SESSION_END') {
            previousUnknownSessions.add(entry.key);
          } else {
            previousUncleanSessions.add(entry.key);
          }
        } catch (_) {
          writeErrors++;
          previousUncleanSessions.add(entry.key);
        }
      }
      await _repairLastSegment();
      await _reconcilePending();
      _available = true;
      _retryCount = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      try {
        await _cleanup();
      } catch (_) {
        writeErrors++;
      }
      _scheduleDrain();
    } catch (_) {
      writeErrors++;
      _available = false;
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_available || _retryTimer != null) return;
    final exponent = math.min(_retryCount, 5);
    final seconds = math.min(1 << exponent, 30);
    _retryCount++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(initialize());
    });
  }

  String _sessionOf(File file) => file.uri.pathSegments.last.split('__').first;

  int _partOf(File file) {
    final filename = file.uri.pathSegments.last;
    return int.tryParse(filename.split('__').last.replaceAll('.jsonl', '')) ?? 0;
  }

  File _fileFor(int part) => File(
        '${_directory!.path}${Platform.pathSeparator}${sessionId}__${part.toString().padLeft(5, '0')}.jsonl',
      );

  Future<List<File>> _segments() async {
    final dir = _directory;
    if (dir == null) return <File>[];
    final entries = await dir
        .list(followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<void> _repairLastSegment() async {
    final file = _fileFor(_part);
    if (!await file.exists()) return;
    final reader = await file.open(mode: FileMode.read);
    var safeLength = 0;
    var length = 0;
    try {
      length = await reader.length();
      if (length == 0) return;
      var remaining = length;
      while (remaining > 0) {
        final take = math.min(32768, remaining);
        remaining -= take;
        await reader.setPosition(remaining);
        final chunk = await reader.read(take);
        final lastNewline = chunk.lastIndexOf(10);
        if (lastNewline >= 0) {
          safeLength = remaining + lastNewline + 1;
          break;
        }
      }
    } finally {
      await reader.close();
    }
    if (safeLength < length) {
      final writer = await file.open(mode: FileMode.append);
      try {
        await writer.truncate(safeLength);
        await writer.flush();
      } finally {
        await writer.close();
      }
      writeErrors++;
    }
    _segmentBytes = safeLength;
  }

  Future<void> _reconcilePending() async {
    if (_pending.isEmpty) return;
    final file = _fileFor(_part);
    if (!await file.exists()) return;
    final persisted = <String>{};
    await for (final raw in file.openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      try {
        final record = jsonDecode(raw);
        if (record is Map<String, dynamic> && record['eventId'] is String) {
          persisted.add(record['eventId'] as String);
        }
      } catch (_) {
        writeErrors++;
      }
    }
    while (_pending.isNotEmpty) {
      String? pendingId;
      try {
        final decoded = jsonDecode(_pending.first);
        if (decoded is Map<String, dynamic>) {
          pendingId = decoded['eventId']?.toString();
        }
      } catch (_) {
        break;
      }
      if (pendingId == null || !persisted.contains(pendingId)) break;
      _pending.removeFirst();
    }
  }

  void _scheduleDrain() {
    if (!_available || _draining != null || _pending.isEmpty) return;
    final running = _drain();
    _draining = running;
    unawaited(running.whenComplete(() {
      _draining = null;
      if (_available && _pending.isNotEmpty) _scheduleDrain();
    }));
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && _available) {
      final selected = <String>[];
      var chunkBytes = 0;
      for (final value in _pending) {
        if (selected.length >= 64 || chunkBytes >= 65536) break;
        selected.add(value);
        chunkBytes += utf8.encode(value).length;
      }
      _inFlightCount = selected.length;
      File? file;
      var priorLength = 0;
      try {
        final nextPart = _segmentBytes + chunkBytes > maxSegmentBytes &&
                _segmentBytes > 0
            ? _part + 1
            : _part;
        file = _fileFor(nextPart);
        priorLength = await file.exists() ? await file.length() : 0;
        final handle = await file.open(mode: FileMode.append);
        try {
          await handle.writeString(selected.join());
          await handle.flush();
        } finally {
          await handle.close();
        }
        for (var i = 0; i < selected.length; i++) {
          _pending.removeFirst();
        }
        _inFlightCount = 0;
        _part = nextPart;
        _segmentBytes = priorLength + chunkBytes;
        _writtenSinceCleanup += selected.length;
        if (_writtenSinceCleanup >= 256) {
          _writtenSinceCleanup = 0;
          try {
            await _cleanup();
          } catch (_) {
            writeErrors++;
          }
        }
      } catch (_) {
        _inFlightCount = 0;
        writeErrors++;
        _available = false;
        try {
          if (file != null && await file.exists()) {
            final handle = await file.open(mode: FileMode.append);
            try {
              await handle.truncate(priorLength);
              await handle.flush();
            } finally {
              await handle.close();
            }
          }
        } catch (_) {
          writeErrors++;
        }
        _scheduleRetry();
        break;
      }
    }
  }

  Future<void> flush() async {
    await initialize();
    while (_available && (_draining != null || _pending.isNotEmpty)) {
      _scheduleDrain();
      final running = _draining;
      if (running == null) break;
      await running;
    }
  }

  Future<void> _cleanup() async {
    final files = await _segments();
    if (files.isEmpty) return;
    final cutoff = DateTime.now().subtract(retention);
    var totalBytes = 0;
    final kept = <File>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        if (stat.modified.isBefore(cutoff) && _sessionOf(file) != sessionId) {
          await file.delete();
          droppedFiles++;
          continue;
        }
        totalBytes += stat.size;
        kept.add(file);
      } catch (_) {
        writeErrors++;
      }
    }
    for (final file in kept) {
      if (totalBytes <= maxStorageBytes) break;
      if (file.path == _fileFor(_part).path) continue;
      try {
        final bytes = await file.length();
        await file.delete();
        totalBytes -= bytes;
        droppedFiles++;
      } catch (_) {
        writeErrors++;
      }
    }
  }

  Future<List<String>> sessions() async {
    await flush();
    final files = await _segments();
    final ids = files.map(_sessionOf).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    if (!ids.contains(sessionId)) ids.insert(0, sessionId);
    return ids;
  }

  bool _matches(Map<String, dynamic> item, String? service, int? sinceMs) {
    final timeMs = (item['timeMs'] as num?)?.toInt();
    if (sinceMs != null && (timeMs == null || timeMs < sinceMs)) {
      return false;
    }
    final itemService = (item['service'] ?? '').toString();
    final operation = (item['operation'] ?? '').toString();
    if (service == null || service == 'all' || service == 'cost') return true;
    return itemService == service ||
        (service == 'realtime' &&
            (operation.startsWith('LISTEN') || operation == 'SNAP'));
  }

  Future<List<FirebaseActivityJournalFileWindow>> _windows({
    String? requestedSessionId,
    bool allSessions = false,
  }) async {
    await flush();
    final files = await _segments();
    final result = <FirebaseActivityJournalFileWindow>[];
    for (final file in files) {
      final fileSession = _sessionOf(file);
      if (!allSessions && fileSession != (requestedSessionId ?? sessionId)) {
        continue;
      }
      try {
        result.add(FirebaseActivityJournalFileWindow(
            file.path, await file.length(), fileSession));
      } catch (_) {
        writeErrors++;
      }
    }
    return result;
  }

  Stream<_JournalReverseLine> _reverseLines(File file, int endOffset) async* {
    final handle = await file.open(mode: FileMode.read);
    try {
      var remaining = math.min(endOffset, await handle.length());
      var suffix = <int>[];
      while (remaining > 0) {
        final take = math.min(32768, remaining);
        remaining -= take;
        await handle.setPosition(remaining);
        final bytes = await handle.read(take);
        final joined = <int>[...bytes, ...suffix];
        var end = joined.length;
        for (var index = joined.length - 1; index >= 0; index--) {
          if (joined[index] != 10) continue;
          if (index + 1 < end) {
            final value = utf8.decode(joined.sublist(index + 1, end),
                allowMalformed: true);
            yield _JournalReverseLine(value, remaining + index + 1);
          }
          end = index;
        }
        suffix = joined.sublist(0, end);
      }
      if (suffix.isNotEmpty) {
        yield _JournalReverseLine(
            utf8.decode(suffix, allowMalformed: true), 0);
      }
    } finally {
      await handle.close();
    }
  }

  Future<FirebaseActivityJournalPage> readPage({
    String? requestedSessionId,
    String? service,
    DateTime? since,
    bool allSessions = false,
    FirebaseActivityJournalCursor? cursor,
    int pageSize = 100,
  }) async {
    final windows = cursor?.files ?? await _windows(
      requestedSessionId: requestedSessionId,
      allSessions: allSessions,
    );
    final requestedService = cursor?.service ?? service;
    final sinceMs = cursor?.sinceMs ?? since?.millisecondsSinceEpoch;
    final sessionCount = windows.map((entry) => entry.session).toSet().length;
    final visible = <String>[];
    FirebaseActivityJournalCursor? nextCursor;
    final size = pageSize.clamp(1, 500).toInt();
    final startCursor = cursor ?? (windows.isEmpty
        ? null
        : FirebaseActivityJournalCursor(
            files: windows,
            index: windows.length - 1,
            offset: windows.last.length,
            service: requestedService,
            sinceMs: sinceMs,
          ));
    var index = cursor?.index ?? windows.length - 1;
    while (index >= 0) {
      final window = windows[index];
      final offset = cursor != null && index == cursor.index
          ? cursor.offset
          : window.length;
      try {
        await for (final row in _reverseLines(File(window.path), offset)) {
          Map<String, dynamic> item;
          try {
            final decoded = jsonDecode(row.value);
            if (decoded is! Map<String, dynamic>) continue;
            item = decoded;
          } catch (_) {
            writeErrors++;
            continue;
          }
          if (!_matches(item, requestedService, sinceMs)) continue;
          final value = item['line'];
          if (value is! String) continue;
          if (visible.length >= size) {
            return FirebaseActivityJournalPage(
              lines: visible,
              startCursor: startCursor,
              nextCursor: nextCursor,
              sessionCount: sessionCount,
              droppedEvents: droppedEvents,
              droppedFiles: droppedFiles,
              writeErrors: writeErrors,
              available: _available,
            );
          }
          visible.add(value);
          nextCursor = FirebaseActivityJournalCursor(
            files: windows,
            index: index,
            offset: row.startOffset,
            service: requestedService,
            sinceMs: sinceMs,
          );
        }
      } catch (_) {
        writeErrors++;
      }
      index--;
    }
    return FirebaseActivityJournalPage(
      lines: visible,
      startCursor: startCursor,
      nextCursor: null,
      sessionCount: sessionCount,
      droppedEvents: droppedEvents,
      droppedFiles: droppedFiles,
      writeErrors: writeErrors,
      available: _available,
    );
  }

  Future<FirebaseActivityJournalCost> readCost({
    String? requestedSessionId,
    DateTime? since,
    bool allSessions = false,
  }) async {
    final windows = await _windows(
      requestedSessionId: requestedSessionId,
      allSessions: allSessions,
    );
    var totalEvents = 0;
    var legacyEvents = 0;
    var read = 0;
    var write = 0;
    var delete = 0;
    var snap = 0;
    var listenStarts = 0;
    var listenCancels = 0;
    var storage = 0;
    var aggregation = 0;
    var transaction = 0;
    var batch = 0;
    var errors = 0;
    var uploadBytes = 0;
    var downloadBytes = 0;
    var resultDocuments = 0;
    var cacheResults = 0;
    var serverResults = 0;
    var committedWrites = 0;
    var committedDeletes = 0;
    final sinceMs = since?.millisecondsSinceEpoch;
    for (final window in windows) {
      try {
        await for (final raw in File(window.path).openRead(0, window.length)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is! Map<String, dynamic>) continue;
            if (!_matches(decoded, null, sinceMs)) continue;
            totalEvents++;
            if ((decoded['schemaVersion'] as num?)?.toInt() != 2) {
              legacyEvents++;
            }
            final operation = (decoded['operation'] ?? '').toString();
            final service = (decoded['service'] ?? '').toString();
            final result = (decoded['result'] ?? '').toString();
            if (result != 'success') {
              if (result == 'error') errors++;
              continue;
            }
            if (operation == 'GET' || operation == 'QUERY') read++;
            if (operation == 'SET' || operation == 'CREATE' ||
                operation == 'UPDATE') write++;
            if (operation == 'DELETE') delete++;
            if (operation == 'SNAP') snap++;
            if (operation == 'LISTEN_START') listenStarts++;
            if (operation == 'LISTEN_CANCEL') listenCancels++;
            if (operation == 'AGGREGATION') aggregation++;
            if (operation == 'TRANSACTION') transaction++;
            if (operation == 'BATCH') batch++;
            if (service == 'storage' && <String>{
              'UPLOAD', 'DOWNLOAD', 'STORAGE_DELETE', 'STORAGE_LIST',
              'METADATA', 'URL_ACCESS',
            }.contains(operation)) {
              storage++;
            }
            final structured = (decoded['schemaVersion'] as num?)?.toInt() == 2;
            if (!structured) continue;
            committedWrites += (decoded['committedWrites'] as num?)?.toInt() ?? 0;
            committedDeletes += (decoded['committedDeletes'] as num?)?.toInt() ?? 0;
            if (service == 'firestore' &&
                (operation == 'GET' || operation == 'QUERY')) {
              resultDocuments += (decoded['documents'] as num?)?.toInt() ?? 0;
              if (decoded['fromCache'] == true) cacheResults++;
              if (decoded['fromCache'] == false) serverResults++;
            }
            final bytes = (decoded['bytes'] as num?)?.toInt() ?? 0;
            if (service == 'storage' && operation == 'UPLOAD') {
              uploadBytes += bytes;
            }
            if (service == 'storage' &&
                (operation == 'DOWNLOAD' || operation == 'URL_ACCESS')) {
              downloadBytes += bytes;
            }
          } catch (_) {
            writeErrors++;
          }
        }
      } catch (_) {
        writeErrors++;
      }
    }
    return FirebaseActivityJournalCost(
      sessionCount: windows.map((w) => w.session).toSet().length,
      totalEvents: totalEvents,
      legacyEvents: legacyEvents,
      read: read,
      write: write + committedWrites,
      delete: delete + committedDeletes,
      snap: snap,
      listenStarts: listenStarts,
      listenCancels: listenCancels,
      storage: storage,
      aggregation: aggregation,
      transaction: transaction,
      batch: batch,
      errors: errors,
      uploadBytes: uploadBytes,
      downloadBytes: downloadBytes,
      resultDocuments: resultDocuments,
      cacheResults: cacheResults,
      serverResults: serverResults,
      committedWrites: committedWrites,
      committedDeletes: committedDeletes,
      droppedEvents: droppedEvents,
      droppedFiles: droppedFiles,
      writeErrors: writeErrors,
      available: _available,
    );
  }

  Future<FirebaseActivityJournalExport> readArchive({
    String? requestedSessionId,
    String? service,
    DateTime? since,
    bool allSessions = false,
  }) async {
    final windows = await _windows(
      requestedSessionId: requestedSessionId,
      allSessions: allSessions,
    );
    final lines = <String>[];
    var totalLines = 0;
    for (final window in windows) {
      try {
        await for (final raw in File(window.path).openRead(0, window.length)
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          try {
            final item = jsonDecode(raw);
            if (item is! Map<String, dynamic>) continue;
            if (!_matches(item, service, since?.millisecondsSinceEpoch)) continue;
            final value = item['line'];
            if (value is! String) continue;
            lines.add(value);
            totalLines++;
          } catch (_) {
            writeErrors++;
          }
        }
      } catch (_) {
        writeErrors++;
      }
    }
    return FirebaseActivityJournalExport(
      lines: lines,
      totalLines: totalLines,
      sessionCount: windows.map((w) => w.session).toSet().length,
      droppedEvents: droppedEvents,
      droppedFiles: droppedFiles,
      writeErrors: writeErrors,
      available: _available,
    );
  }
}
