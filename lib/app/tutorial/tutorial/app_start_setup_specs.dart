import 'package:flutter/material.dart';

class AppStartPermissionSpec {
  const AppStartPermissionSpec({
    required this.step,
    required this.keyName,
    required this.title,
    required this.description,
    required this.icon,
  });

  final int step;
  final String keyName;
  final String title;
  final String description;
  final IconData icon;
}

const List<AppStartPermissionSpec> appStartPermissionSpecs =
    <AppStartPermissionSpec>[
  AppStartPermissionSpec(
    step: 1,
    keyName: 'welcome',
    title: '권한 설정',
    description: '서비스 이용에 필요한 권한을 순서대로 확인합니다.',
    icon: Icons.verified_user_outlined,
  ),
  AppStartPermissionSpec(
    step: 2,
    keyName: 'notifications',
    title: '알림 권한',
    description: '입·출차 요청과 근무 상태 알림을 위해 필요합니다.',
    icon: Icons.notifications_active_outlined,
  ),
  AppStartPermissionSpec(
    step: 3,
    keyName: 'location',
    title: '위치 권한',
    description: '근무와 이동 관련 기능을 위해 필요할 수 있습니다.',
    icon: Icons.my_location_outlined,
  ),
  AppStartPermissionSpec(
    step: 4,
    keyName: 'battery',
    title: '배터리 최적화 제외',
    description: '포그라운드 서비스 안정성을 위해 필요합니다.',
    icon: Icons.battery_saver_outlined,
  ),
  AppStartPermissionSpec(
    step: 5,
    keyName: 'camera',
    title: '카메라 권한',
    description: '업무 사진 촬영 기능을 위해 필요합니다.',
    icon: Icons.photo_camera_outlined,
  ),
  AppStartPermissionSpec(
    step: 7,
    keyName: 'microphone',
    title: '마이크 권한',
    description: '음성 기능과 무전기 송신 기능을 위해 필요합니다.',
    icon: Icons.mic_none_outlined,
  ),
];

AppStartPermissionSpec appStartPermissionSpecForStep(int step) {
  return appStartPermissionSpecs.firstWhere(
    (spec) => spec.step == step,
    orElse: () => throw ArgumentError.value(step, 'step'),
  );
}

List<AppStartPermissionSpec> appStartPermissionSpecsForSteps(
  Iterable<int> steps,
) {
  return steps
      .map(appStartPermissionSpecForStep)
      .toList(growable: false);
}

class AppStartGoogleServiceSpec {
  const AppStartGoogleServiceSpec({
    required this.keyName,
    required this.title,
    required this.description,
    required this.detail,
    required this.icon,
  });

  final String keyName;
  final String title;
  final String description;
  final String detail;
  final IconData icon;
}

const List<AppStartGoogleServiceSpec> appStartGoogleServiceSpecs =
    <AppStartGoogleServiceSpec>[
  AppStartGoogleServiceSpec(
    keyName: 'calendar',
    title: 'Google Calendar',
    description: '업무 일정 조회, 등록, 수정 및 삭제에 사용합니다.',
    detail: 'Calendar · Calendar Events',
    icon: Icons.calendar_month_rounded,
  ),
  AppStartGoogleServiceSpec(
    keyName: 'gmail',
    title: 'Gmail',
    description: '업무 시작·종료 보고와 첨부파일 메일 전송에 사용합니다.',
    detail: 'Gmail Send',
    icon: Icons.mail_rounded,
  ),
  AppStartGoogleServiceSpec(
    keyName: 'cloud_storage',
    title: 'Google Cloud Storage',
    description: '업무 파일과 이미지의 저장 및 조회에 사용합니다.',
    detail: 'Cloud Storage Full Control',
    icon: Icons.cloud_rounded,
  ),
];
