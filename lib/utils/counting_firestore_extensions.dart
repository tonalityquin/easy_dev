// lib/utils/counted_firestore.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'usage_reporter.dart';

/// 기존 Firestore 호출 직후에 UsageReporter.report()를 자동 호출해주는 간단 래퍼.
/// 앱 곳곳의 get/set/update/delete 뒤에 일일이 report()를 넣는 대신,
/// 이 래퍼로 실행하면 초심자도 실수 없이 누락을 줄일 수 있습니다.
class CountedFirestore {
  CountedFirestore._();
  static final CountedFirestore instance = CountedFirestore._();

  final _db = FirebaseFirestore.instance;

  FirebaseFirestore get raw => _db;

  /// 읽기(쿼리 실행). 결과 docs.length를 read 카운트로 누적.
  Future<QuerySnapshot<Map<String, dynamic>>> getQuery(
      Query<Map<String, dynamic>> query, {
        required String area,
      }) async {
    final snap = await query.get();
    final n = snap.docs.length;
    await UsageReporter.instance.report(area: area, action: 'read', n: n == 0 ? 1 : n);
    return snap;
  }

  /// 단일 문서 읽기. 존재 여부와 관계없이 read 1회로 카운트.
  Future<DocumentSnapshot<Map<String, dynamic>>> getDoc(
      DocumentReference<Map<String, dynamic>> ref, {
        required String area,
      }) async {
    final snap = await ref.get();
    await UsageReporter.instance.report(area: area, action: 'read', n: 1);
    return snap;
  }

  /// set(쓰기). merge 유무와 관계없이 write 1회(또는 n지정) 카운트.
  Future<void> setDoc(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data, {
        required String area,
        SetOptions? options,
        int n = 1,
      }) async {
    await ref.set(data, options);
    await UsageReporter.instance.report(area: area, action: 'write', n: n);
  }

  /// update(쓰기). write 1회로 카운트.
  Future<void> updateDoc(
      DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> data, {
        required String area,
        int n = 1,
      }) async {
    await ref.update(data);
    await UsageReporter.instance.report(area: area, action: 'write', n: n);
  }

  /// delete(삭제). delete 1회로 카운트.
  Future<void> deleteDoc(
      DocumentReference<Map<String, dynamic>> ref, {
        required String area,
        int n = 1,
      }) async {
    await ref.delete();
    await UsageReporter.instance.report(area: area, action: 'delete', n: n);
  }

  /// 배치 커밋. 요청한 작업 개수(opCount)를 n으로 받아 한 번에 카운트.
  Future<void> commitBatch(WriteBatch batch, {required String area, int opCount = 1}) async {
    await batch.commit();
    await UsageReporter.instance.report(area: area, action: 'write', n: opCount);
  }
}
