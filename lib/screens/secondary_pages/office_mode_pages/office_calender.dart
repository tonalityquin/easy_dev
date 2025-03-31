import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../states/calendar/office_calendar_state.dart';
import '../../../widgets/dialog/calendar/calendar_dialogs.dart';
import '../../../utils/snackbar_helper.dart';

class OfficeCalenderPage extends StatefulWidget {
  const OfficeCalenderPage({super.key});

  @override
  State<OfficeCalenderPage> createState() => _OfficeCalenderPage();
}

class _OfficeCalenderPage extends State<OfficeCalenderPage> {
  late OfficeCalendarState calendar;
  Map<String, String> _memoMap = {};
  String? _memoKey;

  @override
  void initState() {
    super.initState();
    calendar = OfficeCalendarState();
    _initUserMemoKey();
  }

  Future<void> _initUserMemoKey() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? 'unknown';
    final area = prefs.getString('area') ?? 'unknown';
    final key = 'memoMap_${phone}_$area';

    setState(() {
      _memoKey = key;
    });

    await _loadMemoData();
  }

  Future<void> _loadMemoData() async {
    if (_memoKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_memoKey!);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _memoMap = decoded.map((key, value) => MapEntry(key, value.toString()));
      });
    }
  }

  Future<void> _saveMemoData() async {
    if (_memoKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoKey!, jsonEncode(_memoMap));
  }

  @override
  Widget build(BuildContext context) {
    final selectedMemo = _memoMap[calendar.dateKey(calendar.selectedDate)];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          "달력 기능 테스트 페이지",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildMonthNavigation(),
            _buildDayHeaders(context),
            _buildDateGrid(context),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              controller: TextEditingController(text: selectedMemo ?? ''),
              maxLines: null,
              decoration: const InputDecoration(
                labelText: '선택된 날짜의 메모',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: selectedMemo == null || selectedMemo.isEmpty ? _showMemoDialog : _showEditMemoDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedMemo == null || selectedMemo.isEmpty ? Colors.white : Colors.grey.shade200,
                    foregroundColor: selectedMemo == null || selectedMemo.isEmpty ? Colors.black : Colors.blue,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: selectedMemo == null || selectedMemo.isEmpty
                        ? const BorderSide(color: Colors.grey)
                        : BorderSide.none,
                  ),
                  child: Text(
                    selectedMemo == null || selectedMemo.isEmpty ? '메모 추가' : '메모 수정',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (selectedMemo != null && selectedMemo.isNotEmpty)
                  ElevatedButton(
                    onPressed: _deleteMemo,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('삭제', style: TextStyle(fontSize: 15)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_left),
            onPressed: () => setState(() => calendar.moveToPreviousMonth()),
          ),
          Text(
            calendar.formattedMonth,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_right),
            onPressed: () => setState(() => calendar.moveToNextMonth()),
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders(BuildContext context) {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: days.map((day) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              child: Text(
                day,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateGrid(BuildContext context) {
    final firstDay = DateTime(calendar.currentMonth.year, calendar.currentMonth.month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(calendar.currentMonth.year, calendar.currentMonth.month + 1, 0).day;
    final totalGridItems = firstWeekday + daysInMonth;

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: List.generate(totalGridItems, (index) {
        if (index < firstWeekday) return const SizedBox();

        final day = index - firstWeekday + 1;
        final currentDate = DateTime(calendar.currentMonth.year, calendar.currentMonth.month, day);
        final isSelected = calendar.isSelected(currentDate);
        final hasMemo = _memoMap.containsKey(calendar.dateKey(currentDate));

        return GestureDetector(
          onTap: () {
            setState(() {
              calendar.selectDate(currentDate);
            });
            showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(currentDate)}');
          },
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hasMemo) const Icon(Icons.push_pin, size: 14),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  void _showMemoDialog() {
    final key = calendar.dateKey(calendar.selectedDate);

    showAddMemoDialog(
      context: context,
      onSave: (tempMemo) {
        setState(() {
          _memoMap[key] = tempMemo;
        });
        _saveMemoData();
      },
    );
  }

  void _showEditMemoDialog() {
    final key = calendar.dateKey(calendar.selectedDate);
    final currentMemo = _memoMap[key] ?? '';

    showEditMemoDialog(
      context: context,
      initialMemo: currentMemo,
      onSave: (tempMemo) {
        setState(() {
          _memoMap[key] = tempMemo;
        });
        _saveMemoData();
      },
    );
  }

  void _deleteMemo() {
    final key = calendar.dateKey(calendar.selectedDate);
    setState(() {
      _memoMap.remove(key);
    });
    _saveMemoData();
    showSuccessSnackbar(context, '메모가 삭제되었습니다');
  }
}
