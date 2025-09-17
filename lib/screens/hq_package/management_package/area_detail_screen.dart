// lib/screens/area/area_detail_bottom_sheet.dart
import 'package:flutter/material.dart';
import '../../../repositories/area_user_repository.dart';

/// 호출 예시:
/// await showAreaDetailBottomSheet(context: context, areaName: 'belivus');
Future<void> showAreaDetailBottomSheet({
  required BuildContext context,
  required String areaName,
  AreaUserRepository? repository,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,                  // ✅ 안전영역 반영
    backgroundColor: Colors.transparent, // ✅ 시트 자체에서 배경/라운드 처리
    builder: (_) => FractionallySizedBox(
      heightFactor: 1, // ✅ 화면 최상단까지
      child: AreaDetailBottomSheet(
        areaName: areaName,
        repository: repository,
      ),
    ),
  );
}

class AreaDetailBottomSheet extends StatefulWidget {
  final String areaName;
  final AreaUserRepository _repo;

  AreaDetailBottomSheet({
    super.key,
    required this.areaName,
    AreaUserRepository? repository,
  }) : _repo = repository ?? AreaUserRepository();

  @override
  State<AreaDetailBottomSheet> createState() => _AreaDetailBottomSheetState();
}

class _AreaDetailBottomSheetState extends State<AreaDetailBottomSheet> {
  late Future<List<UserStatus>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget._repo.getUsersForArea(widget.areaName);
  }

  void _reload() {
    setState(() {
      _future = widget._repo.getUsersForArea(widget.areaName);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Grip
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.areaName} 지역 근무자 현황',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            Expanded(
              child: FutureBuilder<List<UserStatus>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '❌ 데이터를 불러오는 중 오류 발생\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    );
                  }

                  final users = snapshot.data ?? [];
                  if (users.isEmpty) {
                    return const Center(
                      child: Text('📭 해당 지역에 근무자가 없습니다.'),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final leadingColor =
                      user.isWorking ? Colors.green : Colors.grey;

                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 2,
                        child: ListTile(
                          leading: Icon(
                            user.isWorking
                                ? Icons.check_circle
                                : Icons.remove_circle_outline,
                            color: leadingColor,
                          ),
                          title: Text(user.name),
                          subtitle: Text(user.isWorking ? '출근 중' : '퇴근'),
                          trailing: Text(
                            user.isWorking ? '🟢 출근' : '⚪ 퇴근',
                            style: TextStyle(
                              color: user.isWorking
                                  ? Colors.green
                                  : Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
