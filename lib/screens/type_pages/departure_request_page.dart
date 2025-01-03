import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';

class DepartureRequestPage extends StatelessWidget {
  const DepartureRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('출차 요청 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final departureRequests = plateState.departureRequests;

          if (departureRequests.isEmpty) {
            return const Center(
              child: Text(
                '출차 요청이 없습니다.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: departureRequests.length,
            itemBuilder: (context, index) {
              final request = departureRequests[index];
              final DateTime requestTime = request['request_time'].toDate();
              final Duration duration = DateTime.now().difference(requestTime);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 50,
                        color: Colors.orange,
                      ),
                    ),
                    Expanded(
                      flex: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            title: Text(
                              '[${request['plate_number']}] ${request['type']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '요청 시간: ${requestTime.toString().substring(0, 19)}\n'
                                  '누적 시간: ${duration.inMinutes}분 ${duration.inSeconds % 60}초\n'
                                  '위치: ${request['location']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await context.read<PlateState>().addDepartureCompleted(request['id']);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('출차 완료가 등록되었습니다.')),
                              );
                            },
                            child: const Text('출차 완료'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
