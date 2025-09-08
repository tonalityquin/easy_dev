import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routes.dart'; // ← 라우트 사용

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // 원본 데이터: question은 "code. xxx" 형태를 그대로 유지
  static const List<_FaqData> _allFaqs = [
    _FaqData(
      question: 'code. common_user_00',
      answer: '\nQ. 로그인이 안되고 있어요.'
          '\n\nA. 진입한 창이 부여받은 계정에 호환이 되나요?'
          '\n\n각 로그인 창마다 다른 검증 로직을 가지고 있습니다. '
          '관리자로부터 제공 받은 계정이 호환되는 창을 다시 확인해주세요.',
    ),
    _FaqData(
      question: 'code. common_user_01',
      answer: '\nQ. 계정 비밀번호를 분실했어요.'
          '\n\nA. 비밀번호는 계정 추가 시 랜덤 함수로 생성됩니다.'
          '\n\n관리자로부터 개발사에 직접 문의하세요. '
          '꼭 개인적으로 비밀번호를 저장하시기 바랍니다.',
    ),
    _FaqData(
      question: 'code. common_user_02',
      answer: '\nQ. 로그아웃을 하고 앱을 실행했어요.'
          '\n그런데 404가 떠요.'
          '\n\nA. 정상적인 앱 종료가 이루어지지 않았습니다.'
          '\n\n로그아웃을 하고 꼭 탭에서 앱을 완전히 종료해주세요.',
    ),
    _FaqData(
      question: 'code. service_user_commute',
      answer: '\nQ. 출근 보고 버튼을 눌러도 반응이 없어요.'
          '\n\nA. 문제는 세 가지 중에 있습니다.'
          '\n\n1.오픈 카카오톡 채팅방이 아니다.'
          '\n2.채팅방이 삭제되었거나 추방당한 적이 있다.'
          '\n3.URL을 잘못 복사하여 붙여넣었다.'
          '\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.',
    ),
    _FaqData(
      question: 'code. service_user_humanResource_00',
      answer: '\nQ. 지역과 사용자를 골랐습니다.'
          '\n그런데 데이터가 없어요.'
          '\n\nA. 문제는 세 가지 중에 있습니다.'
          '\n\n1.해당 계정으로 저장된 로그가 없다.'
          '\n2.링크를 잘못 삽입했다.'
          '\n3.계정 권한을 부여하지 않았다.'
          '\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.',
    ),
    _FaqData(
      question: 'code. service_user_humanResource_01',
      answer: '\nQ. 로그인한 계정에서 구글 드라이브가 안 열려요.'
          '\n\nA. 문제는 두 가지 중에 있습니다.'
          '\n\n1.링크를 잘못 삽입했다.'
          '\n2.계정 권한을 부여하지 않았다.'
          '\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.',
    ),
    _FaqData(
      question: 'code. service_userAccounts_HeadQuarter_00',
      answer: '\nQ. 회사 일정 달력을 열었어요.'
          '\n그런데 일정을 불러오지 못하고 있어요.'
          '\n\nA. 문제는 세 가지 중에 있습니다.'
          '\n\n1.링크를 잘못 삽입했다.'
          '\n2.계정 권한을 부여하지 않았다.'
          '\n3.해당 월에 생성한 할 일이 없다.'
          '\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.',
    ),
    _FaqData(
      question: 'code. service_userAccounts_HeadQuarter_01',
      answer: '\nQ. 완료 탭을 열었어요.'
          '\n그런데 완료된 일을 불러오지 못하고 있어요.'
          '\n\nA. 문제는 두 가지 중에 있습니다.'
          '\n1.계정 권한을 부여하지 않았다.'
          '\n2.완료된 할 일이 없다.'
          '\n\n기본적으로 markdown 문법을 따르고 있습니다.'
          '\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.',
    ),
    _FaqData(
      question: 'code. service_area_HeadQuarter_02',
      answer: '\nQ. 완료된 할 일을 엑셀에 저장하지 못 했습니다.'
          '\n그런데 실수로 먼저 지웠는데 복구하고 싶어요.'
          '\n\nA. 지워진 할 일은 복구할 수 없습니다.'
          '\n\n반드시 사전에 저장 후 삭제해야 합니다.',
    ),
    _FaqData(
      question: 'code. service_area_plate_tts',
      answer: '\nQ. 번호판을 생성할 때와 출차 요청했어요.'
          '\n그런데 소리가 안들려요.'
          '\n\nA. 본 앱은 기본적으로 Google TTS를 사용 중입니다.'
          '\n\n1.설정->일반->글자 읽어주기->기본 엔진'
          '\n"Google 음성 인식 및 합성"을 선택해주세요.'
          '\n2.플레이스토어에 가서 최신 업데이트 버전을 확인하세요.',
    ),
    _FaqData(
      question: 'code. service_area_userManagement_00',
      answer: '\nQ. 계정의 근무지를 변경하고 싶어요.'
          '\n\nA. 동일 계정으로 근무지를 변경할 수 없습니다.'
          '\n\n1.이전 근무자의 계정을 삭제하세요.'
          '\n2.변경된 지역에서 계정을 새롭게 생성하세요.',
    ),
    _FaqData(
      question: 'code. service_area_page_00',
      answer: '\n\nQ. 홈 화면의 구역 내 잔여 데이터를 보고 싶어요.'
          '\n\nA. 구역 내 잔여 데이터 열람은 제한이 있습니다.'
          '\n\n1. 홈 버튼을 누른 후, 구역 현황 화면에 진입 하세요.'
          '\n2. 각 지역마다 5대의 기본값을 설정하고 있습니다.'
          '\n3. 현재 4대의 데이터가 있는 경우 열람이 가능합니다.'
          '\n4. 현재 5대의 데이터가 있는 경우 열람이 가능합니다.'
          '\n5. 현재 6대의 데이터가 있는 경우 열람이 불가능합니다.'
          '\n\n해당 기능의 범위를 늘리고자 하는 경우, 개인 문의 부탁드립니다.',
    ),
    _FaqData(
      question: 'code. service_area_page_01',
      answer: '\n\nQ. 입차 요청과 출차 요청 탭을 눌렀어요.'
          '\n아무 반응이 없어요.'
          '\n\nA. 데이터가 없다는 뜻입니다.'
          '\n\n입차 요청 혹은 출차 요청에 데이터가 없는 경우에는 '
          '해당 화면을 눌러도 진입이 되지 않습니다.',
    ),
    _FaqData(
      question: 'code. service_area_page_02',
      answer: '\n\nQ. 입차 요청과 출차 요청 탭을 눌렀어요.'
          '\n아무 반응이 없어요.'
          '\n\nA. 데이터가 없다는 뜻입니다.'
          '\n\n입차 요청 혹은 출차 요청에 데이터가 없는 경우에는 '
          '해당 화면을 눌러도 진입이 되지 않습니다.',
    ),
    _FaqData(
      question: 'code. service_area_page_03',
      answer: '\n\nQ. 번호판 검색이 안되고 있어요.'
          '\n\nA. 어느 화면에서 번호판을 검색했나요?'
          '\n\n1. 모든 상태를 검색할 수 있는 경우'
          '\n- 입차 요청'
          '\n- 출차 요청'
          '\n\n2. 입차 완료만 검색할 수 있는 경우'
          '\n- 입차 완료'
          '\n\n3. 출차 완료만 검색할 수 있는 경우'
          '\n- 출차 완료(정산 탭)'
          '\n\n해당 화면을 눌러도 진입이 되지 않습니다.',
    ),
  ];

  List<_FaqData> get _filtered {
    if (_query.trim().isEmpty) return _allFaqs;
    final key = _query.trim().toLowerCase();
    // question(= "code. xxx") 텍스트에 부분 일치
    return _allFaqs.where((e) => e.question.toLowerCase().contains(key)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          'FAQ / 문의',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        actionsIconTheme: IconThemeData(color: cs.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
          width: double.infinity,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // 검색바
              TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: '코드 검색 (예: service_area_page_02)',
                  hintText: 'common_user_00, service_area_page_01 등',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          tooltip: '지우기',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),

              // 결과 개수 표시
              Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 16, color: Colors.black54),
                  const SizedBox(width: 6),
                  Text(
                    _query.isEmpty ? '전체 ${_allFaqs.length}건' : '검색 결과 ${_filtered.length}건',
                    style: text.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('검색 결과가 없습니다. 철자를 다시 확인해주세요.'),
                )
              else
                ..._filtered.map((e) => _FaqItem(question: e.question, answer: e.answer)),

              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  // TODO: 실제 문의 채널(오픈채팅/메일/폼)로 연결
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('문의 채널로 연결됩니다. (구현 필요)')),
                  );
                },
                icon: const Icon(Icons.support_agent_rounded),
                label: const Text('문의하기'),
              ),
            ],
          ),
        ),
      ),

      // ▼ 바텀 펠리컨 이미지 (탭하면 선택화면으로 이동)
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.selector,
              (route) => false,
            ),
            borderRadius: BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 120,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqData {
  final String question; // "code. xxx" 형태로 보이게 유지
  final String answer;

  const _FaqData({required this.question, required this.answer});
}
class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(answer, style: text.bodyMedium),
        ],
      ),
    );
  }
}
