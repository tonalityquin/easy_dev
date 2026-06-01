import 'package:cloud_firestore/cloud_firestore.dart';

class PlateBillingCountModel {
  const PlateBillingCountModel({
    required this.id,
    required this.month,
    required this.company,
    required this.area,
    required this.count,
    this.lastPlateDocId,
    this.lastPlateNumber,
    this.lastUserName,
    this.lastCountedAt,
    this.updatedAt,
  });

  final String id;
  final String month;
  final String company;
  final String area;
  final int count;
  final String? lastPlateDocId;
  final String? lastPlateNumber;
  final String? lastUserName;
  final DateTime? lastCountedAt;
  final DateTime? updatedAt;

  factory PlateBillingCountModel.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawCount = data['count'];
    final rawLastCountedAt = data['lastCountedAt'];
    final rawUpdatedAt = data['updatedAt'];
    final company = (data['company'] ?? data['division'] ?? '미지정').toString();
    return PlateBillingCountModel(
      id: doc.id,
      month: (data['month'] ?? '').toString(),
      company: company.trim().isEmpty ? '미지정' : company.trim(),
      area: (data['area'] ?? '미지정').toString(),
      count: rawCount is int
          ? rawCount
          : rawCount is num
              ? rawCount.toInt()
              : 0,
      lastPlateDocId: (data['lastPlateDocId'] as String?)?.trim(),
      lastPlateNumber: (data['lastPlateNumber'] as String?)?.trim(),
      lastUserName: (data['lastUserName'] as String?)?.trim(),
      lastCountedAt:
          rawLastCountedAt is Timestamp ? rawLastCountedAt.toDate() : null,
      updatedAt: rawUpdatedAt is Timestamp ? rawUpdatedAt.toDate() : null,
    );
  }
}
