import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

class EndWorkReportContent extends StatefulWidget {
  final void Function(String reportType, String content) onReport;

  const EndWorkReportContent({super.key, required this.onReport});

  @override
  State<EndWorkReportContent> createState() => _EndWorkReportContentState();
}

class _EndWorkReportContentState extends State<EndWorkReportContent> {
  final TextEditingController _vehicleCountController = TextEditingController();
  final TextEditingController _exitVehicleCountController = TextEditingController();

  void _update() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _vehicleCountController.addListener(_update);
    _exitVehicleCountController.addListener(_update);
  }

  @override
  void dispose() {
    _vehicleCountController.dispose();
    _exitVehicleCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _vehicleCountController.text.trim().isNotEmpty &&
        _exitVehicleCountController.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('업무 종료 보고', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _vehicleCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '입차 차량 수',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _exitVehicleCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '출차 차량 수',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('제출'),
            onPressed: canSubmit ? _handleSubmit : null,
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final user = Provider.of<UserState>(context, listen: false).user;
    final division = user?.divisions.first;
    final area = user?.currentArea;

    if (division == null || area == null) return;

    final entry = int.tryParse(_vehicleCountController.text.trim());
    final exit = int.tryParse(_exitVehicleCountController.text.trim());

    if (entry == null || exit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입차/출차 차량 수는 숫자만 입력 가능합니다.')),
      );
      return;
    }

    // Firestore 정산 요약이 없다면 새로 생성
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final summaryRef = FirebaseFirestore.instance
        .collection('fee_summaries')
        .doc('${division}_$area\_$dateStr');

    final doc = await summaryRef.get();
    if (!doc.exists) {
      await updateLockedFeeSummary(division, area);
    }

    final summary = await summaryRef.get();
    final lockedFee = summary['totalLockedFee'] ?? 0;

    final reportMap = {
      "vehicleInput": entry,
      "vehicleOutput": exit,
      "totalLockedFee": lockedFee,
    };

    final content = jsonEncode(reportMap);
    widget.onReport('end', content);
  }
}

// 🔄 Firestore 정산 요약 작성
Future<void> updateLockedFeeSummary(String division, String area) async {
  final firestore = FirebaseFirestore.instance;
  final date = DateTime.now();
  final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

  final snapshot = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  int total = 0;
  int count = 0;

  for (final doc in snapshot.docs) {
    final fee = doc.data()['lockedFeeAmount'];
    if (fee is int) {
      total += fee;
      count++;
    } else if (fee is double) {
      total += fee.round();
      count++;
    }
  }

  final summaryRef = firestore.collection('fee_summaries').doc('${division}_$area\_$dateStr');
  await summaryRef.set({
    'division': division,
    'area': area,
    'date': dateStr,
    'totalLockedFee': total,
    'vehicleCount': count,
    'lastUpdated': DateTime.now().toIso8601String(),
  });
}

// ☁️ GCS 업로드
Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime.now().toIso8601String().split('T').first;
  final fileName = 'ToDoReports_$dateStr.json';
  final destinationPath = '$division/$area/reports/$fileName';

  report['timestamp'] = dateStr;
  final jsonString = jsonEncode(report);

  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString, encoding: utf8);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);
  final storage = StorageApi(client);

  final media = Media(
    tempFile.openRead(),
    tempFile.lengthSync(),
    contentType: 'application/json',
  );

  final object = await storage.objects.insert(
    Object()
      ..name = destinationPath
      ..contentDisposition = 'attachment'
      ..acl = [ObjectAccessControl()..entity = 'allUsers'..role = 'READER'],
    kBucketName,
    uploadMedia: media,
  );

  client.close();

  return 'https://storage.googleapis.com/$kBucketName/${object.name}';
}

// 🔥 Firestore plates 정리
Future<void> deleteLockedDepartureDocs(String area) async {
  final firestore = FirebaseFirestore.instance;
  final snapshot = await firestore
      .collection('plates')
      .where('type', isEqualTo: 'departure_completed')
      .where('area', isEqualTo: area)
      .where('isLockedFee', isEqualTo: true)
      .get();

  for (final doc in snapshot.docs) {
    await doc.reference.delete();
    debugPrint("🔥 Firestore 삭제 완료: ${doc.id}");
  }
}
