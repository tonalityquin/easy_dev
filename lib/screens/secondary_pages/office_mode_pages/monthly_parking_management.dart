import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'monthly_parking_pages/monthly_plate_bottom_sheet.dart';

class MonthlyParkingManagement extends StatelessWidget {
  const MonthlyParkingManagement({super.key});

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
          const SnackBar(content: Text('사용자 관리 기능은 준비 중입니다.')),
        );
        break;
      case 2:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정렬 기능은 준비 중입니다.')),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
              final data = docs[index].data() as Map<String, dynamic>;

              final plateNumber = docs[index].id.split('_').first;
              final countType = data['countType'] ?? '';
              final regularAmount = data['regularAmount'] ?? 0;
              final duration = data['regularDurationHours'] ?? 0;
              final startDate = data['startDate'] ?? '';
              final endDate = data['endDate'] ?? '';

              return Card(
                child: ListTile(
                  title: Text('$plateNumber - $countType'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('요금: ₩${regularAmount.toString()}'),
                      Text('주차 시간: ${duration}시간'),
                      Text('기간: $startDate ~ $endDate'),
                    ],
                  ),
                  trailing: const Icon(Icons.more_vert),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$plateNumber 상세 보기 준비 중')),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add,
          Icons.person,
          Icons.sort,
        ],
        onIconTapped: (index) => _handleIconTap(context, index),
      ),
    );
  }
}
