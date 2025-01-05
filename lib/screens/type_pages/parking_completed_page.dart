import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';

class ParkingCompletedPage extends StatelessWidget {
  const ParkingCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('입차 완료 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final completedRequests = plateState.completed;

          if (completedRequests.isEmpty) {
            return const Center(
              child: Text(
                '입차 완료된 요청이 없습니다.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: completedRequests.length,
            itemBuilder: (context, index) {
              final request = completedRequests[index];
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
                        color: Colors.green,
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
                              await context.read<PlateState>().addDepartureRequest(request['id']);

                              // mounted를 확인하여 BuildContext의 유효성 확인
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('출차 요청이 등록되었습니다.')),
                                );
                              }
                            },
                            child: const Text('출차 요청'),
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
