import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'attendances/time_edit_bottom_sheet.dart';
import 'utils/google_sheets_helper.dart';
import '../../../states/head_quarter/calendar_selection_state.dart';
import '../../../../models/user_model.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/sheets_config.dart';

class AttendanceCalendar extends StatefulWidget {
  const AttendanceCalendar({super.key});

  @override
  State<AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends State<AttendanceCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  UserModel? _selectedUser;

  // 사용자가 직접 입력(전화번호 또는 전화번호-지역)
  final TextEditingController _userInputCtrl = TextEditingController();
  final FocusNode _userInputFocus = FocusNode();

  // 검색 진행 상태(로더 표시)
  bool _isSearching = false;

  // 시트 캐시
  Map<int, String> _clockInMap = {};
  Map<int, String> _clockOutMap = {};
  final Map<String, Map<int, String>> _inCache = {};
  final Map<String, Map<int, String>> _outCache = {};

  String? _sheetId;

  @override
  void initState() {
    super.initState();
    _loadSheetId();

    // 입력 변화에 따라 suffix 아이콘 갱신
    _userInputCtrl.addListener(() => setState(() {}));

    // 이전 선택 사용자 복원
    final calendarState = context.read<CalendarSelectionState>();
    final presetUser = calendarState.selectedUser;
    if (presetUser != null) {
      _selectedUser = presetUser;
      final area = presetUser.selectedArea?.trim() ?? '';
      _userInputCtrl.text =
      area.isEmpty ? presetUser.phone : '${presetUser.phone}-$area';
      _loadAttendanceTimes(presetUser);
    }
  }

  @override
  void dispose() {
    _userInputCtrl.dispose();
    _userInputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSheetId() async {
    final id = await SheetsConfig.getCommuteSheetId();
    if (!mounted) return;
    setState(() => _sheetId = id);
  }

  Future<void> _openSetSheetIdSheet() async {
    final current = await SheetsConfig.getCommuteSheetId();
    final textCtrl = TextEditingController(text: current ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('출근/퇴근/휴게 스프레드시트 ID 입력',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(
                  labelText: 'Google Sheets ID 또는 전체 URL',
                  helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  final raw = textCtrl.text.trim();
                  if (raw.isEmpty) return;
                  final id = SheetsConfig.extractSpreadsheetId(raw);
                  await SheetsConfig.setCommuteSheetId(id);
                  if (!mounted) return;
                  setState(() {
                    _sheetId = id;
                    _inCache.clear();
                    _outCache.clear();
                    _clockInMap.clear();
                    _clockOutMap.clear();
                  });
                  Navigator.pop(context);
                  showSuccessSnackbar(context, '시트 ID가 저장되었습니다.');
                  if (_selectedUser != null) {
                    _loadAttendanceTimes(_selectedUser!);
                  }
                },
                label: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 전체 지우기(초기화)
  void _clearAll() {
    setState(() {
      _selectedUser = null;
      _userInputCtrl.clear();

      _clockInMap.clear();
      _clockOutMap.clear();
      _inCache.clear();
      _outCache.clear();

      _selectedDay = null;
      _focusedDay = DateTime.now();
    });
    context.read<CalendarSelectionState>().setUser(null);
    showSelectedSnackbar(context, '모든 데이터를 초기화했어요.');
  }

  // 사용자 찾기
  Future<UserModel?> _findUserByInput(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    String phone = raw;
    String? area;
    final dashIdx = raw.indexOf('-');
    if (dashIdx != -1) {
      phone = raw.substring(0, dashIdx).trim();
      area = raw.substring(dashIdx + 1).trim();
    }

    final col = FirebaseFirestore.instance.collection('user_accounts');

    try {
      if (area != null && area.isNotEmpty) {
        // 문서 ID 직조회 (phone-area)
        final docId = '$phone-$area';
        final doc = await col.doc(docId).get();
        if (doc.exists && doc.data() != null) {
          return UserModel.fromMap(doc.id, doc.data()!);
        }
      }

      // phone으로 조회 (여러 명이면 선택)
      final qs = await col.where('phone', isEqualTo: phone).limit(10).get();
      if (qs.docs.isEmpty) return null;
      if (qs.docs.length == 1) {
        final d = qs.docs.first;
        return UserModel.fromMap(d.id, d.data());
      }

      if (!mounted) return null;
      final picked = await showModalBottomSheet<UserModel>(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return SafeArea(
            child: Material(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemBuilder: (_, i) {
                  final d = qs.docs[i];
                  final u = UserModel.fromMap(d.id, d.data());
                  final area = u.selectedArea ?? '-';
                  return ListTile(
                    title: Text('${u.name}  •  $area'),
                    subtitle: Text(u.phone),
                    onTap: () => Navigator.pop(context, u),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: qs.docs.length,
              ),
            ),
          );
        },
      );
      return picked;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onSearchUserPressed() async {
    if (_isSearching) return;
    setState(() => _isSearching = true);
    try {
      final user = await _findUserByInput(_userInputCtrl.text);
      if (user == null) {
        showFailedSnackbar(context,
            '사용자를 찾지 못했습니다. 예) 11100000000 또는 11100000000-belivus');
        return;
      }

      context.read<CalendarSelectionState>().setUser(user);
      setState(() {
        _selectedUser = user;
        _clockInMap.clear();
        _clockOutMap.clear();

        final area = user.selectedArea?.trim() ?? '';
        _userInputCtrl.text = area.isEmpty ? user.phone : '${user.phone}-$area';
      });
      _loadAttendanceTimes(user);
      _userInputFocus.unfocus();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadAttendanceTimes(UserModel user) async {
    if (_sheetId == null || _sheetId!.isEmpty) {
      showFailedSnackbar(context, '스프레드시트 ID가 설정되지 않았습니다. 우측 상단 버튼으로 설정해 주세요.');
      return;
    }

    final area = (user.selectedArea ?? '').trim();
    final userId = '${user.phone}-$area';
    final cacheKey = '$userId-${_focusedDay.year}-${_focusedDay.month}';

    if (_inCache.containsKey(cacheKey) && _outCache.containsKey(cacheKey)) {
      setState(() {
        _clockInMap = _inCache[cacheKey]!;
        _clockOutMap = _outCache[cacheKey]!;
      });
      return;
    }

    try {
      final allRows = await GoogleSheetsHelper.loadClockInOutRecordsById(_sheetId!);

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
    } catch (e) {
      showFailedSnackbar(context, '출퇴근 기록 로드 실패: $e');
    }
  }

  Future<void> _saveAllChangesToSheets() async {
    if (_selectedUser == null) return;
    if (_sheetId == null || _sheetId!.isEmpty) {
      showFailedSnackbar(context, '스프레드시트 ID가 설정되지 않았습니다.');
      return;
    }

    final user = _selectedUser!;
    final area = (user.selectedArea ?? '').trim();
    final userId = '${user.phone}-$area';
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

    try {
      for (final entry in _clockInMap.entries) {
        final date = DateTime(_focusedDay.year, _focusedDay.month, entry.key);
        await GoogleSheetsHelper.updateClockInOutRecordById(
          spreadsheetId: _sheetId!,
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
        await GoogleSheetsHelper.updateClockInOutRecordById(
          spreadsheetId: _sheetId!,
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

      final cacheKey = '$userId-${_focusedDay.year}-${_focusedDay.month}';
      _inCache[cacheKey] = {..._clockInMap};
      _outCache[cacheKey] = {..._clockOutMap};
    } catch (e) {
      showFailedSnackbar(context, '저장 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffixWidth = (_userInputCtrl.text.isNotEmpty ? 92.0 : 48.0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('출석 캘린더', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '전체 지우기',
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAll,
          ),
          IconButton(
            tooltip: '시트 ID 설정',
            icon: const Icon(Icons.assignment_add),
            onPressed: _openSetSheetIdSheet,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ▶︎ “찾기” 버튼을 텍스트필드 안쪽(suffixIcon)으로 통합
                  TextField(
                    controller: _userInputCtrl,
                    focusNode: _userInputFocus,
                    onSubmitted: (_) => _onSearchUserPressed(),
                    decoration: InputDecoration(
                      labelText: '사용자 (전화번호 또는 전화번호-지역)',
                      hintText: '예) 11100000000 또는 11100000000-belivus',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_search),
                      suffixIconConstraints: BoxConstraints.tightFor(width: suffixWidth, height: 48),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_userInputCtrl.text.isNotEmpty)
                            IconButton(
                              tooltip: '입력 지우기',
                              icon: const Icon(Icons.clear),
                              onPressed: () => _userInputCtrl.clear(),
                            ),
                          _isSearching
                              ? const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                              : IconButton(
                            tooltip: '찾기',
                            icon: const Icon(Icons.search),
                            onPressed: _onSearchUserPressed,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

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
                    availableGestures: AvailableGestures.none,
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
                      backgroundColor: Colors.white,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.2),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
