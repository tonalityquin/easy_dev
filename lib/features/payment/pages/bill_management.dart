import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../dev/application/area_state.dart';
import '../applications/bill_state.dart';
import 'sheets/bill_bottom_sheet.dart';

class BillManagement extends StatefulWidget {
  const BillManagement({super.key});

  @override
  State<BillManagement> createState() => _BillManagementState();
}

class _BillManagementState extends State<BillManagement> {
  static const String _screenTag = 'bill management';

  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BillState>().manualBillRefresh();
    });
  }

  void _showBillSettingBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: BillSettingBottomSheet(
            onSave: (billData) async {
              try {
                await context.read<BillState>().addBillFromMap(billData);
              } catch (_) {}
            },
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('삭제 확인'),
            content: const Text('선택한 항목을 삭제하시겠어요?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSelectedBill(BuildContext context) async {
    final billState = context.read<BillState>();
    final selectedId = billState.selectedBillId;

    if (selectedId == null) {
      return;
    }

    final ok = await _confirmDelete(context);
    if (!ok) return;

    try {
      await billState.deleteBill([selectedId]);

      if (context.mounted) {
        billState.toggleBillSelection(selectedId);
      }
    } catch (_) {}
  }

  Future<void> _handleEdit(BuildContext context) async {}

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
            const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
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

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final hasSelection =
        context.select<BillState, bool>((s) => s.selectedBillId != null);

    final won = NumberFormat.decimalPattern();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: _buildScreenTag(context),
        title:
            const Text('정산유형', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child:
              Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
      ),
      body: Consumer<BillState>(
        builder: (context, state, child) {
          final generalBills = state.generalBills
              .where((bill) => bill.area.trim() == currentArea)
              .toList();

          if (generalBills.isEmpty) {
            return const Center(child: Text('현재 지역에 해당하는 정산 데이터가 없습니다.'));
          }

          return ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (generalBills.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '변동 정산',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                  ),
                ),
                Divider(height: 1.0, color: cs.outlineVariant.withOpacity(.75)),
                ...generalBills.map(
                  (bill) => _buildGeneralBillTile(
                    context,
                    state,
                    bill,
                    won,
                    colorScheme: cs,
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onAdd: () => _showBillSettingBottomSheet(context),
        onEdit: hasSelection ? () => _handleEdit(context) : null,
        onDelete: hasSelection ? () => _deleteSelectedBill(context) : null,
      ),
    );
  }

  Widget _buildGeneralBillTile(
    BuildContext context,
    BillState state,
    dynamic bill,
    NumberFormat won, {
    required ColorScheme colorScheme,
  }) {
    final cs = colorScheme;
    final isSelected = state.selectedBillId == bill.id;

    final selectedBg = cs.primaryContainer.withOpacity(.22);

    return Material(
      color: isSelected ? selectedBg : cs.surface,
      child: InkWell(
        onTap: () => state.toggleBillSelection(bill.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.55),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: cs.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.countType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '기본 기준: ${bill.basicStandard}, 기본 금액: ₩${won.format(bill.basicAmount)}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '추가 기준: ${bill.addStandard}, 추가 금액: ₩${won.format(bill.addAmount)}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_circle, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ButtonStyle addStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.primary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle editStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: 3,
      shadowColor: cs.shadow.withOpacity(0.18),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!hasSelection) ...[
          _ElevatedPillButton.icon(
            icon: Icons.add,
            label: '추가',
            style: addStyle,
            onPressed: onAdd,
          ),
        ] else ...[
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: editStyle,
            onPressed: onEdit!,
          ),
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ],
        SizedBox(height: bottomGap),
      ],
    );
  }
}

class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
    Key? key,
  }) {
    return _ElevatedPillButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label, Key? key})
      : super(key: key);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
