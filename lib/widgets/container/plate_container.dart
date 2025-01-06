import 'package:flutter/material.dart';

class PlateContainer extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool Function(Map<String, dynamic>) filterCondition;

  const PlateContainer({
    required this.data,
    required this.filterCondition,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filteredData = data.where(filterCondition).toList();

    if (filteredData.isEmpty) {
      return const Center(
        child: Text(
          '요청이 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredData.length,
      itemBuilder: (context, index) {
        final request = filteredData[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(5),
          ),
          child: ListTile(
            title: Text(
              '[${request['plate_number']}] ${request['type']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '요청 시간: ${request['request_time']}\n위치: ${request['location']}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}
