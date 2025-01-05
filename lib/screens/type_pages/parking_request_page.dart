import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('입차 요청 리스트'),
      ),
      body: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final pendingRequests =
              plateState.requests.where((request) => request['type'] == '입차 요청' || request['type'] == '입차 중').toList();

          if (pendingRequests.isEmpty) {
            return const Center(
              child: Text(
                '입차 요청이 없습니다.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: pendingRequests.length,
            itemBuilder: (context, index) {
              final request = pendingRequests[index];
              final DateTime requestTime = request['request_time'].toDate();
              final Duration duration = DateTime.now().difference(requestTime);
              final bool isInProgress = request['type'] == '입차 중';

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
                      child: GestureDetector(
                        onTap: () async {
                          final newType = isInProgress ? '입차 요청' : '입차 중';

                          // BuildContext 관련 작업은 비동기 작업 전에 실행
                          final messenger = ScaffoldMessenger.of(context);

                          await context.read<PlateState>().updateRequest(
                                request['id'],
                                newType,
                              );

                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Type이 $newType으로 변경되었습니다.')),
                            );
                          }
                        },
                        child: Container(
                          height: 50,
                          color: isInProgress ? Colors.orange : Colors.red,
                        ),
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
                          if (isInProgress)
                            TextButton(
                              onPressed: () async {
                                // 기존 코드에서 문제 해결

                                final messenger = ScaffoldMessenger.of(context);
                                final plateState = context.read<PlateState>();

                                final selectedLocation = await showModalBottomSheet<String>(
                                  context: context,
                                  builder: (context) {
                                    return ListView(
                                      children: [
                                        ListTile(
                                          title: const Text('A'),
                                          onTap: () => Navigator.pop(context, 'A'),
                                        ),
                                        ListTile(
                                          title: const Text('B'),
                                          onTap: () => Navigator.pop(context, 'B'),
                                        ),
                                        ListTile(
                                          title: const Text('C'),
                                          onTap: () => Navigator.pop(context, 'C'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (selectedLocation != null) {
                                  await plateState.addCompleted(
                                    request['id'],
                                    selectedLocation,
                                  );

                                  messenger.showSnackBar(
                                    SnackBar(content: Text('주차 완료: $selectedLocation')),
                                  );
                                }
                              },
                              child: const Text('주차 영역 선택'),
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
