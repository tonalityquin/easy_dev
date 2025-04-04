import 'package:flutter/material.dart';

class StatisticsDocument extends StatefulWidget {
  const StatisticsDocument({Key? key}) : super(key: key);

  @override
  State<StatisticsDocument> createState() => _StatisticsDocumentState();
}

class _StatisticsDocumentState extends State<StatisticsDocument> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '통계 문서',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          '통계 데이터를 여기에 표시하세요.',
          style: TextStyle(fontSize: 16),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('통계 추가 버튼이 눌렸습니다')),
          );
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add),
      ),
    );
  }
}
