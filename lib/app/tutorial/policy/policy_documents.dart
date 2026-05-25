import 'package:flutter/material.dart';

enum PolicyConsentKind {
  termsOfService,
  privacyPolicy,
  accountDeletion,
}

class PolicyDocumentSpec {
  const PolicyDocumentSpec({
    required this.kind,
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.agreeLabel,
    required this.actionLabel,
    required this.body,
  });

  final PolicyConsentKind kind;
  final int step;
  final int totalSteps;
  final String title;
  final String subtitle;
  final IconData icon;
  final String agreeLabel;
  final String actionLabel;
  final String body;
}

PolicyDocumentSpec policyDocumentOf(PolicyConsentKind kind) {
  switch (kind) {
    case PolicyConsentKind.termsOfService:
      return const PolicyDocumentSpec(
        kind: PolicyConsentKind.termsOfService,
        step: 1,
        totalSteps: 3,
        title: '이용 약관',
        subtitle: 'ParkinWorkin 서비스 이용 조건을 확인해 주세요.',
        icon: Icons.description_outlined,
        agreeLabel: '이용 약관에 동의합니다.',
        actionLabel: '다음',
        body: _termsOfServiceBody,
      );
    case PolicyConsentKind.privacyPolicy:
      return const PolicyDocumentSpec(
        kind: PolicyConsentKind.privacyPolicy,
        step: 2,
        totalSteps: 3,
        title: '개인정보보호정책',
        subtitle: '서비스 제공에 필요한 개인정보 처리 기준을 확인해 주세요.',
        icon: Icons.privacy_tip_outlined,
        agreeLabel: '개인정보보호정책에 동의합니다.',
        actionLabel: '다음',
        body: _privacyPolicyBody,
      );
    case PolicyConsentKind.accountDeletion:
      return const PolicyDocumentSpec(
        kind: PolicyConsentKind.accountDeletion,
        step: 3,
        totalSteps: 3,
        title: '계정 삭제 정책',
        subtitle: '계정 삭제 요청과 데이터 처리 기준을 확인해 주세요.',
        icon: Icons.manage_accounts_outlined,
        agreeLabel: '계정 삭제 정책에 동의합니다.',
        actionLabel: '완료',
        body: _accountDeletionPolicyBody,
      );
  }
}

const String _termsOfServiceBody = '''
제1조 목적
본 약관은 ParkinWorkin 앱이 제공하는 업무 지원, 출퇴근 관리, 차량 입출차 관리, 알림 및 관련 부가 기능의 이용 조건과 절차를 정하는 것을 목적으로 합니다.

제2조 서비스의 범위
회사는 사용자에게 업무 현장에서 필요한 정보 입력, 상태 확인, 알림, 기록 조회, 사진 촬영, 위치 기반 보조 기능, 오버레이 표시, 음성 또는 마이크 기반 보조 기능을 제공할 수 있습니다. 실제 제공 기능은 사용자의 권한, 배정된 워크플로우, 회사 또는 현장의 운영 정책에 따라 달라질 수 있습니다.

제3조 사용자 계정
사용자는 부여받은 계정 또는 현장에서 안내받은 인증 정보로 서비스를 이용합니다. 사용자는 자신의 계정 정보를 안전하게 관리해야 하며, 계정 정보의 분실, 공유, 오입력, 무단 사용으로 발생하는 문제에 대해 책임을 질 수 있습니다.

제4조 이용자의 의무
사용자는 서비스 이용 시 실제 업무와 관련된 정보를 정확하게 입력해야 합니다. 허위 정보 입력, 타인의 계정 사용, 시스템 우회, 비정상적인 반복 요청, 업무 기록 조작, 서비스 장애를 유발하는 행위는 금지됩니다.

제5조 권한 사용
앱은 알림, 위치, 카메라, 마이크, 다른 앱 위 표시, 배터리 최적화 제외 등의 권한을 요청할 수 있습니다. 각 권한은 업무 알림, 현장 기능, 사진 촬영, 음성 기능, 오버레이 표시, 안정적인 백그라운드 동작을 위해 사용됩니다. 권한을 허용하지 않으면 일부 기능이 제한될 수 있습니다.

제6조 서비스 변경 및 중단
회사는 운영상 필요, 보안, 시스템 점검, 법령 준수, 기능 개선을 위해 서비스의 일부 또는 전부를 변경하거나 일시 중단할 수 있습니다. 중요한 변경이 있는 경우 앱 내 안내, 별도 공지 또는 관리자를 통해 고지할 수 있습니다.

제7조 기록과 증빙
사용자가 입력한 출퇴근, 입출차, 사진, 메모, 상태 변경, 요청 기록 등은 업무 처리와 분쟁 확인을 위한 자료로 활용될 수 있습니다. 사용자는 기록의 정확성을 유지해야 하며, 잘못된 기록을 발견한 경우 관리자에게 정정 요청을 해야 합니다.

제8조 책임 제한
회사는 사용자의 단말기 상태, 네트워크 장애, 운영체제 제한, 권한 미허용, 외부 서비스 장애, 현장 운영 정책 변경 등 회사가 통제하기 어려운 사유로 발생한 이용 제한에 대해 책임이 제한될 수 있습니다.

제9조 약관의 동의와 효력
사용자가 본 화면에서 동의합니다를 선택하면 본 약관의 내용을 확인하고 동의한 것으로 봅니다. 동의하지 않는 경우 서비스 이용이 제한될 수 있습니다.

제10조 문의
서비스 이용, 계정, 업무 기록, 기능 제한에 관한 문의는 현장 관리자 또는 회사가 지정한 문의 채널을 통해 접수할 수 있습니다.
''';

const String _privacyPolicyBody = '''
제1조 개인정보 처리 목적
ParkinWorkin은 업무 지원, 출퇴근 확인, 차량 입출차 처리, 알림 제공, 사용자 식별, 서비스 안정성 확보, 오류 대응, 고객 문의 처리를 위해 필요한 범위의 개인정보를 처리합니다.

제2조 처리할 수 있는 개인정보 항목
앱은 이름, 전화번호, 계정 식별 정보, 근무지 정보, 출퇴근 기록, 업무 상태 기록, 차량 관련 입력 정보, 사진, 위치 정보, 기기 정보, 앱 사용 로그, 알림 수신 상태, 권한 허용 상태 등을 처리할 수 있습니다. 실제 수집 항목은 사용 기능과 현장 설정에 따라 달라질 수 있습니다.

제3조 개인정보의 이용
수집된 정보는 사용자 인증, 업무 배정 확인, 출퇴근 및 입출차 상태 관리, 현장 운영 지원, 리마인더 발송, 기록 조회, 오류 분석, 서비스 개선을 위해 사용됩니다. 목적과 무관한 방식으로 사용하지 않습니다.

제4조 개인정보 보관 기간
개인정보는 서비스 제공과 업무 기록 보존에 필요한 기간 동안 보관됩니다. 법령, 계약, 현장 운영 정책, 분쟁 대응 필요성이 있는 경우 해당 기간 동안 보관될 수 있으며, 보관 목적이 종료되면 안전한 방법으로 삭제 또는 비식별 처리됩니다.

제5조 제3자 제공
회사는 법령에 근거가 있거나 사용자의 동의가 있는 경우, 또는 업무 수행을 위해 필요한 범위에서 관리자, 운영 주체, 위탁 처리자에게 정보를 제공할 수 있습니다. 제공되는 정보는 필요한 범위로 제한됩니다.

제6조 처리 위탁
서비스 운영을 위해 클라우드 저장소, 데이터베이스, 인증, 알림, 분석, 메일 전송 등 외부 서비스가 사용될 수 있습니다. 회사는 위탁 처리 과정에서 개인정보가 안전하게 관리되도록 필요한 조치를 취합니다.

제7조 위치 정보와 기기 권한
위치 정보는 출퇴근, 현장 확인, 업무 기록 보조 기능에 사용될 수 있습니다. 카메라와 마이크 권한은 사진 촬영, 음성 기능, 업무 증빙 기능을 위해 사용될 수 있습니다. 사용자는 운영체제 설정에서 권한을 변경할 수 있으나, 권한 변경 시 일부 기능이 제한될 수 있습니다.

제8조 이용자의 권리
사용자는 자신의 개인정보에 대해 열람, 정정, 삭제, 처리 정지, 동의 철회를 요청할 수 있습니다. 다만 업무 기록, 법령상 보관 의무, 분쟁 대응에 필요한 정보는 즉시 삭제되지 않을 수 있습니다.

제9조 안전성 확보 조치
회사는 개인정보 보호를 위해 접근 권한 관리, 인증 절차, 저장소 보호, 전송 구간 보호, 로그 관리, 내부 관리 기준 등 합리적인 보호 조치를 적용합니다.

제10조 문의
개인정보 처리와 관련한 문의, 권리 행사, 오류 신고는 현장 관리자 또는 회사가 지정한 개인정보 문의 채널을 통해 접수할 수 있습니다.
''';

const String _accountDeletionPolicyBody = '''
제1조 계정 삭제 요청
사용자는 더 이상 서비스를 이용하지 않거나 계정 삭제가 필요한 경우 현장 관리자 또는 회사가 지정한 문의 채널을 통해 계정 삭제를 요청할 수 있습니다. 요청 시 본인 확인과 업무 기록 확인 절차가 진행될 수 있습니다.

제2조 삭제 처리 범위
계정 삭제가 승인되면 로그인 식별 정보, 앱 이용을 위한 계정 상태, 일부 개인 설정, 더 이상 서비스 제공에 필요하지 않은 개인정보가 삭제 또는 비활성화됩니다. 단, 업무 기록과 법령상 보관이 필요한 정보는 별도 보관될 수 있습니다.

제3조 보관될 수 있는 정보
출퇴근 기록, 업무 수행 기록, 차량 입출차 기록, 결제 또는 정산 관련 기록, 사진 증빙, 관리자 확인 기록, 분쟁 대응에 필요한 로그는 법령, 계약, 현장 운영 정책에 따라 일정 기간 보관될 수 있습니다.

제4조 삭제 처리 기간
계정 삭제 요청은 접수 후 합리적인 기간 내 처리됩니다. 본인 확인, 현장 운영 확인, 미처리 업무, 정산, 분쟁 또는 법적 보존 사유가 있는 경우 처리가 지연될 수 있습니다.

제5조 삭제 후 이용 제한
계정 삭제가 완료되면 해당 계정으로 로그인하거나 기존 업무 데이터에 접근할 수 없습니다. 동일 사용자가 다시 서비스를 이용하려면 새로운 계정 발급 또는 관리자 승인이 필요할 수 있습니다.

제6조 삭제 철회
삭제 요청이 최종 처리되기 전에는 관리자 또는 지정 문의 채널을 통해 철회를 요청할 수 있습니다. 이미 삭제 또는 비식별 처리된 정보는 복구되지 않을 수 있습니다.

제7조 앱 삭제와 계정 삭제의 차이
사용자가 단말기에서 앱을 삭제하더라도 계정과 서버에 저장된 업무 기록이 자동으로 삭제되는 것은 아닙니다. 계정 삭제를 원할 경우 별도의 삭제 요청 절차를 진행해야 합니다.

제8조 문의
계정 삭제, 데이터 보관, 삭제 처리 상태, 재가입 가능 여부에 관한 문의는 현장 관리자 또는 회사가 지정한 문의 채널을 통해 접수할 수 있습니다.
''';
