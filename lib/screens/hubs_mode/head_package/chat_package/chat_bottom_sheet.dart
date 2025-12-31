import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/sheet_chat_service.dart';
import '../../../../states/user/user_state.dart';
import '../../noti_package/shared_spreadsheet_registry.dart';
import '../../noti_package/spreadsheet_registry_bottom_sheet.dart';
import 'chat_panel.dart';
import 'chat_runtime.dart';
import 'chat_log_mailer.dart';

/// 좌측 상단(11시) 라벨 텍스트
const String _screenTag = 'chat';

String _resolveScopeKey(BuildContext context) {
  final currentUser = context.read<UserState>().user;
  final v = currentUser?.currentArea?.trim();
  if (v != null && v.isNotEmpty) return v;
  return kFallbackScopeKey;
}

/// 11시 라벨 위젯 (LocationManagement와 동일 스타일)
Widget _buildScreenTag(BuildContext context) {
  final base = Theme.of(context).textTheme.labelSmall;
  final style = (base ??
      const TextStyle(
        fontSize: 11,
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ))
      .copyWith(
    color: Colors.black54,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  return SafeArea(
    top: true,
    bottom: false,
    left: false,
    right: false,
    child: IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Semantics(
            label: 'screen_tag: $_screenTag',
            child: Text(_screenTag, style: style),
          ),
        ),
      ),
    ),
  );
}

/// ✅ (공용 레지스트리 기반) 채팅용 스프레드시트 선택을 Runtime에 반영
Future<void> _applyActiveChatSheetToRuntime() async {
  final id =
  SharedSpreadsheetRegistry.activeSpreadsheetIdOf(HeadSheetFeature.chat);
  if (id != null && id.trim().isNotEmpty) {
    await ChatRuntime.instance.selectSheetAndRestart(id.trim());
  }
}

/// ✅ (공용 레지스트리 기반) 채팅 시트 관리(별명+ID) 바텀시트
Future<void> _openChatSheetRegistry(BuildContext context) async {
  await SpreadsheetRegistryBottomSheet.showAsBottomSheet(
    context: context,
    feature: HeadSheetFeature.chat,
    title: '채팅 스프레드시트 목록/선택',
    themeBase: const Color(0xFF455A64),
    themeDark: const Color(0xFF263238),
    themeLight: const Color(0xFFB0BEC5),
  );

  // 레지스트리에서 “채팅 활성 별명”이 바뀌었을 수 있으니 Runtime에 반영
  await _applyActiveChatSheetToRuntime();
}

Widget _buildSheetSelectorBar(BuildContext context) {
  return ValueListenableBuilder<bool>(
    valueListenable: ChatRuntime.instance.useSheetsApi,
    builder: (context, apiOn, _) {
      if (!apiOn) return const SizedBox.shrink();

      return ValueListenableBuilder<List<SheetAliasEntry>>(
        valueListenable: SharedSpreadsheetRegistry.entriesNotifier,
        builder: (context, list, __) {
          if (list.isEmpty) return const SizedBox.shrink();

          return ValueListenableBuilder<String>(
            valueListenable: SharedSpreadsheetRegistry.activeChatAliasNotifier,
            builder: (context, selAlias, ___) {
              final selectedAlias = selAlias.trim();

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final e in list) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(e.alias),
                                    selected: e.alias == selectedAlias,
                                    onSelected: (_) async {
                                      // 1) 채팅 활성 별명 설정
                                      await SharedSpreadsheetRegistry
                                          .setActiveAlias(
                                        HeadSheetFeature.chat,
                                        e.alias,
                                      );
                                      // 2) Runtime 재시작(선택된 spreadsheetId로)
                                      await _applyActiveChatSheetToRuntime();
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: '관리',
                        onPressed: () => _openChatSheetRegistry(context),
                        icon: const Icon(Icons.settings),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// ─────────────────────────────────────────────────────────────
/// ✅ 핵심 리팩터링 포인트:
/// - Lite 팝오버와 동일하게, 바텀시트가 "실제로 보이는 동안만"
///   ChatRuntime.start()를 유지하고,
///   닫히면 dispose에서 ChatRuntime.stop()으로 즉시 release.
/// - Sheets 모드일 때만 알림 억제 플래그(chatUiVisible) ON.
/// ─────────────────────────────────────────────────────────────

class _ChatBottomSheetHost extends StatefulWidget {
  final String scopeKey;

  const _ChatBottomSheetHost({
    required this.scopeKey,
  });

  @override
  State<_ChatBottomSheetHost> createState() => _ChatBottomSheetHostState();
}

class _ChatBottomSheetHostState extends State<_ChatBottomSheetHost> {
  bool _booted = false;

  /// Sheets 모드에서만 chatUiVisible을 true로 유지
  bool _chatUiVisibleHeld = false;

  VoidCallback? _useSheetsListener;

  @override
  void initState() {
    super.initState();
    _boot();

    // ✅ 모드 토글(ON/OFF)에 따라 chatUiVisible 정합성 유지
    _useSheetsListener = () {
      _syncChatUiVisibleWithMode();
    };
    ChatRuntime.instance.useSheetsApi.addListener(_useSheetsListener!);
  }

  Future<void> _boot() async {
    await ChatRuntime.instance.ensureInitialized();
    await SharedSpreadsheetRegistry.ensureBootstrapped();

    // 초기 진입 시에도 현재 선택을 Runtime에 반영
    await _applyActiveChatSheetToRuntime();

    // ✅ 바텀시트 "표시 중" 상태로 시작 (Sheets면 acquire)
    await ChatRuntime.instance.start(widget.scopeKey);

    // ✅ Sheets 모드면 알림 억제 ON
    _syncChatUiVisibleWithMode();

    if (!mounted) return;
    setState(() {
      _booted = true;
    });
  }

  void _syncChatUiVisibleWithMode() {
    final sheetsOn = ChatRuntime.instance.useSheetsApi.value;

    if (sheetsOn) {
      if (!_chatUiVisibleHeld) {
        SheetChatService.instance.setChatUiVisible(true);
        _chatUiVisibleHeld = true;
      }
    } else {
      if (_chatUiVisibleHeld) {
        SheetChatService.instance.setChatUiVisible(false);
        _chatUiVisibleHeld = false;
      }
    }
  }

  @override
  void dispose() {
    if (_useSheetsListener != null) {
      ChatRuntime.instance.useSheetsApi.removeListener(_useSheetsListener!);
    }

    // ✅ 바텀시트 종료 시 알림 억제 해제
    if (_chatUiVisibleHeld) {
      SheetChatService.instance.setChatUiVisible(false);
      _chatUiVisibleHeld = false;
    }

    // ✅ (핵심) 바텀시트가 닫히면 즉시 stop → Sheets 모드면 release로 폴링 완전 중단
    unawaited(ChatRuntime.instance.stop());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        _buildScreenTag(context),
        Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(width: 4),
                      const Icon(Icons.forum,
                          size: 20, color: Colors.black87),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '구역 채팅',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // ✅ 채팅 로그 PDF 메일 전송
                      IconButton(
                        tooltip: '채팅 로그를 PDF로 메일 전송',
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        onPressed: () async {
                          await ChatLogMailer.open(context);
                        },
                      ),

                      // ✅ Sheets API ON/OFF 토글 (기본 OFF)
                      ValueListenableBuilder<bool>(
                        valueListenable: ChatRuntime.instance.useSheetsApi,
                        builder: (context, on, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                on ? 'API ON' : 'API OFF',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: on ? Colors.blueGrey : Colors.black54,
                                ),
                              ),
                              Switch.adaptive(
                                value: on,
                                onChanged: (v) async {
                                  await ChatRuntime.instance.setUseSheetsApi(v);

                                  // ✅ UI가 열려있는 동안은 start 유지
                                  await ChatRuntime.instance
                                      .start(ChatRuntime.instance.scopeKey);

                                  // ✅ 모드 변경 즉시 chatUiVisible 정합성 반영
                                  _syncChatUiVisibleWithMode();
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ✅ 선택된 스프레드시트(별명) 전환 바 (API ON일 때만 표시)
            _buildSheetSelectorBar(context),

            const SizedBox(height: 6),
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFEAEAEA),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                // ✅ ChatPanel은 start/stop을 직접 하지 않음(=LiteChatPanel과 동일한 역할 분리)
                child: ChatPanel(scopeKey: widget.scopeKey),
              ),
            ),
          ],
        ),

        // 부트 중 시각적 안정성(선택 사항)
        if (!_booted)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                width: size.width,
                height: size.height,
                color: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}

/// 공개 채팅 바텀시트 열기
/// ✅ 기본: Sheets API OFF(로컬 모드)
Future<void> chatBottomSheet(BuildContext context) async {
  final String scopeKey = _resolveScopeKey(context);

  // 기본 준비(초기 렌더 안정성)
  await ChatRuntime.instance.ensureInitialized();
  await SharedSpreadsheetRegistry.ensureBootstrapped();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withOpacity(0.25),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      final inset = MediaQuery.of(ctx).viewInsets.bottom;
      final size = MediaQuery.of(ctx).size;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(bottom: inset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: size.height,
            width: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 16,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: true,
                  left: false,
                  right: false,
                  bottom: false,
                  // ✅ 라이프사이클은 Host 위젯이 책임
                  child: _ChatBottomSheetHost(scopeKey: scopeKey),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 채팅 열기 버튼
class ChatOpenButton extends StatelessWidget {
  const ChatOpenButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SheetChatState>(
      valueListenable: ChatRuntime.instance.state,
      builder: (context, st, _) {
        final latestMsg = st.latest?.text ?? '';
        final text =
        latestMsg.length > 20 ? '${latestMsg.substring(0, 20)}...' : latestMsg;
        final label = latestMsg.isEmpty ? '채팅 열기' : text;

        return ElevatedButton(
          onPressed: () => chatBottomSheet(context),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.forum, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  st.error != null ? '채팅 오류' : label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
