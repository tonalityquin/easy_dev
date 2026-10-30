import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreSizeEstimate {
  const FirestoreSizeEstimate({
    required this.bytes,
    required this.fieldCount,
    required this.documents,
    this.pointReadUnits = 0,
  });

  final int bytes;
  final int fieldCount;
  final int documents;
  final int pointReadUnits;
}

class FirestoreDocumentSizer {
  const FirestoreDocumentSizer._();

  static int _stringSize(String value) => utf8.encode(value).length + 1;

  static int _nameSize(String path) =>
      path.split('/').where((part) => part.isNotEmpty).fold<int>(16,
          (total, segment) => total + _stringSize(segment));

  static int _valueSize(Object? value) {
    if (value == null || value is bool) return 1;
    if (value is num || value is Timestamp || value is DateTime) return 8;
    if (value is String) return _stringSize(value);
    if (value is GeoPoint) return 16;
    if (value is DocumentReference) return _nameSize(value.path);
    if (value is Blob) return value.bytes.length;
    if (value is Uint8List) return value.length;
    if (value is List) {
      return value.fold<int>(0, (total, child) => total + _valueSize(child));
    }
    if (value is Map) {
      var bytes = 0;
      for (final entry in value.entries) {
        bytes += _stringSize(entry.key.toString()) + _valueSize(entry.value);
      }
      return bytes;
    }
    return 8;
  }

  static int _fields(Object? value) {
    if (value is Map) {
      var result = 0;
      for (final item in value.values) {
        result += 1 + _fields(item);
      }
      return result;
    }
    if (value is List) {
      return value.fold<int>(0, (total, child) => total + _fields(child));
    }
    return 0;
  }

  static FirestoreSizeEstimate document(String path, Object? data) {
    return FirestoreSizeEstimate(
      bytes: _nameSize(path) + _valueSize(data) + 32,
      fieldCount: _fields(data),
      documents: 1,
      pointReadUnits: (( _nameSize(path) + _valueSize(data) + 32 + 4095) ~/ 4096),
    );
  }

  static FirestoreSizeEstimate fromSnapshot(Object? snapshot) {
    if (snapshot is QuerySnapshot) {
      var bytes = 0;
      var fields = 0;
      var pointUnits = 0;
      for (final doc in snapshot.docs) {
        final size = document(doc.reference.path, doc.data());
        bytes += size.bytes;
        fields += size.fieldCount;
        pointUnits += size.pointReadUnits;
      }
      return FirestoreSizeEstimate(
        bytes: bytes,
        fieldCount: fields,
        documents: snapshot.docs.length,
        pointReadUnits: pointUnits,
      );
    }
    if (snapshot is DocumentSnapshot) {
      if (!snapshot.exists) {
        return const FirestoreSizeEstimate(bytes: 0, fieldCount: 0, documents: 0);
      }
      return document(snapshot.reference.path, snapshot.data());
    }
    return const FirestoreSizeEstimate(bytes: 0, fieldCount: 0, documents: 0);
  }

  static FirestoreSizeEstimate fromChanges(Object? snapshot) {
    if (snapshot is QuerySnapshot) {
      var bytes = 0;
      var fields = 0;
      var count = 0;
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.removed) continue;
        final size = document(change.doc.reference.path, change.doc.data());
        bytes += size.bytes;
        fields += size.fieldCount;
        count++;
      }
      return FirestoreSizeEstimate(
        bytes: bytes,
        fieldCount: fields,
        documents: count,
      );
    }
    return fromSnapshot(snapshot);
  }
}
