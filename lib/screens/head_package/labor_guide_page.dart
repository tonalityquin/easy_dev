// lib/screens/head_package/labor_guide_page.dart
import 'package:flutter/material.dart';

import 'labors/statement_form_page.dart';

class LaborGuidePage extends StatelessWidget {
  const LaborGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회사 노무 가이드'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withOpacity(.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '근로 기준, 휴가/휴일, 초과근무, 서식 다운로드 등 노무 관련 정보를 제공합니다.',
                style: text.bodyMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),

            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('근로시간/연장근로 안내'),
              subtitle: const Text('법정 근로시간, 연장/야간/휴일근로 개념'),
              onTap: () {},
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.beach_access_outlined),
              title: const Text('연차휴가/대체휴무'),
              subtitle: const Text('발생 기준, 사용 절차, 정산'),
              onTap: () {},
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.attach_file_outlined),
              title: const Text('신청/보고 서식'),
              subtitle: const Text('연차신청서, 휴직신청서, 야근보고서 등'),
              onTap: () {},
            ),

            // 경위서 양식 연결
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_note_outlined),
              title: const Text('경위서 양식'),
              subtitle: const Text('사건/사고 경위 작성 및 제출'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatementFormPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
