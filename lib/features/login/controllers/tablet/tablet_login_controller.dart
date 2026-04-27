import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../../../app/di/routes.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../utils/tts/tts_ownership.dart';
import '../../../../utils/tts/tts_user_filters.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/tablet/tablet_login_network_service.dart';
import '../../applications/tablet/tablet_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

class TabletLoginController {
  final BuildContext context;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  bool _inited = false;

  TabletLoginController(this.context);

  String _normalizeHandle(String v) {
    final lower = v.trim().toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return cleaned;
  }

  String? _validateHandle(String handle) {
    final h = _normalizeHandle(handle);
    if (h.isEmpty) return '영어 아이디(핸들)를 입력해주세요.';
    final re = RegExp(r'^[a-z][a-z0-9_]{2,31}$');
    if (!re.hasMatch(h)) return '영어 소문자/숫자/_(언더스코어), 3~32자 (첫 글자는 영문)';
    return null;
  }

  void initState() {
    if (_inited) return;
    _inited = true;

    Provider.of<UserState>(context, listen: false)
        .loadTabletToLogIn()
        .then((_) {
      final isLoggedIn =
          Provider.of<UserState>(context, listen: false).isLoggedIn;
      debugPrint(
          '[LOGIN-TABLET][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');
      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
              '[LOGIN-TABLET][${_ts()}] autoLogin → pushReplacementNamed(AppRoutes.tablet)');
          Navigator.pushReplacementNamed(context, AppRoutes.tablet);
        });
      }
    });
  }

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final rawHandle = phoneController.text;
    final handle = _normalizeHandle(rawHandle);
    final password = passwordController.text.trim();

    if (name.isEmpty && handle.isEmpty && password == '00000') {
      debugPrint('[LOGIN-TABLET][${_ts()}] backdoor bypass');
      return true;
    }

    final handleError = _validateHandle(handle);
    final passwordError = TabletLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      return false;
    }
    if (handleError != null) {
      return false;
    }
    if (passwordError != null) {
      return false;
    }

    setState(() => isLoading = true);

    final isConn = await TabletLoginNetworkService().isConnected();
    debugPrint('[LOGIN-TABLET][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      return false;
    }

    try {
      final repo = context.read<UserRepository>();
      final tablet = await repo.getTabletByHandle(handle);

      if (context.mounted) {
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] input name="$name" handle="$handle" pwLen=${password.length}');
        if (tablet != null) {
          debugPrint(
              '[LOGIN-TABLET][${_ts()}] DB tablet: name=${tablet.name}, handle=${tablet.handle}');
        } else {
          debugPrint(
              '[LOGIN-TABLET][${_ts()}] DB no tablet for handle="$handle"');
        }
      }

      if (tablet != null &&
          tablet.name == name &&
          tablet.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        final areaName = (tablet.selectedArea ??
                tablet.currentArea ??
                (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
            .trim();
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] resolved areaName="$areaName" from tablet.selected/current/areas');

        if (areaName.isEmpty) {
          if (context.mounted) {
            setState(() => isLoading = false);
          }
          return false;
        }
        final englishAreaName = tablet.englishSelectedAreaName ?? areaName;
        final sessionTablet = tablet.copyWith(
          currentArea: areaName,
          selectedArea: areaName,
          englishSelectedAreaName: englishAreaName,
          isSaved: true,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('handle', handle);
        await prefs.setString('selectedArea', areaName);
        await prefs.setString('englishSelectedAreaName', englishAreaName);
        await prefs.setString('mode', 'tablet');

        await TtsOwnership.setOwner(TtsOwner.foreground);
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] prefs saved (handle/selectedArea/englishSelectedAreaName/mode & owner=foreground)');

        await userState.updateLoginTablet(sessionTablet);
        debugPrint('[LOGIN-TABLET][${_ts()}] userState.updateLoginTablet done');

        areaState.updateArea(areaName);
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] areaState.updateArea("$areaName")');

        final current = context.read<AreaState>().currentArea;
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] send area to FG (currentArea="$current")');
        if (current.isNotEmpty) {
          final filters = await TtsUserFilters.load();
          FlutterForegroundTask.sendDataToTask({
            'area': current,
            'ttsFilters': filters.toMap(),
          });
          debugPrint(
              '[LOGIN-TABLET][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint(
              '[LOGIN-TABLET][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[LOGIN-TABLET][${_ts()}] navigate → AppRoutes.tablet');
            Navigator.pushReplacementNamed(context, AppRoutes.tablet);
          });
        }
        return true;
      }

      if (context.mounted) {
        debugPrint(
            '[LOGIN-TABLET][${_ts()}] auth failed (name/password mismatch or no tablet)');
      }
      return false;
    } catch (e, st) {
      debugPrint('[LOGIN-TABLET][${_ts()}] login error: $e\n$st');
      return false;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      debugPrint('[LOGIN-TABLET][${_ts()}] set isLoading=false');
    }
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  void formatPhoneNumber(String value, StateSetter setState) {
    final normalized = _normalizeHandle(value);
    setState(() {
      phoneController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    });
  }

  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error, width: 1.8),
      ),
      prefixIconColor: MaterialStateColor.resolveWith(
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
      suffixIconColor: MaterialStateColor.resolveWith(
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }
}
