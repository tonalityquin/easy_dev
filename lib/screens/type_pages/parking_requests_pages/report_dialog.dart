import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

class ParkingReportContent extends StatefulWidget {
  final void Function(String reportType, String content) onReport;

  const ParkingReportContent({super.key, required this.onReport});

  @override
  State<ParkingReportContent> createState() => _ParkingReportContentState();
}

class _ParkingReportContentState extends State<ParkingReportContent> {
  int _selectedTabIndex = 0;
  final TextEditingController _vehicleCountController = TextEditingController();
  final TextEditingController _startReportController = TextEditingController();
  final TextEditingController _middleReportController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery
            .of(context)
            .viewInsets
            .bottom,
        top: 16,
        left: 16,
        right: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '업무 보고',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('업무 시작')),
                ButtonSegment(value: 1, label: Text('보고란')),
                ButtonSegment(value: 2, label: Text('업무 종료')),
              ],
              selected: {_selectedTabIndex},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _selectedTabIndex = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_selectedTabIndex == 0)
              _buildStartReportField()
            else
              if (_selectedTabIndex == 1)
                _buildMiddleReportField()
              else
                _buildEndReportField(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    if (_selectedTabIndex == 0) {
                      _startReportController.clear();
                    } else if (_selectedTabIndex == 1) {
                      _middleReportController.clear();
                    } else {
                      _vehicleCountController.clear();
                    }
                  },
                  child: const Text('지우기'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('제출'),
                  onPressed: _handleSubmit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartReportField() {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _startReportController,
        decoration: const InputDecoration(
          labelText: '업무 시작 내용',
          hintText: '예: "근무지" "몇 명" 정상 출근 건강 이상 없습니다.',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
    );
  }

  Widget _buildMiddleReportField() {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _middleReportController,
        decoration: const InputDecoration(
          labelText: '보고란 내용',
          hintText: '예: 특별 상황, 민원, 기타 보고 사항 입력',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
    );
  }

  Widget _buildEndReportField() {
    return SizedBox(
      width: 300,
      child: TextField(
        controller: _vehicleCountController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '입차 차량 수',
          hintText: '예: 24',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  void _handleSubmit() {
    late String type;
    late String content;

    if (_selectedTabIndex == 0) {
      type = 'start';
      content = _startReportController.text.trim();
    } else if (_selectedTabIndex == 1) {
      type = 'middle';
      content = _middleReportController.text.trim();
    } else {
      type = 'end';
      content = _vehicleCountController.text.trim();
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용을 입력해주세요.')),
      );
      return;
    }

    widget.onReport(type, content);
  }
}

// ==== GCS 관련 메서드 ====

Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final dateStr = DateTime
      .now()
      .toIso8601String()
      .split('T')
      .first; // yyyy-mm-dd
  final fileName = '업무 종료 보고_$dateStr.json';
  final destinationPath = '$division/$area/reports/$fileName';

  report['timestamp'] = dateStr;

  final jsonString = jsonEncode(report);
  final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
  await tempFile.writeAsString(jsonString);

  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
  final scopes = [StorageApi.devstorageFullControlScope];
  final client = await clientViaServiceAccount(accountCredentials, scopes);
  final storage = StorageApi(client);

  final media = Media(tempFile.openRead(), tempFile.lengthSync());
  final object = await storage.objects.insert(
    Object()
      ..name = destinationPath
      ..acl = [ObjectAccessControl()
        ..entity = 'allUsers'
        ..role = 'READER'
      ],
    kBucketName,
    uploadMedia: media,
  );

  client.close();

  final uploadedUrl = 'https://storage.googleapis.com/$kBucketName/${object.name}';
  debugPrint('✅ GCS 업로드 완료: $uploadedUrl');
  return uploadedUrl;
}


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
    debugPrint("🔥 Firestore 삭제 완료: \${doc.id}");
  }
}