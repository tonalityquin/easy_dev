import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../dev/application/area_state.dart';
import 'personal_prompt_components.dart';

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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final area = context.select<AreaState, String>(
      (state) => state.currentArea,
    ).trim();
    final displayName = _name.isEmpty ? '고객' : _name;
    final displayArea = area.isEmpty ? '이용 지점 확인 중' : area;

    return Material(
      color: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      child: SafeArea(
        bottom: false,
        child: AnimatedContainer(
          duration: personalPromptDuration(context),
          height: 62,
          padding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border(
              bottom: BorderSide(color: tokens.borderSubtle),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: tokens.shadow,
                blurRadius: widget.menuOpen ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              PromptAnimatedReveal(
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: tokens.accent.withOpacity(.24),
                    ),
                  ),
                  child: Icon(
                    Icons.local_parking_rounded,
                    color: tokens.onAccentContainer,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ParkinWorkin',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    AnimatedSwitcher(
                      duration: personalPromptDuration(
                        context,
                        PromptUiMotion.selection,
                      ),
                      child: Text(
                        '$displayName님 · $displayArea',
                        key: ValueKey<String>('$displayName|$displayArea'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PromptIconButton(
                icon: widget.menuOpen
                    ? Icons.close_rounded
                    : Icons.menu_rounded,
                tooltip: widget.menuOpen ? '메뉴 닫기' : '메뉴',
                onPressed: widget.enabled ? widget.onMenuPressed : null,
                selected: widget.menuOpen,
                haptic: PromptHaptic.selection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
