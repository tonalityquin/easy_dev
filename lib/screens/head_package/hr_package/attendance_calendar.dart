// lib/screens/head_package/hr_package/attendance_calendar.dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'attendances/time_edit_bottom_sheet.dart';
import 'utils/google_sheets_helper.dart';
import '../../../states/head_quarter/calendar_selection_state.dart';
import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/sheets_config.dart';

class AttendanceCalendar extends StatefulWidget {
  const AttendanceCalendar({super.key});

  @override
  State<AttendanceCalendar> createState() => _AttendanceCalendarState();
}

class _AttendanceCalendarState extends State<AttendanceCalendar> {
  // ── Deep Blue Palette + semantic accents
  static const _base = Color(0xFF0D47A1); // primary
  static const _dark = Color(0xFF09367D); // emphasized text/icons
  static const _light = Color(0xFF5472D3); // tone/border
  static const _fg = Color(0xFFFFFFFF); // foreground
  static const _success = Color(0xFF2E7D32);
  static const _warning = Color(0xFFF9A825);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  UserModel? _selectedUser;

  final TextEditingController _userInputCtrl = TextEditingController();
  final FocusNode _userInputFocus = FocusNode();

  bool _isSearching = false;

  Map<int, String> _clockInMap = {};
  Map<int, String> _clockOutMap = {};
  final Map<String, Map<int, String>> _inCache = {};
  final Map<String, Map<int, String>> _outCache = {};

  String? _sheetId;

  @override
  void initState() {
    super.initState();
    _loadSheetId();

    _userInputCtrl.addListener(() => setState(() {}));

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
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          maxChildSize: 1.0,
          minChildSize: 0.25,
          builder: (ctx, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '출근/퇴근/휴게 스프레드시트 ID 입력',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Google Sheets ID 또는 전체 URL',
                        helperText: 'URL 전체를 붙여넣어도 ID만 자동 추출됩니다.',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      style: FilledButton.styleFrom(
                        backgroundColor: _base,
                        foregroundColor: _fg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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

                        Navigator.pop(ctx);
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
            );
          },
        );
      },
    );
  }

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
                    leading: CircleAvatar(
                      backgroundColor: _light,
                      foregroundColor: _fg,
                      child: const Icon(Icons.person),
                    ),
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
        _userInputCtrl.text =
        area.isEmpty ? user.phone : '${user.phone}-$area';
      });
      _loadAttendanceTimes(user);
      _userInputFocus.unfocus();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadAttendanceTimes(UserModel user) async {
    if (_sheetId == null || _sheetId!.isEmpty) {
      showFailedSnackbar(
          context, '스프레드시트 ID가 설정되지 않았습니다. 우측 상단 버튼으로 설정해 주세요.');
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
      final allRows =
      await GoogleSheetsHelper.loadClockInOutRecordsById(_sheetId!);

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

  // ── 가변 suffix 영역 폭(오버플로우 방지)
  double get _suffixWidth {
    final hasText = _userInputCtrl.text.isNotEmpty;
    final hasSpinner = _isSearching;
    double w = 56; // 기본(아이콘 1개)
    if (hasText) w += 36; // 지우기 버튼
    if (hasSpinner) {
      w += 28; // 스피너 여유
    } else {
      w += 36; // 검색 버튼
    }
    return w.clamp(56, 160).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: const Text('출석 캘린더', style: TextStyle(fontWeight: FontWeight.w800)),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(.06)),
        ),
      ),

      // ✅ 저장을 FAB로 변경
      floatingActionButton: _selectedUser == null
          ? null
          : FloatingActionButton.extended(
        onPressed: _saveAllChangesToSheets,
        backgroundColor: _base,
        foregroundColor: _fg,
        icon: const Icon(Icons.save_rounded),
        label: const Text('변경사항 저장'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      body: CustomScrollView(
        slivers: [
          // ── Legend
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: _LegendRow(
                success: _success,
                warning: _warning,
                light: _light,
                base: _base,
              ),
            ),
          ),

          // ── User Picker
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _UserPickerCard(
                controller: _userInputCtrl,
                focusNode: _userInputFocus,
                suffixWidth: _suffixWidth,
                isSearching: _isSearching,
                onSearch: _onSearchUserPressed,
                selectedUser: _selectedUser,
                onClearUser: _clearAll,
                paletteBase: _base,
                paletteDark: _dark,
                paletteLight: _light,
              ),
            ),
          ),

          // ── Month Navigator
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: _MonthSelector(
                focusedDay: _focusedDay,
                onPrev: () {
                  final prev =
                  DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                  setState(() => _focusedDay = prev);
                  if (_selectedUser != null) _loadAttendanceTimes(_selectedUser!);
                },
                onNext: () {
                  final next =
                  DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                  setState(() => _focusedDay = next);
                  if (_selectedUser != null) _loadAttendanceTimes(_selectedUser!);
                },
                color: _base,
              ),
            ),
          ),

          // ── Calendar
          SliverToBoxAdapter(
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Card(
                elevation: 1,
                surfaceTintColor: _light,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2025, 1, 1),
                    lastDay: DateTime.utc(2025, 12, 31),
                    focusedDay: _focusedDay,
                    rowHeight: 84,
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
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: true,
                      isTodayHighlighted: false,
                      cellMargin: const EdgeInsets.all(4),
                      defaultDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      outsideDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                        color: Colors.black.withOpacity(.02),
                      ),
                      weekendDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                        color: _light.withOpacity(.05),
                      ),
                      selectedDecoration: BoxDecoration(
                        color: _base.withOpacity(.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _base, width: 1.6),
                      ),
                      todayDecoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _light, width: 1.2),
                      ),
                    ),
                    headerStyle: const HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                      headerPadding: EdgeInsets.only(bottom: 6),
                    ),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: _buildCell,
                      todayBuilder: _buildCell,
                      selectedBuilder: _buildCell,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // FAB와 겹치지 않도록 바닥 여백
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  // ── Calendar Cell with adaptive sizing
  Widget _buildCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday = isSameDay(day, DateTime.now());

    final inTime = _clockInMap[day.day] ?? '';
    final outTime = _clockOutMap[day.day] ?? '';

    final hasIn = inTime.isNotEmpty;
    final hasOut = outTime.isNotEmpty;

    final Color statusColor = (hasIn && hasOut)
        ? _success
        : (hasIn || hasOut)
        ? _warning
        : Colors.black38;

    final Color borderColor =
    isSelected ? _base : (isToday ? _light : Colors.black12);

    return LayoutBuilder(
      builder: (context, c) {
        final baseSide = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;

        // 폰트/간격을 셀 크기에 따라 자동 조절
        final dayFs = (baseSide * 0.40).clamp(14.0, 22.0); // 날짜 숫자
        final timeFs = (baseSide * 0.32).clamp(12.0, 18.0); // 시간 숫자
        final smallFs = (baseSide * 0.26).clamp(10.0, 16.0); // 축약/대시
        final vGap = (baseSide * 0.10).clamp(2.0, 8.0);

        final bool singleLineCompact = baseSide < 50;

        Text _timeText(String t, {bool strong = true}) => Text(
          t,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            fontSize: timeFs,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
            color: strong ? Colors.black87 : Colors.black45,
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: .2,
          ),
        );

        return Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? _base.withOpacity(.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.6 : (isToday ? 1.2 : 1.0),
            ),
            boxShadow: isSelected
                ? [
              BoxShadow(
                  color: _base.withOpacity(.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Stack(
              children: [
                // 상태 점
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: (baseSide * 0.13).clamp(6.0, 10.0),
                    height: (baseSide * 0.13).clamp(6.0, 10.0),
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle),
                  ),
                ),

                // 본문
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 날짜 숫자
                        Text(
                          '${day.day}',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isSelected ? _dark : Colors.black87,
                            fontSize: dayFs,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),

                        SizedBox(height: vGap),

                        if (hasIn || hasOut) ...[
                          if (singleLineCompact)
                            Text(
                              '${hasIn ? inTime : '—'} · ${hasOut ? outTime : '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: smallFs,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                letterSpacing: .2,
                              ),
                            )
                          else ...[
                            _timeText(hasIn ? inTime : '—', strong: hasIn),
                            const SizedBox(height: 2),
                            _timeText(hasOut ? outTime : '—', strong: hasOut),
                          ]
                        ] else
                          Text(
                            '—',
                            style:
                            TextStyle(fontSize: smallFs, color: Colors.black38),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

/// Legend row  ➜ Wrap (자동 줄바꿈)
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.success,
    required this.warning,
    required this.light,
    required this.base,
  });

  final Color success;
  final Color warning;
  final Color light;
  final Color base;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );

    Widget itemDot(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(c),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );

    Widget itemSquare(String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            border: Border.all(color: base, width: 1.6),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: light.withOpacity(.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: light.withOpacity(.24)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          itemDot(success, '완료(출·퇴근)'),
          itemDot(warning, '부분(누락)'),
          itemDot(Colors.black38, '기록 없음'),
          itemSquare('선택/오늘 강조'),
        ],
      ),
    );
  }
}

/// User Picker Card + Selected User Summary
class _UserPickerCard extends StatelessWidget {
  const _UserPickerCard({
    required this.controller,
    required this.focusNode,
    required this.suffixWidth,
    required this.isSearching,
    required this.onSearch,
    required this.selectedUser,
    required this.onClearUser,
    required this.paletteBase,
    required this.paletteDark,
    required this.paletteLight,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double suffixWidth;
  final bool isSearching;
  final VoidCallback onSearch;
  final UserModel? selectedUser;
  final VoidCallback onClearUser;
  final Color paletteBase;
  final Color paletteDark;
  final Color paletteLight;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      surfaceTintColor: paletteLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSearch(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                labelText: '사용자 (전화번호 또는 전화번호-지역)',
                hintText: '예) 11100000000 또는 11100000000-belivus',
                filled: true,
                fillColor: paletteLight.withOpacity(.06),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: paletteLight.withOpacity(.35)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: paletteBase, width: 1.6),
                ),
                prefixIcon: const Icon(Icons.person_search),
                // suffixIcon 대신 suffix + ConstrainedBox (폭 유연)
                suffix: ConstrainedBox(
                  constraints:
                  BoxConstraints(minWidth: 56, maxWidth: suffixWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (controller.text.isNotEmpty)
                        IconButton(
                          tooltip: '입력 지우기',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 32),
                          iconSize: 18,
                          icon: const Icon(Icons.clear),
                          onPressed: () => controller.clear(),
                        ),
                      if (isSearching)
                        const Padding(
                          padding: EdgeInsets.only(left: 6, right: 4),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          tooltip: '찾기',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 32, height: 32),
                          iconSize: 18,
                          icon: const Icon(Icons.search),
                          onPressed: onSearch,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (selectedUser != null) ...[
              const SizedBox(height: 12),
              _SelectedUserRow(
                user: selectedUser!,
                onClear: onClearUser,
                base: paletteBase,
                dark: paletteDark,
                light: paletteLight,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedUserRow extends StatelessWidget {
  const _SelectedUserRow({
    required this.user,
    required this.onClear,
    required this.base,
    required this.dark,
    required this.light,
  });

  final UserModel user;
  final VoidCallback onClear;
  final Color base;
  final Color dark;
  final Color light;

  @override
  Widget build(BuildContext context) {
    final area = (user.selectedArea ?? '').trim();
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: light.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: light.withOpacity(.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: base,
            foregroundColor: Colors.white,
            child: const Icon(Icons.person),
          ),
          const SizedBox(width: 12),

          // ✅ 칩들을 '가로 스크롤 한 줄'로
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _chip(Icons.badge, user.name,
                      bg: Colors.white, fg: Colors.black87),
                  const SizedBox(width: 8),
                  _chip(Icons.phone, user.phone,
                      bg: Colors.white, fg: Colors.black87),
                  if (area.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.place, area,
                        bg: light.withOpacity(.18), fg: dark),
                  ],
                  if (division.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.apartment, division,
                        bg: light.withOpacity(.18), fg: dark),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close),
            label: const Text('해제'),
            style: OutlinedButton.styleFrom(
              foregroundColor: dark,
              side: BorderSide(color: dark.withOpacity(.6)),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label,
      {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg.withOpacity(.85)),
          const SizedBox(width: 6),
          // ✅ 한 줄 고정
          Text(
            label,
            softWrap: false,
            overflow: TextOverflow.fade,
            style:
            TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.focusedDay,
    required this.onPrev,
    required this.onNext,
    required this.color,
  });

  final DateTime focusedDay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ym =
        '${focusedDay.year}.${focusedDay.month.toString().padLeft(2, '0')}';
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.24)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: '이전 달',
          ),
          Expanded(
            child: Text(
              ym,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, color: color),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: '다음 달',
          ),
        ],
      ),
    );
  }
}
