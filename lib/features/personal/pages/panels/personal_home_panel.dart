import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../application/personal_calendar_store.dart';
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
  final PageController _pageController = PageController();

  List<PersonalSavedVehicle> _vehicles = const <PersonalSavedVehicle>[];
  List<PersonalTodoItem> _todos = const <PersonalTodoItem>[];
  List<PersonalCalendarEvent> _events = const <PersonalCalendarEvent>[];
  final Map<String, PlateModel?> _statusByVehicleId = <String, PlateModel?>{};
  final Set<String> _loadingVehicleIds = <String>{};
  bool _loadingVehicles = true;
  String _personalName = '';
  String? _selectedVehicleId;
  int _pageIndex = 0;
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
    _loadingVehicleIds.removeWhere((id) => !valid.contains(id));
    if (vehicles.isEmpty) {
      _statusByVehicleId.clear();
      _loadingVehicleIds.clear();
    }
  }

  Future<void> _refreshAllStatuses() async {
    final area = widget.area.trim();
    if (area.isEmpty || _vehicles.isEmpty) {
      if (mounted && _vehicles.isEmpty) {
        setState(() {
          _statusByVehicleId.clear();
          _loadingVehicleIds.clear();
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
    setState(() => _loadingVehicleIds.add(vehicle.id));
    try {
      final plate = await _statusService.fetchCurrentVehiclePlate(
        plateNumber: vehicle.plateNumber,
        area: area,
      );
      if (!mounted) return;
      setState(() {
        _statusByVehicleId[vehicle.id] = plate;
        _loadingVehicleIds.remove(vehicle.id);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusByVehicleId[vehicle.id] = null;
        _loadingVehicleIds.remove(vehicle.id);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _pageIndex = index),
            children: [
              _VehicleLocationPage(
                name: _personalName,
                area: widget.area,
                vehicles: _vehicles,
                selectedVehicle: _selectedVehicle,
                statusByVehicleId: _statusByVehicleId,
                loadingVehicleIds: _loadingVehicleIds,
                loadingVehicles: _loadingVehicles,
                onSelectVehicle: (vehicle) => setState(() => _selectedVehicleId = vehicle.id),
                onRefreshVehicle: _refreshVehicleStatus,
                onOpenVehicle: _openVehicle,
              ),
              _TodayTodoPage(
                todos: _todos,
                events: _events,
                onToggleTodo: _toggleTodo,
                onOpenTodo: _openTodoDialog,
                onOpenCalendar: _openCalendarDialog,
              ),
              _CalendarFocusPage(
                todos: _todos,
                events: _events,
                selectedDay: _selectedCalendarDay,
                onSelectDay: (day) => setState(() => _selectedCalendarDay = day),
                onToggleTodo: _toggleTodo,
                onOpenTodo: _openTodoDialog,
                onOpenCalendar: _openCalendarDialog,
              ),
            ],
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
            onTap: (index) {
              _pageController.animateToPage(
                index,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              );
            },
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
    required this.loadingVehicleIds,
    required this.loadingVehicles,
    required this.onSelectVehicle,
    required this.onRefreshVehicle,
    required this.onOpenVehicle,
  });

  final String name;
  final String area;
  final List<PersonalSavedVehicle> vehicles;
  final PersonalSavedVehicle? selectedVehicle;
  final Map<String, PlateModel?> statusByVehicleId;
  final Set<String> loadingVehicleIds;
  final bool loadingVehicles;
  final ValueChanged<PersonalSavedVehicle> onSelectVehicle;
  final Future<void> Function(PersonalSavedVehicle) onRefreshVehicle;
  final Future<void> Function(PersonalSavedVehicle) onOpenVehicle;

  @override
  Widget build(BuildContext context) {
    final vehicle = selectedVehicle;
    final plate = vehicle == null ? null : statusByVehicleId[vehicle.id];
    final loading = vehicle != null && loadingVehicleIds.contains(vehicle.id);
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
            _LocationMapCard(vehicle: vehicle!, plate: plate, loading: loading),
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
              '현재 주차 중인 위치 정보가 없습니다. 메뉴의 상태 새로고침 또는 차량 상세 보기를 이용해 주세요.',
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
