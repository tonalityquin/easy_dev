import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class HeadquarterDashboardContext {
  HeadquarterDashboardContext._();

  static final ValueNotifier<String> currentModeKey = ValueNotifier<String>('');

  static const Set<String> _supportedModes = <String>{
    'single',
    'double',
    'triple',
    'minor',
  };

  static void publishMode(
    String modeKey, {
    String source = 'unknown',
  }) {
    final normalized = normalizeModeKey(modeKey);
    if (normalized.isEmpty || currentModeKey.value == normalized) return;
    final previous = currentModeKey.value;
    currentModeKey.value = normalized;
    debugPrint(
      '[HQ-DASH-CONTEXT] mode_update source=$source previous=${previous.isEmpty ? 'none' : previous} next=$normalized storage=memory additionalFirebaseRead=0 additionalFirebaseWrite=0',
    );
  }

  static String normalizeModeKey(String value) {
    final normalized = value.trim().toLowerCase();
    return _supportedModes.contains(normalized) ? normalized : '';
  }

  static String modeKeyFromScreen(String screenName) {
    final screen = screenName.trim().toLowerCase();
    if (screen.contains('minor')) return 'minor';
    if (screen.contains('triple')) return 'triple';
    if (screen.contains('double') || screen.contains('lite')) return 'double';
    if (screen.contains('single')) return 'single';
    return normalizeModeKey(currentModeKey.value);
  }

  static String exactModeLabel(String modeKey) {
    switch (normalizeModeKey(modeKey)) {
      case 'single':
        return '싱글';
      case 'double':
        return '더블';
      case 'triple':
        return '트리플';
      case 'minor':
        return '마이너';
      default:
        return '본사';
    }
  }

  static String modeLabel(String modeKey) {
    switch (normalizeModeKey(modeKey)) {
      case 'single':
        return '싱글 · 경량형';
      case 'double':
        return '더블 · 경량형';
      case 'triple':
        return '트리플 · 기본형';
      case 'minor':
        return '마이너 · 확장형';
      default:
        return '본사';
    }
  }
}

class HeadquarterDashboardContextScope extends StatefulWidget {
  const HeadquarterDashboardContextScope({
    super.key,
    required this.modeKey,
    required this.child,
    this.source = 'headquarter_dashboard_scope',
  });

  final String modeKey;
  final Widget child;
  final String source;

  @override
  State<HeadquarterDashboardContextScope> createState() =>
      _HeadquarterDashboardContextScopeState();
}

class _HeadquarterDashboardContextScopeState
    extends State<HeadquarterDashboardContextScope> {
  @override
  void initState() {
    super.initState();
    _publish();
  }

  @override
  void didUpdateWidget(covariant HeadquarterDashboardContextScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modeKey != widget.modeKey || oldWidget.source != widget.source) {
      _publish();
    }
  }

  void _publish() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HeadquarterDashboardContext.publishMode(
        widget.modeKey,
        source: widget.source,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
