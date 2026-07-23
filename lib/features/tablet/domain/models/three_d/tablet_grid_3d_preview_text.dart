part of 'tablet_grid_3d_preview.dart';

class _AttentionPulse extends StatefulWidget {
  const _AttentionPulse({
    required this.color,
    required this.active,
  });

  final Color color;
  final bool active;

  @override
  State<_AttentionPulse> createState() => _AttentionPulseState();
}

class _AttentionPulseState extends State<_AttentionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !widget.active) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _AttentionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.active || reduceMotion) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(0.85),
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        final haloScale = 1.0 + (t * 0.8);
        final haloOpacity = 0.26 * (1.0 - t);
        final dotScale = 0.92 + ((1.0 - t) * 0.12);

        return SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: haloScale,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(haloOpacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Transform.scale(
                scale: dotScale,
                child: child,
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.34),
              blurRadius: 8,
              spreadRadius: 0.4,
            ),
          ],
        ),
      ),
    );
  }
}

extension _TabletGridTextPreviewPart on _TabletGrid3dPreviewState {
  Widget _textStatCard({
    required ColorScheme cs,
    required String label,
    required String value,
    required IconData icon,
    String? hint,
    Color? tone,
    bool emphasize = false,
    bool animate = false,
  }) {
    final base = tone ?? cs.primary;
    final bg =
    emphasize ? base.withOpacity(0.14) : cs.surface.withOpacity(0.16);
    final border =
    emphasize ? base.withOpacity(0.56) : cs.outlineVariant.withOpacity(0.42);
    final valueColor = emphasize ? base : cs.onSurface;
    final labelColor = emphasize ? cs.onSurface : cs.onSurfaceVariant;

    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.component),
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: emphasize ? 1.2 : 1),
        boxShadow: emphasize
            ? [
          BoxShadow(
            color: base.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ]
            : const [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: base.withOpacity(emphasize ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: base),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: labelColor,
                  ),
                ),
              ),
              if (emphasize)
                _AttentionPulse(
                  color: base,
                  active: animate,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 22,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          if (hint != null && hint.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: emphasize
                    ? base.withOpacity(0.92)
                    : cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _textSectionTitle({
    required ColorScheme cs,
    required String title,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTextPreviewPanel({
    required _PreviewEntry entry,
    required int index,
    required int count,
    required ColorScheme cs,
    required TextTheme tt,
  }) {
    final tokens = PromptUiTheme.of(context);
    final loc = entry.location;
    final capacity = max(
      0,
      _locationLooseInt(loc, [
        'capacity',
        'carLimit',
        'vehicleLimit',
        'maxCars',
        'maxCount',
        'parkingLimit',
      ]) ??
          loc.capacity,
    );
    final liveMetrics = resolveTextParkingPreviewMetrics(
      location: loc,
      metricsByLocation: widget.textMetricsByLocation,
    );
    final plateCount = max(
      0,
      liveMetrics?.parkingCompletedCount ??
          _locationLooseInt(loc, [
            'plateCount',
            'currentCount',
            'currentCars',
            'parkedCount',
            'cars',
          ]) ??
          loc.plateCount,
    );
    final departureRequestCount = max(
      0,
      liveMetrics?.departureRequestCount ??
          _locationLooseInt(loc, [
            'departureRequestCount',
            'exitRequestCount',
            'departureRequests',
            'requestDepartureCount',
            'outRequestCount',
          ]) ??
          0,
    );
    final available = capacity > 0 ? max(capacity - plateCount, 0) : null;
    final overCapacity = capacity > 0 && plateCount > capacity;
    final statusColor = overCapacity || available == 0 ? cs.error : cs.primary;

    final currentVehicleTone = tokens.statusParkingCompleted;
    final departureTone = tokens.statusDepartureRequested;

    final metricRows = <Widget>[
      Row(
        children: [
          Expanded(
            child: _textStatCard(
              cs: cs,
              label: '수용 대수',
              value: capacity > 0 ? '${capacity}대' : '미설정',
              hint: capacity > 0 ? '설정값 기준' : '입력 필요',
              icon: Icons.local_parking_rounded,
              tone: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _textStatCard(
              cs: cs,
              label: '입차 완료',
              value: '${plateCount}대',
              hint: plateCount > 0 ? '실제 집계값' : '현재 없음',
              icon: Icons.directions_car_filled_rounded,
              tone: currentVehicleTone,
              emphasize: true,
              animate: plateCount > 0,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _textStatCard(
              cs: cs,
              label: '여유 대수',
              value: available == null ? '계산 불가' : '${available}대',
              hint: overCapacity ? '수용 초과' : '수용-현재',
              icon: Icons.add_road_rounded,
              tone: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _textStatCard(
              cs: cs,
              label: '출차 요청',
              value: '${departureRequestCount}건',
              hint: departureRequestCount > 0 ? '처리 필요' : '요청 없음',
              icon: Icons.logout_rounded,
              tone: departureTone,
              emphasize: true,
              animate: departureRequestCount > 0,
            ),
          ),
        ],
      ),
    ];

    final previewBody = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.tertiaryContainer.withOpacity(0.28),
              cs.surfaceContainerLow,
            ],
          ),
          border:
          Border.all(color: cs.outlineVariant.withOpacity(0.65), width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _withSwipeAffordance(
          index: index,
          count: count,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _textSectionTitle(
                    cs: cs,
                    title: '실시간 요약',
                    icon: Icons.dashboard_rounded,
                  ),
                  const SizedBox(height: 10),
                  ...metricRows,
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return previewBody;
  }
}
