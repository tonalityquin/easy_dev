import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../states/plate/movement_plate.dart';

Future<bool?> showTabletPageStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry, // 시그니처 호환성을 위해 유지(미사용)
  required VoidCallback onDelete, // 시그니처 호환성을 위해 유지(미사용)
}) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors
        .transparent, // ✅ 시트 바깥은 투명 유지(컨테이너에서 surface로 채움)
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          final cs = Theme.of(context).colorScheme;
          final text = Theme.of(context).textTheme;

          // primary를 surface에 얇게 얹어 “브랜드 톤 힌트”
          Color tintOnSurface(double opacity) =>
              Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);

          final sheetBg = cs.surface;
          final sheetBorder = cs.outlineVariant.withOpacity(.85);

          final handleBg = cs.outlineVariant.withOpacity(.8);

          final headerIconBg = tintOnSurface(cs.brightness == Brightness.dark ? 0.18 : 0.10);
          final plateBg = tintOnSurface(cs.brightness == Brightness.dark ? 0.16 : 0.08);
          final plateBorder = cs.primary.withOpacity(cs.brightness == Brightness.dark ? 0.30 : 0.22);

          return Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: sheetBorder)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: handleBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: headerIconBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cs.outline.withOpacity(.10)),
                      ),
                      child: Icon(Icons.directions_car, color: cs.primary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '출차 요청 확인',
                      style: (text.titleMedium ?? const TextStyle()).copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: plateBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: plateBorder),
                    ),
                    child: Text(
                      plate.plateNumber,
                      style: (text.headlineSmall ?? const TextStyle()).copyWith(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '선택한 차량을 정말 출차 요청으로 변경하시겠습니까?',
                    textAlign: TextAlign.center,
                    style: (text.bodySmall ?? const TextStyle()).copyWith(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('아니요'),
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          foregroundColor: cs.onSurface,
                          side: BorderSide(color: cs.outline.withOpacity(.35)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ).copyWith(
                          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                (states) => states.contains(MaterialState.pressed)
                                ? cs.outlineVariant.withOpacity(.20)
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('네, 출차 요청'),
                        onPressed: () async {
                          final movementPlate = context.read<MovementPlate>();
                          await movementPlate.setDepartureRequested(
                            plate.plateNumber,
                            plate.area,
                            plate.location,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ).copyWith(
                          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                                (states) => states.contains(MaterialState.pressed)
                                ? cs.onPrimary.withOpacity(.12)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
