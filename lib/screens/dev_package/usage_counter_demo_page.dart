// lib/screens/dev_package/usage_counter_demo_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/usage_reporter.dart';

class UsageCounterDemoPage extends StatelessWidget {
  const UsageCounterDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ 초기화 완료를 보장하고 화면을 그림
    return FutureBuilder<void>(
      future: UsageReporter.instance.ensureInitialized(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          // ⛏️ Scaffold는 const 생성자가 아님 → const 제거
          return Scaffold(
            appBar: AppBar(title: const Text('사용량 카운터 · 스모크 테스트')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return const _UsageCounterDemoBody();
      },
    );
  }
}

class _UsageCounterDemoBody extends StatefulWidget {
  const _UsageCounterDemoBody();

  @override
  State<_UsageCounterDemoBody> createState() => _UsageCounterDemoBodyState();
}

class _UsageCounterDemoBodyState extends State<_UsageCounterDemoBody> {
  final _db = FirebaseFirestore.instance;

  final _areaController = TextEditingController(text: 'demo_area');
  final _docIdController = TextEditingController(text: 'demo_doc');

  String get _area => _areaController.text.trim();
  String get _docId => _docIdController.text.trim();

  @override
  void dispose() {
    _areaController.dispose();
    _docIdController.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final q = _db.collection('bills').where('area', isEqualTo: _area);
      final snap = await q.get();
      final n = snap.docs.isEmpty ? 1 : snap.docs.length;
      await UsageReporter.instance.report(
        area: _area,
        action: 'read',
        n: n,
        source: 'UsageCounterDemoPage._read',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('READ: docs=${snap.docs.length} → 카운트 +$n')),
      );
    } catch (e) {
      _toast('READ 실패: $e');
    }
  }

  Future<void> _write() async {
    try {
      final ref = _db.collection('bills').doc(_docId);
      await ref.set({
        'area': _area,
        'updatedAt': FieldValue.serverTimestamp(),
        'demo': true,
      }, SetOptions(merge: true));
      await UsageReporter.instance.report(
        area: _area,
        action: 'write',
        n: 1,
        source: 'UsageCounterDemoPage._write',
      );
      _toast('WRITE 완료');
    } catch (e) {
      _toast('WRITE 실패: $e');
    }
  }

  Future<void> _delete() async {
    try {
      final ref = _db.collection('bills').doc(_docId);
      await ref.delete();
      await UsageReporter.instance.report(
        area: _area,
        action: 'delete',
        n: 1,
        source: 'UsageCounterDemoPage._delete',
      );
      _toast('DELETE 완료');
    } catch (e) {
      _toast('DELETE 실패: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final installId = UsageReporter.instance.installId; // ✅ 이미 ensure 완료 상태

    return Scaffold(
      appBar: AppBar(
        title: const Text('사용량 카운터 · 스모크 테스트'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: cs.primaryContainer.withOpacity(.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'installId: $installId\n'
                    '경로: usage_daily/{YYYY-MM-DD}/tenants/{area}/users/{installId}__{source}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _areaController,
            decoration: const InputDecoration(
              labelText: 'area (테넌트/기업 식별)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _docIdController,
            decoration: const InputDecoration(
              labelText: '문서 ID (bills/{docId}로 사용)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('READ'),
                onPressed: _read,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.upload_rounded),
                label: const Text('WRITE'),
                onPressed: _write,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('DELETE'),
                onPressed: _delete,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '✅ 기대 결과\n'
                '1) READ/WRITE/DELETE 수행 시 usage_daily 카운터가 증가합니다.\n'
                '2) 다른 컬렉션 직접 쓰기는 규칙상 막혀야(PERMISSION_DENIED) 정상입니다.\n'
                '3) 동일 동작 재시도 시에도 과증가가 없도록(멱등) 설계되어 있습니다.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
