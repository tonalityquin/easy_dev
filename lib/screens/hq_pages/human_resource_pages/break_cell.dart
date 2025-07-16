import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../models/user_model.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../utils/google_sheets_helper.dart';
import 'breaks/break_edit_bottom_sheet.dart';

class BreakCell extends StatefulWidget {
  const BreakCell({super.key});

  @override
  State<BreakCell> createState() => _BreakCellState();
}

class _BreakCellState extends State<BreakCell> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String? _selectedArea;
  UserModel? _selectedUser;
  List<UserModel> _users = [];

  bool _isLoadingUsers = false;
  Map<int, String> _breakTimeMap = {};

  Future<void> _loadBreakTimes(UserModel user) async {
    final allRows = await GoogleSheetsHelper.loadBreakRecords();

    final userId = '${user.phone}-${user.selectedArea}';

    final breakMap = GoogleSheetsHelper.mapToCellData(
      allRows,
      statusFilter: '휴게',
      selectedYear: _focusedDay.year,
      selectedMonth: _focusedDay.month,
    );

    setState(() {
      _breakTimeMap = breakMap[userId] ?? {};
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

      showSuccessSnackbar(context, '사용자 목록 ${users.length}명 불러왔습니다');
    } catch (e) {
      showFailedSnackbar(context, '사용자 목록 불러오기 실패: $e');
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
        title: const Text('휴식 캘린더', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// 🔹 지역 + 사용자 + 버튼 한 줄
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
                        child: Text(user.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedUser = value;
                      });
                      if (value != null) {
                        _loadBreakTimes(value);
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

            /// 🔹 캘린더
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
                _showEditBottomSheet(selectedDay);
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

            /// 🔹 저장 버튼
            ElevatedButton.icon(
              onPressed: _selectedUser == null ? null : _saveAllChangesToSheets,
              icon: const Icon(Icons.save),
              label: const Text('변경사항 저장'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
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

    final breakTime = _breakTimeMap[day.day] ?? '';

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.redAccent.withOpacity(0.3)
            : isToday
                ? Colors.greenAccent.withOpacity(0.2)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(breakTime, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  void _showEditBottomSheet(DateTime day) {
    final dayKey = day.day;
    final initialTime = _breakTimeMap[dayKey] ?? '00:00';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return BreakEditBottomSheet(
          date: day,
          initialTime: initialTime,
          onSave: (newTime) {
            setState(() {
              _breakTimeMap[dayKey] = newTime;
            });
          },
        );
      },
    );
  }

  Future<void> _saveAllChangesToSheets() async {
    if (_selectedUser == null) return;

    final user = _selectedUser!;
    final userId = '${user.phone}-${user.selectedArea}';
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';
    final area = user.selectedArea ?? '';

    for (final entry in _breakTimeMap.entries) {
      final date = DateTime(_focusedDay.year, _focusedDay.month, entry.key);

      await GoogleSheetsHelper.updateBreakRecord(
        date: date,
        userId: userId,
        userName: user.name,
        area: area,
        division: division,
        time: entry.value,
      );
    }

    showSuccessSnackbar(context, 'Google Sheets에 저장 완료');
  }
}
