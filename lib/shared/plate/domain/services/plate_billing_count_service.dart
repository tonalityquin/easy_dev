import 'package:cloud_firestore/cloud_firestore.dart';

class PlateBillingCountService {
  const PlateBillingCountService._();

  static const String collectionName = 'plate_billing_counts';

  static DateTime nowInKst([DateTime? value]) {
    final base = value ?? DateTime.now();
    return base.toUtc().add(const Duration(hours: 9));
  }

  static String monthKey([DateTime? value]) {
    final date = nowInKst(value);
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  static String normalizeValue(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '미지정';
    return text.replaceAll('/', '／');
  }

  static String normalizeCompany(String? value) {
    final text = normalizeValue(value);
    return text == 'default' ? '미지정' : text;
  }

  static String documentId({
    required String month,
    required String company,
    required String area,
  }) {
    final safeMonth = normalizeValue(month);
    final safeCompany = normalizeCompany(company);
    final safeArea = normalizeValue(area);
    return 'm_${safeMonth}__c_${safeCompany}__a_$safeArea';
  }

  static DocumentReference<Map<String, dynamic>> documentRef({
    required FirebaseFirestore firestore,
    required String month,
    required String company,
    required String area,
  }) {
    return firestore.collection(collectionName).doc(
          documentId(
            month: month,
            company: company,
            area: area,
          ),
        );
  }

  static void incrementInTransaction({
    required Transaction transaction,
    required FirebaseFirestore firestore,
    required String company,
    required String area,
    required String plateDocId,
    required String plateNumber,
    DateTime? countedAt,
    String? userName,
    String billingCountBasis = 'plate_entry_session',
    String sourceCollection = 'plates',
  }) {
    final month = monthKey(countedAt);
    final safeCompany = normalizeCompany(company);
    final safeArea = normalizeValue(area);
    final safeUserName = normalizeValue(userName);
    final ref = documentRef(
      firestore: firestore,
      month: month,
      company: safeCompany,
      area: safeArea,
    );

    transaction.set(
      ref,
      <String, dynamic>{
        'docId': ref.id,
        'month': month,
        'company': safeCompany,
        'division': safeCompany,
        'area': safeArea,
        'aggregationAxis': 'division_area',
        'billingCountBasis': billingCountBasis,
        'sourceCollection': sourceCollection,
        'schemaVersion': 4,
        'count': FieldValue.increment(1),
        'lastPlateDocId': plateDocId,
        'lastPlateNumber': plateNumber,
        'lastUserName': safeUserName,
        'lastCountedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
