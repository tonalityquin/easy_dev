class TutorialStartPageSpec {
  final String imageAsset;
  final String title;
  final String desc;
  final List<String> bullets;
  final String? warning;
  final String? linkLabel;
  final String? linkRoute;

  const TutorialStartPageSpec({
    required this.imageAsset,
    required this.title,
    required this.desc,
    this.bullets = const <String>[],
    this.warning,
    this.linkLabel,
    this.linkRoute,
  });
}

const List<TutorialStartPageSpec> kAppStartFullTutorialPages = [
  TutorialStartPageSpec(
    imageAsset: 'assets/tutorial/00.png',
    title: '워크플로우 선택',
    desc: '부여받은 계정의 권한에 맞게 워크플로우를 선택합니다.',
    bullets: const [
      'WorkFlow A는 최소 기능만을 제공합니다.',
      'WorkFlow B는 출차 요청 기능을 더 제공합니다.',
      'WorkFlow C는 입차 요청 기능도 제공합니다.',
      'WorkFLow D는 출퇴근 관리 기능만을 지원합니다.'
    ],
    warning: null,
    linkLabel: null,
    linkRoute: null,
  ),
  TutorialStartPageSpec(
    imageAsset: 'assets/tutorial/01.png',
    title: '로그인',
    desc: '계정의 정보를 입력하는 화면입니다.',
    bullets: const [
      '이름과 전화번호는 각각 글자 및 숫자 수에 맞춰 익명의 계정도 제공받을 수 있습니다.',
      '비밀번호는 분실 시 복구의 절차가 복잡하니 꼭 메모해야 합니다.',
      '각 계정마다 접근 권한이 다를 수 있으니 지시받은 워크플로우에 접근해야 합니다.',
      '한 번 로그인을 하면 로그아웃을 하기 전까지는 다시 로그인을 하지 않아도 됩니다..'
    ],
    warning: null,
    linkLabel: null,
    linkRoute: null,
  ),
  TutorialStartPageSpec(
    imageAsset: 'assets/tutorial/02.png',
    title: '출근 화면',
    desc: '출근은 하루에 한 번만.',
    bullets: const [
      '1시 방향의 아이콘을 누르면 로그아웃이 가능합니다.',
    ],
    warning: null,
    linkLabel: null,
    linkRoute: null,
  ),
  TutorialStartPageSpec(
    imageAsset: 'assets/tutorial/03.png',
    title: '업무 메인 화면',
    desc: '기본적인 셋업 데이터가 필요합니다.',
    bullets: const [
      '"대시보드" 버튼을 눌러 보조 페이지를 통해 근무지에 대한 기본 정보를 핸드폰으로 가져와야 합니다.',
    ],
    warning: null,
    linkLabel: null,
    linkRoute: null,
  ),
];
