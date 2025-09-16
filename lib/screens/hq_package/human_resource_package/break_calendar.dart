import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'breaks/break_edit_bottom_sheet.dart';
import 'utils/google_sheets_helper.dart';
import '../../../states/head_quarter/calendar_selection_state.dart';
import '../../../../models/user_model.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/sheets_config.dart';

class BreakCalendar extends StatefulWidget {
  const BreakCalendar({super.key});

  @override
  State<BreakCalendar> createState() => _BreakCalendarState();
}

class _BreakCalendarState extends State<BreakCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  UserModel? _selectedUser;

  final TextEditingController _userInputCtrl = TextEditingController();
  final FocusNode _userInputFocus = FocusNode();

  Map<int, String> _breakTimeMap = {};
  final Map<String, Map<int, String>> _breakTimeCache = {};

  bool _isSearching = false;

  String? _sheetId;

  @override
  void initState() {
    super.initState();
    _loadSheetId();

    _userInputCtrl.addListener(() => setState(() {}));

    // 이전 선택 사용자 복원
    final calendarState = context.read<CalendarSelectionState>();
    final presetUser = calendarState.selectedUser;
    if (presetUser != null) {
      _selectedUser = presetUser;
      final area = presetUser.selectedArea?.trim() ?? '';
      _userInputCtrl.text =
      area.isEmpty ? presetUser.phone : '${presetUser.phone}-$area';
      _loadBreakTimes(presetUser);
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
                    _breakTimeCache.clear();
                    _breakTimeMap.clear();
                  });
                  Navigator.pop(context);
                  showSuccessSnackbar(context, '시트 ID가 저장되었습니다.');
                  if (_selectedUser != null) {
                    _loadBreakTimes(_selectedUser!);
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

      _breakTimeMap.clear();
      _breakTimeCache.clear();

      _selectedDay = null;
      _focusedDay = DateTime.now();
    });
    context.read<CalendarSelectionState>().setUser(null);
    showSelectedSnackbar(context, '모든 데이터를 초기화했어요.');
  }

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
        final docId = '$phone-$area';
        final doc = await col.doc(docId).get();
        if (doc.exists && doc.data() != null) {
          return UserModel.fromMap(doc.id, doc.data()!);
        }
      }

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
        _breakTimeMap.clear();

        final area = user.selectedArea?.trim() ?? '';
        _userInputCtrl.text = area.isEmpty ? user.phone : '${user.phone}-$area';
      });
      _loadBreakTimes(user);
      _userInputFocus.unfocus();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadBreakTimes(UserModel user) async {
    if (_sheetId == null || _sheetId!.isEmpty) {
      showFailedSnackbar(context, '스프레드시트 ID가 설정되지 않았습니다. 우측 상단 버튼으로 설정해 주세요.');
      return;
    }

    final area = (user.selectedArea ?? '').trim();
    final userId = '${user.phone}-$area';
    final cacheKey = '$userId-${_focusedDay.year}-${_focusedDay.month}';

    if (_breakTimeCache.containsKey(cacheKey)) {
      setState(() {
        _breakTimeMap = _breakTimeCache[cacheKey]!;
      });
      return;
    }

    try {
      final allRows = await GoogleSheetsHelper.loadBreakRecordsById(_sheetId!);

      final breakMap = GoogleSheetsHelper.mapToCellData(
        allRows,
        statusFilter: '휴게',
        selectedYear: _focusedDay.year,
        selectedMonth: _focusedDay.month,
      );

      setState(() {
        _breakTimeMap = breakMap[userId] ?? {};
        _breakTimeCache[cacheKey] = _breakTimeMap;
      });
    } catch (e) {
      showFailedSnackbar(context, '휴게 기록 로드 실패: $e');
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
      for (final entry in _breakTimeMap.entries) {
        final date = DateTime(_focusedDay.year, _focusedDay.month, entry.key);
        await GoogleSheetsHelper.updateBreakRecordById(
          spreadsheetId: _sheetId!,
          date: date,
          userId: userId,
          userName: user.name,
          area: area,
          division: division,
          time: entry.value,
        );
      }
      showSuccessSnackbar(context, 'Google Sheets에 저장 완료');
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
        title: const Text('휴식 캘린더', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    onPageChanged: (focusedDay) async {
                      setState(() {
                        _focusedDay = focusedDay;
                      });

                      if (_selectedUser != null) {
                        await _loadBreakTimes(_selectedUser!);
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
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.grey),
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
      isScrollControlled: true,
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
}
