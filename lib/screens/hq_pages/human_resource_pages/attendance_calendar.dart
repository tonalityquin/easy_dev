import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'attendances/time_edit_bottom_sheet.dart';
import 'utils/google_sheets_helper.dart';
import '../../../states/head_quarter/calendar_selection_state.dart';
import '../../../../models/user_model.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';

class AttendanceCalendar extends StatefulWidget {
  const AttendanceCalendar({super.key});

  @override
  State<AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends State<AttendanceCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String? _selectedArea;
  UserModel? _selectedUser;
  List<UserModel> _users = [];

  Map<int, String> _clockInMap = {};
  Map<int, String> _clockOutMap = {};

  // ✅ 캐싱용 메모리 저장소
  final Map<String, List<UserModel>> _userCache = {};
  final Map<String, Map<int, String>> _inCache = {};
  final Map<String, Map<int, String>> _outCache = {};

  @override
  void initState() {
    super.initState();

    final calendarState = context.read<CalendarSelectionState>();
    _selectedArea = calendarState.selectedArea;
    _selectedUser = calendarState.selectedUser;

    if (_selectedArea != null) {
      _loadUsers(_selectedArea!).then((_) {
        if (_selectedUser != null) {
          _loadAttendanceTimes(_selectedUser!);
        }
      });
    }
  }

  Future<void> _loadUsers(String area) async {
    if (_userCache.containsKey(area)) {
      print('[CACHE HIT] 사용자 목록 - area=$area');
      setState(() {
        _users = _userCache[area]!;
      });
      return;
    }

    print('[CACHE MISS] 사용자 목록 - area=$area → Firestore 요청');

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('user_accounts').where('selectedArea', isEqualTo: area).get();

      final users = snapshot.docs.map((doc) => UserModel.fromMap(doc.id, doc.data())).toList();

      setState(() {
        _users = users;
        _userCache[area] = users;
      });

      showSuccessSnackbar(context, '사용자 ${users.length}명 불러옴');
    } catch (e) {
      showFailedSnackbar(context, '사용자 불러오기 실패: $e');
    }
  }

  Future<void> _loadAttendanceTimes(UserModel user) async {
    final area = user.selectedArea?.trim() ?? '';
    final userId = '${user.phone}-$area';
    final cacheKey = '$userId-${_focusedDay.year}-${_focusedDay.month}';

    if (_inCache.containsKey(cacheKey) && _outCache.containsKey(cacheKey)) {
      print('[CACHE HIT] 출퇴근 기록 - key=$cacheKey');
      setState(() {
        _clockInMap = _inCache[cacheKey]!;
        _clockOutMap = _outCache[cacheKey]!;
      });
      return;
    }

    print('[CACHE MISS] 출퇴근 기록 - key=$cacheKey → Google Sheets 요청');

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
      _inCache[cacheKey] = _clockInMap;
      _outCache[cacheKey] = _clockOutMap;
    });
  }

  Future<void> _saveAllChangesToSheets() async {
    if (_selectedUser == null || _selectedArea == null) return;

    final user = _selectedUser!;
    final area = _selectedArea!;
    final userId = '${user.phone}-$area';
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

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

    // ✅ 저장 후 캐시도 최신값으로 반영
    final cacheKey = '$userId-${_focusedDay.year}-${_focusedDay.month}';
    _inCache[cacheKey] = {..._clockInMap};
    _outCache[cacheKey] = {..._clockOutMap};
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserState>().user;
    final areaList = user?.areas ?? [];
    final calendarState = context.watch<CalendarSelectionState>();

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
            // ✅ 상단 드롭다운
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
                        calendarState.setArea(value);
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
                      calendarState.setUser(value);
                      setState(() => _selectedUser = value);
                      if (value != null) {
                        _loadAttendanceTimes(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  flex: 2,
                  child: Tooltip(
                    message: '지역 선택 시 자동으로 사용자 목록이 불러와집니다',
                    child: Icon(Icons.cloud, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ✅ 캘린더
            TableCalendar(
              firstDay: DateTime.utc(2025, 1, 1),
              lastDay: DateTime.utc(2025, 12, 31),
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
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
                if (_selectedUser != null) {
                  _loadAttendanceTimes(_selectedUser!);
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

            // ✅ 저장 버튼
            ElevatedButton.icon(
              onPressed: _selectedUser == null || _selectedArea == null ? null : _saveAllChangesToSheets,
              icon: const Icon(Icons.save, size: 20),
              label: const Text('변경사항 저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
