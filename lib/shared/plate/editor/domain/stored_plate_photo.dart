class StoredPlatePhoto {
  StoredPlatePhoto({
    required this.displayUrl,
    required this.displayObjectPath,
    this.thumbnailUrl,
    this.thumbnailObjectPath,
    StoredPlatePhotoMetadata? metadata,
  }) : metadata = metadata ??
            StoredPlatePhotoMetadata.fromObjectPath(displayObjectPath);

  final String displayUrl;
  final String displayObjectPath;
  final String? thumbnailUrl;
  final String? thumbnailObjectPath;
  final StoredPlatePhotoMetadata metadata;

  bool get hasThumbnail =>
      thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty;

  String? get gridThumbnailUrl => hasThumbnail ? thumbnailUrl : null;
}

class StoredPlatePhotoMetadata {
  const StoredPlatePhotoMetadata({
    required this.rawFileName,
    required this.capturedDate,
    required this.capturedTime,
    required this.plateNumber,
    required this.capturedBy,
    this.capturedAt,
  });

  final String rawFileName;
  final String capturedDate;
  final String capturedTime;
  final String plateNumber;
  final String capturedBy;
  final DateTime? capturedAt;

  factory StoredPlatePhotoMetadata.fromObjectPath(
    String objectPath, {
    String fallbackPlateNumber = '',
  }) {
    return StoredPlatePhotoMetadata.fromFileName(
      StoredPlatePhotoCatalog.fileNameOf(objectPath),
      fallbackPlateNumber: fallbackPlateNumber,
    );
  }

  factory StoredPlatePhotoMetadata.fromFileName(
    String fileName, {
    String fallbackPlateNumber = '',
  }) {
    final fallbackPlate = _cleanPlate(fallbackPlateNumber);
    final trimmed = fileName.trim();
    final queryIndex = trimmed.indexOf('?');
    final fragmentIndex = trimmed.indexOf('#');
    var end = trimmed.length;
    if (queryIndex >= 0 && queryIndex < end) end = queryIndex;
    if (fragmentIndex >= 0 && fragmentIndex < end) end = fragmentIndex;
    final source = trimmed.substring(0, end);
    final decoded = _safeDecodeComponent(source);
    final raw = decoded.isEmpty ? source : decoded;
    final normalized = raw.replaceFirst(
      RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false),
      '',
    );

    final first = normalized.indexOf('_');
    final second = first < 0 ? -1 : normalized.indexOf('_', first + 1);
    final third = second < 0 ? -1 : normalized.indexOf('_', second + 1);

    String datePart = '';
    String timePart = '';
    String platePart = '';
    String capturedByPart = '';

    if (first > 0 && second > first && third > second) {
      datePart = normalized.substring(0, first).trim();
      timePart = normalized.substring(first + 1, second).trim();
      platePart = normalized.substring(second + 1, third).trim();
      capturedByPart = normalized.substring(third + 1).trim();
    } else {
      final parts = normalized.split('_').map((part) => part.trim()).toList();
      if (parts.isNotEmpty) datePart = parts[0];
      if (parts.length > 1) timePart = parts[1];
      if (parts.length > 2) platePart = parts[2];
      if (parts.length > 3) capturedByPart = parts.sublist(3).join('_').trim();
    }

    final millis = int.tryParse(timePart);
    DateTime? capturedAt;
    var capturedDate = '';
    var capturedTime = '';
    if (millis != null) {
      try {
        capturedAt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
        capturedDate = _formatDate(capturedAt);
        capturedTime = _formatTime(capturedAt);
      } catch (_) {}
    }
    if (capturedDate.isEmpty) capturedDate = _normalizeDate(datePart);
    if (capturedTime.isEmpty) capturedTime = _normalizeTime(timePart);

    final parsedPlate = _cleanPlate(_safeDecodeComponent(platePart));
    final capturedBy = StoredPlatePhotoFileNameCodec.resolveCapturedBy(
      _safeDecodeComponent(capturedByPart),
    );

    return StoredPlatePhotoMetadata(
      rawFileName: raw,
      capturedDate: capturedDate,
      capturedTime: capturedTime,
      plateNumber: parsedPlate.isEmpty ? fallbackPlate : parsedPlate,
      capturedBy: capturedBy,
      capturedAt: capturedAt,
    );
  }
}

class StoredPlatePhotoFileNameCodec {
  const StoredPlatePhotoFileNameCodec._();

  static String build({
    required DateTime capturedAtUtc,
    required String plateNumber,
    required String capturedBy,
  }) {
    final local = capturedAtUtc.toLocal();
    final date = _formatDate(local);
    final epoch = capturedAtUtc.millisecondsSinceEpoch.toString();
    final plate = _sanitizeFileNameField(
      _cleanPlate(plateNumber),
      fallback: 'unknown',
    );
    final actor = _sanitizeFileNameField(
      resolveCapturedBy(capturedBy),
      fallback: '미확인',
    );
    return '${date}_${epoch}_${plate}_${actor}.jpg';
  }

  static String resolveCapturedBy(String value) {
    final normalized = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return normalized.isEmpty ? '미확인' : normalized;
  }

  static String _sanitizeFileNameField(
    String value, {
    required String fallback,
  }) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/?#%]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? fallback : sanitized;
  }
}

enum StoredPlatePhotoReadMode {
  legacyOnly,
  mixed,
  prefixedOnly,
}

class StoredPlatePhotoCatalog {
  const StoredPlatePhotoCatalog._();

  static const String displayDirectoryName = 'display';
  static const String thumbnailDirectoryName = 'thumbnails';
  static const String prefixedLayoutStartYearMonth = '2026-09';
  static const String legacyCompatibilityEndYearMonth = '2026-09';

  static StoredPlatePhotoReadMode readModeForYearMonth(String yearMonth) {
    final normalized = yearMonth.trim();
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(normalized)) {
      throw FormatException('Invalid yearMonth: $yearMonth');
    }
    if (normalized.compareTo(prefixedLayoutStartYearMonth) < 0) {
      return StoredPlatePhotoReadMode.legacyOnly;
    }
    if (normalized.compareTo(legacyCompatibilityEndYearMonth) <= 0) {
      return StoredPlatePhotoReadMode.mixed;
    }
    return StoredPlatePhotoReadMode.prefixedOnly;
  }

  static String plateDirectoryName(String plateNumber) {
    final compact = _cleanPlate(plateNumber);
    if (compact.isEmpty) return 'unknown';
    return compact.replaceAll(RegExp(r'[\\/]+'), '_');
  }

  static String displayObjectPath({
    required String division,
    required String area,
    required String yearMonth,
    required String plateNumber,
    required String fileName,
  }) {
    final plateDirectory = plateDirectoryName(plateNumber);
    return '$division/$area/images/$yearMonth/$displayDirectoryName/$plateDirectory/$fileName';
  }

  static String displayPrefix({
    required String division,
    required String area,
    required String yearMonth,
    required String plateNumber,
  }) {
    final plateDirectory = plateDirectoryName(plateNumber);
    return '$division/$area/images/$yearMonth/$displayDirectoryName/$plateDirectory/';
  }

  static String thumbnailPrefix({
    required String division,
    required String area,
    required String yearMonth,
    required String plateNumber,
  }) {
    final plateDirectory = plateDirectoryName(plateNumber);
    return '$division/$area/images/$yearMonth/$thumbnailDirectoryName/$plateDirectory/';
  }

  static String legacyDisplayPrefix({
    required String division,
    required String area,
    required String yearMonth,
  }) {
    return '$division/$area/images/$yearMonth/$displayDirectoryName/';
  }

  static String legacyThumbnailPrefix({
    required String division,
    required String area,
    required String yearMonth,
  }) {
    return '$division/$area/images/$yearMonth/$thumbnailDirectoryName/';
  }

  static String legacyRootPrefix({
    required String division,
    required String area,
    required String yearMonth,
  }) {
    return '$division/$area/images/$yearMonth/';
  }

  static String thumbnailObjectPathForDisplay(String displayObjectPath) {
    final normalized = _normalizePath(displayObjectPath);
    if (normalized.isEmpty || isThumbnailObjectPath(normalized)) {
      return normalized;
    }
    final displaySegment = '/$displayDirectoryName/';
    if (normalized.contains(displaySegment)) {
      return normalized.replaceFirst(
        displaySegment,
        '/$thumbnailDirectoryName/',
      );
    }
    final slash = normalized.lastIndexOf('/');
    if (slash < 0) {
      return '$thumbnailDirectoryName/$normalized';
    }
    final directory = normalized.substring(0, slash + 1);
    final fileName = normalized.substring(slash + 1);
    return '$directory$thumbnailDirectoryName/$fileName';
  }

  static String displayObjectPathForThumbnail(String thumbnailObjectPath) {
    final normalized = _normalizePath(thumbnailObjectPath);
    if (normalized.isEmpty || !isThumbnailObjectPath(normalized)) {
      return normalized;
    }
    return normalized.replaceFirst(
      '/$thumbnailDirectoryName/',
      '/$displayDirectoryName/',
    );
  }

  static bool isThumbnailObjectPath(String objectPath) {
    final normalized = _normalizePath(objectPath);
    return normalized.contains('/$thumbnailDirectoryName/');
  }

  static bool isDisplayObjectPath(String objectPath) {
    final normalized = _normalizePath(objectPath);
    return normalized.contains('/$displayDirectoryName/');
  }

  static bool isLegacyDisplayObjectPath(String objectPath) {
    final normalized = _normalizePath(objectPath);
    if (normalized.isEmpty ||
        isDisplayObjectPath(normalized) ||
        isThumbnailObjectPath(normalized)) {
      return false;
    }
    final marker = '/images/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) return false;
    final remainder = normalized.substring(markerIndex + marker.length);
    final segments =
        remainder.split('/').where((part) => part.isNotEmpty).toList();
    return segments.length == 2;
  }

  static bool isDirectChildOfPrefix(String objectPath, String prefix) {
    final normalizedPath = _normalizePath(objectPath);
    final normalizedPrefix = _normalizePath(prefix);
    if (!normalizedPath.startsWith(normalizedPrefix)) return false;
    final remainder = normalizedPath.substring(normalizedPrefix.length);
    return remainder.isNotEmpty && !remainder.contains('/');
  }

  static String fileNameOf(String objectPath) {
    final normalized = _normalizePath(objectPath);
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }

  static String publicUrl(String bucketName, String objectPath) {
    return 'https://storage.googleapis.com/$bucketName/$objectPath';
  }

  static List<StoredPlatePhoto> pairObjectPaths({
    required String bucketName,
    required Iterable<String> objectPaths,
    required String plateNumber,
  }) {
    final newDisplays = <String, String>{};
    final legacyDisplays = <String, String>{};
    final thumbnails = <String, String>{};
    final normalizedPlate = _cleanPlate(plateNumber);

    for (final rawPath in objectPaths) {
      final path = _normalizePath(rawPath.trim());
      if (path.isEmpty || !path.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      final fileMetadata = StoredPlatePhotoMetadata.fromObjectPath(
        path,
        fallbackPlateNumber: plateNumber,
      );
      final filePlate = _cleanPlate(fileMetadata.plateNumber);
      final plateDirectory = plateDirectoryName(plateNumber);
      final matchesPlate = filePlate == normalizedPlate ||
          path.contains('/$plateDirectory/') ||
          path.contains(plateNumber);
      if (!matchesPlate) continue;
      final key = _pairKey(path);
      if (key.isEmpty) continue;
      if (isThumbnailObjectPath(path)) {
        thumbnails.putIfAbsent(key, () => path);
      } else if (isDisplayObjectPath(path)) {
        newDisplays.putIfAbsent(key, () => path);
      } else if (isLegacyDisplayObjectPath(path)) {
        legacyDisplays.putIfAbsent(key, () => path);
      }
    }

    final keys = <String>{...newDisplays.keys, ...legacyDisplays.keys}.toList();
    final photos = <StoredPlatePhoto>[];
    for (final key in keys) {
      final displayPath = newDisplays[key] ?? legacyDisplays[key];
      if (displayPath == null) continue;
      final thumbnailPath = thumbnails[key];
      photos.add(
        StoredPlatePhoto(
          displayUrl: publicUrl(bucketName, displayPath),
          displayObjectPath: displayPath,
          thumbnailUrl: thumbnailPath == null
              ? null
              : publicUrl(bucketName, thumbnailPath),
          thumbnailObjectPath: thumbnailPath,
          metadata: StoredPlatePhotoMetadata.fromObjectPath(
            displayPath,
            fallbackPlateNumber: plateNumber,
          ),
        ),
      );
    }

    photos.sort((a, b) {
      final aTime = a.metadata.capturedAt;
      final bTime = b.metadata.capturedAt;
      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return b.displayObjectPath.compareTo(a.displayObjectPath);
    });
    return List<StoredPlatePhoto>.unmodifiable(photos);
  }

  static String _pairKey(String objectPath) {
    final normalized = _normalizePath(objectPath);
    final marker = '/images/';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) return fileNameOf(normalized);
    final remainder = normalized.substring(markerIndex + marker.length);
    final segments =
        remainder.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.length < 2) return fileNameOf(normalized);
    final yearMonth = segments.first;
    return '$yearMonth/${fileNameOf(normalized)}';
  }

  static String _normalizePath(String value) {
    return value.replaceAll('\\', '/').trim();
  }
}

String _safeDecodeComponent(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';
  try {
    return Uri.decodeComponent(normalized);
  } catch (_) {
    return normalized;
  }
}

String _cleanPlate(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').trim();
}

String _normalizeDate(String value) {
  final normalized = value.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalized)) {
    return normalized;
  }
  if (RegExp(r'^\d{8}$').hasMatch(normalized)) {
    return '${normalized.substring(0, 4)}-${normalized.substring(4, 6)}-${normalized.substring(6, 8)}';
  }
  return '';
}

String _normalizeTime(String value) {
  final normalized = value.trim();
  if (RegExp(r'^\d{6}$').hasMatch(normalized)) {
    return '${normalized.substring(0, 2)}:${normalized.substring(2, 4)}:${normalized.substring(4, 6)}';
  }
  if (RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(normalized)) {
    return normalized;
  }
  return '';
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}
