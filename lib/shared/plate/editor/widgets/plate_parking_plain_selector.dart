import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/location/domain/models/location_model.dart';

class PlateParkingPlainSelector extends StatefulWidget {
  const PlateParkingPlainSelector({
    super.key,
    required this.locations,
    required this.currentLocation,
    required this.area,
    required this.onSelected,
    this.onDebug,
  });

  final List<LocationModel> locations;
  final String currentLocation;
  final String area;
  final ValueChanged<LocationModel> onSelected;
  final ValueChanged<String>? onDebug;

  @override
  State<PlateParkingPlainSelector> createState() =>
      _PlateParkingPlainSelectorState();
}

class _PlateParkingPlainSelectorState extends State<PlateParkingPlainSelector> {
  String _lastSignature = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
  }

  @override
  void didUpdateWidget(covariant PlateParkingPlainSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportReady());
  }

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  void _reportReady() {
    if (!mounted) return;
    final signature =
        '${widget.area}|${widget.locations.map((e) => e.locationName).join('|')}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    widget.onDebug?.call(
      'parking_plain_selector=ready area=${widget.area} count=${widget.locations.length}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final currentKey = _normalize(widget.currentLocation);
    return Material(
      color: tokens.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  size: 18,
                  color: tokens.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '텍스트형 주차 구역',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '${widget.locations.length}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              itemCount: widget.locations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final location = widget.locations[index];
                final current =
                    currentKey.isNotEmpty && _normalize(location.locationName) == currentKey;
                return _PlateParkingPlainTile(
                  location: location,
                  current: current,
                  onTap: () => widget.onSelected(location),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlateParkingPlainTile extends StatefulWidget {
  const _PlateParkingPlainTile({
    required this.location,
    required this.current,
    required this.onTap,
  });

  final LocationModel location;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_PlateParkingPlainTile> createState() => _PlateParkingPlainTileState();
}

class _PlateParkingPlainTileState extends State<_PlateParkingPlainTile> {
  bool _pressed = false;
  bool _activating = false;

  void _setPressed(bool value) {
    if (!mounted || _activating || _pressed == value) return;
    setState(() => _pressed = value);
  }

  Future<void> _activate() async {
    if (_activating) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() {
      _pressed = false;
      _activating = true;
    });
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 105));
      if (!mounted) return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = widget.current || _activating;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 140);
    return Semantics(
      button: true,
      selected: widget.current,
      label: widget.location.locationName,
      child: AnimatedScale(
        scale: _activating ? .97 : (_pressed ? .985 : 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _pressed ? .86 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTapDown: (_) => _setPressed(true),
              onTapCancel: () => _setPressed(false),
              onTapUp: (_) => _setPressed(false),
              onTap: () => unawaited(_activate()),
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                decoration: BoxDecoration(
                  color: active ? tokens.surfaceSelected : tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active ? tokens.accent : tokens.borderSubtle,
                    width: active ? 1.25 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: active
                            ? tokens.accent.withOpacity(.12)
                            : tokens.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.local_parking_rounded,
                        size: 20,
                        color: active ? tokens.accent : tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.location.locationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: active
                                      ? tokens.accent
                                      : tokens.textPrimary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '수용 ${widget.location.capacity}대${widget.current ? ' · 현재 위치' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: active
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey<String>('selected'),
                              color: tokens.accent,
                              size: 20,
                            )
                          : Icon(
                              Icons.chevron_right_rounded,
                              key: const ValueKey<String>('idle'),
                              color: tokens.textSecondary,
                              size: 20,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
