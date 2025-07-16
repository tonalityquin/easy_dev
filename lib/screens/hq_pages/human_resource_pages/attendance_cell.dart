import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../models/user_model.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../utils/google_sheets_helper.dart';

class AttendanceCell extends StatefulWidget {
  const AttendanceCell({super.key});

  @override
  State<AttendanceCell> createState() => _AttendanceCellState();
}

class _AttendanceCellState extends State<AttendanceCell> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String? _selectedArea;
  UserModel? _selectedUser;
  List<UserModel> _users = [];

  bool _isLoadingUsers = false;
  Map<int, String> _clockInMap = {};
  Map<int, String> _clockOutMap = {};

  Future<void> _loadAttendanceTimes(UserModel user) async {
    final allRows = await GoogleSheetsHelper.loadClockInOutRecords();

    final userId = '${user.phone}-${user.selectedArea}';

    final inMap = GoogleSheetsHelper.mapToCellData(
      allRows,
      statusFilter: '출근',
      selectedYear: _focusedDay.year,
      selectedMonth: _focusedDay.month,
    );

    final outMap = GoogleSheetsHelper.mapToCellData(
      allRows,
      statusFilter: '퇴근',
      selectedYear: _focusedDay.year,
      selectedMonth: _focusedDay.month,
    );

    setState(() {
      _clockInMap = inMap[userId] ?? {};
      _clockOutMap = outMap[userId] ?? {};
    });
  }

  Future<void> _loadUsers(String area) async {
    setState(() => _isLoadingUsers = true);

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('selectedArea', isEqualTo: area).get();

      final users = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      setState(() {
        _users = users;
        _selectedUser = users.isNotEmpty ? users.first : null;
      });

      showSuccessSnackbar(context, '사용자 ${users.length}명 불러옴');
    } catch (e) {
      showFailedSnackbar(context, '사용자 불러오기 실패: $e');
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final user = context.read<UserState>().user;

    if (user != null) {
      final initialArea = user.selectedArea ?? '';
      if (initialArea.isNotEmpty) {
        _selectedArea = initialArea;
        _loadUsers(initialArea);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserState>().user;
    final areaList = user?.areas ?? [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '출석 캘린더',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<String>(
                    value: _selectedArea,
                    decoration: const InputDecoration(labelText: '지역'),
                    items: areaList.map((area) {
                      return DropdownMenuItem(
                        value: area,
                        child: Text(
                          area,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedArea = value;
                          _users = [];
                          _selectedUser = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: DropdownButtonFormField<UserModel>(
                    value: _selectedUser,
                    decoration: const InputDecoration(labelText: '사용자'),
                    items: _users.map((user) {
                      return DropdownMenuItem(
                        value: user,
                        child: Text(
                          user.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUser = value;
                      });
                      if (value != null) {
                        _loadAttendanceTimes(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _selectedArea == null || _isLoadingUsers ? null : () => _loadUsers(_selectedArea!),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Icon(Icons.refresh),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              rowHeight: 80,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              calendarStyle: const CalendarStyle(
                outsideDaysVisible: true,
                isTodayHighlighted: false,
                cellMargin: EdgeInsets.all(4),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: _buildCell,
                todayBuilder: _buildCell,
                selectedBuilder: _buildCell,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday = isSameDay(day, DateTime.now());

    final inTime = _clockInMap[day.day] ?? '';
    final outTime = _clockOutMap[day.day] ?? '';

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.orange.withOpacity(0.3)
            : isToday
            ? Colors.blueAccent.withOpacity(0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(inTime, style: const TextStyle(fontSize: 10)),
          Text(outTime, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}
