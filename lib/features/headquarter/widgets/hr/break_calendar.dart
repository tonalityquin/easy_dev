import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../../app/config/email_config.dart';
import '../../../../features/account/domain/models/user/user_model.dart';

import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../../dashboard/applications/common/calendar_selection_state.dart';
import 'utils/calendar_excel_mailer.dart';
import 'mail_recipient_settings.dart';
import 'widgets/time_edit_sheet.dart';

class BreakCalendar extends StatefulWidget {
  const BreakCalendar({
    super.key,
    this.asBottomSheet = false,
    this.usePromptUi = false,
  });

  final bool asBottomSheet;
  final bool usePromptUi;

  static Future<T?> showAsBottomSheet<T>(
    BuildContext context, {
    bool usePromptUi = false,
  }) {
    Widget buildSheet(BuildContext sheetContext) {
      final insets = MediaQuery.of(sheetContext).viewInsets;
      return Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: _BottomSheetFrame(
          heightFactor: 1,
          child: BreakCalendar(
            asBottomSheet: true,
            usePromptUi: usePromptUi,
          ),
        ),
      );
    }

    if (usePromptUi) {
      return showPromptOverlayBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: buildSheet,
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: buildSheet,
    );
  }

  @override
  State<BreakCalendar> createState() => _BreakCalendarState();
}

class _BreakCalendarState extends State<BreakCalendar> {
  PromptUiTokens get _tokens => PromptUiTheme.of(context);
  Color get _base => _tokens.accent;
  Color get _dark => _tokens.accentPressed;
  Color get _light => _tokens.accentContainer;
  Color get _fg => _tokens.onAccent;

  static const int _yearRangePadding = 5;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  UserModel? _selectedUser;

  final TextEditingController _userInputCtrl = TextEditingController();
  final FocusNode _userInputFocus = FocusNode();

  Map<int, String> _breakTimeMap = {};
  Map<int, String> _loadedBreakTimeMap = {};

  final Set<String> _pendingDeleteBreakDates = <String>{};

  final Map<String, Map<int, String>> _breakTimeCache = {};
  final Map<String, Map<int, String>> _breakLoadedCache = {};

  bool _isSearching = false;
  bool _isSendingMail = false;

  final CommuteLogRepository _repo = CommuteLogRepository();

  int _clampYear(int y) {
    if (y < 1) return 1;
    if (y > 9999) return 9999;
    return y;
  }

  DateTime get _calendarFirstDay =>
      DateTime(_clampYear(_focusedDay.year - _yearRangePadding), 1, 1);

  DateTime get _calendarLastDay =>
      DateTime(_clampYear(_focusedDay.year + _yearRangePadding), 12, 31);

  @override
  void initState() {
    super.initState();

    _userInputCtrl.addListener(() => setState(() {}));

    final calendarState = context.read<CalendarSelectionState>();
    final presetUser = calendarState.selectedUser;
    if (presetUser != null) {
      _selectedUser = presetUser;
      final area = presetUser.selectedArea?.trim() ?? '';
      _userInputCtrl.text =
          area.isEmpty ? presetUser.phone : '${presetUser.phone}-$area';

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _loadBreakTimes(presetUser);
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
      _breakTimeMap.clear();
      _loadedBreakTimeMap.clear();
      _pendingDeleteBreakDates.clear();
      _breakTimeCache.clear();
      _breakLoadedCache.clear();
      _selectedDay = null;
      _focusedDay = DateTime.now();
    });
    context.read<CalendarSelectionState>().setUser(null);
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

    final repo = context.read<UserRepository>();

    try {
      if (area != null && area.isNotEmpty) {
        final docId = '$phone-$area';
        final user = await repo.getUserById(docId);
        if (user != null) {
          return user;
        }
      }

      final users = await repo.searchUsersByPhone(phone);
      if (users.isEmpty) return null;
      if (users.length == 1) {
        return users.first;
      }

      if (!mounted) return null;

      Widget buildUserPicker(BuildContext sheetContext) {
        final tokens = PromptUiTheme.of(sheetContext);
        return SafeArea(
          child: Material(
            color: tokens.surfaceRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PromptUiShapes.sheet),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemBuilder: (_, i) {
                final u = users[i];
                final a = u.selectedArea ?? '-';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: tokens.accentContainer,
                    foregroundColor: tokens.onAccentContainer,
                    child: const Icon(Icons.person),
                  ),
                  title: Text('${u.name}  •  $a'),
                  subtitle: Text(u.phone),
                  onTap: () => Navigator.pop(sheetContext, u),
                );
              },
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: tokens.borderSubtle,
              ),
              itemCount: users.length,
            ),
          ),
        );
      }

      final picked = widget.usePromptUi
          ? await showPromptOverlayBottomSheet<UserModel>(
              context: context,
              useSafeArea: true,
              builder: buildUserPicker,
            )
          : await showModalBottomSheet<UserModel>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: buildUserPicker,
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
        return;
      }
      context.read<CalendarSelectionState>().setUser(user);

      setState(() {
        _selectedUser = user;
        _breakTimeMap.clear();
        _loadedBreakTimeMap.clear();
        _pendingDeleteBreakDates.clear();

        final area = user.selectedArea?.trim() ?? '';
        _userInputCtrl.text = area.isEmpty ? user.phone : '${user.phone}-$area';
      });

      await _loadBreakTimes(user);
      _userInputFocus.unfocus();
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  String _userIdOf(UserModel user) {
    final area = (user.selectedArea ?? '').trim();
    return '${user.phone}-$area';
  }

  String _cacheKey(String userId) =>
      '$userId-${_focusedDay.year}-${_focusedDay.month}';

  String _dateStr(int day) =>
      '${_focusedDay.year}-${_focusedDay.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  bool _mapEquals(Map<int, String> a, Map<int, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _loadBreakTimes(UserModel user) async {
    final userId = _userIdOf(user);
    final cacheKey = _cacheKey(userId);

    if (_breakTimeCache.containsKey(cacheKey)) {
      final map = {..._breakTimeCache[cacheKey]!};
      final loaded = {...(_breakLoadedCache[cacheKey] ?? map)};

      if (!mounted) return;
      setState(() {
        _breakTimeMap = map;
        _loadedBreakTimeMap = loaded;
        _pendingDeleteBreakDates.clear();
      });
      return;
    }

    try {
      final map = await _repo.getMonthlyTimes(
        status: '휴게',
        userId: userId,
        year: _focusedDay.year,
        month: _focusedDay.month,
      );

      if (!mounted) return;
      setState(() {
        _breakTimeMap = {...map};
        _loadedBreakTimeMap = {...map};
        _pendingDeleteBreakDates.clear();
        _breakTimeCache[cacheKey] = {...map};
        _breakLoadedCache[cacheKey] = {...map};
      });
    } catch (_) {}
  }

  Future<bool> _persistAllChangesToFirestore() async {
    if (_selectedUser == null) return false;

    final user = _selectedUser!;
    final userId = _userIdOf(user);
    final area = (user.selectedArea ?? '').trim();
    final division = user.divisions.isNotEmpty ? user.divisions.first : '';

    final changed = !_mapEquals(_breakTimeMap, _loadedBreakTimeMap) ||
        _pendingDeleteBreakDates.isNotEmpty;

    if (!changed) {
      return true;
    }

    final payload = <String, String>{};
    for (final e in _breakTimeMap.entries) {
      final ds = _dateStr(e.key);
      final t = e.value.trim();
      if (t.isNotEmpty) payload[ds] = t;
    }

    try {
      if (payload.isNotEmpty) {
        await _repo.upsertLogsForDates(
          status: '휴게',
          userId: userId,
          userName: user.name,
          area: area,
          division: division,
          dateToTime: payload,
        );
      }

      if (_pendingDeleteBreakDates.isNotEmpty) {
        await _repo.deleteLogsForDates(
          status: '휴게',
          userId: userId,
          dateStrs: _pendingDeleteBreakDates,
        );
      }

      final cacheKey = _cacheKey(userId);
      if (!mounted) return true;
      setState(() {
        _loadedBreakTimeMap = {..._breakTimeMap};
        _pendingDeleteBreakDates.clear();
        _breakTimeCache[cacheKey] = {..._breakTimeMap};
        _breakLoadedCache[cacheKey] = {..._loadedBreakTimeMap};
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveAllChangesToFirestore() async {
    await _persistAllChangesToFirestore();
  }

  Future<void> _openMailRecipientSettings() async {
    await MailRecipientSettings.showAsBottomSheet(
      context,
      usePromptUi: widget.usePromptUi,
    );
  }

  Future<bool> _ensureRecipientConfigured() async {
    try {
      final cfg = await EmailConfig.load();
      final to = cfg.to.trim();
      if (EmailConfig.isValidToList(to)) return true;

      await _openMailRecipientSettings();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendMonthlyExcelMail() async {
    if (_selectedUser == null) {
      return;
    }
    if (_isSendingMail) return;

    final ok = await _ensureRecipientConfigured();
    if (!ok) return;

    setState(() => _isSendingMail = true);
    try {
      final saved = await _persistAllChangesToFirestore();
      if (!saved) return;

      final user = _selectedUser!;
      final userId = _userIdOf(user);

      await CalendarExcelMailer.sendBreakMonthExcel(
        year: _focusedDay.year,
        month: _focusedDay.month,
        userId: userId,
        userName: user.name,
        breakByDay: _breakTimeMap,
      );
    } catch (_) {
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
      onPressed: (_selectedUser == null || _isSendingMail)
          ? null
          : _sendMonthlyExcelMail,
      icon: _isSendingMail
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.mail_outline_rounded),
    );
  }

  double get _suffixWidth {
    final hasText = _userInputCtrl.text.isNotEmpty;
    final hasSpinner = _isSearching;
    double w = 56;
    if (hasText) w += 36;
    if (hasSpinner) {
      w += 28;
    } else {
      w += 36;
    }
    return w.clamp(56, 160).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final body = CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: _LegendRowBreak(base: _base, light: _light),
          ),
        ),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: _MonthSelector(
              focusedDay: _focusedDay,
              onPrev: () async {
                final prev =
                    DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                setState(() => _focusedDay = prev);
                if (_selectedUser != null)
                  await _loadBreakTimes(_selectedUser!);
              },
              onNext: () async {
                final next =
                    DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                setState(() => _focusedDay = next);
                if (_selectedUser != null)
                  await _loadBreakTimes(_selectedUser!);
              },
              color: _base,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Card(
              elevation: 1,
              surfaceTintColor: _light,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
                child: TableCalendar(
                  firstDay: _calendarFirstDay,
                  lastDay: _calendarLastDay,
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
                      await _loadBreakTimes(_selectedUser!);
                    }
                  },
                  availableGestures: AvailableGestures.none,
                  calendarStyle: CalendarStyle(
                    outsideDaysVisible: true,
                    isTodayHighlighted: false,
                    cellMargin: const EdgeInsets.all(4),
                    defaultDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _tokens.borderSubtle),
                    ),
                    outsideDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _tokens.borderSubtle),
                      color: _tokens.surfaceOverlay,
                    ),
                    weekendDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _tokens.borderSubtle),
                      color: _light.withOpacity(.05),
                    ),
                    selectedDecoration: BoxDecoration(
                      color: _base.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _base, width: 1.6),
                    ),
                    todayDecoration: BoxDecoration(
                      color: _tokens.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _light, width: 1.2),
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
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

    final fab = _selectedUser == null
        ? null
        : FloatingActionButton.extended(
            onPressed: _saveAllChangesToFirestore,
            backgroundColor: _base,
            foregroundColor: _fg,
            icon: const Icon(Icons.save_rounded),
            label: const Text('변경사항 저장'),
          );

    if (!widget.asBottomSheet) {
      return Scaffold(
        backgroundColor: _tokens.canvas,
        appBar: AppBar(
          backgroundColor: _tokens.canvas,
          surfaceTintColor: _tokens.transparent,
          elevation: 0,
          foregroundColor: _tokens.textPrimary,
          centerTitle: true,
          title: const Text(
            '휴식 캘린더',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _tokens.borderSubtle),
          ),
        ),
        floatingActionButton: fab,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: body,
      );
    }

    return _SheetScaffold(
      title: '휴식 캘린더',
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

  Widget _buildCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday = isSameDay(day, DateTime.now());

    final bool isInFocusedMonth =
        (day.year == _focusedDay.year && day.month == _focusedDay.month);

    final breakTime = isInFocusedMonth ? (_breakTimeMap[day.day] ?? '') : '';
    final hasBreak = breakTime.isNotEmpty;

    final borderColor =
        isSelected ? _base : (isToday ? _light : _tokens.borderSubtle);

    return LayoutBuilder(
      builder: (context, c) {
        final baseSide = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;

        final dayFs = (baseSide * 0.40).clamp(14.0, 22.0);
        final timeFs = (baseSide * 0.34).clamp(12.0, 18.0);
        final smallFs = (baseSide * 0.26).clamp(10.0, 16.0);
        final vGap = (baseSide * 0.10).clamp(2.0, 8.0);
        final dot = (baseSide * 0.13).clamp(6.0, 10.0);

        return Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? _tokens.surfaceSelected : _tokens.surfaceRaised,
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
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Stack(
              children: [
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: dot,
                    height: dot,
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hasBreak ? _base : _tokens.textDisabled,
                      shape: BoxShape.circle,
                    ),
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
                            color: isSelected ? _dark : _tokens.textPrimary,
                            fontSize: dayFs,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        SizedBox(height: vGap),
                        hasBreak
                            ? Text(
                                breakTime,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: timeFs,
                                  fontWeight: FontWeight.w800,
                                  color: _tokens.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                  letterSpacing: .2,
                                ),
                              )
                            : Text(
                                '—',
                                style: TextStyle(
                                  fontSize: smallFs,
                                  color: _tokens.textDisabled,
                                ),
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

  Future<void> _showEditBottomSheet(DateTime day) async {
    final dayKey = day.day;
    final initialTime = _breakTimeMap[dayKey] ?? '00:00';

    final newTime = await showBreakTimeSheet(
      context: context,
      date: day,
      initialTime: initialTime,
    );
    if (newTime == null) return;

    final dateStr = _dateStr(dayKey);
    final t = newTime.trim();

    setState(() {
      if (t.isEmpty || t == '00:00') {
        _breakTimeMap.remove(dayKey);
        _pendingDeleteBreakDates.add(dateStr);
      } else {
        _breakTimeMap[dayKey] = t;
        _pendingDeleteBreakDates.remove(dateStr);
      }
    });
  }
}

class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({
    required this.child,
    this.heightFactor = 1,
  });

  final Widget child;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return FractionallySizedBox(
      heightFactor: heightFactor,
      widthFactor: 1.0,
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 8,
                  color: tokens.shadow,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: tokens.surfaceRaised,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
                color: PromptUiTheme.of(context).handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
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

class _LegendRowBreak extends StatelessWidget {
  const _LegendRowBreak({required this.base, required this.light});

  final Color base;
  final Color light;

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
            Text(
              t,
              style: TextStyle(
                fontSize: 12,
                color: PromptUiTheme.of(context).textPrimary,
              ),
            ),
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
            Text(
              t,
              style: TextStyle(
                fontSize: 12,
                color: PromptUiTheme.of(context).textPrimary,
              ),
            ),
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
          itemDot(base, '휴게 기록 있음'),
          itemDot(PromptUiTheme.of(context).textDisabled, '기록 없음'),
          itemSquare('선택/오늘 강조'),
        ],
      ),
    );
  }
}

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
                labelText: '전화번호 혹은 코드번호',

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
            foregroundColor: PromptUiTheme.of(context).onAccent,
            child: const Icon(Icons.person),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _chip(context, Icons.badge, user.name,
                      bg: PromptUiTheme.of(context).surfaceRaised, fg: PromptUiTheme.of(context).textPrimary),
                  const SizedBox(width: 8),
                  _chip(context, Icons.phone, user.phone,
                      bg: PromptUiTheme.of(context).surfaceRaised, fg: PromptUiTheme.of(context).textPrimary),
                  if (area.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(context, Icons.place, area,
                        bg: light.withOpacity(.18), fg: dark),
                  ],
                  if (division.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _chip(context, Icons.apartment, division,
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label,
      {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: PromptUiTheme.of(context).borderSubtle),
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
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w700,
            ),
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
