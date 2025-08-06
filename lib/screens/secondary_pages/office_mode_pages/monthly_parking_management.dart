import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'monthly_parking_pages/monthly_plate_bottom_sheet.dart';

class MonthlyParkingManagement extends StatefulWidget {
  const MonthlyParkingManagement({super.key});

  @override
  State<MonthlyParkingManagement> createState() => _MonthlyParkingManagementState();
}

class _MonthlyParkingManagementState extends State<MonthlyParkingManagement> {
  String? _selectedDocId;

  void _handleIconTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (context) => const MonthlyPlateBottomSheet(),
        );
        break;

      case 1:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정 기능은 준비 중입니다.')),
        );
        break;

      case 2:
        if (_selectedDocId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제할 항목을 선택해주세요.')),
          );
          return;
        }

        FirebaseFirestore.instance.collection('plate_status').doc(_selectedDocId).delete().then((_) {
          setState(() => _selectedDocId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제되었습니다.')),
          );
        }).catchError((e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('삭제 실패: $e')),
          );
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.read<UserState>().currentArea.trim();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '정기 주차 관리 페이지',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('plate_status')
            .where('type', isEqualTo: '정기')
            .where('area', isEqualTo: currentArea)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('등록된 정기 주차 정보가 없습니다.'));
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final docId = doc.id;
              final data = doc.data() as Map<String, dynamic>;

              final plateNumber = docId.split('_').first;
              final countType = data['countType'] ?? '';
              final regularAmount = data['regularAmount'] ?? 0;
              final duration = data['regularDurationHours'] ?? 0;
              final startDate = data['startDate'] ?? '';
              final endDate = data['endDate'] ?? '';
              final isSelected = docId == _selectedDocId;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDocId = isSelected ? null : docId;
                  });
                },
                child: Card(
                  elevation: isSelected ? 6 : 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected ? const BorderSide(color: Colors.redAccent, width: 2) : BorderSide.none,
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$plateNumber - $countType',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Icon(Icons.more_vert),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.attach_money, size: 20, color: Colors.green),
                            const SizedBox(width: 6),
                            Text('요금: ₩$regularAmount', style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.schedule, size: 20, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Text('주차 시간: $duration시간', style: const TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20, color: Colors.deepOrange),
                            const SizedBox(width: 6),
                            Text(
                              '기간: $startDate ~ $endDate',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20, color: Colors.purple),
                            const SizedBox(width: 6),
                            Text(
                              '상태 메시지: ${data['customStatus'] ?? '없음'}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add,
          Icons.wallet,
          Icons.delete,
        ],
        onIconTapped: (index) => _handleIconTap(context, index),
      ),
    );
  }
}
