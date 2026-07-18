import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

enum RoadmapStatus { planned, inProgress, done }

enum RoadmapLoad { light, medium, heavy }

class RoadmapItem {
  const RoadmapItem({
    this.date,
    this.load,
    required this.title,
    required this.notes,
    required this.status,
  });

  final String? date;
  final RoadmapLoad? load;
  final String title;
  final List<String> notes;
  final RoadmapStatus status;
}

const List<RoadmapItem> _roadmapData = <RoadmapItem>[
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '차량 차종 인식 모델 기능 추가',
    notes: <String>[
      '차량 전면부를 촬영하여 제조사와 차종 명을 삽입할 수 있도록 하는 기능',
    ],
    status: RoadmapStatus.inProgress,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: '홈페이지 모드 지원',
    notes: <String>[
      '홈페이지로 출차 요청 및 업무 보조 지원',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.medium,
    title: '특정 고객용 모드 지원',
    notes: <String>[
      '고객 개인에게 설치되는 앱 내에서 본인 차량만 출차 요청 할 수 있도록 하는 모드 지원',
    ],
    status: RoadmapStatus.planned,
  ),
  RoadmapItem(
    load: RoadmapLoad.heavy,
    title: 'QR 코드 지원',
    notes: <String>[
      'Case A.사용자가 QR코드를 촬영하여 받은 일회성 페이지에서 특정 번호판을 입차 완료에서 출차 요청으로 변경',
      'Case B.사용자가 출차 요청한 후, 발급받은 QR코드를 촬영하여 출차 완료가 되면 알림 수신',
    ],
    status: RoadmapStatus.planned,
  ),
];

class RoadmapBottomSheet extends StatelessWidget {
  const RoadmapBottomSheet({super.key});

  Color _statusColor(PromptUiTokens tokens, RoadmapStatus status) {
    switch (status) {
      case RoadmapStatus.planned:
        return tokens.info;
      case RoadmapStatus.inProgress:
        return tokens.accent;
      case RoadmapStatus.done:
        return tokens.success;
    }
  }

  Color _statusContainer(PromptUiTokens tokens, RoadmapStatus status) {
    switch (status) {
      case RoadmapStatus.planned:
        return tokens.infoContainer;
      case RoadmapStatus.inProgress:
        return tokens.accentContainer;
      case RoadmapStatus.done:
        return tokens.successContainer;
    }
  }

  Color _statusForeground(PromptUiTokens tokens, RoadmapStatus status) {
    switch (status) {
      case RoadmapStatus.planned:
        return tokens.onInfoContainer;
      case RoadmapStatus.inProgress:
        return tokens.onAccentContainer;
      case RoadmapStatus.done:
        return tokens.onSuccessContainer;
    }
  }

  String _statusLabel(RoadmapStatus status) {
    switch (status) {
      case RoadmapStatus.planned:
        return '계획';
      case RoadmapStatus.inProgress:
        return '진행 중';
      case RoadmapStatus.done:
        return '완료';
    }
  }

  Color _loadColor(PromptUiTokens tokens, RoadmapLoad load) {
    switch (load) {
      case RoadmapLoad.light:
        return tokens.success;
      case RoadmapLoad.medium:
        return tokens.warning;
      case RoadmapLoad.heavy:
        return tokens.danger;
    }
  }

  Color _loadContainer(PromptUiTokens tokens, RoadmapLoad load) {
    switch (load) {
      case RoadmapLoad.light:
        return tokens.successContainer;
      case RoadmapLoad.medium:
        return tokens.warningContainer;
      case RoadmapLoad.heavy:
        return tokens.dangerContainer;
    }
  }

  Color _loadForeground(PromptUiTokens tokens, RoadmapLoad load) {
    switch (load) {
      case RoadmapLoad.light:
        return tokens.onSuccessContainer;
      case RoadmapLoad.medium:
        return tokens.onWarningContainer;
      case RoadmapLoad.heavy:
        return tokens.onDangerContainer;
    }
  }

  String _loadLabel(RoadmapLoad load) {
    switch (load) {
      case RoadmapLoad.light:
        return '여유';
      case RoadmapLoad.medium:
        return '보통';
      case RoadmapLoad.heavy:
        return '과중';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 1,
      minChildSize: 0.4,
      maxChildSize: 1,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(PromptUiShapes.sheet),
            ),
            border: Border.all(color: tokens.borderSubtle),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.handle,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          border: Border.all(color: tokens.borderSubtle),
                        ),
                        child: Icon(
                          Icons.timeline_rounded,
                          color: tokens.onAccentContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '프로세스 로드맵',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '로드맵은 상시 변경 혹은 취소될 수 있습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PromptIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).maybePop(),
                        haptic: PromptHaptic.selection,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: RoadmapStatus.values.map((status) {
                      return _LegendChip(
                        label: _statusLabel(status),
                        color: _statusColor(tokens, status),
                        background: _statusContainer(tokens, status),
                        foreground: _statusForeground(tokens, status),
                      );
                    }).toList(growable: false),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                Expanded(
                  child: ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: _roadmapData.length,
                    itemBuilder: (context, index) {
                      final item = _roadmapData[index];
                      return PromptAnimatedReveal(
                        delay: Duration(milliseconds: index * 45),
                        offset: const Offset(0, 0.035),
                        child: _TimelineTile(
                          item: item,
                          statusColor: _statusColor(tokens, item.status),
                          statusContainer:
                              _statusContainer(tokens, item.status),
                          statusForeground:
                              _statusForeground(tokens, item.status),
                          statusLabel: _statusLabel(item.status),
                          loadColor: item.load == null
                              ? null
                              : _loadColor(tokens, item.load!),
                          loadContainer: item.load == null
                              ? null
                              : _loadContainer(tokens, item.load!),
                          loadForeground: item.load == null
                              ? null
                              : _loadForeground(tokens, item.load!),
                          loadLabel:
                              item.load == null ? null : _loadLabel(item.load!),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.item,
    required this.statusColor,
    required this.statusContainer,
    required this.statusForeground,
    required this.statusLabel,
    this.loadColor,
    this.loadContainer,
    this.loadForeground,
    this.loadLabel,
  });

  final RoadmapItem item;
  final Color statusColor;
  final Color statusContainer;
  final Color statusForeground;
  final String statusLabel;
  final Color? loadColor;
  final Color? loadContainer;
  final Color? loadForeground;
  final String? loadLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 18),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: statusColor.withOpacity(0.32),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 2,
                  height: 98,
                  margin: const EdgeInsets.only(top: 6),
                  color: tokens.borderSubtle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: <Widget>[
                      if ((item.date ?? '').trim().isNotEmpty)
                        _MetaChip(
                          text: item.date!,
                          background: tokens.surfaceOverlay,
                          foreground: tokens.textSecondary,
                          border: tokens.borderSubtle,
                        ),
                      if (loadLabel != null &&
                          loadContainer != null &&
                          loadForeground != null &&
                          loadColor != null)
                        _MetaChip(
                          text: loadLabel!,
                          background: loadContainer!,
                          foreground: loadForeground!,
                          border: loadColor!.withOpacity(0.4),
                        ),
                      _MetaChip(
                        text: statusLabel,
                        background: statusContainer,
                        foreground: statusForeground,
                        border: statusColor.withOpacity(0.4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.title,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...item.notes.map(
                    (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: tokens.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              note,
                              style: textTheme.bodyMedium?.copyWith(
                                color: tokens.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.text,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String text;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
