import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';

import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../../../shared/plate/domain/services/plate_status_record.dart';
import '../../application/personal_calendar_store.dart';
import '../../application/personal_monthly_parking_sync_service.dart';
import '../../application/personal_saved_vehicle_store.dart';
import '../../application/personal_todo_store.dart';
import '../../application/personal_vehicle_status_service.dart';
import '../../domain/models/personal_calendar_event.dart';
import '../../domain/models/personal_saved_vehicle.dart';
import '../../domain/models/personal_todo_item.dart';
import '../dialogs/personal_calendar_dialog.dart';
import '../dialogs/personal_departure_success_dialog.dart';
import '../dialogs/personal_todo_dialog.dart';
import '../dialogs/personal_vehicle_editor_dialog.dart';
import '../dialogs/personal_vehicle_status_sheet.dart';

class PersonalHomePanel extends StatefulWidget {
  const PersonalHomePanel({
    super.key,
    required this.area,
  });

  final String area;

  @override
  PersonalHomePanelState createState() => PersonalHomePanelState();
}

class PersonalHomePanelState extends State<PersonalHomePanel> {
  final PersonalSavedVehicleStore _vehicleStore = PersonalSavedVehicleStore();
  final PersonalVehicleStatusService _statusService = PersonalVehicleStatusService();
  final PersonalTodoStore _todoStore = PersonalTodoStore();
  final PersonalCalendarStore _calendarStore = PersonalCalendarStore();
  final PersonalMonthlyParkingSyncService _monthlySyncService = PersonalMonthlyParkingSyncService();
  static const int _pageLoopBase = 3000;
  final PageController _pageController = PageController(initialPage: _pageLoopBase);

  List<PersonalSavedVehicle> _vehicles = const <PersonalSavedVehicle>[];
  List<PersonalTodoItem> _todos = const <PersonalTodoItem>[];
  List<PersonalCalendarEvent> _events = const <PersonalCalendarEvent>[];
  final Map<String, PlateModel?> _statusByVehicleId = <String, PlateModel?>{};
  final Map<String, PlateStatusRecord?> _monthlyStatusByVehicleId = <String, PlateStatusRecord?>{};
  final Set<String> _loadingVehicleIds = <String>{};
  final Set<String> _loadingMonthlyVehicleIds = <String>{};
  bool _loadingVehicles = true;
  String _personalName = '';
  String? _selectedVehicleId;
  int _pageIndex = 0;
  int _rawPageIndex = _pageLoopBase;
  bool _showMonthlyParkingPanel = false;
  DateTime _selectedCalendarDay = _today();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant PersonalHomePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) {
      _refreshAllStatuses();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> addVehicleFromMenu() async {
    await _addVehicle();
  }

  Future<void> refreshEverythingFromMenu() async {
    await _refreshEverything();
  }

  Future<void> openTodoDialogFromMenu() async {
    await _openTodoDialog();
  }

  Future<void> openCalendarDialogFromMenu() async {
    await _openCalendarDialog();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final name = (prefs.getString('personalName') ?? '').trim();
    final vehicles = await _vehicleStore.load();
    final todos = await _todoStore.load();
    final events = await _calendarStore.load();
    if (!mounted) return;
    setState(() {
      _personalName = name;
      _vehicles = vehicles;
      _todos = todos;
      _events = events;
      _selectedVehicleId = vehicles.isNotEmpty ? vehicles.first.id : null;
      _loadingVehicles = false;
      _clearStaleStatuses(vehicles);
    });
    await _refreshAllStatuses();
  }

  Future<void> _reloadVehicles() async {
    final vehicles = await _vehicleStore.load();
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      if (_selectedVehicleId == null || vehicles.every((v) => v.id != _selectedVehicleId)) {
        _selectedVehicleId = vehicles.isNotEmpty ? vehicles.first.id : null;
      }
      _clearStaleStatuses(vehicles);
    });
    await _refreshAllStatuses();
  }

  Future<void> _reloadTodos() async {
    final todos = await _todoStore.load();
    if (!mounted) return;
    setState(() => _todos = todos);
  }

  Future<void> _reloadEvents() async {
    final events = await _calendarStore.load();
    if (!mounted) return;
    setState(() => _events = events);
  }

  Future<void> _refreshEverything() async {
    await _reloadVehicles();
    await _reloadTodos();
    await _reloadEvents();
  }

  void _clearStaleStatuses(List<PersonalSavedVehicle> vehicles) {
    final valid = vehicles.map((e) => e.id).toSet();
    _statusByVehicleId.removeWhere((id, _) => !valid.contains(id));
    _monthlyStatusByVehicleId.removeWhere((id, _) => !valid.contains(id));
    _loadingVehicleIds.removeWhere((id) => !valid.contains(id));
    _loadingMonthlyVehicleIds.removeWhere((id) => !valid.contains(id));
    if (vehicles.isEmpty) {
      _statusByVehicleId.clear();
      _monthlyStatusByVehicleId.clear();
      _loadingVehicleIds.clear();
      _loadingMonthlyVehicleIds.clear();
      _showMonthlyParkingPanel = false;
    }
  }

  Future<void> _refreshAllStatuses() async {
    final area = widget.area.trim();
    if (area.isEmpty || _vehicles.isEmpty) {
      if (mounted) {
        setState(() {
          _statusByVehicleId.clear();
          _monthlyStatusByVehicleId.clear();
          _loadingVehicleIds.clear();
          _loadingMonthlyVehicleIds.clear();
          _showMonthlyParkingPanel = false;
        });
      }
      return;
    }
    for (final vehicle in _vehicles) {
      await _refreshVehicleStatus(vehicle);
    }
  }

  Future<void> _refreshVehicleStatus(PersonalSavedVehicle vehicle) async {
    final area = widget.area.trim();
    if (area.isEmpty) return;
    setState(() {
      _loadingVehicleIds.add(vehicle.id);
      _loadingMonthlyVehicleIds.add(vehicle.id);
    });
    try {
      final plate = await _statusService.fetchCurrentVehiclePlate(
        plateNumber: vehicle.plateNumber,
        area: area,
      );
      final monthly = await _statusService.fetchMonthlyParkingStatus(
        plateNumber: vehicle.plateNumber,
        area: area,
      );
      await _monthlySyncService.syncVehicleMonthlyParking(
        vehicle: vehicle,
        record: monthly,
        calendarStore: _calendarStore,
        todoStore: _todoStore,
      );
      final syncedTodos = await _todoStore.load();
      final syncedEvents = await _calendarStore.load();
      if (!mounted) return;
      setState(() {
        _statusByVehicleId[vehicle.id] = plate;
        _monthlyStatusByVehicleId[vehicle.id] = monthly;
        _todos = syncedTodos;
        _events = syncedEvents;
        _loadingVehicleIds.remove(vehicle.id);
        _loadingMonthlyVehicleIds.remove(vehicle.id);
      });
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.home.vehicleStatusRefresh',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'area': area,
          'vehicleId': vehicle.id,
          'plateNumberInput': vehicle.plateNumber,
          'source': 'PersonalVehicleStatusService.fetchCurrentVehiclePlate, PersonalVehicleStatusService.fetchMonthlyParkingStatus',
        },
      );
      if (!mounted) return;
      setState(() {
        _statusByVehicleId[vehicle.id] = null;
        _monthlyStatusByVehicleId[vehicle.id] = null;
        _loadingVehicleIds.remove(vehicle.id);
        _loadingMonthlyVehicleIds.remove(vehicle.id);
      });
    }
  }

  Future<void> _openVehicle(PersonalSavedVehicle vehicle) async {
    final changed = await showPersonalVehicleStatusSheet(
      context: context,
      vehicle: vehicle,
      area: widget.area,
      initialPlate: _statusByVehicleId[vehicle.id],
    );
    if (changed == true) {
      await _refreshVehicleStatus(vehicle);
    }
  }

  Future<void> _addVehicle() async {
    final result = await showPersonalVehicleEditorDialog(context: context);
    if (result == null) return;
    if (result.vehicle != null) {
      await _vehicleStore.upsert(result.vehicle!);
      await _reloadVehicles();
      if (!mounted) return;
      setState(() => _selectedVehicleId = result.vehicle!.id);
      _showSnack('차량을 저장했습니다.', success: true);
    }
  }

  Future<void> _openTodoDialog() async {
    await showPersonalTodoDialog(context);
    await _reloadTodos();
  }

  Future<void> _openCalendarDialog() async {
    await showPersonalCalendarDialog(context);
    await _reloadEvents();
    await _reloadTodos();
  }

  Future<void> _toggleTodo(PersonalTodoItem todo) async {
    await _todoStore.upsert(todo.copyWith(done: !todo.done, updatedAt: DateTime.now()));
    await _reloadTodos();
  }

  PersonalSavedVehicle? get _selectedVehicle {
    if (_vehicles.isEmpty) return null;
    final id = _selectedVehicleId;
    if (id == null) return _vehicles.first;
    for (final vehicle in _vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return _vehicles.first;
  }

  void _showSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
      ),
    );
  }

  int _logicalPageIndex(int rawIndex) => rawIndex % 3;

  void _handlePageChanged(int rawIndex) {
    final logicalIndex = _logicalPageIndex(rawIndex);
    setState(() {
      _rawPageIndex = rawIndex;
      _pageIndex = logicalIndex;
      if (logicalIndex != 0) {
        _showMonthlyParkingPanel = false;
      }
    });
  }

  void _goToPage(int logicalIndex) {
    final target = logicalIndex.clamp(0, 2).toInt();
    if (target == 0 && _showMonthlyParkingPanel) {
      setState(() => _showMonthlyParkingPanel = false);
    }
    if (!_pageController.hasClients) {
      setState(() => _pageIndex = target);
      return;
    }
    var delta = target - _pageIndex;
    if (delta > 1) delta -= 3;
    if (delta < -1) delta += 3;
    _pageController.animateToPage(
      _rawPageIndex + delta,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleVehiclePanel() {
    if (_selectedVehicle == null) return;
    setState(() => _showMonthlyParkingPanel = !_showMonthlyParkingPanel);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _handlePageChanged,
            itemBuilder: (context, rawIndex) {
              final index = _logicalPageIndex(rawIndex);
              if (index == 0) {
                return _VehicleLocationPage(
                  name: _personalName,
                  area: widget.area,
                  vehicles: _vehicles,
                  selectedVehicle: _selectedVehicle,
                  statusByVehicleId: _statusByVehicleId,
                  monthlyStatusByVehicleId: _monthlyStatusByVehicleId,
                  loadingVehicleIds: _loadingVehicleIds,
                  loadingMonthlyVehicleIds: _loadingMonthlyVehicleIds,
                  loadingVehicles: _loadingVehicles,
                  showMonthlyParkingPanel: _showMonthlyParkingPanel,
                  onToggleVehiclePanel: _toggleVehiclePanel,
                  onSelectVehicle: (vehicle) => setState(() {
                    _selectedVehicleId = vehicle.id;
                    _showMonthlyParkingPanel = false;
                  }),
                  onRefreshVehicle: _refreshVehicleStatus,
                  onOpenVehicle: _openVehicle,
                );
              }
              if (index == 1) {
                return _TodayTodoPage(
                  todos: _todos,
                  events: _events,
                  onToggleTodo: _toggleTodo,
                  onOpenTodo: _openTodoDialog,
                  onOpenCalendar: _openCalendarDialog,
                );
              }
              return _CalendarFocusPage(
                todos: _todos,
                events: _events,
                selectedDay: _selectedCalendarDay,
                onSelectDay: (day) => setState(() => _selectedCalendarDay = day),
                onToggleTodo: _toggleTodo,
                onOpenTodo: _openTodoDialog,
                onOpenCalendar: _openCalendarDialog,
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottom),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.42))),
          ),
          child: _PageSwitcher(
            current: _pageIndex,
            onTap: _goToPage,
          ),
        ),
      ],
    );
  }
}

class _VehicleLocationPage extends StatelessWidget {
  const _VehicleLocationPage({
    required this.name,
    required this.area,
    required this.vehicles,
    required this.selectedVehicle,
    required this.statusByVehicleId,
    required this.monthlyStatusByVehicleId,
    required this.loadingVehicleIds,
    required this.loadingMonthlyVehicleIds,
    required this.loadingVehicles,
    required this.showMonthlyParkingPanel,
    required this.onToggleVehiclePanel,
    required this.onSelectVehicle,
    required this.onRefreshVehicle,
    required this.onOpenVehicle,
  });

  final String name;
  final String area;
  final List<PersonalSavedVehicle> vehicles;
  final PersonalSavedVehicle? selectedVehicle;
  final Map<String, PlateModel?> statusByVehicleId;
  final Map<String, PlateStatusRecord?> monthlyStatusByVehicleId;
  final Set<String> loadingVehicleIds;
  final Set<String> loadingMonthlyVehicleIds;
  final bool loadingVehicles;
  final bool showMonthlyParkingPanel;
  final VoidCallback onToggleVehiclePanel;
  final ValueChanged<PersonalSavedVehicle> onSelectVehicle;
  final Future<void> Function(PersonalSavedVehicle) onRefreshVehicle;
  final Future<void> Function(PersonalSavedVehicle) onOpenVehicle;

  @override
  Widget build(BuildContext context) {
    final vehicle = selectedVehicle;
    final plate = vehicle == null ? null : statusByVehicleId[vehicle.id];
    final monthlyStatus = vehicle == null ? null : monthlyStatusByVehicleId[vehicle.id];
    final loading = vehicle != null && loadingVehicleIds.contains(vehicle.id);
    final loadingMonthly = vehicle != null && loadingMonthlyVehicleIds.contains(vehicle.id);
    return RefreshIndicator(
      onRefresh: () async {
        final current = selectedVehicle;
        if (current == null) return;
        await onRefreshVehicle(current);
      },
      child: _ResponsivePage(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeHero(
              name: name,
              area: area,
              vehicleCount: vehicles.length,
              activePlate: plate,
              hasSelectedVehicle: vehicle != null,
              onOpenSelected: vehicle == null ? null : () => onOpenVehicle(vehicle),
            ),
            const SizedBox(height: 12),
            if (loadingVehicles)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (vehicles.isEmpty)
              const _EmptyVehicleLocationState()
            else ...[
              _VehicleSelector(
                vehicles: vehicles,
                selectedId: vehicle?.id,
                statuses: statusByVehicleId,
                onSelect: onSelectVehicle,
              ),
              const SizedBox(height: 12),
              _VehicleSwipeDeck(
                showMonthlyParkingPanel: showMonthlyParkingPanel,
                onToggle: onToggleVehiclePanel,
                mapCard: _LocationMapCard(vehicle: vehicle!, plate: plate, loading: loading),
                monthlyCard: _MonthlyParkingInfoCard(
                  vehicle: vehicle,
                  monthlyStatus: monthlyStatus,
                  loading: loadingMonthly,
                ),
              ),
            ],
            SizedBox(height: MediaQuery.of(context).size.height < 680 ? 12 : 20),
          ],
        ),
      ),
    );
  }
}

class _TodayTodoPage extends StatelessWidget {
  const _TodayTodoPage({
    required this.todos,
    required this.events,
    required this.onToggleTodo,
    required this.onOpenTodo,
    required this.onOpenCalendar,
  });

  final List<PersonalTodoItem> todos;
  final List<PersonalCalendarEvent> events;
  final Future<void> Function(PersonalTodoItem) onToggleTodo;
  final Future<void> Function() onOpenTodo;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final todayTodos = todos.where((todo) => todo.dueDate == null || _sameDay(todo.dueDate!, today)).toList();
    final todayEvents = events.where((event) => _sameDay(event.dayOnly, today)).toList();
    final done = todayTodos.where((todo) => todo.done).length;
    final progress = todayTodos.isEmpty ? 0.0 : done / todayTodos.length;

    return _ResponsivePage(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageTitleCard(
            icon: Icons.checklist_rounded,
            title: '오늘 할 일',
            subtitle: todayTodos.isEmpty ? '오늘 처리할 차량 메모를 만들어 보세요.' : '${todayTodos.length}개 중 $done개 완료',
            actionLabel: '관리',
            onAction: onOpenTodo,
          ),
          const SizedBox(height: 12),
          _ProgressCard(progress: progress, total: todayTodos.length, done: done),
          const SizedBox(height: 12),
          _LinkedSectionTitle(title: '할 일', actionLabel: '할 일 관리', onAction: onOpenTodo),
          if (todayTodos.isEmpty)
            const _EmptyInlineCard(icon: Icons.task_alt_rounded, text: '오늘 표시할 할 일이 없습니다.')
          else
            ...todayTodos.map(
              (todo) => _TodoRowCard(todo: todo, onToggle: () => onToggleTodo(todo)),
            ),
          const SizedBox(height: 10),
          _LinkedSectionTitle(title: '오늘 일정', actionLabel: '달력 보기', onAction: onOpenCalendar),
          if (todayEvents.isEmpty)
            const _EmptyInlineCard(icon: Icons.event_available_rounded, text: '오늘 연결된 일정이 없습니다.')
          else
            ...todayEvents.map((event) => _EventRowCard(event: event)),
        ],
      ),
    );
  }
}

class _CalendarFocusPage extends StatelessWidget {
  const _CalendarFocusPage({
    required this.todos,
    required this.events,
    required this.selectedDay,
    required this.onSelectDay,
    required this.onToggleTodo,
    required this.onOpenTodo,
    required this.onOpenCalendar,
  });

  final List<PersonalTodoItem> todos;
  final List<PersonalCalendarEvent> events;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final Future<void> Function(PersonalTodoItem) onToggleTodo;
  final Future<void> Function() onOpenTodo;
  final Future<void> Function() onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final selectedTodos = todos.where((todo) => todo.dueDate != null && _sameDay(todo.dueDate!, selectedDay)).toList();
    final selectedEvents = events.where((event) => _sameDay(event.dayOnly, selectedDay)).toList();

    return _ResponsivePage(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageTitleCard(
            icon: Icons.calendar_month_rounded,
            title: '달력',
            subtitle: '일정과 할 일이 같은 날짜에서 함께 보입니다.',
            actionLabel: '관리',
            onAction: onOpenCalendar,
          ),
          const SizedBox(height: 12),
          _InlineCalendar(
            selectedDay: selectedDay,
            todos: todos,
            events: events,
            onSelectDay: onSelectDay,
          ),
          const SizedBox(height: 12),
          _LinkedSectionTitle(title: _formatKoreanDate(selectedDay), actionLabel: '일정 관리', onAction: onOpenCalendar),
          if (selectedEvents.isEmpty && selectedTodos.isEmpty)
            const _EmptyInlineCard(icon: Icons.calendar_today_rounded, text: '선택한 날짜에 일정이나 할 일이 없습니다.')
          else ...[
            ...selectedEvents.map((event) => _EventRowCard(event: event)),
            ...selectedTodos.map((todo) => _TodoRowCard(todo: todo, onToggle: () => onToggleTodo(todo))),
          ],
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onOpenTodo,
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('이 날짜의 할 일 관리'),
          ),
        ],
      ),
    );
  }
}

class _ResponsivePage extends StatelessWidget {
  const _ResponsivePage({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding.copyWith(bottom: padding.bottom + bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - padding.vertical),
            child: child,
          ),
        );
      },
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.name,
    required this.area,
    required this.vehicleCount,
    required this.activePlate,
    required this.hasSelectedVehicle,
    required this.onOpenSelected,
  });

  final String name;
  final String area;
  final int vehicleCount;
  final PlateModel? activePlate;
  final bool hasSelectedVehicle;
  final VoidCallback? onOpenSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final displayName = name.trim().isEmpty ? '고객' : name.trim();
    final status = activePlate?.typeEnum == PlateType.parkingCompleted ? '출차 요청 가능' : '내 차량 위치 확인';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color.alphaBlend(cs.primary.withOpacity(.17), cs.surface),
            Color.alphaBlend(cs.primary.withOpacity(.04), cs.surface),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.primary.withOpacity(.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$displayName님, 내 차를 확인해요',
                  style: text.titleLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${area.trim().isEmpty ? '이용 지점 확인 중' : area.trim()} · 등록 차량 $vehicleCount대 · $status',
                  style: text.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HeroDetailIcon(
            enabled: hasSelectedVehicle,
            onTap: onOpenSelected,
          ),
        ],
      ),
    );
  }
}


class _HeroDetailIcon extends StatefulWidget {
  const _HeroDetailIcon({
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_HeroDetailIcon> createState() => _HeroDetailIconState();
}

class _HeroDetailIconState extends State<_HeroDetailIcon> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  @override
  void didUpdateWidget(covariant _HeroDetailIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.enabled ? '선택 차량 상세 보기' : '차량을 먼저 추가해 주세요',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: widget.enabled ? 1 : .46,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          scale: _pressed ? .94 : 1,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: widget.enabled ? _handleTap : null,
              onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
              onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
              onTapCancel: widget.enabled ? () => _setPressed(false) : null,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: cs.primary.withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                ),
                child: Icon(Icons.near_me_rounded, color: cs.onPrimary, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleSelector extends StatelessWidget {
  const _VehicleSelector({
    required this.vehicles,
    required this.selectedId,
    required this.statuses,
    required this.onSelect,
  });

  final List<PersonalSavedVehicle> vehicles;
  final String? selectedId;
  final Map<String, PlateModel?> statuses;
  final ValueChanged<PersonalSavedVehicle> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final vehicle = vehicles[index];
          final selected = vehicle.id == selectedId;
          final type = statuses[vehicle.id]?.typeEnum;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) => onSelect(vehicle),
            avatar: Icon(_statusIcon(type), size: 17, color: selected ? cs.onPrimary : cs.primary),
            label: Text(vehicle.displayPlate),
            labelStyle: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
            selectedColor: cs.primary,
            backgroundColor: cs.surfaceContainerLow,
            side: BorderSide(color: selected ? cs.primary : cs.outlineVariant.withOpacity(.55)),
          );
        },
      ),
    );
  }
}


class _VehicleSwipeDeck extends StatelessWidget {
  const _VehicleSwipeDeck({
    required this.showMonthlyParkingPanel,
    required this.onToggle,
    required this.mapCard,
    required this.monthlyCard,
  });

  final bool showMonthlyParkingPanel;
  final VoidCallback onToggle;
  final Widget mapCard;
  final Widget monthlyCard;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -180) onToggle();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, .05),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offsetAnimation, child: child),
          );
        },
        child: showMonthlyParkingPanel
            ? KeyedSubtree(key: const ValueKey<String>('monthlyParkingPanel'), child: monthlyCard)
            : KeyedSubtree(key: const ValueKey<String>('locationMapPanel'), child: mapCard),
      ),
    );
  }
}

class _MonthlyParkingInfoCard extends StatelessWidget {
  const _MonthlyParkingInfoCard({
    required this.vehicle,
    required this.monthlyStatus,
    required this.loading,
  });

  final PersonalSavedVehicle vehicle;
  final PlateStatusRecord? monthlyStatus;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final height = MediaQuery.of(context).size.height < 700 ? 330.0 : 360.0;
    final record = monthlyStatus;

    return Container(
      height: height,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : record == null
              ? _MonthlyParkingEmptyState(vehicle: vehicle)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                          child: Icon(Icons.local_parking_rounded, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('월주차 정보', style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(vehicle.displayPlate, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        _MonthlyStatusChip(record: record),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Column(
                        children: [
                          _MonthlyInfoRow(
                            icon: Icons.date_range_rounded,
                            label: '기간 / 만료 상태',
                            value: _monthlyPeriodSummary(record),
                          ),
                          const SizedBox(height: 7),
                          _MonthlyInfoRow(
                            icon: Icons.apartment_rounded,
                            label: '정산명',
                            value: _emptyDash(record.countType),
                          ),
                          const SizedBox(height: 7),
                          _MonthlyInfoRow(
                            icon: Icons.confirmation_number_rounded,
                            label: '상품',
                            value: _monthlyProductSummary(record),
                          ),
                          const SizedBox(height: 7),
                          _MonthlyInfoRow(
                            icon: Icons.payments_rounded,
                            label: '요금',
                            value: _formatWon(record.regularAmount),
                          ),
                          const SizedBox(height: 7),
                          _MonthlyInfoRow(
                            icon: Icons.receipt_long_rounded,
                            label: '최근 결제',
                            value: _recentPaymentSummary(record),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_double_arrow_up_rounded, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '위로 밀어 도면 보기',
                          style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}

class _MonthlyParkingEmptyState extends StatelessWidget {
  const _MonthlyParkingEmptyState({required this.vehicle});

  final PersonalSavedVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_parking_outlined, color: cs.primary, size: 46),
          const SizedBox(height: 12),
          Text(vehicle.displayPlate, style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            '현재 지점에 등록된 월주차 정보가 없습니다.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_double_arrow_up_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('위로 밀어 도면 보기', style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyStatusChip extends StatelessWidget {
  const _MonthlyStatusChip({required this.record});

  final PlateStatusRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = _monthlyStatusLabel(record);
    final expired = label == '만료';
    final urgent = label == '오늘 만료' || label == '만료 임박';
    final bg = expired
        ? cs.errorContainer
        : urgent
            ? cs.tertiaryContainer
            : cs.primaryContainer;
    final fg = expired
        ? cs.onErrorContainer
        : urgent
            ? cs.onTertiaryContainer
            : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _MonthlyInfoRow extends StatelessWidget {
  const _MonthlyInfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Icon(icon, size: 17, color: cs.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationMapCard extends StatelessWidget {
  const _LocationMapCard({required this.vehicle, required this.plate, required this.loading});

  final PersonalSavedVehicle vehicle;
  final PlateModel? plate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height < 700 ? 270.0 : 330.0;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(.04), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : plate == null
                ? _MapEmptyState(vehicle: vehicle)
                : PersonalDepartureRequestFocusedGrid(
                    area: plate!.area,
                    details: parsePersonalParkingLocation(plate!.location),
                  ),
      ),
    );
  }
}

class _MapEmptyState extends StatelessWidget {
  const _MapEmptyState({required this.vehicle});

  final PersonalSavedVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: cs.primary, size: 46),
            const SizedBox(height: 12),
            Text(
              vehicle.displayPlate,
              style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '현재 주차 중인 위치 정보가 없습니다. 메뉴의 데이터 갱신 또는 차량 상세 보기를 이용해 주세요.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVehicleLocationState extends StatelessWidget {
  const _EmptyVehicleLocationState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 42, 22, 42),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cs.outlineVariant.withOpacity(.60)),
      ),
      child: Column(
        children: [
          Icon(Icons.directions_car_filled_outlined, size: 54, color: cs.primary),
          const SizedBox(height: 14),
          Text('등록된 차량이 없습니다.', style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('우측 상단 메뉴에서 차량을 추가하면 도면으로 내 차 위치를 확인할 수 있습니다.', textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.4)),
        ],
      ),
    );
  }
}

class _PageTitleCard extends StatelessWidget {
  const _PageTitleCard({required this.icon, required this.title, required this.subtitle, required this.actionLabel, required this.onAction});

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cs.primary.withOpacity(.09), cs.surface),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: cs.primary.withOpacity(.13)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: cs.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(subtitle, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.3)),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress, required this.total, required this.done});

  final double progress;
  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('완료율', style: text.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900))),
              Text('$done / $total', style: text.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress.clamp(0, 1),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedSectionTitle extends StatelessWidget {
  const _LinkedSectionTitle({required this.title, required this.actionLabel, required this.onAction});

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900))),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _TodoRowCard extends StatelessWidget {
  const _TodoRowCard({required this.todo, required this.onToggle});

  final PersonalTodoItem todo;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: todo.done ? cs.surfaceContainerLow : cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant.withOpacity(.55))),
      child: CheckboxListTile(
        value: todo.done,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(todo.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w900, decoration: todo.done ? TextDecoration.lineThrough : null)),
        subtitle: Text(_todoSubtitle(todo), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EventRowCard extends StatelessWidget {
  const _EventRowCard({required this.event});

  final PersonalCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant.withOpacity(.55))),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.event_rounded, color: cs.onPrimaryContainer),
        ),
        title: Text(event.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w900)),
        subtitle: Text(_eventSubtitle(event), style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _EmptyInlineCard extends StatelessWidget {
  const _EmptyInlineCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _InlineCalendar extends StatelessWidget {
  const _InlineCalendar({required this.selectedDay, required this.todos, required this.events, required this.onSelectDay});

  final DateTime selectedDay;
  final List<PersonalTodoItem> todos;
  final List<PersonalCalendarEvent> events;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final month = DateTime(selectedDay.year, selectedDay.month, 1);
    final first = DateTime(month.year, month.month, 1);
    final startOffset = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: startOffset));
    final days = List<DateTime>.generate(42, (i) => DateTime(gridStart.year, gridStart.month, gridStart.day + i));
    final labels = const ['일', '월', '화', '수', '목', '금', '토'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: cs.outlineVariant.withOpacity(.55))),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: () => onSelectDay(DateTime(month.year, month.month - 1, 1)), icon: const Icon(Icons.chevron_left_rounded)),
              Expanded(child: Text('${month.year}년 ${month.month}월', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: () => onSelectDay(DateTime(month.year, month.month + 1, 1)), icon: const Icon(Icons.chevron_right_rounded)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: labels.map((label) => Expanded(child: Center(child: Text(label, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900))))).toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemBuilder: (context, index) {
              final day = days[index];
              final inMonth = day.month == month.month;
              final selected = _sameDay(day, selectedDay);
              final hasEvent = events.any((e) => _sameDay(e.dayOnly, day));
              final hasTodo = todos.any((t) => t.dueDate != null && _sameDay(t.dueDate!, day));
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelectDay(DateTime(day.year, day.month, day.day)),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : inMonth ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(.35)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${day.day}', style: text.labelMedium?.copyWith(color: selected ? cs.onPrimary : inMonth ? cs.onSurface : cs.onSurfaceVariant.withOpacity(.55), fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _DayDot(visible: hasEvent, color: selected ? cs.onPrimary : cs.primary),
                          if (hasEvent && hasTodo) const SizedBox(width: 3),
                          _DayDot(visible: hasTodo, color: selected ? cs.onPrimary : cs.tertiary),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 5, height: 5, decoration: BoxDecoration(color: visible ? color : Colors.transparent, shape: BoxShape.circle));
  }
}

class _PageSwitcher extends StatelessWidget {
  const _PageSwitcher({required this.current, required this.onTap});

  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final icons = <IconData>[
      Icons.directions_car_filled_rounded,
      Icons.checklist_rounded,
      Icons.calendar_month_rounded,
    ];
    final labels = <String>['내 차량', '할 일', '달력'];
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(999), border: Border.all(color: cs.outlineVariant.withOpacity(.45))),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: current == i ? cs.primary : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i], size: 17, color: current == i ? cs.onPrimary : cs.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(labels[i], style: TextStyle(color: current == i ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: FontWeight.w900, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


String _emptyDash(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? '-' : text;
}

DateTime? _parseMonthlyDate(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final normalized = text.replaceAll('.', '-').replaceAll('/', '-');
  final direct = DateTime.tryParse(normalized);
  if (direct != null) return DateTime(direct.year, direct.month, direct.day);
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

int? _monthlyDaysLeft(PlateStatusRecord record) {
  final end = _parseMonthlyDate(record.endDate);
  if (end == null) return null;
  return end.difference(_today()).inDays;
}

String _monthlyStatusLabel(PlateStatusRecord record) {
  final days = _monthlyDaysLeft(record);
  if (days == null) return '기간 확인 필요';
  if (days < 0) return '만료';
  if (days == 0) return '오늘 만료';
  if (days <= 7) return '만료 임박';
  return '이용 중';
}

String _monthlyDdayText(PlateStatusRecord record) {
  final days = _monthlyDaysLeft(record);
  if (days == null) return 'D-Day 확인 불가';
  if (days < 0) return '만료';
  if (days == 0) return 'D-Day';
  return 'D-$days';
}

String _monthlyPeriodSummary(PlateStatusRecord record) {
  final start = _emptyDash(record.startDate);
  final end = _emptyDash(record.endDate);
  final range = start == '-' && end == '-' ? '-' : '$start ~ $end';
  final status = _monthlyStatusLabel(record);
  final dday = _monthlyDdayText(record);
  if (range == '-') return '$status · $dday';
  return '$range · $status · $dday';
}

String _monthlyProductSummary(PlateStatusRecord record) {
  final regularType = _emptyDash(record.regularType);
  final durationValue = record.regularDurationValue ?? record.regularDurationHours;
  final periodUnit = _emptyDash(record.periodUnit);
  if (durationValue == null || durationValue <= 0 || periodUnit == '-') return regularType;
  return '$regularType · $durationValue$periodUnit';
}

String _formatWon(int? value) {
  if (value == null || value <= 0) return '-';
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final left = raw.length - i;
    buffer.write(raw[i]);
    if (left > 1 && left % 3 == 1) buffer.write(',');
  }
  return '${buffer}원';
}

String _formatPaymentAmount(String? amountText) {
  final text = (amountText ?? '').trim();
  if (text.isEmpty) return '-';
  final normalized = text.replaceAll(',', '').replaceAll('원', '').trim();
  final amount = int.tryParse(normalized);
  if (amount == null) return text;
  return _formatWon(amount);
}

PlateStatusPaymentRecord? _latestPayment(PlateStatusRecord record) {
  if (record.paymentHistory.isEmpty) return null;
  final payments = List<PlateStatusPaymentRecord>.from(record.paymentHistory);
  payments.sort((a, b) {
    final at = a.paidAt?.millisecondsSinceEpoch ?? -1;
    final bt = b.paidAt?.millisecondsSinceEpoch ?? -1;
    if (at != bt) return bt.compareTo(at);
    return record.paymentHistory.indexOf(b).compareTo(record.paymentHistory.indexOf(a));
  });
  return payments.first;
}

String _formatMonthlyPaymentDate(PlateStatusPaymentRecord payment) {
  if (payment.paidAt != null) return _formatDate(payment.paidAt!);
  final raw = (payment.paidAtRaw ?? '').trim();
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) return _formatDate(parsed);
  return raw;
}

String _recentPaymentSummary(PlateStatusRecord record) {
  final payment = _latestPayment(record);
  if (payment == null) return '-';
  final amount = _formatPaymentAmount(payment.amountText);
  final date = _formatMonthlyPaymentDate(payment);
  if (date.isEmpty) return amount;
  return '$date · $amount';
}

IconData _statusIcon(PlateType? type) {
  return switch (type) {
    PlateType.parkingCompleted => Icons.local_parking_rounded,
    PlateType.departureRequests => Icons.near_me_rounded,
    PlateType.departureCompleted => Icons.check_circle_outline_rounded,
    PlateType.parkingRequests => Icons.login_rounded,
    null => Icons.help_outline_rounded,
  };
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDate(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${d.year}.${two(d.month)}.${two(d.day)}';
}

String _formatKoreanDate(DateTime dt) {
  final d = dt.toLocal();
  return '${d.month}월 ${d.day}일';
}

String _todoSubtitle(PersonalTodoItem todo) {
  final parts = <String>[];
  if (todo.plateNumber.trim().isNotEmpty) parts.add(todo.plateNumber.trim());
  if (todo.dueDate != null) parts.add(_formatDate(todo.dueDate!));
  return parts.isEmpty ? '날짜 없음' : parts.join(' · ');
}

String _eventSubtitle(PersonalCalendarEvent event) {
  final parts = <String>[];
  if (event.plateNumber.trim().isNotEmpty) parts.add(event.plateNumber.trim());
  if (event.note.trim().isNotEmpty) parts.add(event.note.trim());
  return parts.isEmpty ? _formatDate(event.date) : parts.join(' · ');
}
