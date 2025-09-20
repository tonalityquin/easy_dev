// lib/utils/init/dev_initializer.dart
// (비용 방지) 현재 모든 Firestore I/O를 주석 처리했습니다.
// 나중에 개발 시드가 필요하면 아래 블록의 주석을 해제하세요.

// import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> registerDevResources() async {
  // --- 비용 방지: Firestore 접근 코드 전체 주석 처리 시작 ---
  /*
  final firestore = FirebaseFirestore.instance;

  final divisionDoc = firestore.collection('divisions').doc('dev');
  if (!(await divisionDoc.get()).exists) {
    await divisionDoc.set({
      'name': 'dev',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  final areaQuery = await firestore.collection('areas')
      .where('division', isEqualTo: 'dev')
      .get();
  if (areaQuery.docs.isEmpty) {
    await firestore.collection('areas').doc('dev-dev').set({
      'name': 'dev',
      'division': 'dev',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  const devPhone = '00000000000';
  const devArea = 'dev';
  const devAccountId = '$devPhone-$devArea';

  final userDoc = firestore.collection('user_accounts').doc(devAccountId);
  if (!(await userDoc.get()).exists) {
    await userDoc.set({
      'name': 'developer',
      'phone': devPhone,
      'email': 'dev@gmail.com',
      'password': '00000',
      'divisions': ['dev'],
      'areas': ['dev'],
      'role': 'dev',
      'isWorking': false,
      'isSaved': false,
      'isSelected': false,
      'currentArea': null,
    });
  }
  */
  // --- 비용 방지: Firestore 접근 코드 전체 주석 처리 끝 ---

  // 현재는 아무 것도 하지 않습니다.
}
