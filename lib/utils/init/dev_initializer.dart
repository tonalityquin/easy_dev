import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> registerDevResources() async {
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
}
