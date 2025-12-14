// lib/screens/head_package/hr_package/attendance_calendar.dart
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../states/head_quarter/calendar_selection_state.dart';
import '../../../../models/user_model.dart';
import '../../../../utils/api/email_config.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../repositories/commute_log_repository.dart';
import '../../../../utils/google_auth_session.dart';
import 'utils/calendar_excel_mailer.dart';
import 'mail_recipient_settings.dart';
import 'widgets/time_edit_sheet.dart';

/// 출석 캘린더 (Firestore 기반)
/// - asBottomSheet=true: 아래에서 92% 높이로 올라오는 바텀시트 UI
/// - [AttendanceCalendar.showAsBottomSheet] 헬퍼로 간편 호출
class AttendanceCalendar extends StatefulWidget {
  const AttendanceCalendar({super.key, this.asBottomSheet = false});

  /// true면 AppBar 대신 시트 전용 헤더(핸들/닫기/액션)를 사용
  final bool asBottomSheet;

  /// 바텀시트(92%)로 열기
  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _BottomSheetFrame(
            heightFactor: 1, // ✅ 진짜 바텀시트 느낌(전체 화면 X)
            child: AttendanceCalendar(asBottomSheet: true),
          ),
        );
      },
    );
  }

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
  bool _isSendingMail = false;

  // 현재 화면에 표시되는 월의 출근/퇴근 day->time
  Map<int, String> _clockInMap = {};
  Map<int, String> _clockOutMap = {};

  // 로드 기준(Dirty 체크용)
  Map<int, String> _loadedClockInMap = {};
  Map<int, String> _loadedClockOutMap = {};

  // 저장 시 삭제 요청(00:00 처리 등)
  final Set<String> _pendingDeleteInDates = <String>{};
  final Set<String> _pendingDeleteOutDates = <String>{};

  // 캐시(유저+월)
  final Map<String, Map<int, String>> _inCache = {};
  final Map<String, Map<int, String>> _outCache = {};
  final Map<String, Map<int, String>> _inLoadedCache = {};
  final Map<String, Map<int, String>> _outLoadedCache = {};

  final CommuteLogRepository _repo = CommuteLogRepository();

  // 안전한 스낵바 호출(빌드 이후에만)
  void _showFailedAfterBuild(String msg) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showFailedSnackbar(context, msg);
    });
  }

  @override
  void initState() {
    super.initState();

    _userInputCtrl.addListener(() => setState(() {}));

    final calendarState = context.read<CalendarSelectionState>();
    final presetUser = calendarState.selectedUser;

    if (presetUser != null) {
      _selectedUser = presetUser;
      final area = presetUser.selectedArea?.trim() ?? '';
      _userInputCtrl.text = area.isEmpty ? presetUser.phone : '${presetUser.phone}-$area';

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _loadAttendanceTimes(presetUser);
      });
    }
  }

  @override
  void dispose() {
    _userInputCtrl.dispose();
    _userInputFocus.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _selectedUser = null;
      _userInputCtrl.clear();

      _clockInMap.clear();
      _clockOutMap.clear();
      _loadedClockInMap.clear();
      _loadedClockOutMap.clear();

      _pendingDeleteInDates.clear();
      _pendingDeleteOutDates.clear();

      _inCache.clear();
      _outCache.clear();
      _inLoadedCache.clear();
      _outLoadedCache.clear();

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
      // 1) 정확한 docId가 주어진 경우 우선 조회
      if (area != null && area.isNotEmpty) {
        final docId = '$phone-$area';
        final doc = await col.doc(docId).get();

        if (doc.exists && doc.data() != null) {
          return UserModel.fromMap(doc.id, doc.data()!);
        }
      }

      // 2) phone으로 다건 조회
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
        builder: (sheetCtx) {
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
                  final a = u.selectedArea ?? '-';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _light,
                      foregroundColor: _fg,
                      child: const Icon(Icons.person),
                    ),
                    title: Text('${u.name}  •  $a'),
                    subtitle: Text(u.phone),
                    onTap: () => Navigator.pop(sheetCtx, u),
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
        _showFailedAfterBuild('사용자를 찾지 못했습니다. 예) 11100000000 또는 11100000000-belivus');
        return;
      }

      context.read<CalendarSelectionState>().setUser(user);
      setState(() {
        _selectedUser = user;

        _clockInMap.clear();
        _clockOutMap.clear();
        _loadedClockInMap.clear();
        _loadedClockOutMap.clear();

        _pendingDeleteInDates.clear();
        _pendingDeleteOutDates.clear();

        final area = user.selectedArea?.trim() ?? '';
        _userInputCtrl.text = area.isEmpty ? user.phone : '${user.phone}-$area';
      });

      await _loadAttendanceTimes(user);
      _userInputFocus.unfocus();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  String _userIdOf(UserModel user) {
    final area = (user.selectedArea ?? '').trim();
    return '${user.phone}-$area';
  }

  String _cacheKey(String userId) => '$userId-${_focusedDay.year}-${_focusedDay.month}';

  String _dateStr(int day) =>
      '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  bool _mapEquals(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _loadAttendanceTimes(UserModel user) async {
    final userId = _userIdOf(user);
    final cacheKey = _cacheKey(userId);

    // 캐시 우선
    if (_inCache.containsKey(cacheKey) && _outCache.containsKey(cacheKey)) {
      final inMap = {..._inCache[cacheKey]!};
      final outMap = {..._outCache[cacheKey]!};

      final inLoaded = {...(_inLoadedCache[cacheKey] ?? inMap)};
      final outLoaded = {...(_outLoadedCache[cacheKey] ?? outMap)};

      if (!mounted) return;
      setState(() {
        _clockInMap = inMap;
        _clockOutMap = outMap;
        _loadedClockInMap = inLoaded;
        _loadedClockOutMap = outLoaded;
        _pendingDeleteInDates.clear();
        _pendingDeleteOutDates.clear();
      });
      return;
    }

    try {
      final inMap = await _repo.getMonthlyTimes(
        status: '출근',
        userId: userId,
        year: _focusedDay.year,
        month: _focusedDay.month,
      );
      final outMap = await _repo.getMonthlyTimes(
        status: '퇴근',
        userId: userId,
        year: _focusedDay.year,
        month: _focusedDay.month,
      );

      if (!mounted) return;
      setState(() {
        _clockInMap = {...inMap};
        _clockOutMap = {...outMap};

        _loadedClockInMap = {...inMap};
        _loadedClockOutMap = {...outMap};

        _pendingDeleteInDates.clear();
        _pendingDeleteOutDates.clear();

        _inCache[cacheKey] = {...inMap};
        _outCache[cacheKey] = {...outMap};
        _inLoadedCache[cacheKey] = {...inMap};
        _outLoadedCache[cacheKey] = {...outMap};
      });
    } catch (e) {
      _showFailedAfterBuild('출퇴근 기록 로드 실패(Firestore): $e');
    }
  }

  Future<void> _saveAllChangesToFirestore() async {
    if (_selectedUser == null) return;

    final user = _selectedUser!;
    final userId = _userIdOf(user);
    final area = (user.selectedArea ?? '').trim();
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

    final changed = !_mapEquals(_clockInMap, _loadedClockInMap) ||
        !_mapEquals(_clockOutMap, _loadedClockOutMap) ||
        _pendingDeleteInDates.isNotEmpty ||
        _pendingDeleteOutDates.isNotEmpty;

    if (!changed) {
      showSelectedSnackbar(context, '변경된 내용이 없습니다.');
      return;
    }

    // 업서트 payload
    final inPayload = <String, String>{};
    for (final e in _clockInMap.entries) {
      final ds = _dateStr(e.key);
      final t = e.value.trim();
      if (t.isNotEmpty) inPayload[ds] = t;
    }

    final outPayload = <String, String>{};
    for (final e in _clockOutMap.entries) {
      final ds = _dateStr(e.key);
      final t = e.value.trim();
      if (t.isNotEmpty) outPayload[ds] = t;
    }

    try {
      // 1) 업서트
      if (inPayload.isNotEmpty) {
        await _repo.upsertLogsForDates(
          status: '출근',
          userId: userId,
          userName: user.name,
          area: area,
          division: division,
          dateToTime: inPayload,
        );
      }
      if (outPayload.isNotEmpty) {
        await _repo.upsertLogsForDates(
          status: '퇴근',
          userId: userId,
          userName: user.name,
          area: area,
          division: division,
          dateToTime: outPayload,
        );
      }

      // 2) 삭제(00:00 등)
      if (_pendingDeleteInDates.isNotEmpty) {
        await _repo.deleteLogsForDates(
          status: '출근',
          userId: userId,
          dateStrs: _pendingDeleteInDates,
        );
      }
      if (_pendingDeleteOutDates.isNotEmpty) {
        await _repo.deleteLogsForDates(
          status: '퇴근',
          userId: userId,
          dateStrs: _pendingDeleteOutDates,
        );
      }

      showSuccessSnackbar(context, 'Firestore에 저장 완료');

      // 로드 기준/캐시 갱신
      final cacheKey = _cacheKey(userId);
      setState(() {
        _loadedClockInMap = {..._clockInMap};
        _loadedClockOutMap = {..._clockOutMap};
        _pendingDeleteInDates.clear();
        _pendingDeleteOutDates.clear();

        _inCache[cacheKey] = {..._clockInMap};
        _outCache[cacheKey] = {..._clockOutMap};
        _inLoadedCache[cacheKey] = {..._loadedClockInMap};
        _outLoadedCache[cacheKey] = {..._loadedClockOutMap};
      });
    } catch (e) {
      _showFailedAfterBuild('저장 실패(Firestore): $e');
    }
  }

  Future<void> _openMailRecipientSettings() async {
    await MailRecipientSettings.showAsBottomSheet(context);
  }

  /// 메일 발송 전 수신자(To) 설정 여부/유효성 검사
  Future<bool> _ensureRecipientConfigured() async {
    try {
      final cfg = await EmailConfig.load();
      final to = cfg.to.trim();
      if (EmailConfig.isValidToList(to)) return true;

      _showFailedAfterBuild('메일 수신자(To)가 설정되어 있지 않습니다. 수신자 설정에서 등록하세요.');
      await _openMailRecipientSettings();
      return false;
    } catch (e) {
      _showFailedAfterBuild('수신자(To) 설정 확인 실패: $e');
      return false;
    }
  }

  Future<void> _sendMonthlyExcelMail() async {
    if (_selectedUser == null) {
      _showFailedAfterBuild('사용자를 먼저 선택하세요.');
      return;
    }
    if (_isSendingMail) return;

    // ✅ 수신자 설정 확인
    final ok = await _ensureRecipientConfigured();
    if (!ok) return;

    setState(() => _isSendingMail = true);
    try {
      final user = _selectedUser!;
      final userId = _userIdOf(user);

      await CalendarExcelMailer.sendAttendanceMonthExcel(
        year: _focusedDay.year,
        month: _focusedDay.month,
        userId: userId,
        userName: user.name,
        clockInByDay: _clockInMap,
        clockOutByDay: _clockOutMap,
      );

      showSuccessSnackbar(context, '메일 발송 완료');
    } catch (e) {
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        _showFailedAfterBuild('구글 계정 연결이 만료되었습니다. 다시 로그인 후 시도하세요.');
      } else {
        _showFailedAfterBuild('메일 발송 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _isSendingMail = false);
    }
  }

  Widget _recipientSettingsButton() {
    return IconButton(
      tooltip: '메일 수신자(To) 설정',
      onPressed: _openMailRecipientSettings,
      icon: const Icon(Icons.alternate_email_rounded),
    );
  }

  Widget _mailActionButton() {
    return IconButton(
      tooltip: '엑셀 첨부 메일 발송',
      onPressed: (_selectedUser == null || _isSendingMail) ? null : _sendMonthlyExcelMail,
      icon: _isSendingMail
          ? const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      )
          : const Icon(Icons.mail_outline_rounded),
    );
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
    // 공통 본문(페이지/시트 공용)
    final body = CustomScrollView(
      slivers: [
        // Legend
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

        // User Picker
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

        // Month Navigator
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: _MonthSelector(
              focusedDay: _focusedDay,
              onPrev: () async {
                final prev = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                setState(() => _focusedDay = prev);
                if (_selectedUser != null) await _loadAttendanceTimes(_selectedUser!);
              },
              onNext: () async {
                final next = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                setState(() => _focusedDay = next);
                if (_selectedUser != null) await _loadAttendanceTimes(_selectedUser!);
              },
              color: _base,
            ),
          ),
        ),

        // Calendar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              elevation: 1,
              surfaceTintColor: _light,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
                child: TableCalendar(
                  firstDay: DateTime.utc(2025, 1, 1),
                  lastDay: DateTime.utc(2025, 12, 31),
                  focusedDay: _focusedDay,
                  rowHeight: 84,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) async {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    if (_selectedUser != null) {
                      await _showEditBottomSheet(selectedDay);
                    }
                  },
                  onPageChanged: (focusedDay) async {
                    setState(() => _focusedDay = focusedDay);
                    if (_selectedUser != null) {
                      await _loadAttendanceTimes(_selectedUser!);
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

        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );

    // 저장 FAB
    final fab = _selectedUser == null
        ? null
        : FloatingActionButton.extended(
      onPressed: _saveAllChangesToFirestore,
      backgroundColor: _base,
      foregroundColor: _fg,
      icon: const Icon(Icons.save_rounded),
      label: const Text('변경사항 저장'),
    );

    // ===== 페이지 모드 =====
    if (!widget.asBottomSheet) {
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
            _recipientSettingsButton(),
            _mailActionButton(),
            IconButton(
              tooltip: '전체 지우기',
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAll,
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1),
          ),
        ),
        floatingActionButton: fab,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: body,
      );
    }

    // ===== 바텀시트 모드 =====
    return _SheetScaffold(
      title: '출석 캘린더',
      onClose: () => Navigator.of(context).maybePop(),
      body: body,
      trailingActions: [
        _recipientSettingsButton(),
        _mailActionButton(),
        IconButton(
          tooltip: '전체 지우기',
          icon: const Icon(Icons.delete_sweep),
          onPressed: _clearAll,
        ),
      ],
      fab: fab,
      fabAlignment: Alignment.bottomRight,
      fabLift: 20,
      fabPadding: const EdgeInsets.only(right: 16, bottom: 16),
    );
  }

  // Calendar Cell with adaptive sizing
  // - 출근(in) 시간은 "윗행", 퇴근(out) 시간은 "아랫행"
  // - outside day(다른 달)는 현재 달 데이터가 섞이지 않도록 시간 표시를 비움
  Widget _buildCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday = isSameDay(day, DateTime.now());

    final bool isInFocusedMonth = (day.year == _focusedDay.year && day.month == _focusedDay.month);

    final inTime = isInFocusedMonth ? (_clockInMap[day.day] ?? '') : '';
    final outTime = isInFocusedMonth ? (_clockOutMap[day.day] ?? '') : '';

    final hasIn = inTime.isNotEmpty;
    final hasOut = outTime.isNotEmpty;

    final Color statusColor = (hasIn && hasOut)
        ? _success
        : (hasIn || hasOut)
        ? _warning
        : Colors.black38;

    final Color borderColor = isSelected ? _base : (isToday ? _light : Colors.black12);

    return LayoutBuilder(
      builder: (context, c) {
        final baseSide = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;

        final dayFs = (baseSide * 0.40).clamp(14.0, 22.0);
        final timeFs = (baseSide * 0.32).clamp(12.0, 18.0);
        final smallFs = (baseSide * 0.26).clamp(10.0, 16.0);
        final vGap = (baseSide * 0.10).clamp(2.0, 8.0);

        Text _timeText(String t, {required bool strong}) => Text(
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
                offset: const Offset(0, 2),
              )
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
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                ),

                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                          _timeText(hasIn ? inTime : '—', strong: hasIn),
                          const SizedBox(height: 2),
                          _timeText(hasOut ? outTime : '—', strong: hasOut),
                        ] else
                          Text('—', style: TextStyle(fontSize: smallFs, color: Colors.black38)),
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

  Future<void> _showEditBottomSheet(DateTime day) async {
    final dayKey = day.day;

    final inTime = _clockInMap[dayKey] ?? '00:00';
    final outTime = _clockOutMap[dayKey] ?? '00:00';

    final res = await showAttendanceTimeSheet(
      context: context,
      date: day,
      initialInTime: inTime,
      initialOutTime: outTime,
    );
    if (res == null) return;

    final dateStr = _dateStr(dayKey);

    setState(() {
      // 출근
      final inT = res.inTime.trim();
      if (inT.isEmpty || inT == '00:00') {
        _clockInMap.remove(dayKey);
        _pendingDeleteInDates.add(dateStr);
      } else {
        _clockInMap[dayKey] = inT;
        _pendingDeleteInDates.remove(dateStr);
      }

      // 퇴근
      final outT = res.outTime.trim();
      if (outT.isEmpty || outT == '00:00') {
        _clockOutMap.remove(dayKey);
        _pendingDeleteOutDates.add(dateStr);
      } else {
        _clockOutMap[dayKey] = outT;
        _pendingDeleteOutDates.remove(dateStr);
      }
    });
  }
}

/// ===== 가변 높이 바텀시트 프레임 =====
class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({
    required this.child,
    this.heightFactor = 1,
  });

  final Widget child;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: heightFactor,
      widthFactor: 1.0,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 8,
                color: Color(0x33000000),
                offset: Offset(0, 8),
              ),
            ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.white,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== 바텀시트 전용 스캐폴드 =====
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.onClose,
    required this.body,
    this.trailingActions,
    this.fab,
    this.fabAlignment = Alignment.bottomCenter,
    this.fabLift = 24.0,
    this.fabPadding = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget>? trailingActions;
  final Widget body;

  final Widget? fab;
  final Alignment fabAlignment;
  final double fabLift;
  final EdgeInsets fabPadding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingActions != null) ...trailingActions!,
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
            const SizedBox(height: 64),
          ],
        ),
        if (fab != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Align(
                alignment: fabAlignment,
                child: Transform.translate(
                  offset: Offset(0, -fabLift),
                  child: Padding(
                    padding: fabPadding,
                    child: fab!,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Legend row ➜ Wrap
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                suffix: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 56, maxWidth: suffixWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (controller.text.isNotEmpty)
                        IconButton(
                          tooltip: '입력 지우기',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
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
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
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
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _chip(Icons.badge, user.name, bg: Colors.white, fg: Colors.black87),
                  const SizedBox(width: 8),
                  _chip(Icons.phone, user.phone, bg: Colors.white, fg: Colors.black87),
                  if (area.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.place, area, bg: light.withOpacity(.18), fg: dark),
                  ],
                  if (division.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(Icons.apartment, division, bg: light.withOpacity(.18), fg: dark),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, {required Color bg, required Color fg}) {
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
          Text(
            label,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w700),
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
    final ym = '${focusedDay.year}.${focusedDay.month.toString().padLeft(2, '0')}';
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
