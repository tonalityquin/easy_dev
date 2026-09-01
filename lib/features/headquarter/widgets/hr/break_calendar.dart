import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../app/config/email_config.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_content_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/account/domain/models/user/user_model.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../../dashboard/applications/common/calendar_selection_state.dart';
import '../../../selector/application/dev_auth.dart';
import 'mail_recipient_settings.dart';
import 'utils/calendar_excel_mailer.dart';
import 'widgets/time_edit_sheet.dart';

enum BreakCalendarPresentation {
  page,
  leftSideDock,
}

enum _SaveVisualState {
  idle,
  saving,
  success,
  failure,
}

class BreakCalendar extends StatefulWidget {
  const BreakCalendar({
    super.key,
    this.presentation = BreakCalendarPresentation.page,
  });

  final BreakCalendarPresentation presentation;

  static Future<T?> showAsLeftSideDock<T>(
    BuildContext context, {
    bool useRootNavigator = false,
  }) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[BreakCalendar] side_dock_push_request side=left motion=operations_210_190 translate=-22_to_0 opacity=0.90_to_1 reduceMotion=$reduceMotion',
    );
    try {
      return await showOperationsLeftSideDock<T>(
        context: context,
        barrierLabel: '휴게 관리',
        useRootNavigator: useRootNavigator,
        maxWidth: 360,
        widthFactor: 0.92,
        barrierDismissible: true,
        builder: (_) => const BreakCalendar(
          presentation: BreakCalendarPresentation.leftSideDock,
        ),
      );
    } finally {
      debugPrint('[BreakCalendar] side_dock_closed side=left');
    }
  }

  @override
  State<BreakCalendar> createState() => _BreakCalendarState();
}

class _BreakCalendarState extends State<BreakCalendar> {
  CommonUiTokens get _tokens => CommonUiTheme.of(context);
  Color get _base => _tokens.accent;
  Color get _dark => _tokens.accentPressed;
  Color get _light => _tokens.accentContainer;
  bool get _useCommonUi =>
      widget.presentation == BreakCalendarPresentation.leftSideDock;

  static const int _yearRangePadding = 5;

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  UserModel? _selectedUser;

  final TextEditingController _userInputCtrl = TextEditingController();
  final FocusNode _userInputFocus = FocusNode();
  final CommuteLogRepository _repo = CommuteLogRepository();
  final List<String> _debugLines = <String>[];

  Map<int, String> _breakTimeMap = <int, String>{};
  Map<int, String> _loadedBreakTimeMap = <int, String>{};
  final Set<String> _pendingDeleteBreakDates = <String>{};
  final Map<String, Map<int, String>> _breakTimeCache =
      <String, Map<int, String>>{};
  final Map<String, Map<int, String>> _breakLoadedCache =
      <String, Map<int, String>>{};

  bool _isSearching = false;
  bool _isSendingMail = false;
  bool _isLoadingMonth = false;
  bool _developerMode = false;
  bool _showUserPicker = false;
  int _monthDirection = 1;
  Object? _monthLoadError;
  Object? _searchError;
  String? _searchMessage;
  _SaveVisualState _saveState = _SaveVisualState.idle;
  List<UserModel> _candidateUsers = <UserModel>[];

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
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    _userInputCtrl.addListener(_handleInputChanged);

    final calendarState = context.read<CalendarSelectionState>();
    final presetUser = calendarState.selectedUser;
    if (presetUser != null) {
      _selectedUser = presetUser;
      final area = presetUser.selectedArea?.trim() ?? '';
      _userInputCtrl.text =
          area.isEmpty ? presetUser.phone : '${presetUser.phone}-$area';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recordDebug(
        'initialized presentation=${widget.presentation.name} developerMode=$_developerMode presetUser=${presetUser != null}',
      );
      unawaited(_refreshDeveloperMode());
      if (presetUser != null) {
        unawaited(_loadBreakTimes(presetUser, reason: 'preset'));
      }
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    _userInputCtrl.removeListener(_handleInputChanged);
    _userInputCtrl.dispose();
    _userInputFocus.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    if (!mounted) return;
    setState(() {
      _searchMessage = null;
      _searchError = null;
    });
  }

  void _handleDeveloperModeChanged() {
    final enabled = DevAuth.devModeEnabled.value;
    if (!mounted || _developerMode == enabled) return;
    setState(() => _developerMode = enabled);
    _recordDebug('developer_mode_notifier=$enabled');
  }

  void _recordDebug(String message) {
    final line = '[BreakCalendar] $message';
    _debugLines.add(line);
    if (_debugLines.length > 140) {
      _debugLines.removeRange(0, _debugLines.length - 140);
    }
    debugPrint(line);
  }

  Future<void> _refreshDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    _recordDebug('developer_mode=$enabled');
    if (_developerMode == enabled) return;
    setState(() => _developerMode = enabled);
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    final media = MediaQuery.maybeOf(context);
    final user = _selectedUser;
    final area = user?.selectedArea?.trim() ?? '';
    final division = user != null && user.divisions.isNotEmpty
        ? user.divisions.first
        : '';
    _recordDebug(
      'developer_status_open presentation=${widget.presentation.name} user=${user?.name ?? '-'} area=$area division=$division month=${_monthKey(_focusedDay)} selectedDay=${_selectedDay?.day ?? -1} records=${_breakTimeMap.length} dirty=$_dirtyDayCount deletes=${_pendingDeleteBreakDates.length} cache=${_breakTimeCache.length} loading=$_isLoadingMonth monthError=${_monthLoadError != null} searching=$_isSearching searchError=${_searchError != null} candidates=${_candidateUsers.length} picker=$_showUserPicker save=${_saveState.name} mail=$_isSendingMail reduceMotion=${media?.disableAnimations ?? false}',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '휴게 관리 상태',
      initialMessage: '휴게 관리 상태를 수집하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    if (!trace.developerMode) return;
    trace.log(
      'presentation=${widget.presentation.name}, user=${user?.name ?? '-'}, userId=${user == null ? '-' : _userIdOf(user)}, area=$area, division=$division, month=${_monthKey(_focusedDay)}, selectedDay=${_selectedDay?.toIso8601String() ?? '-'}',
      progress: 0.18,
    );
    trace.log(
      'breakRecords=${_breakTimeMap.length}, loaded=${_loadedBreakTimeMap.length}, dirty=$_dirtyDayCount, pendingDeletes=${_pendingDeleteBreakDates.length}, cache=${_breakTimeCache.length}, loadedCache=${_breakLoadedCache.length}',
      progress: 0.36,
    );
    trace.log(
      'loading=$_isLoadingMonth, monthError=${_monthLoadError ?? '-'}, searching=$_isSearching, searchError=${_searchError ?? '-'}, searchMessage=${_searchMessage ?? '-'}, candidates=${_candidateUsers.length}, picker=$_showUserPicker',
      progress: 0.50,
    );
    trace.log(
      'saveState=${_saveState.name}, sendingMail=$_isSendingMail, reduceMotion=${media?.disableAnimations ?? false}',
      progress: 0.58,
    );
    final snapshot = List<String>.of(_debugLines);
    if (snapshot.isEmpty) {
      trace.log('기록된 휴게 관리 로그가 없습니다.', progress: 0.88);
    } else {
      for (var i = 0; i < snapshot.length; i++) {
        trace.log(
          snapshot[i],
          progress: 0.58 + ((i + 1) / snapshot.length) * 0.36,
        );
      }
    }
    await trace.succeed('휴게 관리 상태 수집이 완료되었습니다.');
  }

  String _monthKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}';

  String _monthLabel(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}';

  String _dockSubtitle() {
    final user = _selectedUser;
    if (user == null) return '직원을 선택해 주세요';
    final area = user.selectedArea?.trim() ?? '';
    final userLabel = area.isEmpty ? user.name : '${user.name} · $area';
    return '$userLabel · ${_monthLabel(_focusedDay)}';
  }

  int get _dirtyDayCount {
    final days = <int>{..._breakTimeMap.keys, ..._loadedBreakTimeMap.keys};
    return days.where((day) {
      return (_breakTimeMap[day] ?? '') != (_loadedBreakTimeMap[day] ?? '');
    }).length;
  }

  bool _isDirtyDay(int day) {
    return (_breakTimeMap[day] ?? '') != (_loadedBreakTimeMap[day] ?? '');
  }

  void _clearAll() {
    _recordDebug('screen_reset');
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
      _candidateUsers = <UserModel>[];
      _showUserPicker = false;
      _searchMessage = null;
      _searchError = null;
      _monthLoadError = null;
      _saveState = _SaveVisualState.idle;
    });
    context.read<CalendarSelectionState>().setUser(null);
  }

  void _beginUserChange() {
    _recordDebug('user_change_start');
    setState(() {
      _selectedUser = null;
      _userInputCtrl.clear();
      _breakTimeMap.clear();
      _loadedBreakTimeMap.clear();
      _pendingDeleteBreakDates.clear();
      _selectedDay = null;
      _candidateUsers = <UserModel>[];
      _showUserPicker = false;
      _searchMessage = null;
      _searchError = null;
      _monthLoadError = null;
      _saveState = _SaveVisualState.idle;
    });
    context.read<CalendarSelectionState>().setUser(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _userInputFocus.requestFocus();
    });
  }

  Future<List<UserModel>> _findUsersByInput(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return <UserModel>[];

    String phone = raw;
    String? area;
    final dashIdx = raw.indexOf('-');
    if (dashIdx != -1) {
      phone = raw.substring(0, dashIdx).trim();
      area = raw.substring(dashIdx + 1).trim();
    }

    final repo = context.read<UserRepository>();
    if (area != null && area.isNotEmpty) {
      final docId = '$phone-$area';
      final user = await repo.getUserById(docId);
      if (user != null) return <UserModel>[user];
    }
    return repo.searchUsersByPhone(phone);
  }

  Future<void> _onSearchUserPressed() async {
    if (_isSearching) return;
    final input = _userInputCtrl.text.trim();
    if (input.isEmpty) return;
    _recordDebug('user_search_start inputLength=${input.length}');
    setState(() {
      _isSearching = true;
      _searchMessage = null;
      _searchError = null;
      _candidateUsers = <UserModel>[];
    });
    try {
      final users = await _findUsersByInput(input);
      if (!mounted) return;
      _recordDebug('user_search_complete count=${users.length}');
      if (users.isEmpty) {
        setState(() => _searchMessage = '직원을 찾지 못했습니다.');
        return;
      }
      if (users.length == 1) {
        await _selectUser(users.first, source: 'search_single');
        return;
      }
      setState(() {
        _candidateUsers = users;
        _showUserPicker = true;
      });
      _recordDebug('user_picker_open count=${users.length}');
      _userInputFocus.unfocus();
    } catch (error, stackTrace) {
      if (!mounted) return;
      _recordDebug('user_search_failure error=$error stack=$stackTrace');
      setState(() => _searchError = error);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectUser(
    UserModel user, {
    required String source,
  }) async {
    _recordDebug(
      'user_select source=$source user=${user.name} area=${user.selectedArea ?? '-'}',
    );
    context.read<CalendarSelectionState>().setUser(user);
    setState(() {
      _selectedUser = user;
      _breakTimeMap.clear();
      _loadedBreakTimeMap.clear();
      _pendingDeleteBreakDates.clear();
      _candidateUsers = <UserModel>[];
      _showUserPicker = false;
      _searchMessage = null;
      _searchError = null;
      final area = user.selectedArea?.trim() ?? '';
      _userInputCtrl.text = area.isEmpty ? user.phone : '${user.phone}-$area';
    });
    _userInputFocus.unfocus();
    await _loadBreakTimes(user, reason: 'user_select');
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

  Future<void> _loadBreakTimes(
    UserModel user, {
    required String reason,
  }) async {
    final userId = _userIdOf(user);
    final cacheKey = _cacheKey(userId);
    _recordDebug(
      'month_load_start reason=$reason userId=$userId month=${_monthKey(_focusedDay)}',
    );

    if (_breakTimeCache.containsKey(cacheKey)) {
      final map = <int, String>{..._breakTimeCache[cacheKey]!};
      final loaded = <int, String>{...(_breakLoadedCache[cacheKey] ?? map)};
      if (!mounted) return;
      setState(() {
        _breakTimeMap = map;
        _loadedBreakTimeMap = loaded;
        _pendingDeleteBreakDates.clear();
        _monthLoadError = null;
        _isLoadingMonth = false;
      });
      _recordDebug('month_load_cache_hit records=${map.length}');
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingMonth = true;
        _monthLoadError = null;
      });
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
        _breakTimeMap = <int, String>{...map};
        _loadedBreakTimeMap = <int, String>{...map};
        _pendingDeleteBreakDates.clear();
        _breakTimeCache[cacheKey] = <int, String>{...map};
        _breakLoadedCache[cacheKey] = <int, String>{...map};
        _monthLoadError = null;
      });
      _recordDebug('month_load_remote_complete records=${map.length}');
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _monthLoadError = error);
      _recordDebug('month_load_failure error=$error stack=$stackTrace');
    } finally {
      if (mounted) setState(() => _isLoadingMonth = false);
    }
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
      _recordDebug('save_skip reason=no_changes');
      return true;
    }

    final payload = <String, String>{};
    for (final e in _breakTimeMap.entries) {
      final ds = _dateStr(e.key);
      final t = e.value.trim();
      if (t.isNotEmpty) payload[ds] = t;
    }

    _recordDebug(
      'save_persist_start payload=${payload.length} deletes=${_pendingDeleteBreakDates.length}',
    );
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
        _loadedBreakTimeMap = <int, String>{..._breakTimeMap};
        _pendingDeleteBreakDates.clear();
        _breakTimeCache[cacheKey] = <int, String>{..._breakTimeMap};
        _breakLoadedCache[cacheKey] = <int, String>{..._loadedBreakTimeMap};
      });
      _recordDebug('save_persist_complete');
      return true;
    } catch (error, stackTrace) {
      _recordDebug('save_persist_failure error=$error stack=$stackTrace');
      return false;
    }
  }

  Future<void> _saveAllChangesToFirestore() async {
    if (_selectedUser == null || _saveState == _SaveVisualState.saving) return;
    _recordDebug('save_action_start dirty=$_dirtyDayCount');
    setState(() => _saveState = _SaveVisualState.saving);
    final ok = await _persistAllChangesToFirestore();
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      setState(() => _saveState = _SaveVisualState.success);
      _recordDebug('save_action_success');
      unawaited(Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _saveState == _SaveVisualState.success) {
          setState(() => _saveState = _SaveVisualState.idle);
        }
      }));
    } else {
      HapticFeedback.mediumImpact();
      setState(() => _saveState = _SaveVisualState.failure);
      _recordDebug('save_action_failure');
    }
  }

  Future<void> _openMailRecipientSettings() async {
    _recordDebug('recipient_settings_open');
    await MailRecipientSettings.showAsBottomSheet(
      context,
      useCommonUi: _useCommonUi,
    );
    _recordDebug('recipient_settings_close');
  }

  Future<bool> _ensureRecipientConfigured() async {
    try {
      final cfg = await EmailConfig.load();
      final to = cfg.to.trim();
      if (EmailConfig.isValidToList(to)) return true;
      await _openMailRecipientSettings();
      return false;
    } catch (error, stackTrace) {
      _recordDebug('recipient_check_failure error=$error stack=$stackTrace');
      return false;
    }
  }

  Future<void> _sendMonthlyExcelMail() async {
    if (_selectedUser == null || _isSendingMail) return;
    final ok = await _ensureRecipientConfigured();
    if (!ok) return;

    _recordDebug('mail_send_start month=${_monthKey(_focusedDay)}');
    setState(() => _isSendingMail = true);
    try {
      final saved = await _persistAllChangesToFirestore();
      if (!saved) {
        _recordDebug('mail_send_abort reason=save_failed');
        return;
      }
      final user = _selectedUser!;
      final userId = _userIdOf(user);
      await CalendarExcelMailer.sendBreakMonthExcel(
        year: _focusedDay.year,
        month: _focusedDay.month,
        userId: userId,
        userName: user.name,
        breakByDay: _breakTimeMap,
      );
      _recordDebug('mail_send_complete');
    } catch (error, stackTrace) {
      _recordDebug('mail_send_failure error=$error stack=$stackTrace');
    } finally {
      if (mounted) setState(() => _isSendingMail = false);
    }
  }

  Future<void> _changeMonth(int delta) async {
    if (_isLoadingMonth) return;
    final target = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    _recordDebug(
      'month_change from=${_monthKey(_focusedDay)} to=${_monthKey(target)} direction=$delta',
    );
    HapticFeedback.selectionClick();
    setState(() {
      _monthDirection = delta >= 0 ? 1 : -1;
      _focusedDay = target;
      _selectedDay = null;
      _saveState = _SaveVisualState.idle;
    });
    if (_selectedUser != null) {
      await _loadBreakTimes(_selectedUser!, reason: 'month_change');
    }
  }

  Future<void> _retryMonthLoad() async {
    final user = _selectedUser;
    if (user == null) return;
    await _loadBreakTimes(user, reason: 'retry');
  }

  Widget _buildDockHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final subtitle = _dockSubtitle();

    return CommonAnimatedReveal(
      offset: const Offset(-0.025, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
        child: Row(
          children: [
            Icon(Icons.free_breakfast_rounded, color: tokens.warning, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _developerMode ? _showDeveloperStatus : null,
                onLongPress: _developerMode ? _showDeveloperStatus : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '휴게 관리',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(-0.025, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          subtitle,
                          key: ValueKey<String>(subtitle),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_developerMode)
              IconButton(
                tooltip: '개발 상태',
                onPressed: _showDeveloperStatus,
                icon: Icon(
                  Icons.terminal_rounded,
                  color: tokens.iconSecondary,
                  size: 20,
                ),
              ),
            PopupMenuButton<String>(
              tooltip: '휴게 관리 메뉴',
              icon: Icon(
                Icons.more_vert_rounded,
                color: tokens.iconSecondary,
                size: 21,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'recipient':
                    unawaited(_openMailRecipientSettings());
                    break;
                  case 'mail':
                    unawaited(_sendMonthlyExcelMail());
                    break;
                  case 'reset':
                    HapticFeedback.lightImpact();
                    _clearAll();
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  value: 'recipient',
                  child: Text('메일 수신자'),
                ),
                PopupMenuItem<String>(
                  value: 'mail',
                  enabled: _selectedUser != null && !_isSendingMail,
                  child: Text(_isSendingMail ? '메일 발송 중' : 'Excel 메일 발송'),
                ),
                const PopupMenuItem<String>(
                  value: 'reset',
                  child: Text('화면 초기화'),
                ),
              ],
            ),
            IconButton(
              tooltip: '휴게 관리 닫기',
              onPressed: () {
                HapticFeedback.lightImpact();
                _recordDebug('side_dock_close source=header');
                Navigator.of(context).maybePop();
              },
              icon: Icon(
                Icons.close_rounded,
                color: tokens.iconPrimary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSwitcher(BuildContext context) {
    return CommonSideDockContentCropSwitcher(
      activeKey: _showUserPicker ? 'break_user_picker' : 'break_main',
      originAlignment: Alignment.centerLeft,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
      child: _showUserPicker
          ? _buildUserCandidateView(context)
          : _buildMainContent(context),
    );
  }

  Widget _buildUserCandidateView(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 4, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: '휴게 관리로 돌아가기',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _recordDebug('user_picker_back');
                  setState(() => _showUserPicker = false);
                },
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '직원 선택',
                      style: text.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${_candidateUsers.length}명 검색됨',
                      style: text.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _candidateUsers.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: tokens.borderSubtle),
            itemBuilder: (context, index) {
              final user = _candidateUsers[index];
              final area = user.selectedArea?.trim() ?? '';
              final division =
                  user.divisions.isNotEmpty ? user.divisions.first : '';
              final meta = <String>[
                user.phone,
                if (area.isNotEmpty) area,
                if (division.isNotEmpty) division,
              ].join(' · ');
              return CommonAnimatedReveal(
                delay: Duration(milliseconds: 18 * (index > 8 ? 8 : index)),
                offset: const Offset(-0.02, 0),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    unawaited(_selectUser(user, source: 'search_multiple'));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 20,
                          color: tokens.iconSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.name,
                                style: text.bodyMedium?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: tokens.iconSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  offset: const Offset(-0.02, 0),
                  child: _buildUserSection(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, color: tokens.borderSubtle),
              ),
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 30),
                  offset: const Offset(-0.02, 0),
                  child: _buildMonthNavigator(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, color: tokens.borderSubtle),
              ),
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 50),
                  offset: const Offset(-0.02, 0),
                  child: _buildLegend(context),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, color: tokens.borderSubtle),
              ),
              SliverToBoxAdapter(child: _buildMonthStatus(context)),
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 70),
                  offset: const Offset(0, 0.015),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      final direction = _monthDirection.toDouble();
                      final offset = Tween<Offset>(
                        begin: Offset(0.04 * direction, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<String>(_monthKey(_focusedDay)),
                      child: _buildCalendar(context),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 85),
          offset: const Offset(0, 0.02),
          child: _buildSaveFooter(context),
        ),
      ],
    );
  }

  Widget _buildUserSection(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final user = _selectedUser;
    if (user != null) {
      final area = user.selectedArea?.trim() ?? '';
      final division = user.divisions.isNotEmpty ? user.divisions.first : '';
      final meta = <String>[
        user.phone,
        if (area.isNotEmpty) area,
        if (division.isNotEmpty) division,
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 20,
              color: tokens.iconSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _beginUserChange,
              child: const Text('변경'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '직원 선택',
            style: text.labelLarge?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _userInputCtrl,
            focusNode: _userInputFocus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(_onSearchUserPressed()),
            decoration: InputDecoration(
              isDense: true,
              labelText: '전화번호 혹은 코드번호',
              prefixIcon: const Icon(Icons.person_search_rounded),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: tokens.borderSubtle),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _base, width: 1.5),
              ),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: '직원 검색',
                      onPressed: _onSearchUserPressed,
                      icon: const Icon(Icons.search_rounded),
                    ),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : CommonUiMotion.selection,
            curve: CommonUiMotion.enter,
            child: (_searchMessage == null && _searchError == null)
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          _searchError == null
                              ? Icons.search_off_rounded
                              : Icons.error_outline_rounded,
                          size: 17,
                          color: _searchError == null
                              ? tokens.textSecondary
                              : tokens.danger,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _searchError == null
                                ? _searchMessage!
                                : '직원 정보를 불러오지 못했습니다.',
                            style: text.bodySmall?.copyWith(
                              color: _searchError == null
                                  ? tokens.textSecondary
                                  : tokens.danger,
                            ),
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

  Widget _buildMonthNavigator(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: '이전 달',
            onPressed: _isLoadingMonth ? null : () => unawaited(_changeMonth(-1)),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.selection,
              child: Text(
                _monthLabel(_focusedDay),
                key: ValueKey<String>(_monthKey(_focusedDay)),
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '다음 달',
            onPressed: _isLoadingMonth ? null : () => unawaited(_changeMonth(1)),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Wrap(
        spacing: 14,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FlatLegendItem(color: _base, label: '기록 있음'),
          _FlatLegendItem(color: tokens.textDisabled, label: '기록 없음'),
        ],
      ),
    );
  }

  Widget _buildMonthStatus(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    if (_selectedUser == null) return const SizedBox.shrink();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget child;
    if (_isLoadingMonth) {
      child = Row(
        key: const ValueKey<String>('loading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '휴게 기록 최신화 중',
            style: text.bodySmall?.copyWith(color: tokens.textSecondary),
          ),
        ],
      );
    } else if (_monthLoadError != null) {
      child = Row(
        key: const ValueKey<String>('error'),
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: tokens.danger),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '최신 기록을 불러오지 못했습니다.',
              style: text.bodySmall?.copyWith(color: tokens.danger),
            ),
          ),
          TextButton(
            onPressed: _retryMonthLoad,
            child: const Text('다시 시도'),
          ),
        ],
      );
    } else {
      child = Row(
        key: const ValueKey<String>('ready'),
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 17, color: _base),
          const SizedBox(width: 7),
          Text(
            '휴게 기록 ${_breakTimeMap.length}일',
            style: text.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        child: child,
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
      child: TableCalendar(
        firstDay: _calendarFirstDay,
        lastDay: _calendarLastDay,
        focusedDay: _focusedDay,
        headerVisible: false,
        rowHeight: 84,
        daysOfWeekHeight: 28,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) async {
          HapticFeedback.selectionClick();
          _recordDebug(
            'date_select date=${selectedDay.toIso8601String()} editable=${_selectedUser != null}',
          );
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
          if (_selectedUser != null) {
            await _showEditBottomSheet(selectedDay);
          }
        },
        onPageChanged: (focusedDay) async {
          if (focusedDay.year == _focusedDay.year &&
              focusedDay.month == _focusedDay.month) {
            return;
          }
          final direction = focusedDay.isAfter(_focusedDay) ? 1 : -1;
          setState(() {
            _monthDirection = direction;
            _focusedDay = focusedDay;
            _selectedDay = null;
          });
          if (_selectedUser != null) {
            await _loadBreakTimes(_selectedUser!, reason: 'calendar_page');
          }
        },
        availableGestures: AvailableGestures.none,
        calendarStyle: const CalendarStyle(
          outsideDaysVisible: true,
          isTodayHighlighted: false,
          cellMargin: EdgeInsets.zero,
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: TextStyle(
            color: _tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          weekendStyle: TextStyle(
            color: _tokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        calendarBuilders: CalendarBuilders(
          defaultBuilder: _buildCell,
          todayBuilder: _buildCell,
          selectedBuilder: _buildCell,
          outsideBuilder: _buildCell,
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, DateTime day, DateTime focusedDay) {
    final isSelected = isSameDay(day, _selectedDay);
    final isToday = isSameDay(day, DateTime.now());
    final isInFocusedMonth =
        day.year == _focusedDay.year && day.month == _focusedDay.month;
    final breakTime = isInFocusedMonth ? (_breakTimeMap[day.day] ?? '') : '';
    final hasBreak = breakTime.isNotEmpty;
    final dirty = isInFocusedMonth && _isDirtyDay(day.day);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSide = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dayFs = (baseSide * 0.34).clamp(12.0, 18.0);
        final timeFs = (baseSide * 0.29).clamp(10.0, 15.0);
        final smallFs = (baseSide * 0.24).clamp(9.0, 13.0);
        final vGap = (baseSide * 0.08).clamp(1.0, 5.0);

        return AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: CommonUiMotion.enter,
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? _base.withOpacity(.08) : Colors.transparent,
            borderRadius: isSelected || isToday
                ? BorderRadius.circular(8)
                : BorderRadius.zero,
            border: isSelected
                ? Border.all(color: _base, width: 1.2)
                : isToday
                    ? Border.all(color: _light, width: 1)
                    : null,
          ),
          child: Stack(
            children: [
              Positioned(
                right: 3,
                top: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dirty)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: _base,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: hasBreak ? _base : _tokens.textDisabled,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
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
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: isInFocusedMonth
                              ? (isSelected ? _dark : _tokens.textPrimary)
                              : _tokens.textDisabled,
                          fontSize: dayFs,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: vGap),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        child: hasBreak
                            ? Text(
                                breakTime,
                                key: ValueKey<String>('break_$breakTime'),
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: timeFs,
                                  fontWeight: FontWeight.w800,
                                  color: _tokens.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              )
                            : Text(
                                '—',
                                key: const ValueKey<String>('break_empty'),
                                style: TextStyle(
                                  fontSize: smallFs,
                                  color: _tokens.textDisabled,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSaveFooter(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final dirty = _dirtyDayCount;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final canSave = _selectedUser != null &&
        _saveState != _SaveVisualState.saving &&
        dirty > 0;

    Widget status;
    switch (_saveState) {
      case _SaveVisualState.saving:
        status = Row(
          key: const ValueKey<String>('saving'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text('저장 중', style: text.bodySmall),
          ],
        );
        break;
      case _SaveVisualState.success:
        status = Row(
          key: const ValueKey<String>('success'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 17, color: tokens.success),
            const SizedBox(width: 5),
            Text(
              '저장 완료',
              style: text.bodySmall?.copyWith(color: tokens.success),
            ),
          ],
        );
        break;
      case _SaveVisualState.failure:
        status = Row(
          key: const ValueKey<String>('failure'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 17, color: tokens.danger),
            const SizedBox(width: 5),
            Text(
              '저장 실패',
              style: text.bodySmall?.copyWith(color: tokens.danger),
            ),
          ],
        );
        break;
      case _SaveVisualState.idle:
        status = Text(
          dirty == 0 ? '변경사항 없음' : '변경 $dirty건',
          key: ValueKey<String>('dirty_$dirty'),
          style: text.bodySmall?.copyWith(
            color: dirty == 0 ? tokens.textSecondary : _base,
            fontWeight: FontWeight.w700,
          ),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: status,
            ),
          ),
          TextButton.icon(
            onPressed: canSave
                ? _saveAllChangesToFirestore
                : (_saveState == _SaveVisualState.failure && dirty > 0
                    ? _saveAllChangesToFirestore
                    : null),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('변경사항 저장'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditBottomSheet(DateTime day) async {
    final dayKey = day.day;
    final initialTime = _breakTimeMap[dayKey] ?? '00:00';
    _recordDebug(
      'date_edit_open date=${day.toIso8601String()} break=$initialTime',
    );

    final newTime = await showBreakTimeSheet(
      context: context,
      date: day,
      initialTime: initialTime,
      useCommonUi: _useCommonUi,
    );
    if (newTime == null) {
      _recordDebug('date_edit_cancel date=${day.toIso8601String()}');
      return;
    }

    final dateStr = _dateStr(dayKey);
    final value = newTime.trim();
    setState(() {
      if (value.isEmpty || value == '00:00') {
        _breakTimeMap.remove(dayKey);
        _pendingDeleteBreakDates.add(dateStr);
      } else {
        _breakTimeMap[dayKey] = value;
        _pendingDeleteBreakDates.remove(dateStr);
      }
      _saveState = _SaveVisualState.idle;
    });
    _recordDebug(
      'date_edit_apply date=$dateStr break=$value dirty=$_dirtyDayCount',
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContentSwitcher(context);
    if (widget.presentation == BreakCalendarPresentation.page) {
      return Scaffold(
        backgroundColor: _tokens.canvas,
        appBar: AppBar(
          backgroundColor: _tokens.canvas,
          surfaceTintColor: _tokens.transparent,
          elevation: 0,
          foregroundColor: _tokens.textPrimary,
          title: const Text(
            '휴게 관리',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_developerMode)
              IconButton(
                tooltip: '개발 상태',
                onPressed: _showDeveloperStatus,
                icon: const Icon(Icons.terminal_rounded),
              ),
            IconButton(
              tooltip: '메일 수신자',
              onPressed: _openMailRecipientSettings,
              icon: const Icon(Icons.alternate_email_rounded),
            ),
            IconButton(
              tooltip: 'Excel 메일 발송',
              onPressed: _selectedUser == null || _isSendingMail
                  ? null
                  : _sendMonthlyExcelMail,
              icon: _isSendingMail
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mail_outline_rounded),
            ),
            IconButton(
              tooltip: '화면 초기화',
              onPressed: _clearAll,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ),
        body: content,
      );
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDockHeader(context),
          Divider(height: 1, color: _tokens.borderSubtle),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _FlatLegendItem extends StatelessWidget {
  const _FlatLegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
