import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/selector/application/dev_auth.dart';
import '../diagnostics/firebase_activity_meter.dart';
import '../init/app_navigator.dart';
import 'status_dialog.dart';
import '../../shared/plate/domain/enums/plate_type.dart';
import '../../shared/plate/domain/models/plate_model.dart';
import '../../shared/plate/domain/models/plate_view_verification_plan.dart';

class _DeveloperStatusEvent {
  const _DeveloperStatusEvent({
    required this.id,
    required this.time,
    required this.operation,
    required this.message,
    required this.failed,
    required this.details,
  });

  final int id;
  final DateTime time;
  final String operation;
  final String message;
  final bool failed;
  final Map<String, Object?> details;

  String get code => message
      .split('\n')
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');
}

class DevFirebaseDebugDialog {
  DevFirebaseDebugDialog._();

  static const int _capacity = 200;
  static final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  static final List<_DeveloperStatusEvent> _events = <_DeveloperStatusEvent>[];
  static bool _showing = false;
  static bool _listeningToMode = false;
  static int _sequence = 0;
  static int _discarded = 0;

  static void _ensureModeListener() {
    if (_listeningToMode) return;
    _listeningToMode = true;
    DevAuth.devModeEnabled.addListener(() {
      if (DevAuth.devModeEnabled.value) return;
      _events.clear();
      _discarded = 0;
      _changes.value++;
    });
  }

  static String get _allDebugPrintCode =>
      _events.map((event) => event.code).join('\n');

  static Future<void> show({
    BuildContext? context,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
    String title = 'Firebase 디버그',
    bool useCommonUi = false,
    bool success = false,
    bool copyAsDebugPrintCode = false,
    bool devModeOnly = false,
  }) async {
    final fullText = _buildFullText(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    debugPrint(fullText);

    final enabled = devModeOnly
        ? await DevAuth.isDevModeEnabled()
        : await DevAuth.isDeveloperLoggedIn();
    if (!enabled || !DevAuth.devModeEnabled.value) return;

    _ensureModeListener();
    _events.add(_DeveloperStatusEvent(
      id: ++_sequence,
      time: DateTime.now(),
      operation: operation,
      message: fullText,
      failed: error != null ||
          (details['verification'] == 'VERIFY_INCONCLUSIVE' ||
                  details['verification'] == 'VERIFY_PENDING_WRITES'
              ? false
              : !success),
      details: Map<String, Object?>.unmodifiable(details),
    ));
    if (_events.length > _capacity) {
      _discarded += _events.length - _capacity;
      _events.removeRange(0, _events.length - _capacity);
    }
    _changes.value++;

    if (_showing) return;
    final ctx = _resolveContext(context);
    if (ctx == null || !ctx.mounted) return;
    _showing = true;
    unawaited(_showHistory(ctx, useCommonUi: useCommonUi));
  }

  static Future<void> _showHistory(
    BuildContext context, {
    required bool useCommonUi,
  }) async {
    try {
      await StatusDialog.show(
        context,
        title: '개발자 STATUS 기록',
        tone: StatusDialogTone.success,
        copyText: 'debugPrint(',
        copyTextProvider: () async => _allDebugPrintCode,
        copyButtonLabel: '전체 debugPrint 코드 복사',
        requireDeveloperModeForCopy: true,
        developerContent: const _DeveloperStatusHistory(),
        visibleDuration: Duration.zero,
        awaitManualClose: true,
        useCommonUi: useCommonUi,
      );
    } catch (error, stackTrace) {
      debugPrint('[DEV_STATUS] dialog_failed=$error\n$stackTrace');
    } finally {
      _showing = false;
    }
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context != null && context.mounted) return context;
    final appContext = AppNavigator.context;
    if (appContext != null && appContext.mounted) return appContext;
    return null;
  }

  static String _buildFullText({
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final now = DateTime.now().toIso8601String();
    final b = StringBuffer()
      ..writeln('[Firebase Debug]')
      ..writeln('time: $now')
      ..writeln('operation: $operation');

    if (details.isNotEmpty) {
      b.writeln('details:');
      for (final entry in details.entries) {
        b.writeln('- ${entry.key}: ${_stringify(entry.value)}');
      }
    }

    if (error != null) {
      b.writeln('errorType: ${error.runtimeType}');
      if (error is FirebaseException) {
        b.writeln('firebase.plugin: ${error.plugin}');
        b.writeln('firebase.code: ${error.code}');
        if ((error.message ?? '').trim().isNotEmpty) {
          b.writeln('firebase.message: ${error.message}');
        }
      }
      b.writeln('error: $error');
    }

    if (stackTrace != null) {
      b.writeln('stackTrace:');
      b.writeln(stackTrace.toString());
    }

    return b.toString().trimRight();
  }

  static String _stringify(Object? value) {
    if (value == null) return 'null';
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_stringify(entry.value)}')
          .join(', ');
    }
    if (value is Iterable) {
      return value.map((entry) => _stringify(entry)).join(', ');
    }
    return value.toString();
  }
}

class _DeveloperStatusHistory extends StatefulWidget {
  const _DeveloperStatusHistory();

  @override
  State<_DeveloperStatusHistory> createState() => _DeveloperStatusHistoryState();
}

class _DeveloperStatusHistoryState extends State<_DeveloperStatusHistory> {
  int? _selectedId;
  int? _copiedId;
  bool _verifying = false;

  Future<void> _copySelected(_DeveloperStatusEvent event) async {
    if (!DevAuth.devModeEnabled.value ||
        !await DevAuth.isDevModeEnabled()) return;
    if (!mounted || !DevAuth.devModeEnabled.value) return;
    try {
      await Clipboard.setData(ClipboardData(text: event.code));
      if (mounted && DevAuth.devModeEnabled.value) {
        setState(() => _copiedId = event.id);
      }
    } catch (error) {
      debugPrint('[DEV_STATUS] selected_copy_failed=$error');
    }
  }

  String _verificationArea(_DeveloperStatusEvent event) {
    if (event.details['verificationPlanVersion'] == 1) {
      return event.details['areaAfter']?.toString().trim() ?? '';
    }
    if (event.details.containsKey('actualViewArea')) {
      return event.details['actualViewArea']?.toString().trim() ?? '';
    }
    return (event.details['area'] ?? event.details['areaArgument'])
            ?.toString()
            .trim() ??
        '';
  }

  bool _canVerify(_DeveloperStatusEvent event) =>
      event.details['verificationPlanVersion'] == 1 &&
      event.details['verificationEligible'] == true &&
      (event.details['plateDocId']?.toString().trim().isNotEmpty ?? false) &&
      _verificationArea(event).isNotEmpty;

  Future<void> _verifySelected(_DeveloperStatusEvent event) async {
    if (!_canVerify(event) || _verifying) return;
    if (!DevAuth.devModeEnabled.value ||
        !await DevAuth.isDevModeEnabled()) return;
    if (!mounted || !DevAuth.devModeEnabled.value) return;
    setState(() => _verifying = true);
    const collections = <String>[
      'parking_requests_view',
      'parking_completed_view',
      'departure_requests_view',
    ];
    final plateId = event.details['plateDocId']!.toString().trim();
    final eventArea = _verificationArea(event);
    final beforeArea = event.details['areaBefore']?.toString().trim() ?? '';
    final expectedType =
        plateTypeFromFirestoreValue(event.details['expectedPlateType']);
    final expectedNumber =
        event.details['expectedPlateNumber']?.toString().trim() ?? '';
    final checks = <String, String>{};
    var pending = false;
    var serverGets = 0;
    var invalid = 0;
    var found = 0;
    var verdict = 'VERIFY_INCONCLUSIVE';
    var reason = 'VERIFICATION_PLAN_INCOMPLETE';
    String? currentType;
    String? currentArea;
    String? currentNumber;
    Object? error;
    StackTrace? stackTrace;
    try {
      final source = await FirebaseFirestore.instance
          .collection('plates')
          .doc(plateId)
          .get(const GetOptions(source: Source.server))
          .trackFirestore(
            'GET',
            'app/utils/dev_firebase_debug_dialog.dart',
            collection: 'plates',
            pathTemplate: 'plates/*',
            readPurpose: 'MANUAL_PLATE_VIEW_VERIFY',
          );
      serverGets++;
      pending = source.metadata.hasPendingWrites;
      final data = source.data();
      final currentPlateType =
          plateTypeFromFirestoreValue(data?[PlateFields.type]);
      currentType = currentPlateType?.firestoreValue;
      currentArea = data?[PlateFields.area]?.toString().trim();
      currentNumber = data?[PlateFields.plateNumber]?.toString().trim();
      if (!source.exists || data == null) {
        reason = 'SOURCE_NOT_FOUND';
      } else if (pending) {
        verdict = 'VERIFY_PENDING_WRITES';
        reason = 'SOURCE_PENDING_WRITES';
      } else if (expectedType == null || expectedNumber.isEmpty ||
          currentPlateType == null || currentArea == null ||
          currentArea.isEmpty || currentNumber == null ||
          currentNumber.isEmpty) {
        reason = 'SOURCE_OR_EXPECTATION_INCOMPLETE';
      } else if (currentPlateType != expectedType ||
          currentArea != eventArea || currentNumber != expectedNumber) {
        reason = 'EVENT_SOURCE_CHANGED';
      } else {
        final areas = <String>[
          currentArea,
          if (beforeArea.isNotEmpty && beforeArea != currentArea) beforeArea,
        ];
        final expectedCollection =
            PlateViewVerificationPlan.collectionFor(currentPlateType);
        var matches = true;
        for (final area in areas) {
          for (final collection in collections) {
            if (!DevAuth.devModeEnabled.value) {
              reason = 'DEVELOPER_MODE_DISABLED';
              return;
            }
            final snapshot = await FirebaseFirestore.instance
                .collection(collection)
                .doc(area)
                .get(const GetOptions(source: Source.server))
                .trackFirestore(
                  'GET',
                  'app/utils/dev_firebase_debug_dialog.dart',
                  collection: collection,
                  pathTemplate: '$collection/*',
                  readPurpose: 'MANUAL_PLATE_VIEW_VERIFY',
                );
            serverGets++;
            pending = pending || snapshot.metadata.hasPendingWrites;
            final items = snapshot.data()?['items'];
            if (items != null && items is! Map) {
              checks['$collection/$area'] = 'ITEMS_SCHEMA_INVALID';
              invalid++;
              matches = false;
              continue;
            }
            final existsInItems = items is Map && items.containsKey(plateId);
            final entry = existsInItems ? items[plateId] : null;
            final shouldExist = area == currentArea &&
                collection == expectedCollection;
            final key = '$collection/$area';
            if (!existsInItems) {
              checks[key] = 'ABSENT';
              if (shouldExist) matches = false;
              continue;
            }
            found++;
            if (entry is! Map) {
              checks[key] = 'PRESENT_SCHEMA_INVALID';
              invalid++;
              matches = false;
              continue;
            }
            final number = entry[PlateFields.plateNumber];
            final schemaOk = number is String &&
                number.trim().isNotEmpty &&
                number == currentNumber &&
                !entry.containsKey('plateNumber');
            if (!schemaOk) invalid++;
            checks[key] = schemaOk
                ? 'PRESENT_SCHEMA_OK'
                : 'PRESENT_SCHEMA_INVALID';
            if (!shouldExist || !schemaOk) matches = false;
          }
        }
        if (pending) {
          verdict = 'VERIFY_PENDING_WRITES';
          reason = 'PENDING_LOCAL_WRITES';
        } else if (matches) {
          verdict = 'VERIFY_PASSED';
          reason = 'CURRENT_SOURCE_AND_VIEWS_MATCH';
        } else {
          verdict = 'VERIFY_FAILED';
          reason = 'CURRENT_VIEW_STATE_MISMATCH';
        }
      }
    } catch (e, st) {
      error = e;
      stackTrace = st;
      verdict = 'VERIFY_READ_FAILED';
      reason = 'SERVER_READ_ERROR';
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
    if (!DevAuth.devModeEnabled.value || !mounted) return;
    await DevFirebaseDebugDialog.show(
      operation: 'plateView.manualServerVerification',
      error: error,
      stackTrace: stackTrace,
      details: <String, Object?>{
        'plateDocId': plateId,
        'operationSourceEventId': event.id,
        'areaAfter': eventArea,
        'areaBefore': beforeArea,
        'expectedPlateType': expectedType?.firestoreValue,
        'expectedPlateNumber': expectedNumber,
        'expectedViewCollection':
            PlateViewVerificationPlan.collectionFor(expectedType),
        'sourceCurrentType': currentType,
        'sourceCurrentArea': currentArea,
        'sourceCurrentPlateNumber': currentNumber,
        'viewResultAtOperation': event.details['viewResult'],
        'verification': verdict,
        'verificationReason': reason,
        'foundInViewCount': found,
        'invalidSchemaCount': invalid,
        'hasPendingWrites': pending,
        'perCollectionAndArea': checks,
        'serverGets': serverGets,
        'serverGetsMaximum': beforeArea.isNotEmpty && beforeArea != eventArea
            ? 7
            : 4,
        'verificationScope': 'CURRENT_SOURCE_STATE',
        'verificationTime': DateTime.now().toIso8601String(),
      },
      title: 'View 서버 데이터 검증',
      success: verdict == 'VERIFY_PASSED',
      useCommonUi: true,
      copyAsDebugPrintCode: true,
      devModeOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<bool>(
      valueListenable: DevAuth.devModeEnabled,
      builder: (context, enabled, _) {
        if (!enabled) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('개발자 모드가 종료되었습니다.'),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: DevFirebaseDebugDialog._changes,
          builder: (context, version, _) {
            final events = DevFirebaseDebugDialog._events.toList()
              ..sort((a, b) {
                if (a.failed != b.failed) return a.failed ? -1 : 1;
                return b.id.compareTo(a.id);
              });
            final selected = events.isEmpty
                ? null
                : events.firstWhere(
                    (e) => e.id == _selectedId,
                    orElse: () => events.first,
                  );
            final argumentArea =
                selected?.details['areaArgument']?.toString().trim() ?? '';
            final actualArea =
                selected == null ? '' : _verificationArea(selected);
            final areaMismatch = argumentArea.isNotEmpty &&
                actualArea.isNotEmpty &&
                argumentArea != actualArea;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '최근 ${events.length}건 · 이전 제외 ${DevFirebaseDebugDialog._discarded}건',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 175,
                  child: ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final active = selected?.id == event.id;
                      return AnimatedContainer(
                        duration: duration,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: active
                              ? colors.primaryContainer.withOpacity(0.38)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          dense: true,
                          selected: active,
                          leading: Icon(
                            event.failed
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: event.failed ? colors.error : colors.primary,
                            size: 20,
                          ),
                          title: Text(
                            event.operation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            event.time.toLocal().toIso8601String(),
                            maxLines: 1,
                          ),
                          onTap: () => setState(() {
                            _selectedId = event.id;
                            _copiedId = null;
                          }),
                        ),
                      );
                    },
                  ),
                ),
                if (selected != null) ...<Widget>[
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.97, end: 1)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: Container(
                      key: ValueKey<int>(selected.id),
                      height: 120,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          selected.message,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  if (selected.details['verificationPlanVersion'] == 1) ...<Widget>[
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Container(
                        key: ValueKey<String>(
                          'verify-plan-${selected.id}-${selected.details['expectedPlateType']}',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '기대 상태: ${selected.details['expectedPlateType'] ?? "미확정"} · 목표 View: ${selected.details['expectedViewCollection'] ?? "모두 없음"}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  if (selected.details.containsKey('actualViewArea')) ...<Widget>[
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: duration,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Container(
                        key: ValueKey<String>(
                          'region-${selected.id}-$actualArea',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: actualArea.isEmpty
                              ? colors.surfaceContainerHighest
                              : areaMismatch
                                  ? colors.errorContainer.withOpacity(0.45)
                                  : colors.primaryContainer.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              actualArea.isEmpty
                                  ? Icons.remove_circle_outline
                                  : areaMismatch
                                      ? Icons.warning_amber_rounded
                                      : Icons.location_on_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                actualArea.isEmpty
                                    ? 'View 쓰기 생략 · 서버 저장 검증 없음'
                                    : argumentArea.isEmpty
                                        ? '실제 저장/검증 지역: $actualArea'
                                        : '화면 지역: $argumentArea · 실제 저장/검증 지역: $actualArea',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (_canVerify(selected))
                    OutlinedButton.icon(
                      onPressed: _verifying ? null : () => _verifySelected(selected),
                      icon: _verifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_outlined),
                      label: Text('현재 상태 서버 검증 (최대 ${((selected.details['areaBefore']?.toString().trim().isNotEmpty ?? false) && selected.details['areaBefore'] != selected.details['areaAfter']) ? 7 : 4} GET)'),
                    ),
                  AnimatedScale(
                    scale: _copiedId == selected.id ? 1.025 : 1,
                    duration: duration,
                    child: OutlinedButton.icon(
                      onPressed: () => _copySelected(selected),
                      icon: Icon(
                        _copiedId == selected.id
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                      ),
                      label: Text(
                        _copiedId == selected.id
                            ? '복사 완료'
                            : '선택 debugPrint 코드 복사',
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
