import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/user_model.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../utils/google_sheets_helper.dart';
import 'attendances/time_edit_bottom_sheet.dart';

class AttendanceCell extends StatefulWidget {
  final String selectedArea;

  const AttendanceCell({super.key, required this.selectedArea});

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

  @override
  void initState() {
    super.initState();
    _loadSelectedAreaFromPrefs();
  }

  Future<void> _loadSelectedAreaFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea')?.trim();
    if (area != null) {
      setState(() {
        _selectedArea = area;
      });
      await _loadUsers(area);
    }
  }

  Future<void> _saveSelectedAreaToPrefs(String area) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedArea', area.trim());
  }

  Future<void> _loadAttendanceTimes(UserModel user) async {
    final area = user.selectedArea?.trim() ?? '';
    final userId = '${user.phone}-$area';

    final allRows = await GoogleSheetsHelper.loadClockInOutRecords(area);

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
        _selectedUser = null;
      });

      showSuccessSnackbar(context, '사용자 ${users.length}명 불러옴');
    } catch (e) {
      showFailedSnackbar(context, '사용자 불러오기 실패: $e');
    } finally {
      setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _saveAllChangesToSheets() async {
    if (_selectedUser == null) return;

    final user = _selectedUser!;
    final area = user.selectedArea?.trim() ?? '';
    final userId = '${user.phone}-$area';
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

    print('[SAVE] userId=$userId, area=$area');

    for (final entry in _clockInMap.entries) {
      final date = DateTime(_focusedDay.year, _focusedDay.month, entry.key);
      await GoogleSheetsHelper.updateClockInOutRecord(
        date: date,
        userId: userId,
        userName: user.name,
        area: area,
        division: division,
        status: '출근',
        time: entry.value,
      );
    }

    for (final entry in _clockOutMap.entries) {
      final date = DateTime(_focusedDay.year, _focusedDay.month, entry.key);
      await GoogleSheetsHelper.updateClockInOutRecord(
        date: date,
        userId: userId,
        userName: user.name,
        area: area,
        division: division,
        status: '퇴근',
        time: entry.value,
      );
    }

    showSuccessSnackbar(context, 'Google Sheets에 저장 완료');
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
        title: const Text('출석 캘린더', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        child: Text(area, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      if (value != null) {
                        await _saveSelectedAreaToPrefs(value);
                        setState(() {
                          _selectedArea = value;
                          _users = [];
                          _selectedUser = null;
                        });
                        await _loadUsers(value);
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
                        child: Text(user.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedUser = value);
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

                if (_selectedUser != null) {
                  _showEditBottomSheet(selectedDay);
                }
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
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _selectedUser == null ? null : _saveAllChangesToSheets,
              icon: const Icon(Icons.save, size: 20),
              label: const Text(
                '변경사항 저장',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
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

  void _showEditBottomSheet(DateTime day) {
    final dayKey = day.day;
    final inTime = _clockInMap[dayKey] ?? '00:00';
    final outTime = _clockOutMap[dayKey] ?? '00:00';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return TimeEditBottomSheet(
          date: day,
          initialInTime: inTime,
          initialOutTime: outTime,
          onSave: (newIn, newOut) {
            setState(() {
              _clockInMap[dayKey] = newIn;
              _clockOutMap[dayKey] = newOut;
            });
          },
        );
      },
    );
  }
}
