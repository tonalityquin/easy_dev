import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../dev/application/area_state.dart';

class PersonalTopNavigation extends StatefulWidget {
  const PersonalTopNavigation({
    super.key,
    required this.menuOpen,
    required this.onMenuPressed,
    this.enabled = true,
  });

  final bool menuOpen;
  final VoidCallback onMenuPressed;
  final bool enabled;

  @override
  State<PersonalTopNavigation> createState() => _PersonalTopNavigationState();
}

class _PersonalTopNavigationState extends State<PersonalTopNavigation> {
  String _name = '';

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _name = (prefs.getString('personalName') ?? '').trim());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final area = context.select<AreaState, String>((s) => s.currentArea).trim();
    final displayName = _name.isEmpty ? '고객' : _name;
    final displayArea = area.isEmpty ? '이용 지점 확인 중' : area;

    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 58,
          padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(.45)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(cs.primary.withOpacity(.12), cs.surface),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(.12)),
                ),
                child: Icon(Icons.local_parking_rounded, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ParkinWorkin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$displayName님 · $displayArea',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.2,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: widget.menuOpen ? '메뉴 닫기' : '메뉴',
                onPressed: widget.enabled ? widget.onMenuPressed : null,
                icon: const Icon(Icons.menu_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
