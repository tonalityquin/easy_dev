import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cooperation_Calendar_pages/utils/service_calendar_logic.dart';
import '../../../../utils/snackbar_helper.dart';

class CompletedTaskPage extends StatefulWidget {
  final String calendarId;

  const CompletedTaskPage({super.key, required this.calendarId});

  @override
  State<CompletedTaskPage> createState() => _CompletedTaskPageState();
}

class _CompletedTaskPageState extends State<CompletedTaskPage> {
  List<calendar.Event> _completedEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompletedEvents();
  }

  Future<void> _loadCompletedEvents() async {
    setState(() => _isLoading = true);
    try {
      final allEventsByDay = await loadEventsForMonth(
        month: DateTime.now(),
        filterStates: {},
        calendarId: widget.calendarId,
      );

      final seenIds = <String>{};
      final events = allEventsByDay.values
          .expand((list) => list)
          .where((e) => _getProgress(e.description) == 100)
          .where((e) {
        final id = e.id;
        if (id == null || seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      })
          .toList();

      setState(() {
        _completedEvents = events;
      });
    } catch (e) {
      debugPrint('🚨 완료된 이벤트 로딩 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _showConfirmBottomSheet(String title, String message) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                left: 24,
                right: 24,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text(message, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text('취소'),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: commonActionButtonStyle.copyWith(
                          backgroundColor: MaterialStateProperty.all(Colors.redAccent),
                          foregroundColor: MaterialStateProperty.all(Colors.white),
                        ),
                        child: const Text('확인'),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _deleteCompletedEvents() async {
    final confirm = await _showConfirmBottomSheet(
      '삭제 확인',
      '완료된 할 일들을 모두 삭제하시겠습니까?\n\n'
          '⚠️ 삭제된 할 일들은 복구할 수 없습니다.',
    );
    if (!confirm) return;

    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);
    for (var e in _completedEvents) {
      if (e.id != null) {
        await calendarApi.events.delete(widget.calendarId, e.id!);
      }
    }

    await _loadCompletedEvents();

    if (mounted) {
      // ✅ 기본 SnackBar → 커스텀 스낵바
      showSuccessSnackbar(context, '완료된 할 일을 모두 삭제했습니다.');
    }
  }

  Future<void> _saveToGoogleSheet() async {
    final confirm = await _showConfirmBottomSheet(
      '저장 확인',
      '완료된 할 일을 저장하시겠습니까?\n\n'
          '✅ 저장 후에는 완료된 할 일들을 삭제해 주세요.',
    );
    if (!confirm) return;

    const sheetMap = {
      'belivus': '1fjN8kfBJv9_CNGSeSNq5SeU3VtvvzJn5qPKrehpk72E',
      'pelican': '17e9XbKXXlO39rgxOLB7OnbFBFI-Zy5lBYftGCXNwjxw',
    };

    final prefs = await SharedPreferences.getInstance();
    final selectedArea = prefs.getString('selectedArea') ?? 'belivus';
    final spreadsheetId = sheetMap[selectedArea] ?? sheetMap['belivus']!;
    const range = '완료!A2';
    final dateFormat = DateFormat('yyyy-MM-dd');

    try {
      final client = await getAuthClient(write: true);
      final sheetsApi = sheets.SheetsApi(client);

      final values = _completedEvents.map((event) {
        final date = event.start?.date;
        final formattedDate = date != null ? dateFormat.format(date) : '';
        return [formattedDate, event.summary ?? '', event.description ?? ''];
      }).toList();

      final valueRange = sheets.ValueRange.fromJson({"values": values});

      await sheetsApi.spreadsheets.values.append(
        valueRange,
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );

      if (mounted) {
        // ✅ 성공 스낵바
        showSuccessSnackbar(context, 'Google Sheet에 저장 완료');
      }
    } catch (e) {
      debugPrint('🚨 Google Sheet 저장 실패: $e');
      if (mounted) {
        // ✅ 실패 스낵바
        showFailedSnackbar(context, '저장 중 오류 발생');
      }
    }
  }

  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('완료된 할 일', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _completedEvents.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.inbox, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text('완료된 할 일이 없습니다.', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      )
          : ListView.builder(
        itemCount: _completedEvents.length,
        itemBuilder: (context, index) {
          final e = _completedEvents[index];
          final date = e.start?.date;
          final formattedDate = date != null ? DateFormat('yyyy-MM-dd').format(date) : '날짜 없음';
          return Card(
            color: Colors.white,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formattedDate,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.summary ?? '무제',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if ((e.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        e.description!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: _completedEvents.isEmpty
          ? null
          : Padding(
        padding: const EdgeInsets.only(bottom: 16.0, right: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'saveBtn',
              onPressed: _saveToGoogleSheet,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              icon: const Icon(Icons.upload),
              label: const Text('저장', style: TextStyle(fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'deleteBtn',
              onPressed: _deleteCompletedEvents,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              icon: const Icon(Icons.delete),
              label: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ✅ 공통 버튼 스타일 정의
final ButtonStyle commonActionButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: Colors.black87,
  textStyle: const TextStyle(fontWeight: FontWeight.bold),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  elevation: 3,
  side: const BorderSide(color: Colors.grey),
);
