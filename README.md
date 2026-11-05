# ParkinWorkin — 기술 명세 및 개발 초기화

초기 설계 기준은 `261103 1901.zip`이며, Firebase Activity Center V2는 `261103 2300.zip`, Plate TTS 계측 분리는 `261103 2347.zip`, **AppBar 높이 복원은 `261104 0027.zip`, Firebase 계측 세션·로컬 보존은 `261104 0117.zip`, 저널 복구·범위별 COST·파일 커서 조회·종료 상태 정정은 `261104 0202.zip`, 사용자 상태·출퇴근 요청 중복 방지는 `261104 0236.zip`, 2차 비용 최적화는 `261104 1413.zip`**을 기준으로 한다. APP RESTART 건너뛰기와 개발자 로그인 성공 시 디버그 모드 자동 활성화 등 기존 동작은 유지한다. 이 문서는 `261104 2123.zip`을 기준으로 한 지역 선택 말풍선 화면 경계·글자 확대·스크롤 대응과 2026-11-04 제공된 Firestore Security Rules, 실제 Dart 코드 및 명시적으로 전달된 초기 백엔드 상태를 구분해 설명한다. 코드의 정적 확인과 실제 Firebase 프로젝트의 배포·실행 검증은 서로 다르다.

## 1. 변경할 수 없는 설계 전제

| 조건 | 프로젝트 계약 |
| --- | --- |
| Firebase Authentication UID | 인증 UID를 업무 계정 문서 ID와 동일시하지 않는다. 계정 연결·Firebase 인증·업무 계정 검증은 별도 단계다. |
| Cloud Functions 배제 | 이 프로젝트의 인증, 계정 생성, 지역 생성에 Cloud Functions를 신규 도입하지 않는다. |
| GCS `publicRead` | 이미지 업로드의 공개 읽기는 의도된 정책이다. 업로드·수정·삭제 권한까지 공개한다는 뜻은 아니다. |
| 초기 백엔드 | `divisions/dev` 문서는 존재한다. `areas`, `user_accounts`, `user_accounts_show`는 비어 있다고 가정한다. 이는 사용자가 제공한 환경 전제이며 런타임 실측이 아니다. |
| 회사 문서 보존 | `divisions/dev`가 있으면 필드, 버전, 생성 시각, 초기 관리자 참조를 **전부 변경하지 않는다**. 없을 때만 생성한다. |
| 사용자 경험 | 기존 화면의 AppBar 높이 56dp, 본문 시작 위치, 중앙 버튼과 좌측 로고 배치를 유지한다. 우측 Activity Center는 높이 48dp 안에 고정하며 UI 계측으로 헤더를 확장하지 않는다. 기존 애니메이션을 유지하고 신규 `hintText`·수정 Dart 주석을 추가하지 않는다. |
| 디버깅 | `debugPrint`와 개발자 모드 ON일 때 `STATUS`의 `debugPrint 코드 복사`를 유지한다. 민감정보 원문은 진단 로그에 기록하지 않는다. |
| 사용자 표시 | 계정 연결·인증 과정의 일반 앱 안내 문구에 내부 백엔드 제품·기술명을 표시하지 않는다. 외부 제공자가 제어하는 계정 선택·동의 UI는 예외다. |
| 비용 최적화 2차 전제 | 동일 업무 계정의 다중 기기 동시 접속은 이번 범위에서 제외한다. **옛 구조의 출퇴근 레거시 `logs` 데이터는 존재하지 않는다**는 제공 전제를 사용하며, 현재 월별 기록·관리자 달력 기능과 실제 필수 상태 변경은 유지한다. |

보안은 실제 운영상 필수 위험만 수정 대상으로 평가하고, 선택적 강화는 별도 요청 없이 진행하지 않는다. 비용 최적화는 실제 청구 단위 및 사용량과 연결해 판단한다.

## 2. 프로젝트 구성과 진입

| 위치 | 책임 |
| --- | --- |
| `lib/main.dart` | 앱 시작과 Firebase 초기화. 기존 근무 알림 통신은 유지하고 Activity Bridge 수신 콜백은 등록하지 않음 |
| `lib/app/tutorial/tutorial/start_gate_screen.dart` | 최초 설정/세션 복원 판단 |
| `lib/features/launcher/page/power_boot_screen.dart` | 전원 시작, 최초 사용 목적 |
| `lib/app/terminal/presentation/parkinworkin_terminal_screen.dart` | 런처, Mini Terminal, 계정 인증 Dialog, 개발자 도움말 UI, APP RESTART 제목 5회 탭, 인증 Route 오버레이 제거 확인 및 런처 대상 업무 화면 이동 |
| `lib/app/init/app_navigator.dart` | 기존 Route 이름별 `onRouteChanged`·`onRouteSettled` 유지, 실제 최상단 Route 객체 및 퇴장 중인 오버레이 추적, STATUS 종료 뒤 런처 이동 재개 알림 |
| `lib/features/launcher/application/mode_launcher_controller.dart` | 로그인 명령, 계정/지역/모드 진행, 개발자 비밀번호 성공 후 디버그 상태 활성화 |
| `lib/features/launcher/application/terminal_auth_coordinator.dart` | 계정 유형, 로그인과 업무 계정 검증 |
| `lib/app/auth/google_auth_session.dart` | 외부 계정과 Firebase 인증 세션 관리 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | 개발용 회사·본사 지역·표시 전용 Count 초기값·계정/예약/경량 View 조건부 생성·복구 |
| `lib/shared/secondary/pages/sheets/tabs/dev_management_common.dart` | 지역 생성 Payload 및 표시 전용 Count 초기값 계약 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 개발자 계정의 Root·코드 예약·경량 View 원자적 Batch 생성 및 수정·이동 트랜잭션 |
| `lib/features/account/domain/models/user/user_model.dart` | 일반 업무 계정 원본 전체 필드 |
| `lib/features/account/domain/models/user/user_account_view_projection.dart` | 지역별 계정 관리 View의 9개 필드 Projection 명세 |
| `lib/shared/page/widget/picker_sheet/area_denied_bubble.dart` | 최초 런처·본사 사이드독·지역 선택 시트가 재사용하는 화면 경계 보정 플로팅 말풍선, 큰 글자용 높이 제한·내부 스크롤, 목록 스크롤 시작 즉시 종료, 애니메이션 및 개발자 진단 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | `debugPrint` 진단 수집, 개발자 Status Dialog와 Firebase 활동 로그 복사 |
| `lib/app/diagnostics/firebase_activity_meter.dart` | Firebase/Firestore/Storage API 계측, 메모리 이벤트·카운터, 호출부 확장 |
| `lib/app/diagnostics/firebase_activity_journal.dart` | 세션별 JSONL 저장, 실패 재시도·부분 쓰기 복구, 보관 범위별 COST 집계, 파일 커서 기반 100건 조회 |
| `lib/app/diagnostics/firebase_activity_center_dialog.dart` | 개발자 전용 Firebase Activity Center, 보관 세션·기간의 COST 조회, 파일 커서 페이지, debugPrint 코드 복사와 페이드 애니메이션 |
| `lib/features/account/data/services/user_status_service.dart` | 문서별 쓰기 순서 보존, 성공한 필드 값 추적, 순차 중복 UPDATE 생략 및 실제 쓰기 발생 여부 반환 |
| `lib/features/account/domain/repositories/user_repository.dart`, `lib/features/account/data/repositories/firestore_user_repository.dart` | 로그인·지역 동기화의 실제 원격 WRITE 여부를 호출부에 반환; 직접 계정 문서를 수정할 때 상태 확인 캐시 무효화 |
| `lib/features/account/applications/user_state.dart` | 기존 10초 지역 쓰기 생략 규칙 제거·확인된 원격 쓰기 및 로컬 갱신 유지. 로그인 세션 결과를 `LauncherDiagnostics`에 기록하고 인증 중 자동 STATUS Route 생성 방지 |
| `lib/features/commute/domain/repositories/commute_log_repository.dart` | 오늘 출근·관리자 달력의 월별 문서만 GET, 레거시 GET·삭제 SET 제거, 저장소 인스턴스 간 동시 동일 월 GET 공유 |
| `lib/shared/tts/application/foreground_task_handler.dart` | 기존 Plate TTS 및 근무 상태 알림 실행. Firebase Activity Bridge 시작·종료 호출 없음 |
| `lib/shared/tts/data/repositories/firestore_plate_tts_listener_repository.dart` | Plate TTS용 원래 Firestore 직접 조회·스냅샷 구독 유지. Activity Center 중계 래퍼 미적용 |
| `lib/app/diagnostics/firebase_activity_http.dart` | 공개 GCS URL HTTP 요청 상태·수신 본문 바이트 계측 |
| `lib/app/init/db_connection_status_section.dart` | AppBar 내부 116×48dp 컴팩트 상태·카운터 패널, 개발자 전용 상세 진입, 상태·숫자 페이드 애니메이션과 전체 카운터 접근성 정보 |
| `lib/features/dev/application/debug_session_controller.dart` | 개발자 승인 상태를 확인하여 전역 디버그 모드 활성화·비활성화 |
| `lib/features/selector/application/dev_auth.dart` | SharedPreferences 디버그 모드 상태, ValueNotifier 및 새 시작 시 복원·초기화 정책 |
| `lib/features/launcher/application/launcher_actions.dart`, `lib/app/init/app_exit_service.dart` | 기본 재시작 버튼의 앱 종료 준비·Android 네이티브 Activity 재실행 요청 |
| `lib/shared/auth/account_code_number.dart` | 코드번호 검증·생성·문서 ID·마스킹 |

최초 사용 목적은 지사 직원·본사 직원·출퇴근 기록형 → 일반 계정, 태블릿 설치형 → 태블릿형, 개인용 → 개인형으로 지정된다. 런처 인증 이후 회사·지역·허용 모드를 결정한다. 단순 Firebase 인증과 업무 계정 로그인의 성공은 다르다.

## 3. 회사 `divisions/dev`의 기존 상태

사용자가 제공한 기존 문서는 다음과 같다. 파일에 포함된 시드 데이터가 아니라 실제 백엔드에 존재한다고 전달된 값이다.

| 필드 | 기존 값 | 도움말 실행 후 |
| --- | --- | --- |
| `name` | `dev` | 유지 |
| `companyId` | `dev` | 유지 |
| `accountWriteLocked` | `false` | 유지 |
| `accountWriteVersion` | `11` | 유지 |
| `areaConfigVersion` | `3` | 유지 |
| `createdAt` | 2025-05-08 23:02:37 KST | 유지 |
| `initialAdminAccountId` | `aef260e9aa1-dev` | 유지 |

`initialAdminAccountId`는 계정이 실제 존재한다는 증거가 아니라 계정 문서 참조다. 이 참조 ID의 코드번호가 유효하다면 초기 개발 계정 생성에 사용하고 **기존 회사 참조를 다시 쓰지 않는다**. 참조 형식이 잘못됐거나 참조된 문서가 다른 계정이면 자동 덮어쓰기 대신 중단한다.

회사 문서 자체가 없는 경우만 신규 생성한다. 새 문서에는 `name`, `companyId`, `accountWriteLocked=false`, 초기 버전 `accountWriteVersion=0`, `areaConfigVersion=0`, 무작위 코드번호를 기반으로 한 `initialAdminAccountId`, 서버 `createdAt`을 기록한다. 기존 문서의 11·3 버전을 새 회사에 복제하지 않는다.

## 4. 런처 로그인 Dialog UI

| 위치/상태 | 내용 |
| --- | --- |
| 상단 `ACCOUNT VERIFICATION` | 제목 영역을 2초 이내 간격으로 연속 5회 탭하면 수집된 진단 로그를 `debugPrint(...)` 코드로 복사한다. |
| 상단 오른쪽 끝 | **일반 계정(`TerminalAccountKind.user`)이고 개발자 비밀번호 로그인 모드가 ON인 경우에만** 도움말 아이콘을 표시한다. 개인형·태블릿형은 개발자 로그인 모드가 ON이어도 도움말 아이콘을 표시하지 않는다. 진행 중에는 원형 로딩 표시로 바뀐다. |
| 계정 유형 | 현재 `PROFILE` 표시 |
| 입력 1 | `NAME or Unique` |
| 입력 2 | `코드번호`; 기존 코드 포맷터·검증 유지 |
| 코드번호 바로 아래 | 중앙 정렬 `계정 연결` / `연결 계정 변경` 버튼 |
| 하단 왼쪽 | 연결된 계정 이메일 또는 `연결된 계정 없음` |
| 하단 오른쪽 | `로그인`; 개발자 비밀번호 경로에서는 `계정 확인` |
| 도움말 실행 결과 | 인라인 로딩·성공·오류 표시, 결과 애니메이션·햅틱; 성공 시 계정 이름과 코드번호를 기존 입력 필드에 적용 |

Mini Terminal의 오픈 660ms, 닫힘 410ms, 내용 페이드·스케일과 입력 필드 포커스 전환을 유지한다. 도움말은 `AnimatedSwitcher`로 등장/퇴장하고, 결과 영역은 `FadeTransition`과 `SizeTransition`으로 바뀐다. 개발자 비밀번호 인증 오류 안내에는 160ms Fade·Slide 전환을 추가하며 애니메이션 감소 설정에서는 시간을 0으로 사용한다. 인증 중 로그인 세션 동기화가 성공하거나 실패해도 자동 성공·실패 STATUS 다이얼로그를 열지 않고 `LauncherDiagnostics.record()`에 결과를 남긴다. 닫힘 모션 완료 후 인증창 자신의 Route만 종료한다. 호출자가 직접 생성·보관한 `RawDialogRoute`의 Pop 결과와 `route.completed`를 차례로 확인하여 **170ms Fade·Slide 퇴장 및 오버레이 제거 완료**를 기다린 다음 런처 결과를 처리한다. 모션 감소 설정에서는 전환 시간이 0ms가 된다.

### 서로 다른 개발자 기능

| 조작 | 기능 | 권한 효과 |
| --- | --- | --- |
| 이름·코드번호가 빈 상태로 로그인 버튼 5회(일반·개인형), 3회(태블릿형) | `DeveloperAccountAuthorization.authorizeInteractive()`를 통해 개발자 비밀번호 인증 모드 승인 | 승인 성공 후 `_developerPasswordMode=true`, 업무 계정 로그인 자체를 완료하지는 않음 |
| 제목 `ACCOUNT VERIFICATION` 5회 연속 탭 | 메모리의 디버그 로그 클립보드 복사 | 권한 상승 없음 |
| 일반 계정에서 개발자 비밀번호 모드 활성화 시 헤더 우측 `?` | 개발 회사·지역·일반형 dev 계정 초기화 | 개인형·태블릿형은 표시·실행 모두 제외, 인증 및 충돌 검증 이후 누락 문서만 생성 |
| 전역 Developer Mode ON 상태의 `STATUS` | 진단 상태 Dialog 및 `debugPrint 코드 복사` | 기존 `DevAuth.devModeEnabled` 기준 유지 |
| `APP RESTART` 제목을 2초 이내 간격으로 5회 탭 | 재시작 Dialog를 닫힘 애니메이션과 함께 종료하고 업무 목적지로 이동 | 인증·지역·모드 검증 생략 없음 |
| 개발자 비밀번호 인증 성공 | 기존 승인 검증 후 `DebugSessionController.enable()` 호출 | 디버그 모드 ON이 확인돼야 로그인 완료 처리 |

개발자 비밀번호 인증 중 다른 STATUS Route가 위에 올라오는 상태에서도 `Navigator.pop()`으로 임의 최상단 Route를 닫지 않는다. 인증창 Route가 현재 최상단이고 명시적 종료가 허용된 경우에는 `pop()`으로 기존 Route Fade 애니메이션을 유지한다. 다른 Route가 최상단이면 소유한 인증창 Route만 `removeRoute()`로 종료하며 다른 팝업을 대신 닫지 않는다. 별도 STATUS는 사용자 요청으로 열린 경우에만 표시하며 로그인 성공·실패 진단은 기존 개발자 STATUS 클립보드에 유지한다. 인증창의 `route.completed` 확인 뒤 런처의 실제 Route가 최상단인지 검사하고, 사용자가 직접 연 STATUS 등 다른 Route가 위에 있으면 이를 강제 삭제하지 않고 정상 종료 및 오버레이 제거까지 화면 전환을 보류한다. 현재 로그인 런처가 최상단이 된 뒤에만 `pushReplacementNamed()`를 실행한다. STATUS 등 `PopupRoute`만 정상 종료를 기다리며, 전혀 다른 업무 PageRoute가 최상단이면 `launcher_navigation_stack_invalid`로 처리해 이전 로그인 전환을 중단한다. `_closing`은 첫 Route 검사 통과 뒤에 설정하고 이동 실패 시 복구해 영구 잠금이 발생하지 않도록 한다. 이 변경은 인증 성공·Role·지역·Firebase 쓰기 정책에 영향을 주지 않는다.

`_developerPasswordMode`와 전역 `DevAuth.devModeEnabled`는 별도 상태다. Debug 빌드의 개발자 승인 경로와 Release 빌드의 허용 계정 승인 경로도 다르다. 도움말 아이콘은 **일반 계정과 개발자 비밀번호 모드 ON을 모두 충족할 때만** 표시되며, 실행 함수에서도 같은 계정 유형 및 상태를 검사한다. 개인형·태블릿형은 기존 개발자 비밀번호 로그인만 유지하고 일반형 dev 초기화 기능에서 배제한다. 이 UI 검사로 Firestore 서버의 권한 규칙이 강화되는 것은 아니다. 개발자 도움말을 표시하거나 실행하는 것만으로는 전역 Developer Mode를 임의 ON으로 바꾸지 않는다. **개발자 비밀번호 로그인 검증에 성공한 경우에만** 기존 `DebugSessionController.enable()`을 호출하여 전역 디버그 모드를 ON으로 전환하고, 실패하면 로그인 완료로 처리하지 않는다.

### APP RESTART Dialog 재시작 및 숨겨진 건너뛰기

`ModeLauncherController`에서 수동 Google 계정 로그인 성공 및 업무 경로 준비를 완료하면 `requiresManualGoogleLoginRestart`가 설정되고, `parkinworkin_terminal_screen.dart`의 `_finalizeLauncherAndNavigate()`에서 `APP RESTART`를 표시한다. 기존 세션 자동 복원과 개발자 비밀번호 로그인은 이 재시작 요청 대상이 아니다. 제목을 누르는 것만으로 인증 절차나 Firebase UID·업무 계정 검증을 우회하지 않는다.

| 동작 | 조건·구현 | 결과 |
| --- | --- | --- |
| `재시작` 버튼 | 안내문 타이핑 완료 후 활성화, 중복 실행 차단 | `LauncherActions.restartApp()` → `AppExitService.restartApp()` → Android 플랫폼 재시작 요청. 기존 기능 유지 |
| 제목 `APP RESTART` 1~4회 탭 | 연속 입력 간격 2초 이내, 제목 영역만 감지 | 재시작 Dialog 유지, 외관·안내문 변경 없음 |
| 제목 `APP RESTART` 5회 탭 | Dialog 열림 완료, 재시작·건너뛰기 처리 중이 아닐 때 | `manual_google_login_restart_skip_requested` 진단 기록, 햅틱, Mini Terminal 닫힘 애니메이션, Dialog 종료, `manual_google_login_restart_skipped` 기록 |
| 건너뛰기 이후 | `_showManualGoogleLoginRestartNotice()`가 `false`를 반환 | `_resolveActiveWorkSessionNavigationTarget()` 및 `_closeLauncherAndNavigate()`의 기존 업무 경로로 진행; 네이티브 재시작 호출 없음 |
| 재시작 실행 중 제목 탭 | `_restarting=true` | 건너뛰기 처리 차단 |
| 건너뛰기 실행 중 재시작 버튼 | `_skipping=true` | 버튼 비활성화, 중복 실행 차단 |
| 모션 감소 옵션 | `reduceMotion=true` | 애니메이션 시간만 0으로 변경; 건너뛰기와 업무 이동은 동일 |

상단 `APP RESTART`는 평소에는 일반 제목과 동일하게 보이며 추가 힌트나 버튼을 표시하지 않는다. 제목의 연속 탭 판정은 2초 간격이며, 5회째에만 건너뛰기를 실행한다. 기존 오픈 660ms, 닫힘 410ms, 라우트 페이드 170ms, 안내 타이핑(문자당 24ms)과 개발자 `STATUS` 버튼을 유지한다. 건너뛰기 중에는 기존 `_MiniTerminalFrameState.close()`를 호출한다. Android 실제 재시작 성공과 프로세스 완전 종료는 별개이고, 건너뛰기는 이 네이티브 요청을 호출하지 않는다.

### 개발자 비밀번호 로그인 성공과 디버그 모드

`mode_launcher_controller.dart`의 `authenticateResolvedPassword()`는 `TerminalAuthCoordinator.verifyResolvedAccountPassword()`가 성공하여 유효한 계정이 반환됐을 때만 `DebugSessionController.enable(source: 'launcher_developer_password_login')`을 호출한다. 이 함수는 `DeveloperAccountAuthorization.isAuthorized`를 재검사하고 `DevAuth.setDevModeEnabled(true)`로 앱 내부 디버그 상태를 갱신한다. **비밀번호 검증 실패·개발자 승인 만료·디버그 활성화 실패에서는 디버그를 새로 ON으로 만들지 않고, 개발자 로그인 완료로 진행하지 않는다.**

성공 진단 이벤트 `developer_password_debug_enabled`, 실패 이벤트 `developer_password_debug_enable_failed` 또는 `developer_password_login_debug_unavailable`을 `LauncherDiagnostics.record()`에 기록한다. 전역 디버그 ON 이후에는 기존 Mini Terminal `STATUS`를 통해 `ParkinWorkinTerminalDiagnostics.debugPrintCode`를 클립보드로 복사할 수 있다. 이미 ON인 경우에도 동일 공유 상태를 사용한다. 개발자 비밀번호 인증 성공의 기존 Status Dialog 호출은 디버그 자동 활성화보다 앞에 두어 새 Status 팝업이 로그인 흐름에 갑자기 추가되지 않도록 한다. 사용자에게는 로그인 성공 이후 헤더 `STATUS` 버튼이 표시된다.

이 디버그 모드는 Flutter의 `kDebugMode` 빌드 플래그를 변경하지 않는다. 일반 Google 로그인에는 디버그 자동 활성화를 적용하지 않는다. 앱을 재실행한 경우 `DevAuth.restorePrefs()`의 첫 시작 정책에 따라 디버그 모드가 다시 OFF로 초기화될 수 있으므로 영구 ON이라고 해석하지 않는다.

## 5. 개발용 초기 데이터 생성 — 도움말 동작

**일반 계정(`TerminalAccountKind.user`)의 개발자 비밀번호 로그인 모드에서만** `lib/features/launcher/application/dev_bootstrap_service.dart`의 `DevBootstrapService.ensure(email: ...)`를 호출한다. 개인형·태블릿형은 도움말 UI를 숨기며 실행 함수 진입 검사에서도 즉시 반환하므로 이 기능으로 인한 Firestore 조회·쓰기가 발생하지 않는다. 도움말을 누를 때 연결된 계정이 없으면 기존 대화형 계정 연결 절차를 시도한다. 취소하거나 유효한 비익명 Firebase 인증과 외부 계정 이메일 일치가 없으면 문서를 생성하지 않는다. 연결 이메일은 신규 개발 계정의 등록 이메일로 사용하며 임의 이메일을 만들지 않는다.

| 순서 | 문서 경로 | 존재 시 | 없을 때 |
| --- | --- | --- | --- |
| 1 | `divisions/dev` | 내용 확인 후 **쓰기 0회**, `accountWriteLocked=true`이면 중단 | 회사 생성, 안전한 신규 코드로 `initialAdminAccountId` 지정 |
| 2 | `areas/dev-dev` | `division`, `name`, `isHeadquarter` 일치 검사 후 보존 | `headquarterAreaPayload()` 사용하여 생성 |
| 3 | `user_accounts_show/dev-dev` | 회사·지역 식별자 확인 후 기존 표시용 Count 값을 보존 | `accountMetaPayload()`로 0명 메타 생성 |
| 4 | `user_accounts/{accountId}` | 이름 `dev`, 역할 `headAdmin`, 코드, 회사·지역, 등록 이메일 일치 확인 | `DevUserWriteService.createUser()`로 신규 생성 |
| 5 | `user_account_codes/{codeNumber}` | 기존 예약이 같은 사용자를 가리키는지 확인 | 신규 계정 Batch에서 예약, 기존 계정은 검증 후 누락분만 복구 |
| 6 | `user_accounts_show/dev-dev`의 `users.{accountId}` 중첩 Map | 코드·Role·지역·활성 상태 검증 후 보존 | 계정 생성 Batch에서 경량 View 생성 |

`areas/dev-dev`는 본사 지역이며 `name=dev`, `englishName=dev`, `division=dev`, `isHeadquarter=true`, `modes=[single,double,triple,minor]`, 개발 테스트용 capability 목록, 서버 `createdAt/updatedAt`을 사용한다. 새 메타에는 **표시 전용** `activeCount=0`, `inactiveCount=0`, `totalCount=0`을 초기값으로 기록한다. `activeLimit`, `totalLimit`은 새로 작성하지 않는다. 기존 메타의 Count 값은 계정 CRUD에 의해 자동으로 변경되지 않는다. 신규 계정 생성 후에도 표시 전용 Count 값이 자동으로 1/0/1로 증가하지 않는 것은 의도된 동작이다.

개발 계정은 `name=dev`, `role=headAdmin`, `isActive=true`, `divisions=[dev]`, `areas=[dev]`, `currentArea=dev`, `selectedArea=dev`, 네 가지 정규 모드, 연결된 이메일을 가진다. 코드번호는 `AccountCodeNumber.isValid()`를 충족한다. 기존 회사의 `initialAdminAccountId=aef260e9aa1-dev`가 있다면 계정 ID와 코드번호는 해당 참조에 따른다. 회사가 새로 생성될 경우에는 `AccountCodeNumber.generate()`의 무작위 코드를 사용한다.

계정 생성은 `DevUserWriteService.createUser()`를 사용하며, `user_accounts` 원본, `user_account_codes` 예약, 지역 문서 내 `users.{accountId}` Map 항목의 **3개 대상 문서를 하나의 Batch로 기록**한다. `DevBootstrapResult.writeOperations`의 `accountCreated`도 3건으로 계산한다. 기존 계정의 조회용 View만 누락돼 복구한 경우 `projectionRepaired`는 1건, 코드번호 예약과 View를 함께 복구한 경우에는 합계 2건으로 계산한다. 이 계산은 실제 실행한 문서 쓰기 건수의 합이며 서비스 요청 횟수나 Firebase 청구 금액을 의미하지 않는다. 개발자 생성 경로는 예약 코드 GET 1회와 Root 존재 GET 1회를 수행한다. 회사·지역·표시용 메타 초기화는 별도의 존재 확인 트랜잭션을 사용한다. 계정 생성 도중 오류가 나면 앞서 생성한 지역·메타는 남을 수 있으므로 다음 실행에서 다시 확인하며, 임의 삭제하거나 이전 문서를 덮어쓰지 않는다.

### 기존 데이터와 재실행

- 이미 완성된 `dev` 회사·지역·메타·계정은 재사용하고 쓰지 않는다. 도움말 버튼 중복 입력은 UI에서 차단한다.
- 신규 문서 생성은 Firestore 트랜잭션의 존재 검사 후 수행한다. 다른 기기에서 동시에 생성하면 기존 계정·예약 충돌을 다시 확인한다.
- 기존 계정의 코드번호 예약 문서가 없으면 동일 계정을 가리키도록 복구할 수 있다. View 사용자 문서가 없으면 Root·예약 소유자·Role·지역 검증을 거쳐 경량 View만 복구하며 Count 필드는 건드리지 않는다.
- 조회용 문서·회사 참조·계정 이메일·역할·코드·지역이 충돌하면 수정을 중단한다. 표시 전용 Count 값과 실제 사용자 수를 비교해 자동 복구하거나 회사·계정 원본을 임의 재작성하지 않는다.
- 기존 회사에 `initialAdminAccountId`가 없거나 형식이 잘못된 경우에는 신규 계정을 추측해서 만들지 않고 사용자 확인을 요구한다.
- 계정 생성은 `password`를 저장하지 않는다. 따라서 dev 계정의 일반 이메일 기반 로그인 가능성과 **개발자 비밀번호 로그인 가능 여부는 별개**이며, 저장된 비밀번호가 없다면 후자의 인증은 성공하지 않는다. 기본·고정 비밀번호를 새로 심지 않는다.

## 6. 진단 기록·복사·오류 처리

`DevBootstrapService`는 요청, 회사·지역 준비, 계정 쓰기 단계, 성공·실패를 `ParkinWorkinTerminalDiagnostics.record()`로 기록하며 내부적으로 `debugPrint`를 호출한다. 계정 코드번호, 이메일, 인증 토큰은 새 초기화 진단에 원문으로 기록하지 않는다. 기존 서비스의 상세 메시지를 그대로 노출하는 대신 단계별 이벤트와 처리된 문서 수를 기록한다.

최초 개발자 초기화 완료 기록의 `writeOperations`는 회사·본사 지역·표시용 메타 생성 각 1건과 신규 계정 Batch 3건을 합산하므로 모두 신규 생성되면 6건이다. 경량 View만 복구하면 1건으로 기록한다. 기존 STATUS의 완료 안내와 복사한 `debugPrint(...)` 코드에 동일한 수정 수치가 반영된다. 최초 초기화에 없는 문서를 새로 쓰는 경우에만 실제 쓰기가 발생한다.

로그인 세션 동기화는 성공 시 `login_session_sync_succeeded`, 실패 시 `login_session_sync_failed`를 `LauncherDiagnostics.record(scope: auth)`로 기록한다. 개발자 비밀번호 인증창은 `launcher_auth_dialog_close_started`, `launcher_auth_dialog_route_close_requested`, `launcher_auth_dialog_route_popped`(Navigator 종료 결과), `launcher_auth_dialog_overlay_removed`(퇴장 및 오버레이 제거 완료), 기존 호환 이벤트 `launcher_auth_dialog_route_closed`를 순서대로 기록하며 Route를 식별할 수 없는 경우 `launcher_auth_dialog_close_failed`를 기록한다. 런처 이동 단계에서는 `launcher_navigation_deferred`·`launcher_navigation_resumed`·`launcher_navigation_stack_invalid`·`launcher_dashboard_navigation_requested`를 구분하여 기록한다. 세션 동기화 결과를 표시하기 위해 런처 인증 도중 자동 STATUS Route를 추가하지 않는다. 성공·실패 진단은 `LauncherDiagnostics.debugPrintCode`와 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()`의 기존 STATUS 복사 경로에 포함된다. 기존 `DevFirebaseDebugDialog.show()`는 로그인 이외의 업무 기능에서 그대로 사용할 수 있다.

로그 복사는 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCode` 형식을 유지한다. 개발자 `STATUS`에서는 클립보드 버튼을 누를 때 `debugPrintCodeWithJournal()`로 기존 진단과 로컬 보관된 현재 세션의 Firebase 기록을 비동기로 합친다. APP RESTART 건너뛰기 및 디버그 자동 활성화도 `LauncherDiagnostics.record()` 및 `ParkinWorkinTerminalDiagnostics.record()`에 기록되어 `debugPrint(...)` 코드 복사 대상에 포함된다. 개발자 `STATUS` Dialog의 클립보드 버튼은 진입 시 및 복사 실행 직전에 `DevAuth.isDevModeEnabled()`로 권한을 재확인하며, 별도의 제목 5회 탭 복사는 개발자 권한을 제공하지 않는다. 진단 복사 과정에는 Firestore 읽기·쓰기가 필요 없다. UI는 연결 실패·권한 만료·문서 충돌과 일반 네트워크 오류를 구분해 표시한다.

### Firebase Activity Center — 비용 관련 앱 활동 계측

이 기능은 **메인 앱 Isolate에서 계측이 연결된 호출부**의 Firebase/Google Cloud Storage API 활동을 집계한다. 포그라운드 Plate TTS Isolate의 Firestore 활동은 안정성 우선 정책에 따라 의도적으로 통합하지 않는다. Firebase 프로젝트 전체의 실제 청구액·청구 읽기 수가 아니다. 로그를 서버에 저장하거나 계측 목적으로 Firestore를 추가 조회하지 않는다.

| 화면/권한 | 디버그 OFF | 디버그 ON |
| --- | --- | --- |
| 우측 상단 `LIVE DB` · `STORAGE DB` | 상시 표시 | 상시 표시 |
| 우측 상단 `READ` · `WRITE` · `DELETE` · `SNAP` · `LISTEN` · `STORAGE` | 상시 계측·표시 | 상시 계측·표시 |
| `ACTIVITY CENTER` 진입 항목 | 표시, 상세 접근 거부 | 표시, 상세 Dialog 진입 가능 |
| 최근 이벤트·유형별 필터·상세 상태 | 접근 거부 | 열람 가능 |
| 활동 로그 클립보드 복사 | 접근 거부 | `debugPrint(...)` 코드로 복사 가능 |
| 기존 `STATUS`의 `debugPrint 코드 복사` | 기존 개발자 접근 정책 | 기존 진단에 Firebase 활동 로그도 병합 |

#### 기존 헤더 높이 복원 및 1시 방향 관측 패널

Activity Center 도입 전 `261103 2050.zip`의 일반 AppBar는 기본 `kToolbarHeight`인 **56dp**, Single 내부·주차 완료 AppBar는 `toolbarHeight: kToolbarHeight`였다. 관측 패널 도입으로 `261104 0027.zip`에는 7개 화면에 `toolbarHeight: 128`, 우측 영역 `height: 116`, `maxWidth: 168`이 적용되어 본문 시작 위치를 아래로 이동시켰다. 이번 변경은 **7개 화면 모두 원래 56dp 헤더 높이로 복원**하고 본문 시작 위치를 유지한다.

| 위치·구성 | 변경 전 `0027.zip` | 헤더 복원 후 |
| --- | --- | --- |
| 본사·Single·Double·Triple·Minor 대시보드 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | 기본 AppBar 56dp, 우측 `kToolbarHeight - 8`=48dp·최대 132dp |
| Single 내부 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | AppBar 56dp, 우측 48dp·최대 116dp |
| 주차 완료 화면 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | AppBar 56dp, 우측 48dp·최대 132dp |
| 공통 관측 위젯 | 163dp 폭, 상태·집계·진입 문구의 세로 누적 | 고정 116×48dp, 상태 두 줄·집계 두 줄, 전체 패널 탭 |
| 본문 시작 위치 | 추가 툴바 높이 72dp만큼 하강 | 기존 높이와 동일한 위치 |

고정 패널 1행에는 `LIVE DB ON/OFF`, 2행에는 `STORAGE DB ON/OFF`를 표시한다. 3행 `R·W·D`는 READ·WRITE·DELETE, 4행 `SN·L·ST`는 SNAP·현재 활성 LISTEN·STORAGE를 뜻한다. 카운터는 큰 값에서 K/M/B 단위로 축약하며, **계측 원본 수치·상세 설명은 기존 Activity Center Dialog와 개발자 `STATUS` 복사에 유지**한다. 첫 줄의 화살표 및 패널 전체 탭으로 Activity Center에 진입하되, 개발자 모드가 OFF이면 기존처럼 상세 접근을 거부한다. 화면 판독기에는 축약하지 않은 전체 명칭·수치를 제공한다.

상태 점의 `AnimatedContainer`, ON/OFF의 `AnimatedSwitcher`, 카운터의 페이드 전환을 보존한다. 색상·텍스트만 바뀌고 패널 크기는 고정되며 `MediaQuery.disableAnimations`이면 전환 시간을 0으로 한다. 터치 가능한 기존 1시 방향 패널을 `IgnorePointer`로 복원하지 않으며, 7개 화면의 좌측 로고·중앙 터미널 버튼·기존 업무 애니메이션은 변경하지 않는다. 계측용 Firestore 요청이나 Storage 작업도 추가하지 않는다.

현재 `LIVE DB ON`은 익명이 아닌 Firebase Auth 사용자가 존재한다는 뜻이고, `STORAGE DB ON`은 사용 가능한 Google 로그인 세션이 존재한다는 뜻이다. 이것을 서버 통신 정상 여부 또는 비용 발생 여부로 단정하지 않는다. 디버그 OFF에서도 계측 서비스는 작동하지만, 개별 활동의 상세 정보·복사는 디버그 모드 ON에서만 제공한다. 열린 Dialog에서 디버그 모드가 꺼지면 닫히고 복사 시점에도 모드를 재검사한다.

#### 앱 전체 실행 세션의 계측과 로컬 보관 — 2026-11-04

앱이 `main()`에 진입해 `WidgetsFlutterBinding.ensureInitialized()`가 끝나면 `FirebaseActivityMeter.startSession()`으로 `SESSION_START`를 동기 기록한다. `initializeJournal()`은 UI 시작을 불필요하게 대기시키지 않고 비동기 실행한다. 저장 경로 준비 전 이벤트는 최대 4096개의 메모리 대기열에 기록한 뒤 준비되면 기록한다. 대기열이 넘치거나 디스크 쓰기 실패가 발생하면 누락·실패 수치로 표시한다. 메인 Isolate의 Flutter/Firebase SDK 메서드가 계측 래퍼를 거쳐야만 호출 내용이 기록된다. 앱 실행 구간을 표시하는 행위 자체가 Firebase 읽기·쓰기를 추가하지 않는다.

| 라이프사이클 단계 | 기존 동작 | 이번 수정 후 | 비용 해석 |
| --- | --- | --- | --- |
| `main()` 첫 실행 | Meter 최초 참조 시점부터 이벤트 존재 | `SESSION_START`를 Firebase 초기화 이전에 기록, 로그 저장소 준비 | SESSION_START 자체는 Firebase 비용이 아님 |
| Firebase Core 초기화 | 별도 초기화 진단 | `firebase_core / INITIALIZE_APP` 성공·실패·지연 기록 | Firestore READ가 아님 |
| App Check 활성화·진단 토큰 | 별도 진단만 존재 | `ACTIVATE`, `TOKEN_FORCE_REFRESH` 계측 | 과금 문서 읽기와 별개 |
| 기존 Google·Firebase 인증 준비 | 인증 진단 중심 | `CONFIGURE_RUNTIME`, `INITIALIZE_SESSION`, `BOOTSTRAP_EXISTING_USER`, 실제 Firebase `SIGN_IN_*`, `SIGN_OUT` 계측 | 인증 API 기록 자체가 청구 단위를 확정하지 않음 |
| 로그인·로그아웃·화면 이동 | UI 단계가 변경 | 동일 세션 ID 유지, 계측 계속 | 앱 실행 중 관측 범위 연속 유지 |
| 앱 백그라운드 | 앱 생명주기에 따름 | 계측을 수동 중단하지 않음 | OS가 프로세스를 종료하면 마지막 기록이 유실될 수 있음 |
| 정상 종료·재시작 요청 | 업무·알림 서비스 정리 후 종료 | `SESSION_EXIT_REQUESTED`/`SESSION_RESTART_REQUESTED`, `SESSION_EXIT_PREPARED`/`SESSION_RESTART_PREPARED` 기록·저널 flush 시도 | PREPARED는 종료 준비를 뜻하며 OS 프로세스 종료 확정 신호가 아님 |
| 종료 실패 | 기존 업무·알림 복구 | `SESSION_EXIT_FAILED`/`SESSION_RESTART_FAILED` 기록 후 기존 복구 유지 | 계측을 멈추지 않음 |
| OS 강제 종료 | 종료 콜백 보장되지 않음 | 파일에 남은 이벤트 유지, 다음 실행에서 `PREVIOUS_SESSION_UNCLEAN` 또는 `PREVIOUS_SESSION_OUTCOME_UNKNOWN` 구분 | 마지막 사건 유실 및 실제 종료 여부는 앱만으로 확정 불가 |
| 앱 새 실행 | 메모리 누적 초기화 | 새 sessionId·새 카운터, 이전 보관 파일은 제한 내 유지 | 세션 사이 합계는 별도로 조회 |

로컬 파일은 `path_provider`의 Application Support 디렉터리 아래 `firebase_activity/`에 저장하는 JSON Lines 형식이다. 세션별 파일명에 세션 ID와 파일 순번을 포함하고, 2MiB 단위로 나눈다. 기본 보관 한도는 **최근 7일·총 20MiB**이며 한도 초과 시 오래된 조각부터 삭제한다. 현재 열려 있는 조각은 삭제하지 않지만 현재 세션의 오래된 조각도 용량 제한으로 정리될 수 있으므로, 앱이 수일간 실행되거나 이벤트가 매우 많은 경우 완전한 무기한 보존을 보장하지 않는다. UI의 최근 500개는 기존처럼 메모리에서 즉시 표시하고, 저장된 이벤트는 로컬 파일에서 별도로 읽는다. 모든 파일 쓰기는 비동기로 수행하며 오류가 기존 인증·Firestore·Storage 업무 요청의 성공 여부에 영향을 주지 않도록 격리한다.

`FirebaseActivityJournal`은 이벤트 시각, 세션 ID, 서비스, 작업 종류, 결과와 이미 마스킹된 진단 문자열만 로컬에 기록한다. 실제 사용자 문서 본문, UID·이메일, 차량번호, OAuth 토큰, 다운로드 서명 URL을 추가로 수집하지 않는다. 계측 파일은 서버에 전송하거나 Firestore 문서로 저장하지 않는다. 파일은 앱 전용 디렉터리이지만 디버그 기기·백업·탈옥 등에서는 별도 보호가 필요하며 장기간 개인정보 관련 로그를 보존하지 않도록 용량·기간 제한을 적용한다.

| 조회·복사 진입점 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 상단 116×48dp 패널 | 실시간 누적 요약 | 그대로 유지, 헤더 56dp 불변 |
| Activity Center 기본 목록 | 메모리 최근 500개 | 그대로 유지, `보관 기록` 모드와 전환 애니메이션 추가 |
| 보관 기록 | 미지원 | 현재·이전·전체 보관 세션 및 시간 필터, JSONL 파일을 최신순 역방향으로 읽는 커서 기반 100건 페이지 조회 |
| Activity Center 클립보드 복사 | 최근 500개 이벤트만 | 선택 세션·서비스·시간 범위의 로컬 보관 기록 전체를 `debugPrint(...)` 코드로 복사 시도 |
| `COST` 복사 | 현재 실행 세션의 메모리 요약 | 선택한 보관 세션·기간의 구조화 JSONL 이벤트에서 계산한 `OBSERVED / ESTIMATED / UNAVAILABLE` 복사, 화면과 같은 집계 결과 사용 |
| `STATUS` 클립보드 복사 | 기존 진단 + 최근 Firebase 이벤트 | 복사 실행 시 기존 진단 + 현재 세션의 보관 이벤트 전체를 동적으로 생성 |
| 디버그 OFF | 상세 열람 제한 | 로컬 기록은 계속, 상세·복사는 제한 |
| 디버그 ON→OFF | 기존 상세 닫힘 | 상세 닫힘 유지, `STATUS` 복사 버튼에서도 권한 재검사 |
| 로컬 파일 접근 실패 | 최근 메모리만 존재 | 실패 시 대기열 보존·지수 백오프 복구 시도, 오류·누락 표시, 로컬 파일 복사 실패 시 현재 세션의 최근 500개 메모리 기록으로 대체 가능 |

클립보드 복사는 Android 클립보드 처리 한계로 매우 큰 로그에서 실패할 수 있다. 실패하면 성공으로 표시하지 않으며, 서비스·시간 범위를 좁혀 다시 복사할 수 있다. 앱 내 로컬 보관에서 이미 삭제되었거나 저장되지 않은 이벤트를 복원할 수 없으며, `PREVIOUS_SESSION_UNCLEAN`은 이전 세션의 종료 준비가 확인되지 않음을 뜻한다. `PREVIOUS_SESSION_OUTCOME_UNKNOWN`은 준비 또는 이전 버전의 종료 기록은 있지만 OS의 실제 프로세스 종료 결과를 확인할 수 없다는 뜻이다. Apple/Android 플랫폼의 프로세스 중단에서는 종료 후 코드를 실행할 수 없으므로 종료 준비 기록이 없는 것이 곧 앱 결함이라는 뜻은 아니다.

Firebase Auth·Google Auth·App Check의 진단 이벤트는 실제 Firebase 과금 단위와 분리해 `auth`, `google_auth`, `app_check`, `firebase_core`, `lifecycle`로 기록한다. 기존 READ·WRITE·DELETE·SNAP·STORAGE 합계에는 포함하지 않는다. Firestore 표준/엔터프라이즈 요금, 인덱스 읽기, Rules 의존 읽기, 보존·저장 용량, SDK 내부 재시도, 다른 기기 및 서버 작업은 앱 계측만으로 확정할 수 없다. Plate TTS 포그라운드 Isolate의 구독은 이전 합의대로 계측에서 제외하고 **기존 정상 처리 코드를 변경하지 않는다**.

#### 사용자 상태·출퇴근 Firestore 요청 절감 — 2026-11-04, `261104 1413.zip` 기반 2차

이번 변경은 단일 기기 사용과 **레거시 출퇴근 기록 없음**을 요구 전제로 삼는다. 오늘 출근 여부 확인과 관리자 월별 달력 조회는 별개 기능이므로, 관리자 출퇴근·휴게 달력은 삭제하지 않는다. Firestore 작업을 계측하기 위한 추가 GET·UPDATE는 발생시키지 않는다. Firebase UID·인증 흐름·Plate TTS·근무 알림·Firestore Rules는 변경하지 않는다.

| 실제 호출부 | `1413.zip` 수정 전 | 수정 후 | 이유 및 효과 |
| --- | --- | --- | --- |
| `UserStatusService._safeUpdate()` | 동시 동일 요청만 공유; 직후의 동일값 순차 UPDATE는 다시 전송 | 동일 문서의 쓰기를 요청 순서대로 수행하며 **성공한 원격 필드 값**과 차이를 비교. 동일하면 `WRITE_SKIPPED`, 일부만 바뀌면 필요한 필드만 UPDATE | 서버에 이미 성공적으로 저장했다고 확인된 값만 생략. 실패 시 해당 문서의 확인 상태 무효화 |
| 동일 문서의 교차 요청 | 서로 다른 값의 UPDATE가 동시에 겹칠 수 있음 | 동일 문서 쓰기를 직렬화하고, 서로 다른 변경을 사이에 둔 동일값 요청은 임의로 합치지 않음 | `A→B→A` 요청의 최종 결과를 `B`로 바꾸지 않음 |
| 동시 동일 UPDATE | `_pendingExactUpdates`로 공유 | 가장 최근에 요청된 동일 변경인 경우만 공유, 중간에 다른 변경이 있으면 개별 실행 | 중복 제거와 요청 순서를 동시에 보존 |
| `updateLoginSession()` | 항상 UPDATE하며 사용자 진단은 쓰기 1회로 출력 | 같은 공통 상태 비교 경로를 사용하고 호출자에게 **실제 전송 여부 `bool`** 반환, 진단에도 0/1 적용 | 로그인 상태 동일 시 0회 가능. 로그인 문서가 없으면 기존대로 실패 처리하여 부분 계정 생성 금지 |
| `UserState.areaPickerCurrentArea()` | 최근 10초 조건으로 상태 확인 | **10초 기준 제거**. 저장소가 성공한 상태를 확인한 경우만 UPDATE 생략, 로컬 UI·`AreaState.updateArea`는 그대로 수행 | 단일 기기 전제. 원격 성공 증거가 없으면 기존 WRITE 수행 |
| 직접 `updateUser`·`updateTablet`·삭제 | 상태 서비스의 필드 확인 기록과 독립 | 전체 계정 문서를 별도 코드가 수정하기 전에 확인 캐시 무효화 | 잘못된 과거 필드 상태를 근거로 생략하지 않도록 방어 |
| 월별 출퇴근 GET | Repository 인스턴스별 동일 GET만 공유 | 동일 FirebaseFirestore 인스턴스의 저장소들이 진행 중인 동일 월별 문서 GET 공유 | 완료된 Future는 제거, 최신 기록을 영구 캐싱하지 않음 |
| `hasLogForDate()` | 월별 GET에서 없으면 레거시 GET | **월별 GET 1회만 확인**, 레거시 GET 제거 | 오늘 출근 기록이 없는 경우 GET 2→1 가능. 오류는 미출근으로 위장하지 않고 호출자에게 전달 |
| `getMonthlyTimes()` | 월별 + 레거시 GET 후 병합 | 월별 문서만 조회하고 기존 일자별 시각 포맷을 반환 | 관리자 달력은 유지, 상태별 GET 2→1 가능 |
| `deleteLogsForDates()` | 월별 SET·필요 시 정리 후 레거시 루트 SET | 레거시 삭제 SET 제거, 월별 기록 삭제·빈 월 정리는 유지 | 레거시 SET 1회 제거. `_deleteMonthDocIfEmpty()`의 추가 GET·조건부 DELETE는 유지 |
| `_ensureRootDoc()` | 월별 기록 저장 시 루트 메타데이터 SET | **유지** | `latestYearMonth` 등 별도 메타 필드·외부 규칙 의존 여부 미확정이므로 무리하게 삭제하지 않음 |
| Activity Center 최적화 안내 | 200ms 글자 페이드 | 페이드와 세로 미세 슬라이드 전환, `disableAnimations` 시 즉시 전환 | 새로운 화면 크기·헤더 변경 없음 |

실제로 생략된 작업은 `service=optimization`, `result=skipped`로 Journal에 기록한다. `WRITE_COALESCED`, `WRITE_SKIPPED`, `WRITE_FIELDS_REDUCED`, `MONTH_GET_COALESCED`, `LEGACY_GET_SKIPPED`, `LEGACY_WRITE_SKIPPED`는 서버 작업이 아니므로 READ·WRITE 카운터를 증가시키지 않는다. 이벤트에는 메서드 경로·필드 이름·생략 사유만 기록하며 계정 ID·필드 값·로그인 비밀번호를 새로 기록하지 않는다. 기존 개발자 모드 ON의 `STATUS` Dialog와 Activity Center에서 `debugPrint(...)` 코드로 복사할 수 있으며, OFF에도 저널 기록은 계속한다.

이 변경은 **제공된 운영 전제가 유효할 때** 월별 구조의 출퇴근 기록을 동일하게 보존한다. 실제 서버에 구형 `logs` 기록이 남아 있거나 구형 앱이 다시 기록한다면 해당 기록은 조회·삭제되지 않는다. 직접적인 계정 수정이 다른 서비스에서 병행되거나 서버 규칙·외부 관리자가 필드를 갱신하는 경우에는 상태 추적 값이 최신 서버 값과 다를 수 있다. 이번 범위는 동일 계정의 다중 기기 동시 접속을 제외하나, 전면적인 서버 동시성 제어를 제공하는 것은 아니다. 또한 Firebase SDK 호출 수 절감과 실제 청구량·결제 금액은 다른 수치다.

#### 계측 정의

| 지표·이벤트 | 측정하는 값 | 청구량 해석 시 한계 |
| --- | --- | --- |
| `GET` | 단일 문서 `get()` 완료 | 캐시 응답, 과금 읽기와 다름 |
| `QUERY` | 쿼리 `get()` 완료; 반환 문서 수·캐시 여부 | GET 호출 1회가 문서 1개 읽기라는 뜻이 아님 |
| `AGGREGATION` | `count().get()` 완료 | 인덱스 읽기 청구 단위는 계측할 수 없음 |
| `SET`, `UPDATE`, `DELETE` | 비트랜잭션 문서 작업 완료 | CREATE와 덮어쓰기·병합을 무리하게 구분하지 않음 |
| `TRANSACTION` | 트랜잭션 Future 완료·실패 | 작업 기록과 확정 문서 작업 집계는 별도로 유지 |
| `STAGE_SET`, `STAGE_UPDATE`, `STAGE_DELETE` | 트랜잭션·배치 내부에 예약한 작업 | 예약 단계에서 WRITE/DELETE에 합산하지 않음; 재시도된 트랜잭션은 마지막 성공 시도만 확정 |
| `BATCH` | 배치 커밋 Future 완료·실패 | 커밋 성공한 배치의 문서 쓰기·삭제 건수를 별도로 확정 |
| `LISTEN_START`, `LISTEN_CANCEL` | 메인 앱의 계측 Stream 실제 구독 시작·해제 | Plate TTS 포그라운드 구독은 활성 리스너 수에 포함되지 않음 |
| `SNAP` | 구독 스트림의 스냅샷 수신·문서 수·변경 수·캐시/미확정 쓰기 상태 | SNAP 1회가 청구 읽기 1회는 아님 |
| `UPLOAD`, `DOWNLOAD`, `URL_ACCESS`, `STORAGE_DELETE`, `STORAGE_LIST`, `METADATA` | Storage SDK·GCS API·공개 GCS URL 요청 | 업로드 TaskSnapshot, Media 스트림 소비 완료 및 HTTP 본문 바이트를 계측; 확정 네트워크 과금량은 아님 |
| `ERROR` | 성공 대신 실패한 작업의 오류 유형·소요 시간 | 실패했어도 일부 백엔드 작업이 발생했을 수 있음 |

상단의 각 수치는 포그라운드 Plate TTS를 제외한 앱 관측 범위에 한정된다. `READ`는 성공한 명시적 GET·QUERY 호출 수, `WRITE`는 성공한 일반 SET·CREATE·UPDATE 작업 수에 트랜잭션·배치의 **커밋 성공 문서 쓰기 수**를 더한 값, `DELETE`는 일반 문서 삭제에 커밋 성공 삭제 작업을 더한 값이다. `SNAP`은 수신 이벤트 수, `LISTEN`은 현재 활성 계측 리스너 수, `STORAGE`는 성공한 계측 객체 작업 수이다. 트랜잭션·배치 자체의 호출 이벤트와 예약 단계 `STAGE_*`는 WRITE에 중복 합산하지 않는다. **WRITE/DELETE는 계측된 클라이언트 확정 작업 수이며 프로젝트 전체 청구량을 보증하지 않는다.**

트랜잭션은 `runTrackedActivityTransaction()`으로 실행한다. `Zone`에 시도별 `STAGE_*` 작업 수를 저장하고, 재시도 중 실패한 시도의 수를 버리고 **최종 Firestore Future 성공 이후 마지막 성공 시도에서 확인된 쓰기만 `COMMITTED_TRANSACTION`으로 기록**한다. 배치는 `trackedActivityBatch()`가 `set/update/delete` 횟수를 수집하고 원래 `WriteBatch.commit()` 성공 후 `COMMITTED_BATCH`를 기록한다. 커밋 실패는 확정 집계 0건이며 기존 `BATCH`·`TRANSACTION` 로그와 예외 처리는 유지한다. SDK에 드러나지 않은 서버 내부 동작과 기존 `STAGE_*`가 삽입되지 않은 트랜잭션 작업은 관측 범위 밖일 수 있다.

현재 프로젝트의 FlutterFire `WriteBatch.update()` 및 `Transaction.update()`는 `Map<String, dynamic>`을 요구한다. 따라서 `FirebaseActivityWriteBatch.update()`도 해당 타입을 유지한다. 중첩 Map의 특정 사용자 ID와 하위 필드를 안전하게 바꿀 때는 **문자열 키를 가진 계층형 Map 데이터**를 `set(..., SetOptions(mergeFields: [FieldPath(...)]))`로 전달한다. `FieldPath`는 `update()`의 Map 키가 아니라 `mergeFields`의 요소로 사용하므로 사용자 ID에 점(`.`)이 있어도 경로 분리 오류를 피한다. `FieldValue.delete()`로 문서 내부 Map 필드를 제거하는 작업은 **문서 쓰기(WRITE)** 로 계측하고, 문서 자체를 삭제하는 `batch.delete()`만 `DELETE`로 계측한다. 실제 `set`/`update`는 커밋 성공 후 `COMMITTED_BATCH`에 기록한다.

`COST`는 전체 활동 로그의 별칭이 아니라 전용 분석 화면이다. `OBSERVED`는 호출 수·반환 문서 수·캐시/서버 응답·확정 쓰기·삭제·스냅샷·Storage 처리 바이트를 제시한다. `ESTIMATED`는 현재 SDK 관측값으로 확정 과금액을 산출할 수 없다는 조건을 표시하며 **임의 금액을 생성하지 않는다**. `UNAVAILABLE`에는 인덱스 읽기·Rules 의존 읽기·저장 용량·SDK 내부 재시도·다른 클라이언트 비용을 명시한다. COST 복사 버튼은 전체 이벤트가 아닌 이 세 범주의 요약을 `debugPrint(...)`로 출력한다.

Storage 작업에서는 Firebase Storage `TaskSnapshot.bytesTransferred`, `getData()` 반환 바이트, GCS `Media.stream` 실제 소비 크기, GCS 공개 URL HTTP 응답 `bodyBytes.length`를 각각 계측한다. 메타데이터만 조회하는 `storage.objects.get`은 `DOWNLOAD`이 아니라 `METADATA`로 분류한다. 요청 본문 크기·객체 크기·실제 네트워크 청구 전송량은 서로 다른 수치다. HTTP 계측은 확인된 `storage.googleapis.com` CSV 다운로드 호출부에만 연결하며 외부 이미지 로더가 자체 실행하는 다운로드는 포함하지 않을 수 있다.

Plate TTS·근무 상태 알림에 사용하는 포그라운드 Task Isolate는 Firebase Activity Center 계측 브리지를 사용하지 않는다. `foreground_task_handler.dart`에서는 `FirebaseActivityBridge.startForeground()`와 `stopForeground()` 호출을 제거하고, `main.dart`에서는 `ensureMainReceiver()`를 제거한다. 기존 `FlutterForegroundTask.initCommunicationPort()`, 근무 상태 알림 콜백, Plate TTS의 Firebase 조회·스냅샷 구독 및 소유권 관리 방식은 유지한다. 따라서 포그라운드 Plate TTS가 서버에서 문서를 읽거나 스냅샷을 수신해도 메인 화면의 READ·SNAP·LISTEN에 합산되지 않을 수 있으며, 이것을 과금 활동 0건으로 해석하지 않는다. Activity Center의 장애가 Plate TTS 실행 조건·구독·음성 안내·근무 상태 알림을 변화시키지 않는 것을 우선한다.

압축 파일 덮어쓰기는 기존 파일 삭제를 수행하지 않으므로 `lib/app/diagnostics/firebase_activity_bridge.dart`가 기존 프로젝트에 남아 있을 수 있다. 이 파일은 본 수정 후 앱 진입점과 포그라운드 핸들러에서 참조되지 않는 비사용 코드이며, 런타임에서 콜백을 등록하거나 포그라운드로 계측 메시지를 보내지 않는다. 저장소에서 파일까지 정리하려면 별도 삭제가 필요하다.

계측 작업은 `firebase_activity_meter.dart`의 메모리 링 버퍼(최근 500개 이벤트), `ValueNotifier`와 세션별 로컬 JSON Lines 저장소로 분리한다. UI는 120ms 단위로 갱신을 병합하며 서버 접근 없이 값을 표시한다. 디버그 ON에서만 각 이벤트를 `debugPrint`로 출력한다. 로그 필드는 시각·서비스·작업 종류·출처 코드 파일·결과·지연시간·문서 수·확인 가능한 바이트·캐시 여부로 제한한다. 동적 문서 ID, Google 이메일, 비밀번호, 계정 코드번호, 객체 URL, 인증 토큰은 이벤트에 기록하지 않는다.

#### 실제 수정과 커버리지

- `lib/app/diagnostics/firebase_activity_meter.dart`: 메인 앱의 시도별 커밋 확정 수, 별도 COST 요약, Stream·Future 계측. 이전 Isolate 수신 유틸리티는 실행 경로에서 사용하지 않음
- `lib/app/diagnostics/firebase_activity_center_dialog.dart`: COST 전용 분석, 개발자 권한 검증·로그 복사, 필터 전환 페이드 및 포그라운드 Plate TTS 미계측 안내
- `lib/app/diagnostics/firebase_activity_http.dart`: 공개 GCS HTTP GET 횟수·상태·본문 크기 기록
- `lib/shared/tts/application/foreground_task_handler.dart`: Activity Bridge 호출만 제거하고 기존 Plate TTS·근무 상태 알림 처리 보존
- `lib/shared/tts/data/repositories/firestore_plate_tts_listener_repository.dart`: `2050.zip`의 직접 GET·snapshots 동작 원형 복원
- `lib/main.dart`: Activity Bridge 메인 수신은 연결하지 않고, 앱 진입 시 계측 세션 시작 및 Firebase 초기화·App Check·초기 인증 작업 관측을 추가한다. 기존 통신 포트 및 근무 알림 초기화는 보존한다
- `lib/app/init/db_connection_status_section.dart`: 인증 기반 DB ON/OFF, 상시 활동 요약, `ACTIVITY CENTER` 터치 연결
- `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart`: 기존 `STATUS` 복사에 보관된 현재 세션 전체 Firebase 이벤트를 비동기로 병합하고 복사 시 개발자 권한을 재검사
- 기존 우측 상단 DB 상태부를 쓰는 7개 화면: 확장됐던 AppBar를 56dp로 원복하고 기존 화면별 최대 너비 132dp/116dp와 48dp 표시 영역을 복원. 전체 패널 탭 유지, 116×48dp 고정 UI로 계측 표시
- 기존 Firestore 호출부: 일반 읽기·쓰기·snapshots 유지, `runTrackedActivityTransaction` 30곳 및 Firestore 배치 생성 14곳을 커밋 확정 계측으로 연결
- 기존 Storage 호출부: Firebase Storage SDK 음성·백업, GCS 객체 `insert/get/list`, GCS Media 스트림, 공개 GCS CSV HTTP 다운로드 4곳 계측

해당 계측은 런타임 동작을 가로채는 전역 네트워크 프록시가 아니라, **수정한 Dart 호출부에 삽입한 계측 확장**이다. 호출부 자체가 이 파일의 범위 밖에 있으면 계측되지 않는다. Google Cloud Storage 이미지 로더 내부 요청, SDK 내부 재시도, 보안 규칙에서 발생하는 문서 접근, Firestore 인덱스 사용, Plate TTS 포그라운드 Isolate와 다른 Isolate, 다른 기기, 서버 측 작업, TTL/PITR/백업, 저장 용량 및 통신 비용은 정확히 계측하지 못한다. 집계에서 `0`은 계측된 작업이 없다는 뜻이지 전체 프로젝트 과금이 0이라는 뜻은 아니다.

Firestore 에디션 및 요금·무료 한도는 프로젝트 구성과 공식 Firebase/GCP 청구 설정에서 확인해야 한다. 최종 청구 금액과 비교할 때는 Firebase 사용량 화면 또는 Google Cloud Billing 기록을 기준으로 삼는다. 모니터링 UI가 Firestore에 활동 로그를 저장하지 않으므로 계측을 위한 별도 Firestore 문서 쓰기는 없다. 기존 READ·WRITE 실행의 실제 결과나 재시도 정책을 변경하지 않는다.

#### 저널 복구·범위별 COST·실제 페이지 조회 — `261104 0202.zip` 기준

이번 리팩터링의 목표는 기존 업무 처리나 Firestore 쓰기 정책을 바꾸지 않고 Activity Center의 기록 보존과 해석 정확도를 높이는 것이다. 계측은 `main()` 실행 직후부터 계속하며 개발자 모드 ON/OFF는 기록 여부가 아니라 상세 열람·복사 권한만 결정한다. Plate TTS 포그라운드 Isolate는 기존 안정성 우선 제외 정책을 유지한다.

| 항목 | `0202.zip` 수정 전 | 수정 후 |
| --- | --- | --- |
| 종료 기록 | `_closeApplication()`·네이티브 재시작 요청 전 `SESSION_END` 기록 | `SESSION_EXIT_PREPARED`·`SESSION_RESTART_PREPARED`로 기록, 실제 프로세스 종료 확인을 주장하지 않음 |
| 이전 세션 판정 | 마지막 이벤트가 `SESSION_END`인지에 가까운 단순 판정 | 가장 최근 이전 세션에서 종료 준비/재시작 준비 후 결과는 `PREVIOUS_SESSION_OUTCOME_UNKNOWN`, 준비 없음·실패는 `PREVIOUS_SESSION_UNCLEAN` |
| 저널 초기화 오류 | 실패 후 자동 재시도 부족 | 실패 상태에서 재초기화 가능, 1·2·4·8·16·30초를 상한으로 하는 지수 백오프 재시도 |
| JSONL 쓰기 실패 | 쓰기 전에 최대 64개 대기 이벤트를 제거하여 유실 가능 | 쓰기 성공·flush 이후 제거, 실패하면 대기열 보존, 부분 쓰기 롤백 시도 |
| 불완전한 파일 끝 | 손상 JSONL 레코드 재사용 위험 | 재초기화 때 마지막 완결된 줄 이후를 정리하고 이벤트 ID로 기록 중복 완화 |
| 대기열 상한 | 4096개 초과 시 오래된 이벤트 제거 | 이미 쓰기 중인 이벤트를 보호, 새 이벤트의 누락을 별도 계수하고 Firebase 업무는 계속 |
| COST 선택 범위 | 현재 세션 메모리 누적값이 과거·시간 범위에도 표시 | 저널에 구조화된 시각·문서 수·커밋 쓰기·캐시·바이트 필드를 바탕으로 선택 세션·기간별 계산 |
| 과거 구버전 기록 | 문자열 로그만 존재 | `schemaVersion=2` 이전 기록은 `legacyEvents`로 표시하고 수치 불완전성 안내 |
| COST 화면과 복사 | 선택 조건과 결과가 불일치할 수 있음 | 화면에 사용한 동일한 COST 집계 스냅샷을 클립보드용 `debugPrint(...)` 문자열로 변환 |
| 보관 로그 페이지 | 전체 JSONL을 `List<String>`으로 읽은 다음 100건만 표시 | 파일을 뒤에서부터 읽고 100건만 반환하는 커서 조회, 시작 파일 크기를 다음 페이지까지 유지 |
| 전체 로그 복사 | 전체 보관 범위의 JSONL을 순차 읽어 복사 | 유지, 페이지 조회와 독립적인 경로 사용 |

새 기록의 `schemaVersion=2`에는 `eventId`, `timeMs`, `sessionId`, `service`, `operation`, `result`, `documents`, `bytes`, `fromCache`, `committedWrites`, `committedDeletes`, 마스킹된 진단 `line`을 저장한다. 과거 파일은 삭제하거나 소급 변조하지 않는다. 과거 기록의 작업명과 성공 여부는 일부 합산할 수 있지만 구조화되지 않은 필드는 복원할 수 없고, 저장 실패나 보관 한도 삭제된 이벤트도 복구할 수 없다. 따라서 COST는 **선택한 범위에서 실제 보관한 앱 관측값**이며 전체 Firebase 청구량이 아니다. 현재 활성 LISTEN 수는 과거 시점에 재현 가능한 값으로 단정하지 않고, 선택 범위에서 관측한 LISTEN 시작·해제 이벤트 수를 별도로 표시한다.

저널 복구는 최선의 노력 방식이다. 디스크 공간 부족, 장기 접근 오류, 강제 종료, 손상된 세그먼트 및 4096개 대기열 초과 상황에서는 기록 손실이 여전히 발생할 수 있다. `droppedEvents`, `droppedFiles`, `writeErrors`, `legacyEvents`, 저장 가능 상태를 통해 이러한 한계를 표시한다. 계측 기록 때문에 신규 Firestore 읽기·쓰기 또는 GCS 객체 작업을 만들지 않는다.

최근 500개 메모리 화면, 우측 상단 56dp AppBar·116×48dp 관측 패널, 상태 점·카운터·Dialog 애니메이션과 보관 페이지 `AnimatedSwitcher` 180ms 전환(모션 감소 시 0ms), 개발자 `STATUS`의 비동기 `debugPrint 코드 복사` 및 복사 직전 권한 검사는 그대로 유지한다. 기존 `AppExitService`의 종료 준비·네이티브 종료·실패 시 알림 복구 순서는 변경하지 않으며 기록하는 이벤트 이름만 바꾼다.

## 7. Firestore Rules 및 보안 평가

다음은 **사용자가 제공한 Rules 텍스트**를 근거로 하며 배포 여부는 미확인이다.

| 경로 | 공개/인증 정책 | 검토 결과 |
| --- | --- | --- |
| `divisions`, `areas`, `user_accounts`, `user_account_codes`, `user_accounts_show` | 로그인한 Firebase 사용자에게 읽기·쓰기 허용 | 개발자 도움말의 UI 조건이나 클라이언트 승인만으로는 타 사용자의 직접 SDK 쓰기를 막지 못함 |
| 대부분의 업무 컬렉션 | `request.auth != null` | 회사·현장·역할 간 서버 권한 분리가 없음 |
| `/{path=**}/plates/{plateDocId}` | 누구나 읽기 허용 | GCS 이미지 `publicRead`와는 **별도의 문서 공개** 정책임 |
| `usage_daily/...` | 조건부 쓰기, 읽기·삭제 차단 | UID-문서 user 일치 검사가 없고 이벤트 생성량 자체는 제한하지 않음 |
| 기타 명시되지 않은 경로 | 거부 | 기본 차단 유지 |

이번 변경은 기존 Rules를 수정하거나 Cloud Functions를 추가하지 않는다. **보안 판정:** 완전히 통제된 개발·테스트 환경에서 초기화 기능의 확인용으로는 사용할 수 있다. 그러나 제공된 Rules가 운영 서버에 적용된 채 실제 사용자·차량·회사 데이터를 저장하는 경우, Firebase에 로그인한 다른 사용자의 데이터 접근·수정 위험이 있으므로 공개 운영 전 서버 권한 규칙 검토가 필수다. 도움말은 개발자 승인과 인증 이메일 일치 여부를 확인하지만 서버의 독립적인 관리자 권한 검증을 대신할 수 없다.

Firebase UID를 업무 accountId로 바꾸거나 GCS `publicRead`를 제거하는 것은 해결책의 전제가 아니다. 실제 위협과 무관한 보안 강화는 보류한다. 공개 이미지에 민감한 자료를 저장하지 않도록 운영 데이터는 별도 검증한다.

## 8. 비용·사용량 평가

| 동작 | Firestore/서비스 작업 | 비용 정책 |
| --- | --- | --- |
| 도움말 아이콘 표시, 애니메이션, 제목 탭·로그 복사 | 로컬 UI·클립보드, Firestore 읽기/쓰기 없음 | 최적화 불필요 |
| APP RESTART 제목 5회 탭·건너뛰기 | 로컬 상태·진단 로그·내비게이션, 직접적인 Firestore 쓰기 없음 | 기존 업무 화면 진입 후 정상 조회는 별도 비용 발생 가능 |
| 개발자 로그인 성공 후 디버그 ON | 승인 검사와 로컬 SharedPreferences 갱신, 추가 Firestore 쓰기 없음 | 실패 시 추가 인증·업무 조회를 수행하지 않고 로그인 완료 차단 |
| 첫 실행에서 이미 있는 `divisions/dev` 검사 | 트랜잭션 문서 읽기, 회사 쓰기 0 | 기존 버전 보존 및 불필요한 쓰기 방지 |
| 없는 지역·메타 생성 | 각 문서 1회 쓰기 | 최초 실행만 |
| 신규 dev 계정 | 원본·코드 예약·경량 View, 총 3개 문서 쓰기 | 코드 예약 GET 1 + Root 존재 GET 1, Batch 쓰기 3건, 완료 진단에서도 `accountCreated=3`건으로 계산. 카운트 메타 갱신 없음 |
| 기존 dev 계정의 누락된 View 복구 | 경량 View 문서 SET 1건 | `projectionRepaired=1`건으로 계산, 예약 문서까지 복구한 경우 합계 2건. Count 갱신 없음 |
| 최초 정상 생성의 핵심 쓰기 | 신규 개발 회사·본사·메타 3건과 계정 3건, 합계 최대 6건 | 기존 회사·지역 존재 여부에 따라 달라짐. 실제 청구 실측치가 아님 |
| 완전한 상태에서 재실행 | 정상 흐름에서 쓰기 0, 확인 읽기 발생 | 정기 실행/자동 리스너 없음 |
| 계정 연결 | Google/Firebase 인증 API, 별도 Firestore 사용자 문서 생성 없음 | 요금제에 따라 인증 비용 정책 별도 |
| 계정 중복 검사 | 일반 신규 계정은 코드 예약 GET 1회, 개발자 신규 계정은 코드 예약 GET 1회 + Root GET 1회 | 인덱스 완전성 검증은 운영 선행 조건 |
| 중첩 Map `FieldPath` Batch 타입 호환 | 래퍼의 `update()`를 SDK 타입으로 되돌리고 `set(..., mergeFields: [FieldPath(...)])` 사용 | 추가 Firestore 조회·문서 쓰기 없음; 기존 부분 갱신과 원자성 유지 |
| 실시간 차량·음성 수신 | Firestore `snapshots()` 읽기 및 재연결 | 이용량에 따라 과금, 정상 기능이므로 유지 |
| 음성 전송 후 정리 | 전송마다 정리 대상 최대 32개 조회 | 전송량 증가 시 실제 비용을 계측하고 최적화 판단 |
| GCS 공개 이미지 | 저장·요청·다운로드 네트워크 사용량 | `publicRead` 유지, 전송 트래픽 관찰 |

### 실제 사용자 상태·출퇴근 호출 최적화 비용 비교 — 2차

| 동작 | `1413.zip` 기존 SDK 작업 | 2차 변경 후 | 적용 조건 |
| --- | --- | --- | --- |
| 오늘 출근 기록이 없는 사용자 | 월별 GET 1 + 레거시 GET 1 | **월별 GET 1** | 레거시 출퇴근 데이터가 없다는 전제 |
| 이미 오늘 출근한 사용자 | 월별 GET 1 | 월별 GET 1 | 기존 로컬 출근 기록 캐시 사용 시 GET 0 유지 |
| 관리자 출퇴근 달력의 월별 출근·퇴근 조회 | 출근/퇴근 월별 GET 2 + 레거시 GET 최대 2 | **월별 GET 2** | 달력 UI·시각 결과 유지 |
| 관리자 휴게 달력 | 월별 GET 1 + 레거시 GET 1 가능 | **월별 GET 1** | 같은 월·휴게 상태 기준 |
| 출퇴근 날짜 삭제 | 월별 SET + 레거시 SET + 빈 월 확인 GET 등 | **레거시 SET 1건 제거** | 빈 월 GET·조건부 DELETE는 그대로 |
| 동일 계정 상태를 연속으로 두 번 저장 | UPDATE 2 가능 | 첫 성공 후 동일 필드면 UPDATE 1 | 중간에 다른 상태 변경 없고 성공한 원격 쓰기 증거가 있음 |
| 동일 문서에 A→B→A 순서의 서로 다른 변경 | UPDATE 3 | UPDATE 3 | 최종 상태 보존을 위해 모두 수행 |
| 로그인 상태가 이미 이번 실행에서 확인됨 | UPDATE 1 | UPDATE 0 가능 | `UserStatusService`의 필드별 원격 성공 상태가 존재 |
| 첫 로그인 상태 쓰기·근무 ON/OFF 실제 변경 | UPDATE 1 | UPDATE 1 | 초기 원격 확인이 없거나 값이 실제로 다름 |
| 월별 문서 동시 조회(서로 다른 Repository 객체) | GET 2 가능 | 진행 중이면 GET 1 | 같은 FirebaseFirestore 객체·문서·연월 |
| 사용자 상태 UPDATE 4건이 전부 다른 변경 | UPDATE 4 | UPDATE 4 | 무조건 4→1로 줄이지 않음 |

기존 로그의 UPDATE 4건이 실제 중복이라고 확정된 것은 아니다. 2차 수정은 원인을 구분하고 가능한 연속 중복을 제거하도록 코드 경로를 바꾼 것이다. Firestore Standard의 기본 문서 단위와 실제 청구 금액, Security Rules 의존 읽기·네트워크 비용은 분리해 평가한다. 출퇴근 월별 문서 하나의 GET은 오늘 날짜만 읽었다고 과금 단위가 더 줄어드는 것이 아니라, **존재하지 않는 레거시 위치에 대한 두 번째 GET을 제거**했기 때문에 절감된다.

계정 생성 10 Reads 목표 등의 수치는 실제 SDK/서버 계측 전에는 보증하지 않는다. SDK 호출 횟수와 청구 읽기 수는 다를 수 있다. Firestore 쿼리의 빈 결과, 트랜잭션 재시도, 리스너 재연결, Rules 의존 문서 읽기 등에 따라 비용이 추가된다. 로그인 Dialog의 연결 상태 표시 자체는 실시간 Firestore 구독이 아니다.

권장 실측: Firebase Console/Google Cloud Billing에서 기능별 문서 읽기·쓰기·삭제, 인증 사용자 수, GCS 저장·전송을 확인한다. 사용량이 적은 개발 단계에서 비용이 실제로 증가했다는 근거 없이 정상 기능을 축소하지 않는다. 예산 알림은 이상 징후 감지용이며 자동 과금 중단을 보장하지 않는다.

공식 문서: https://firebase.google.com/docs/firestore/pricing · https://firebase.google.com/pricing · https://cloud.google.com/storage/pricing · https://firebase.google.com/docs/firestore/security/rules-structure

## 9. 실행 검증 시나리오

| 입력·서버 상태 | 기대 동작 |
| --- | --- |
| 로그인 계정 비연결 | Dialog 표시; 도움말을 누르면 연결 절차를 거쳐 유효한 세션 확보 후 생성. 취소 시 쓰기 없음 |
| 모든 계정에서 개발자 비밀번호 모드 OFF | 헤더 오른쪽 도움말 없음 |
| 일반 계정에서 빈 로그인 버튼 5회 후 개발자 승인 | 개발자 인증 배너 + 도움말 표시; 일반형 dev 초기화 실행 가능 |
| 개인형에서 빈 로그인 버튼 5회 후 개발자 승인 | 개발자 인증 배너 표시, 도움말 숨김; 기존 개인형 개발자 로그인 유지 |
| 태블릿형에서 빈 로그인 버튼 3회 후 개발자 승인 | 개발자 인증 배너 표시, 도움말 숨김; 기존 태블릿형 개발자 로그인 유지 |
| 개인형·태블릿형에서 개발 초기화 함수 실행 조건 검사 | 즉시 종료, 이 기능으로 인한 Firestore 조회·쓰기는 없음 |
| 기존 `divisions/dev` 존재 | `accountWriteVersion=11`, `areaConfigVersion=3`, `initialAdminAccountId=aef260e9aa1-dev`, 생성 시각 등 보존 |
| `accountWriteLocked=true` | 초기화 중단, 회사 원본 유지 |
| 지역·메타·계정 모두 없음 | 누락 문서만 트랜잭션 생성, 계정 원본/예약/상위 메타 문서 내부 사용자 Map 생성 |
| 도움말 두 번 실행 | 최초 1회만 생성, 두 번째는 존재 확인 후 쓰기 없음 |
| 코드 예약 충돌·계정 이메일 불일치 | 자동 덮어쓰기 금지, 오류 표시 |
| 계정 원본만 있고 View 누락 | Root·예약 검증 후 경량 View만 복구, Count 미변경, `writeOperations`에 1건 반영 |
| 회사·본사·메타·개발자 계정 모두 신규 생성 | `writeOperations=6`, STATUS 진단 및 Firebase 문서 쓰기 수와 일치 |
| 코드 예약과 View 모두 누락된 기존 개발자 계정 | 검증 후 문서 2건 복구, `writeOperations=2` |
| 원본과 View의 코드·Role·지역 충돌 | 자동 덮어쓰기 금지, 기존 자료 보존 |
| 회사·지역 일부만 생성 후 네트워크 오류 | 재실행 시 남은 데이터 보존, 누락 단계만 수행 |
| 제목 연속 5회 탭 | `debugPrint(...)` 복사, 도움말 실행과 무관 |
| 전역 개발자 모드 ON에서 `STATUS` | 기존 진단 Dialog와 `debugPrint 코드 복사` 사용 가능 |
| 계정 A 활성·비활성 상태 변경 | Root·지역 Map의 계정 A 상태만 변경하고 같은 지역 계정 B 및 표시용 Count 보존, `COMMITTED_BATCH` 확인 |
| 계정 A 삭제 | Root·코드 예약 문서 삭제와 `users.{계정A}` Map 필드 삭제가 정상 실행되고 계정 B Map 보존 |
| 기존 Map의 `password` Backfill | 대상 `users.{계정ID}.password` 필드만 제거하고 기존 계정·상위 메타 보존 |
| 중첩 Map 계측 래퍼 정적 검사 | `Map<String, dynamic>`의 계층형 본문과 `mergeFields` 사용으로 보고된 5개 타입 오류가 `flutter analyze`에서 사라짐 |
| 개발자 STATUS 로그 증가·클립보드 | 진단 건수 Fade·Slide, 모션 감소 시 0ms, 개발자 모드 ON에서 `debugPrint(...)` 코드 복사 가능 |
| 애니메이션 감소 설정 | 효과가 즉시 전환되어도 기능 유지 |
| 작업 완료 후 기존 로그인 | 이름·코드 입력 및 이메일 일치 검증 유지, 개발자 비밀번호는 별도 요건 |
| APP RESTART 제목 4회 탭 | Dialog 유지, 네이티브 재시작 없음, 업무 화면 이동 없음 |
| APP RESTART 제목 5회 탭 | 닫힘 모션·진단 이벤트, 재시작 스킵, 기존 업무 목적지로 이동 |
| APP RESTART 제목 탭 간격 2초 초과 | 연속 입력 카운터 초기화 |
| APP RESTART `재시작` 버튼 | 기존 플랫폼 재시작 흐름 유지, 제목 5회 탭과 중복 실행 없음 |
| 개발자 로그인 세션 동기화 성공·실패 | 인증 과정 중 STATUS 자동 팝업 없음, 성공·실패 이벤트 기록, 기존 원격 저장·실패 예외 처리 유지 |
| 개발자 인증창 닫기 | 410ms Mini Terminal 닫힘 → 소유 Route 종료 → 170ms Fade·Slide → `RawDialogRoute.completed`로 반투명 배경 제거 완료 확인 |
| 인증창 위 별도 STATUS 창 존재 | 인증창 자신의 Route만 제거, STATUS는 강제 닫지 않고 사용자 종료 및 오버레이 제거 완료 이후 런처 이동 재개 |
| 인증창 종료 후 본사 이동 | `launcher_auth_dialog_route_popped` → `launcher_auth_dialog_overlay_removed` → `launcher_dialog_phase_changed ... closed` → `launcher_presentation_finalize_start` → `terminal_close_complete` → `launcher_dashboard_navigation_requested` 확인 |
| STATUS 퇴장 중 대시보드 이동 요청 | 다른 Route가 위에 있거나 `completed`가 남아 있으면 `launcher_navigation_deferred`, 종료 후 `launcher_navigation_resumed` 기록 |
| STATUS가 런처 위에 있는 상태에서 뒤로가기 | 먼저 STATUS를 정상 종료, 본사 이동 후 과거 런처 재등장 없음 |
| 대시보드 이동 실패·Dispose | `launcher_navigation_stack_invalid` 기록, 이전 `_closing` 잠금 복구 또는 취소, 중복 전환 없음 |
| 인증 중 오류 메시지 | 160ms Fade·Slide, 모션 감소 시 즉시 전환 |
| 개발자 모드 ON에서 로그인 후 STATUS 복사 | 자동 팝업 없이 기존 STATUS 화면에서 `login_session_sync_*` 및 Route 종료 이벤트 `debugPrint(...)` 복사 |
| 개발자 비밀번호 검증 성공 + 승인 유효 | 디버그 ON, 공유 ValueNotifier 반영, `STATUS` 및 `debugPrint 코드 복사` 사용 가능 |
| 개발자 비밀번호 검증 실패 또는 승인 세션 만료 | 로그인 완료·디버그 자동 활성화 없음 |
| 개발자 디버그 활성화 자체 실패 | 기존 인증을 완료한 것으로 처리하지 않으며 오류 표시 후 재시도 가능 |
| 일반 계정의 Google 방식 로그인 | 디버그 자동 ON 없음, 기존 APP RESTART 조건 유지 |
| 접근성 모션 감소 설정 + APP RESTART 스킵 | 닫힘 시간 0이어도 업무 화면 진입 가능 |


### AppBar 56dp 복원 및 우측 Activity Center UI 검증

| 테스트 화면·상황 | 통과 기준 |
| --- | --- |
| 본사·Single·Double·Triple·Minor 대시보드 | 원래 기본 AppBar 56dp 유지, 기존 좌측 로고·중앙 터미널 버튼 위치와 본문 시작점 변화 없음 |
| Single 내부 | `toolbarHeight: kToolbarHeight`, 우측 최대 너비 116dp, 상태 영역 48dp, 본문 위치 동일 |
| 주차 완료 화면 | `toolbarHeight: kToolbarHeight`, 우측 최대 너비 132dp, 상태 영역 48dp, 조건부 DB 상태 표시 정상 |
| 일반 화면 우측 표시 | 최대 너비 132dp, 공통 패널 116×48dp, 상태·카운터 총 4행이 헤더를 확장하지 않음 |
| DB 인증 ON/OFF 전환 | 상태 값·점 색상 전환이 헤더 크기를 바꾸지 않음 |
| READ/WRITE/DELETE/SNAP/LISTEN/STORAGE 갱신 | R/W/D, SN/L/ST 2행의 수치가 갱신되며 높이·본문 시작 위치 고정 |
| 카운터 999 → 1.0K 및 큰 값 | 축약값이 패널 안에 표시되고 상세 Dialog에는 정확한 원본 정수가 표시됨 |
| 디버그 OFF | 우측 카운터는 상시 표시, 탭해도 상세 Dialog는 접근 거부 |
| 디버그 ON | 패널 전체 탭으로 상세 Dialog 열람·클립보드 복사 가능 |
| 디버그 ON에서 기존 `STATUS` | Firebase 활동을 포함한 `debugPrint(...)` 코드 복사 유지 |
| 좁은 화면·글꼴 확대·화면 판독기 | 우측 패널의 렌더 높이 고정, 중앙 터미널 버튼 터치 가능, 의미 있는 전체 계측 명칭 전달 |
| 애니메이션 감소 설정 | 상태·숫자 애니메이션 0ms 처리, 앱바 높이 유지 |

### Plate TTS 안정성 우선 원복 범위

| 구성요소 | `2347.zip` 수정 전 | 원복 후 |
| --- | --- | --- |
| `main.dart` | Activity Bridge 수신 콜백 등록 | 등록 제거. 기본 근무 상태·알림 수신은 유지 |
| `foreground_task_handler.dart` | 계측 브리지 시작과 종료 호출 3곳 | 해당 호출만 제거. TTS 시작·중지·소유권·근무 상태 처리 보존 |
| `firestore_plate_tts_listener_repository.dart` | Firestore `get()`·`snapshots()` 계측 확장 적용 | 원래 `get()`·`snapshots()` 호출로 복원 |
| Activity Center | 메인 + 전달된 포그라운드 활동 일부 병합 | 메인 앱에서 관측한 활동만 표시. 원격 TTS 활동은 미계측 |
| COST · `STATUS` | 분석·진단 로그 복사 | 유지. COST에 포그라운드 TTS 미계측 경계 명시 |
| 애니메이션 | 기존 요약 카운터·Dialog 페이드 | 유지하고 필터 변경 텍스트 전환 추가. 접근성 설정 시 전환 시간 0 |

### Firebase Activity Center 검증 시나리오

| 수행 | 기대되는 결과 |
| --- | --- |
| 디버그 OFF로 본사·Single/Double/Triple/Minor·내부·주차 완료 화면 표시 | 우측 `LIVE DB`·`STORAGE DB`와 READ/WRITE/DELETE/SNAP/LISTEN/STORAGE 상시 보임 |
| 디버그 OFF에서 실제 조회·저장·실시간 수신 | 상단 집계 증가; 센터 상세는 열리지 않음 |
| 개발자 비밀번호 로그인 성공 및 디버그 ON | Activity Center 열림, 필터·로그 복사 및 STATUS 진단 복사 가능 |
| 단일 문서 GET, Query GET, count GET | 조회 결과·집계 구분 및 성공/실패 기록 |
| 트랜잭션 실패 또는 재시도 | 예약 작업은 STAGE로 남고 커밋되지 않은 작업은 WRITE 청구로 합산하지 않음 |
| Firebase Storage 업로드와 GCS 목록·다운로드 | 작업별 STORAGE 카운터와 확인 가능한 바이트 기록 |
| 디버그 ON → OFF | 상단 요약 유지, 상세 Dialog 접근·복사 차단 |
| 화면 이탈·리스너 취소 | 계측된 활성 LISTEN 수 감소 |
| 트랜잭션 STAGE 4개 후 최종 성공 | WRITE +4, 재시도 횟수와 관계없이 한 번만 확정 |
| 트랜잭션 STAGE 4개 후 최종 실패 | WRITE +0, 기존 실패 예외 유지 |
| 배치 SET 3건·DELETE 2건 성공 | WRITE +3, DELETE +2; 실패 시 확정 작업 +0 |
| COST 선택·복사 | OBSERVED / ESTIMATED / UNAVAILABLE 별도 표시와 요약 debugPrint 복사 |
| GCS 객체 메타데이터 확인 | METADATA 증가, DOWNLOAD 증가 없음 |
| GCS 공개 CSV HTTP GET 4개 호출부 | URL_ACCESS와 실제 받은 bodyBytes 길이 기록, 오류 상태 보존 |
| GCS Media CSV 스트림 완료 | 데이터 수신 완료 시 다운로드 크기 기록, 중복 성공 기록 없음 |
| Plate TTS 포그라운드 시작·차량 변경 | 기존 Firestore 구독과 음성 안내가 이전과 동일하게 작동 |
| 포그라운드 Plate TTS에서 SNAP 수신 | 메인 Meter에 원격 이벤트를 전달하지 않고 READ·SNAP·LISTEN에 합산하지 않음 |
| 포그라운드 Task 종료·재시작 | 기존 TTS 세션·소유권 및 근무 상태 알림 절차 유지 |
| 메인 앱에서 Firestore 스냅샷 수신 | 메인 SNAP 증가, 포그라운드 구독에 영향 없음 |
| 다른 Isolate, 공개 GCS 이미지 URL 사용 | 연결되지 않은 경로는 미계측일 수 있음을 문서와 대조 |
| 접근성 애니메이션 감소 | 패널 카운터·활동 Dialog 애니메이션 시간 단축 |

### 앱 전체 실행 세션·로컬 로그·복사 테스트

| 테스트 | 통과 조건 |
| --- | --- |
| 앱 Cold Start | `SESSION_START`가 `INITIALIZE_APP`보다 먼저 저장되며 개발자 OFF에서도 기록 |
| App Check·Google 초기화·Firebase 인증 | 원문 토큰/UID 없이 결과와 소요 시간 기록, 기존 로그인 흐름 동일 |
| 초기 로그인 이전 Firestore 조회 | 실제 계측 호출부를 통해 발생한 경우 로그와 상단 수치에 반영 |
| 이벤트 501개 이상 | 실시간 목록 최대 500개, 보관 기록에는 보관 한도 내 이전 이벤트 존재 |
| 100건 단위 보관 목록 | JSONL 전체 메모리 적재 없이 역방향 스트림으로 최대 100개 읽기, 처음 조회한 파일 길이·커서로 안정적인 이전·다음 페이지 이동 |
| 앱 백그라운드·복귀 | 동일 실행 세션 유지, 새 `SESSION_START`가 중복 기록되지 않음 |
| 로그아웃·재로그인 | 앱 실행 세션 유지, Auth 이벤트 별도 기록 |
| 정상 종료 요청 | `SESSION_EXIT_REQUESTED` 후 `SESSION_EXIT_PREPARED`와 저널 flush를 시도하고, 실제 종료 성공을 확정 이벤트로 오기록하지 않음 |
| 재시작 성공·실패 | 기존 네이티브 재시작 동작 유지, 실패 시 로그 작성·서비스 복구 유지 |
| 강제 종료·이전 세션 미종료 | 마지막 저장된 이벤트 보존 및 다음 실행에서 미종료 가능성 기록 |
| 7일·20MiB 초과 | 오래된 조각 정리, 누락된 파일 수와 저장 오류 표시 |
| 저장소 권한/쓰기 오류 | 기존 Firebase 요청 정상 진행, 대기열 보호·부분 쓰기 정리·재초기화·제한적 재시도로 복구, 잔여 유실 건수 표시 |
| 디버그 OFF → ON | 앱 실행부터 기록된 로컬 로그를 Activity Center에서 조회 가능 |
| Activity Center 복사 | 선택 세션·기간·필터의 `debugPrint(...)` 코드 복사, 권한 재검사 |
| 기존 개발자 `STATUS` | 복사 버튼 터치 시 최신 보관 Firebase 기록과 기존 진단 병합, 모드 OFF면 복사 차단 |
| 보관 기록 화면 전환 | `AnimatedSwitcher` 페이드, `disableAnimations` 시 0ms, 56dp AppBar 불변 |
| Plate TTS·근무 상태 알림 | 포그라운드 브리지 미연결 유지, 기존 동작 정상 |

### 2026-11-04 사용자 상태·출퇴근 비용 최적화 2차 검증

| 테스트 | 통과 기준 |
| --- | --- |
| 첫 로그인·세션 복원 | 인증·지역·근무 상태가 기존과 동일, 실제 원격 UPDATE가 필요하면 1건 전송 |
| 로그인 세션 동일값 순차 재요청 | 첫 UPDATE 성공 후 두 번째는 `WRITE_SKIPPED`, 로그인 Dialog 진단의 `firebaseWrite=0` |
| 로그인 대상 문서 없음 | 새 부분 계정을 만들지 않고 기존과 동일하게 실패 전달 |
| 동일 문서 A→B→A | 3개의 순서를 보존하여 최종 A가 서버에 남음 |
| 동시에 동일 UPDATE | 최종 서버 UPDATE 1건, 대기 호출자도 같은 성공·실패 전달 |
| 일부 필드만 이미 같은 UPDATE | 변경된 필드만 서버 전송하고 `WRITE_FIELDS_REDUCED` 기록 |
| 상태 UPDATE 실패·재호출 | 확인 상태 무효화, 실패를 생략으로 처리하지 않음 |
| 계정 전체 모델 직접 수정·삭제 | 확인된 필드 상태 초기화, 이후 필수 UPDATE 생략 금지 |
| 지역 재선택 | 10초에 의존하지 않고 저장소의 성공한 필드 상태로 판단, 로컬 화면·애니메이션 유지 |
| 오늘 처음 출근 여부 | 월별 문서 GET 한 번, 빈 결과면 출근 전 상태 유지 |
| 이미 출근한 사용자 | 월별 문서의 오늘 날짜 기록을 정상 감지하고 중복 출근 방지 |
| 출퇴근 GET 서버 실패 | 기록 없음(`false`)으로 오인하지 않고 실패 전파, 성공한 빈 결과만 `false` |
| 서로 다른 Repository의 동일 월 동시 GET | 요청 중에만 공유해 실제 GET 1회, 완료 후 재요청은 신규 GET |
| 관리자 출퇴근·휴게 달력 | 출근/퇴근/휴게의 월별 정보·기존 페이드·전환 동일, 레거시 GET 없음 |
| 출퇴근 날짜 수정·삭제 | 월별 필드 갱신/삭제와 빈 월 삭제 기능 유지, 레거시 SET 없음 |
| 진단과 비용 | 최적화 `result=skipped`는 READ·WRITE에 추가되지 않고 `STATUS`에서 개발자 ON일 때만 복사 가능 |
| 애니메이션 접근성 | `AnimatedSwitcher` 페이드/슬라이드, `MediaQuery.disableAnimations` 시 전환 0ms |
| 다른 기능 회귀 | 56dp AppBar, 116×48dp 패널, Plate TTS, 근무 알림, UID, 기존 Rules·GCS 공개 읽기 변경 없음 |

실제 SDK/Android 환경에서 위 시나리오를 실행하기 전에는 빌드 성공·동시성·비용 절감량이 검증됐다고 주장하지 않는다.

### 2026-11-04 Journal 운영 안정성 및 COST 범위 검증

| 테스트 | 통과 조건 |
| --- | --- |
| `main()` 초기 계측 | Firebase 초기화보다 먼저 `SESSION_START` 기록, 디버그 OFF에서도 관측 지속 |
| 종료·재시작 준비 | `SESSION_EXIT_PREPARED` 또는 `SESSION_RESTART_PREPARED`로 저장, 실제 종료 확정으로 오인하지 않음 |
| 종료·재시작 실패 | `SESSION_EXIT_FAILED`/`SESSION_RESTART_FAILED`, 기존 근무 상태·서비스 복구 유지 |
| 이전 세션 상태 | 정상 종료 준비 기록이 없는 경우 `PREVIOUS_SESSION_UNCLEAN`, 준비 후 결과 미확인 경우 `PREVIOUS_SESSION_OUTCOME_UNKNOWN` |
| 최초 저널 초기화 오류 | 지수 백오프로 자동 재시도, 앱 실행·Firebase 업무에는 영향 없음 |
| JSONL 부분 쓰기 | 마지막 불완전 레코드 정리, 쓰기 전 대기열 제거 금지, 기록 이벤트 ID 대조 |
| 저장 중 대기열 4096개 초과 | 쓰기 중인 항목을 보호하고 유실 수를 기록, 실패 후 가능한 이벤트부터 순서대로 저장 |
| 현재 세션 COST | 선택 세션의 JSONL 기록에서 계산, 현재 메모리 이벤트와 혼동하지 않음 |
| 과거 세션·전체 세션 COST | 해당 보관 세션만 또는 모든 보관 세션 합산, 화면과 클립보드의 집계 기준 동일 |
| 최근 15분·1시간 COST | 선택 시각의 구조화 이벤트만 포함, 다른 기간 누적값 제외 |
| 구조화 이전 JSONL | `legacyEvents`로 구분, 문서 수·커밋 확정 수·바이트를 임의로 0의 근거로 단정하지 않음 |
| 보관 파일 삭제·쓰기 오류 | 분석 불완전 상태 표시, 공식 청구량으로 오인하지 않음 |
| 100건 페이지 | 파일 최신순 역방향 조회, 전체 파일 목록 메모리 적재 없음 |
| 페이지 전환 중 로그 추가 | 조회 시작 시점의 파일 길이를 커서에 보존하여 기존 페이지에 중복·누락이 없도록 함 |
| `COST` 개발자 복사 | 선택한 범위에 계산된 분석 스냅샷을 `debugPrint(...)`로 복사, 복사 직전 개발자 권한 재확인 |
| Plate TTS·헤더·애니메이션 | 기존 Foreground Task 미계측 정책, 56dp AppBar, 116×48dp 패널, `AnimatedSwitcher`·모션 감소 처리 유지 |

## 10. 검증 상태 및 배포 경계

**현재 헤더 복원 패치의 기준은 `261104 0027.zip`이다.** 변경 범위는 공통 AppBar 상태 패널 1개, AppBar를 포함한 화면 7개와 본 README다. Firebase Activity Meter, COST Dialog, Plate TTS, 포그라운드 서비스, Firestore Rules, 개발자 `STATUS`는 이번 헤더 수정에서 변경하지 않는다. 완전한 Flutter 프로젝트와 기기에서 56dp 헤더·48dp 패널·터치 겹침 및 다크 모드·글꼴 확대를 검증해야 한다. 해당 실행 검증 전에는 실제 화면에서 픽셀 단위로 동일함을 확정하지 않는다.

앞선 Plate TTS 계측 분리는 `261103 2347.zip`을 기준으로 제공된 Dart 소스의 **정적 수정**이다. 수정된 파일만 원본 상대 경로를 유지한 ZIP으로 제공한다. Dart 파일에는 주석을 포함하지 않고 새 `hintText`를 넣지 않는다. 초기 로그인, APP RESTART, 개발자 디버그 ON, 우측 상단 상태·Activity Center 상시 표시, 애니메이션, `STATUS`의 `debugPrint 코드 복사`를 보존한다. Firestore Rules, Firebase UID 체계, GCS `publicRead`, Cloud Functions 배제, 기존 `divisions/dev` 원본 데이터는 변경하지 않는다.

기준 ZIP은 Flutter SDK·완전한 Android 프로젝트·`pubspec.yaml`을 포함하지 않으므로 변경 파일을 기존 **완전한 Flutter 프로젝트 루트에 덮어써야 한다**. 정적 경로 대조와 구조 검증은 컴파일·실기기 검증을 대신하지 않는다. 현재 환경에 Dart/Flutter SDK가 없으므로 `dart format`, `flutter analyze`, Android 빌드와 실제 Firebase 트랜잭션 재시도·배치 실패·GCS 스트림 및 Plate TTS·근무 상태 알림의 실기기 회귀 동작을 검증하지 못했다. 배포 전에 테스트 Firebase 환경과 Android 실기기에서 9장의 시나리오를 확인해야 한다.

### 2026-11-04 Activity Center 헤더 레이아웃 복원

| 실제 변경 파일 | 변경 전 | 변경 후 |
| --- | --- | --- |
| `lib/app/init/db_connection_status_section.dart` | 세로로 긴 163dp 폭 상태·활동 패널 | 116×48dp 4행 고정 패널, R/W/D·SN/L/ST 숫자 축약, 전체 접근성 라벨, 탭·페이드 애니메이션 유지 |
| `lib/features/dashboard/pages/common/headquarter_page.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | 기본 AppBar 56dp, 우측 48dp·132dp |
| `lib/features/dashboard/pages/single/widgets/single_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/double/widgets/double_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/triple/widgets/triple_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/minor/widgets/minor_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/mode_single/page/single_inside_screen.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | `kToolbarHeight`, 우측 48dp·116dp |
| `lib/shared/page/pages/common/parking_completed_page/parking_completed_page_shell.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | `kToolbarHeight`, 우측 48dp·132dp |

본 변경에서 대시보드 5개 화면의 우측 바깥 여백은 상하 각 4dp로 조정해 48dp 패널과 합쳐 정확히 56dp 높이 안에 배치한다. Activity Center Dialog는 별도 화면이므로 AppBar 높이를 변경하지 않는다. `R/W/D/SN/L/ST`는 시각적 축약이며 내부 계측 데이터 및 `debugPrint` 복사 형식은 바꾸지 않는다. 신규 `hintText`·수정 Dart 주석은 없다. 정적 파일 검사만으로 실제 기기 레이아웃·컴파일 성공을 보장하지 않으며, 9장의 7개 화면 회귀 검증을 배포 전 수행한다.

### 2026-11-04 Flutter 분석기 오류·경고 교정

이번 오류 교정의 적용 기준은 `261104 0020.zip`이며, 업무 데이터·Plate TTS·근무 상태 알림 실행 코드는 변경하지 않는다.

| 파일 | 변경 전 | 변경 후 | 근거 |
| --- | --- | --- | --- |
| `lib/app/diagnostics/firebase_activity_meter.dart` | `FirebaseActivityWriteBatch.update<T>(DocumentReference<T>, T)`가 존재하지 않는 `WriteBatch.update<T>()`를 호출 | `update(DocumentReference<Object?>, Map<String, dynamic>)`로 SDK 서명에 맞춰 위임 | FlutterFire `WriteBatch.update`는 제네릭이 아니며 업데이트 본문은 `Map<String, dynamic>` |
| `lib/app/init/db_connection_status_section.dart` | 사용하지 않는 `_AppBarStatusChip` 선언 잔존 | 미사용 클래스 삭제 | 상단 요약은 기존 `_ActivityConnectionLine`, `_ActivityCountsLine`과 `AnimatedSwitcher`를 사용 |
| `lib/shared/plate/widgets/departure_completed_history_workspace.dart` | 사용하지 않는 `package:http/http.dart` import | 해당 import 삭제 | GCS 공개 URL GET은 `FirebaseActivityHttp.get()`에서 처리 |

교정 후 배치 업데이트 데이터는 기존과 동일하게 Firestore SDK에 전달된다. `_writes` 증가는 실제 `WriteBatch.update()` 호출이 예외 없이 반환된 이후에만 수행하며, 확정 집계는 기존과 같이 `commit()` 성공 후 기록한다. 상단 DB 상태·계측 요약과 COST 애니메이션, 개발자 모드 ON에서의 `STATUS` 및 `debugPrint(...)` 코드 클립보드 복사는 그대로 유지한다. 새 `hintText`나 Dart 주석을 추가하지 않는다.

이 패치는 제공된 Flutter 분석기 진단 두 오류와 두 경고를 대상으로 한 최소 수정이다. 현재 작업 환경에 Flutter·Dart SDK가 없어 `flutter analyze`와 실기기 실행은 수행하지 못했다. 완전한 프로젝트에서 `flutter analyze`로 네 진단이 해소되는지 확인해야 한다.

### 2026-11-05 중첩 Map `FieldPath` 및 Firebase Activity Batch 호환 수정 이력

이 절은 `261105 0340.zip`에 대한 이전 패치의 이력이다. 당시 제안은 `FirebaseActivityWriteBatch.update()`만 `Map<Object, Object?>`로 확장하는 것이었으나 실제 프로젝트의 Firestore SDK는 `Map<String, dynamic>`을 요구해 호출부 5곳에서 컴파일 오류가 발생했다. 아래 표의 확장안은 **현재 적용 코드가 아니라 폐기된 이전 시도**다.

| 항목 | 수정 전 | 수정 후 | 근거 |
| --- | --- | --- | --- |
| `firebase_activity_meter.dart` | `update(DocumentReference<Object?>, Map<String, dynamic>)` | `update(DocumentReference<Object?>, Map<Object, Object?>)` | `FieldPath`와 문자열 키를 동시에 허용 |
| `user_write_service.dart` 활성 상태 변경 | `statusPayload()`의 Map 타입을 래퍼가 거부 | 호출부 유지, 래퍼가 그대로 전달 | 선택한 계정 Map의 상태 필드만 수정 |
| `user_write_service.dart` 계정 삭제 | `deletePayload()`의 Map 타입을 래퍼가 거부 | 호출부 유지, 래퍼가 그대로 전달 | 다른 계정을 보존하며 특정 Map 키 삭제 |
| `user_active_state_backfill_service.dart` | `password` 필드 삭제용 Map 타입을 래퍼가 거부 | 호출부 유지, 래퍼가 그대로 전달 | 레거시 필드만 삭제하고 원본 정보 보존 |
| `developer_operation_status_dialog.dart` | 로그 건수 라벨은 즉시 변경 | 220ms Fade·Slide `AnimatedSwitcher` 추가 | STATUS의 진단 누적 상태를 구분하고 `disableAnimations`에 따라 0ms 적용 |

이력상 `Map<Object, Object?>` 래퍼 확장안을 적용했으나 실제 프로젝트의 `WriteBatch.update()` 및 `Transaction.update()`가 `Map<String, dynamic>`을 요구하여 컴파일 오류 5건이 발생했다. 후속 수정에서는 래퍼를 SDK 타입으로 복원하고, 사용자 Map 이동·상태 갱신·삭제·Backfill을 계층형 문자열 Map과 `SetOptions(mergeFields: [FieldPath(...)])`의 `set()`으로 변경했다. 이 방식은 사용자 ID를 점 구분 문자열로 합치지 않고 다른 사용자 Map과 표시용 Count를 보존한다. `set()`은 문서 쓰기 1건으로 계측하며 원래의 Batch·트랜잭션 원자성, `AccountRoleDiagnostics`·`DeveloperOperationTrace`의 개발자 모드 ON `debugPrint(...)` 복사 권한 검사를 유지한다.

소스 ZIP에 `pubspec.yaml` 및 실제 Flutter/Dart SDK가 포함되지 않아 의존성 버전 기반의 컴파일 성공 여부는 여기서 확인할 수 없다. 프로젝트에서 `flutter analyze`로 위 세 호출의 타입 오류 제거를 확인하고, 활성 상태 변경·삭제·Backfill·STATUS 복사 및 모션 감소 설정을 실제 기기와 Firestore에서 검증해야 한다. 정적 구조 확인만으로 실행 성공이나 요금 절감을 선언하지 않는다.

### 2026-11-05 개발자 로그인 모달 Route 충돌 방지

`261105 1259.zip`과 같은 날 로그인 진단에서 본사 컨텍스트 활성화는 성공했지만 인증창 종료 애니메이션 뒤에 Route 종료와 대시보드 이동 로그가 없었다. 세션 저장 성공 직후 `user_state.dart`가 `unawaited(DevFirebaseDebugDialog.show())`로 별도 STATUS Route를 열었고 비밀번호 인증창은 `Navigator.of(context).pop()`으로 최상단 Route를 종료해 충돌 가능성이 있었다. 이는 원인 후보이며 당시 로그만으로 어떤 Route가 제거됐는지까지 확정한 것은 아니다.

| 수정 파일 | 수정 전 | 수정 후 | 실행 검증 |
| --- | --- | --- | --- |
| `user_state.dart` | 로그인 원격 저장 성공·실패 시 별도 STATUS 자동 팝업 | `LauncherDiagnostics.record()`로 결과 기록, 기존 예외 및 `debugPrint` 유지 | 로그인 중 자동 모달이 생기지 않음 |
| `parkinworkin_terminal_screen.dart` | 인증창 종료 시 최상단 `Navigator.pop()` | 인증창 소유 `ModalRoute` 식별, 닫힘 애니메이션 후 현재 Route만 pop 또는 특정 Route만 remove, 종료 완료 진단 추가 | `showGeneralDialog` 완료 및 대시보드 진입 |
| 비밀번호 인증 오류 UI | 기본 Fade `AnimatedSwitcher` | Fade·Slide 160ms 전환, 모션 감소 시 0ms | 오류 UI 레이아웃과 접근성 |
| 개발자 STATUS | 인증 중 자동 성공·실패 팝업과 겹칠 수 있음 | 자동 팝업 없이 누적 진단을 수동 STATUS에서 복사, 기존 권한 검사 유지 | ON에서 복사 가능, OFF에서 제한 |

로그인 세션의 Firestore 저장, Root 계정, 중첩 Map, 표시 전용 Count, Role 7종 및 회사·지역 접근은 변경하지 않는다. 실제 `flutter analyze`와 개발자 로그인·일반 Google 로그인·모션 감소·STATUS 복사 검증을 완료하기 전에는 실기기 해결이 확인됐다고 기록하지 않는다.

### 2026-11-05 로그인 인증 Route 오버레이 제거 및 Navigator 스택 보호 후속 보완

**기준 소스: `261105 1401.zip`.** 바로 위의 로그인 Route 충돌 방지 이력은 그대로 보존한다. 기존 `showGeneralDialog()`의 반환 Future는 Route 종료 결과를 알려주지만 반투명 오버레이까지 제거됐음을 보장하지 않았고, 수동 STATUS가 런처 위에 남아 있으면 `pushReplacementNamed()`가 런처가 아닌 STATUS를 교체할 수 있었다. 이는 코드상 존재했던 위험이며 실제 단말에서 발생한 횟수는 확인되지 않았다.

| 수정 파일 | 이전 동작 | 후속 수정 | 근거 |
| --- | --- | --- | --- |
| `parkinworkin_terminal_screen.dart` | `showGeneralDialog()` Future 뒤 `route_closed` 기록 | `RawDialogRoute<void>`을 직접 `Navigator.push`하고 `route.completed` 후 `launcher_auth_dialog_overlay_removed` 및 `route_closed` 기록 | Pop Future와 모달 퇴장·오버레이 제거 완료 시점이 다름 |
| `parkinworkin_terminal_screen.dart` | 인증창을 제거해도 STATUS가 위에 있을 수 있음 | `ModalRoute.of(context)`와 실제 최상단 Route가 일치할 때까지 전환 보류, STATUS 종료 후 재개 | `pushReplacementNamed()`는 최상단 Route를 교체함 |
| `parkinworkin_terminal_screen.dart` | `_closing=true` 설정 후 Route 상태 변화를 별도 대기하지 않음 | 먼저 최상단 상태 검사, 전환 중 추가 모달도 재확인, 오류 발생 시 `_closing`과 시작 화면 애니메이션 복구 | 영구 잠금·이전 런처 잔존 예방 |
| `app_navigator.dart` | `didRemove`에서 제거한 Route 아래를 최상단으로 오인할 수 있음 | 실제 Route 스택 객체 추적, 퇴장 중 `TransitionRoute.completed`가 끝나면 구독자 통지 | STATUS 위에서 비밀번호창 `removeRoute()`하는 상황에서도 정확한 최상단 유지 |
| Mini Terminal 모달 전환 | 170ms Fade | 기존 Fade에 부드러운 미세 Slide 추가, 애니메이션 감소 시 0ms | 사용자 진입·퇴장 흐름 명료화 |

**진단 계약:** `launcher_auth_dialog_route_popped`는 종료 결과 확정, `launcher_auth_dialog_overlay_removed`는 `RawDialogRoute.completed` 완료를 뜻한다. 이전 호환 이벤트 `launcher_auth_dialog_route_closed`는 완료 시점까지 늦춰 기록한다. STATUS 등 상위 Route가 남아 있으면 `launcher_navigation_deferred`, 정상 닫힘 후 `launcher_navigation_resumed`, 상태 불일치·실패는 `launcher_navigation_stack_invalid`, 실제 교체 요청은 `launcher_dashboard_navigation_requested`로 기록한다. `AppNavigatorObserver`는 기존 `main.dart`의 `onRouteChanged`와 `onRouteSettled` 콜백을 변경하지 않으며 새로운 Route 객체 구독은 별도로 유지한다.

**검증 계약:** 개발자 비밀번호·Google 일반 로그인·자동 세션 복원·APP RESTART(확인 및 5회 탭)·모션 감소 ON/OFF·STATUS 수동 열기/닫기·다른 사용자 Route 이동·뒤로가기·위젯 dispose를 각각 검증한다. 로그인창을 닫은 뒤 오버레이가 완전히 사라지고 본사 대시보드가 보이며, 뒤로가기로 이전 런처가 재등장하지 않아야 한다. 실제 `flutter analyze` 및 실기기 테스트는 별도 수행 전까지 미검증으로 남긴다.



### 2026-11-05 실제 FlutterFire 시그니처에 맞춘 중첩 Map 쓰기 보정

`261105 0414.zip` 기준 사용자가 보고한 `argument_type_not_assignable` 다섯 건은 이전 `Map<Object, Object?>` 방식이 설치된 FlutterFire `WriteBatch.update()`와 `Transaction.update()`의 `Map<String, dynamic>` 입력 계약에 맞지 않아 발생했다. 계측 래퍼 매개변수만 확장해도 원래 SDK로 전달하는 지점에서 오류가 나므로, 다음과 같이 **부분 변경을 `set(..., SetOptions(mergeFields: [FieldPath(...)])`로 대체**한다.

| 오류가 발생했던 곳 | 기존 구현 | 수정된 구현 | 안전성 기준 |
| --- | --- | --- | --- |
| `firebase_activity_meter.dart:728` | 원래 SDK의 `update()`에 `Map<Object, Object?>` 전달 | 계측 래퍼의 `update()`를 `Map<String, dynamic>`으로 복원 | 기존 문자열 기반 업데이트와 확정 계측 유지 |
| `user_write_service.dart:429` | Map 필드 두 키를 `tx.update()` | `tx.set()` + `movePayload/moveOptions` | 이전 ID 제거 + 새 ID 등록, 다른 사용자 보존 |
| `user_write_service.dart:436` | 이전 Map ID를 `tx.update()`로 삭제 | `tx.set()` + `deletePayload/deleteOptions` | 해당 Map 키만 제거 |
| `dev_user_write_service.dart:246` | 개발자 ID 변경 시 `tx.update()` | `tx.set()` + `movePayload/moveOptions` | 일반 계정과 동일 저장 규칙 |
| `dev_user_write_service.dart:253` | 이전 개발자 Map ID를 `tx.update()` | `tx.set()` + `deletePayload/deleteOptions` | 이전 지역 Map 항목만 제거 |
| 계정 활성 상태 `user_write_service.dart` | `batch.update()`에 `FieldPath` 키 Map 전달 | `batch.set()` + `statusPayload/statusOptions` | `isActive`, `updatedAt`, `disabledAt`만 변경 |
| 계정 삭제 `user_write_service.dart` | `batch.update()`에 `FieldPath` 키 Map 전달 | `batch.set()` + `deletePayload/deleteOptions` | Root·예약 삭제와 원자적 처리 |
| 활성 상태 Backfill | `batch.update()`에 `FieldPath` 키 Map 전달 | `batch.set()` + `passwordDeletePayload/passwordDeleteOptions` | 기존 Map의 `password` 필드만 삭제 |

`mergeFields`는 사용자 ID를 점 구분 문자열로 만들지 않고 `FieldPath(<String>['users', userId, ...])`로 경로를 구분한다. 문서의 `users` 전체 Map이나 `totalCount`, `activeCount`, `inactiveCount`를 덮어쓰지 않는다. 문서 내부 키 삭제는 여전히 문서 쓰기 1건이며 `COMMITTED_BATCH` 계측에 포함된다. `AccountRoleDiagnostics`, STATUS의 `debugPrint(...)` 클립보드 복사와 개발자 모드 ON 확인, 기존 Fade·Slide·Scale 애니메이션 및 모션 감소 설정은 변경하지 않는다.

컴파일 확인은 실제 프로젝트에서 `flutter analyze`로 수행한다. Firebase 실환경에서는 동일 지역의 사용자 두 명을 준비한 뒤 활성 전환·삭제·ID 변경·지역 이동·Backfill 각각을 실행하여 **대상 Map만 변경되는지** 확인한다. `FieldValue.delete()`가 포함된 `set(..., mergeFields: ...)` 처리와 서버 권한은 실제 SDK 및 Firestore Rules에서 확인할 항목이므로 실행하지 않은 테스트를 통과로 기록하지 않는다.



### 2026-11-04 앱 실행 전체 구간 Firebase Activity Journal 추가

**변경 기준 ZIP: `261104 0117.zip`.** 수정 범위는 계측 엔진과 신규 Journal, `main.dart` 초기화, Firebase Auth Bridge, 앱 종료 서비스, Activity Center Dialog, 터미널 `STATUS`, 개발자 전용 Status Dialog 복사 경로 및 README다. 헤더는 56dp, 우측 패널은 116×48dp를 유지하며 Plate TTS·포그라운드 서비스 및 Firestore Rules는 변경하지 않는다.

| 수정 파일 | 이전 | 개선 후 |
| --- | --- | --- |
| `lib/app/diagnostics/firebase_activity_journal.dart` (신규) | 메모리 500개 이외 이벤트 보관 없음 | 앱 전용 JSON Lines 기록, 2MiB 조각·7일·20MiB 정리, 보관 세션 조회·복사 |
| `lib/app/diagnostics/firebase_activity_meter.dart` | 실시간 계측과 최근 500개 복사 | `SESSION_START`·저널 기록·세션 전체 비동기 export, 기존 비용 카운터 유지 |
| `lib/main.dart` | 날짜·앱 초기화 후 Firebase 초기화 | 바인딩 직후 시작 기록, Firebase Core·App Check·초기 인증 계측 |
| `lib/features/dashboard/applications/common/firebase_google_auth_bridge.dart` | 로그인/로그아웃 개별 진단 | 실제 Firebase Auth signIn/signOut Future를 계측 |
| `lib/app/init/app_exit_service.dart` | 기존 종료·재시작 | 종료 요청/실패 기록·Flush 시도 후 기존 플랫폼 종료 흐름 유지 |
| `lib/app/diagnostics/firebase_activity_center_dialog.dart` | 최근 500개 실시간 로그만 표시 | 보관 세션/기간/페이지 조회 및 전체 범위 debugPrint 복사, 기존 애니메이션 보존 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | Firebase 최근 이벤트만 복사 | 기존 진단 + 로컬 현재 세션 전체 로그를 복사 시점에 병합 |
| `lib/app/utils/status_dialog.dart` | 제공된 고정 문자열 클립보드 복사 | 개발자 전용 비동기 생성기·복사 시점 권한 재검사 옵션 추가, 일반 복사는 유지 |

소스·README를 수정한 사실과 컴파일·실기기 성공 여부는 구분한다. Flutter/Dart SDK와 완전한 프로젝트가 없는 환경에서는 `flutter analyze`, Firebase 실제 요청·네트워크 차단·앱 강제 종료 및 Android 클립보드 처리 결과를 보증하지 않는다. 9장의 세션 관련 테스트를 실기기에서 완료한 후 배포한다.

### 2026-11-04 Firebase Activity Journal 신뢰성 개선

**기준 소스: `261104 0202.zip`.** 수정 파일은 `lib/app/diagnostics/firebase_activity_journal.dart`, `firebase_activity_meter.dart`, `firebase_activity_center_dialog.dart`, `lib/app/init/app_exit_service.dart` 및 본 README다. 완전한 Dart 파일을 같은 경로에 덮어쓰며, 주석과 `hintText`를 추가하지 않는다.

저널 재시도·부분 쓰기 정리, 세션·기간별 구조화 COST 계산, 역방향 JSONL 커서 페이지, 종료 준비 이벤트 분리가 적용됐다. 기존 전체 세션 `STATUS` 로그 복사·애니메이션·56dp AppBar·Plate TTS·근무 상태 알림·Firestore Rules·GCS `publicRead`는 수정하지 않는다.

정적 구조·상대 import·ZIP 무결성 검사와 Flutter 컴파일·실기기 실행 검증은 구분한다. Flutter/Dart SDK·완전한 Android 빌드 파일이 없는 환경에서는 `flutter analyze`, 디스크 I/O 실패 복구, 대용량 로그 페이지 이동, 개발자 클립보드 권한 및 실제 Firebase 호출 집계의 성공 여부를 보증할 수 없다. 배포 전 9장의 회귀 시나리오를 실행해야 한다.

### 2026-11-04 사용자 상태·출퇴근 읽기·쓰기 중복 방지 패치

**기준 소스: `261104 0236.zip`.** `user_status_service.dart`, `user_state.dart`, `commute_log_repository.dart`, `firebase_activity_center_dialog.dart`의 생략 없는 전체 Dart 소스와 README만 원래 상대 경로로 덮어쓴다. 9장의 동시 동일 요청·확인된 지역 쓰기·마이그레이션 표식 검증을 적용 전에 수행해야 하며, 실측되지 않은 READ/WRITE 절감량을 확정 수치로 주장하지 않는다.

기존 7일/20MiB Activity Journal, 현재·이전 세션 COST, 개발자 전용 `STATUS` 로컬 기록 비동기 병합 및 클립보드 복사 코드는 그대로 유지한다. `optimization` 이벤트는 별도 서버 호출이 아니며 Firestore 카운터를 증가시키지 않는다. `debugPrint(...)` 코드 복사 직전에 개발자 모드 권한 검사를 다시 수행하는 기존 구현을 변경하지 않는다.

화면의 56dp AppBar와 116×48dp 계측 패널, Plate TTS 직접 Firestore 구독, 근무 상태 알림, 로그인 Firebase UID, GCS 공개 읽기, 기존 `divisions/dev`, 기존 화면·상태 애니메이션은 변경하지 않는다. 비용 최적화 Dialog의 설명 전환은 기존 `AnimatedSwitcher`를 활용하고 `disableAnimations`이면 0ms로 처리한다. 수정한 Dart에는 주석 및 신규 `hintText`를 포함하지 않는다. 현재 제공된 ZIP에는 완전한 Flutter 프로젝트 루트가 없고 실행 환경에 Dart/Flutter SDK가 없어 실제 컴파일·Android 실기기·동시성·다중 기기 회귀 동작은 미검증이다.

### 2026-11-04 Firestore 비용 최적화 2차 — `261104 1413.zip` 기준

수정하는 완전한 Dart 파일은 `user_status_service.dart`, `user_state.dart`, `user_repository.dart`, `firestore_user_repository.dart`, `commute_log_repository.dart`, `firebase_activity_center_dialog.dart` 6개와 본 README다. 덮어쓰기 ZIP에는 변경 파일만 기존 상대 경로대로 포함하고 나머지는 그대로 유지한다. 새로 설치하거나 이동해야 할 파일은 없다.

| 검증 대상 | 이 패치의 정적 처리 | 추가 실기기 확인 |
| --- | --- | --- |
| 레거시 데이터 없음 | 레거시 조회·삭제 전용 WRITE 경로 제거; 월별 데이터 유지 | 현재 서버에 구형 출퇴근 `logs`가 실제 없음을 운영자가 확인 |
| 상태 원격 쓰기 | 문서별 요청 순서·성공 필드 추적·동일값 생략·로그인 쓰기 0/1 표시 | 로그인·로그아웃·근무 시작·지역 전환 반복 수행 |
| 관리자 월별 달력 | 월별 조회 결과 포맷과 저장/삭제는 보존 | 관리자 출퇴근·휴게 달력 표시·삭제·전환 확인 |
| 진단·애니메이션 | Activity Center 최적화 안내 페이드·슬라이드, 모션 감소 지원 | 개발자 `STATUS` `debugPrint(...)` 클립보드 복사 및 OFF 접근 차단 |
| 변경 제외 | Plate TTS·근무 알림·56dp 헤더·116×48dp 패널·Firebase 인증 UID·Firestore Rules·GCS `publicRead` | 실제 Android 회귀 검증 |

문서 원본 필드 값을 서버에서 추가 조회해 비교하지 않으며, **이번 앱 실행 중 성공한 원격 상태 쓰기를 확인한 경우에만** 순차 중복 UPDATE를 생략한다. 직접 계정 모델 쓰기는 상태 확인 캐시를 무효화한다. 필드 값이나 사용자 식별자가 새 `optimization` 이벤트에 저장되지 않는다. Firestore 자체의 유료 SDK 호출과 로컬 생략 진단을 구분한다.

현재 배포 자료에는 완전한 Flutter 프로젝트 루트와 Dart/Flutter SDK가 없어 `flutter analyze`, Android 빌드, 실제 Firestore READ·WRITE 절감 및 운영 Rules/레거시 데이터 확인은 수행하지 못했다. 정적 구조 검사나 ZIP 무결성만으로 실기기에서의 성공을 보장하지 않는다. 수정한 Dart 파일의 주석은 제거하고 신규 `hintText`는 삽입하지 않는다.


## 11. 일반 계정 역할 7종 및 접근 정책 — 2026-11-04 소스 수정안

### 11.1 일반 계정의 역할 코드 및 표시명

일반 계정은 `role` 필드에 아래 영어 문자열 중 하나를 저장한다. 화면에는 해당 한글명을 표시한다. 저장 필드 이름과 Firebase Authentication UID는 변경하지 않는다. 태블릿 계정의 별도 직급 역할 9종은 변경하지 않는다.

| 한글 표시명 | role |
| --- | --- |
| 대표자 | `ceo` |
| 본사 관리자 | `headAdmin` |
| 본사 직원 | `headStaff` |
| 지사 관리자 | `branchAdmin` |
| 지사 심화 관리자 | `branchProAdmin` |
| 지사 직원 | `branchStaff` |
| 지사 심화 직원 | `branchProStaff` |

### 11.2 일반 계정의 관리 기능 권한표

허용은 역할 정책상 허용을 의미한다. `sector`, `location`, `rule`, `tablet`, `monthly`, `bill`은 지역별 capability가 활성화되어야 화면에서 실행할 수 있다. `user`는 역할 정책으로 판단한다.

| 역할 | 계정 | 섹터 | 구역 | 업무 규칙 | 태블릿 | 정기 주차 | 정산 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `ceo` | O | O | O | O | O | O | O |
| `headAdmin` | O | O | O | O | O | O | O |
| `headStaff` | O | O | O | O | O | O | O |
| `branchAdmin` | X | X | X | X | X | X | X |
| `branchProAdmin` | O | O | O | X | O | O | O |
| `branchStaff` | X | X | X | X | X | X | X |
| `branchProStaff` | X | X | X | X | X | O | O |

총 49개 역할/관리 기능 조합 중 허용 29개, 비허용 20개다. 명칭의 관리자·직원 여부로 관리 기능을 자동 상속하지 않는다. 공통 정책은 `lib/app/models/account_role.dart`와 `lib/shared/secondary/application/secondary_info.dart`의 `kRolePolicy`에 둔다. 일반 계정 역할 enum의 중복 정의를 제거하고 관리 화면과 계정 편집 화면은 같은 모델을 사용한다.

### 11.3 본사 운영 관리와 지사 업무 접근의 분리

`divisions`는 사용자 회사 소속, `areas`는 허용된 지역 이름 배열, `selectedArea`와 `currentArea`는 현재 선택·실행 중인 업무 지역으로 구분한다. 회사명과 같은 지역명이 본사 지역명으로 사용된다. `ceo`, `headAdmin`, `headStaff`가 회사명에 해당하는 본사 지역으로 진입하려면 `areas`에 그 지역이 배정되어 있어야 하고, 실제 회사·지역 문서에 `isHeadquarter=true`가 확인되어야 한다. 문자열 이름 일치만으로 본사 지역임을 확정하지 않는다.

본사 역할 3종의 7개 운영 관리 기능과 회사 소속 지사 관리 데이터 접근 방침은 유지한다. **지사의 실제 업무 세션 진입은 별도 권한**이며 본사 역할이더라도 사용자 문서의 `areas`에 대상 지사 이름이 있어야 허용한다. 회사·지역 유효성, 모드 지원 여부도 추가로 검사한다. `selectedArea`를 다른 지사명으로 바꾸는 것으로 업무 접근 권한을 얻을 수 없다.

회사 소속 전체 지역 마스터를 런처 SQLite Snapshot 또는 회사별 Firestore 지역 조회로 확보하고, 지역 선택 목록에는 같은 회사의 모든 지사를 표시한다. `areas`에 배정되지 않은 지사는 반투명·잠금 아이콘으로 나타나며 터치하면 `현재 계정에 허용되지 않은 지역입니다.`라는 말풍선 안내를 표시한다. 실제 지역 이동과 업무 활성화는 진행하지 않는다. 배정 지역이라도 해당 모드가 없다면 모드 미지원 안내를 보여준다. 다른 회사의 지역은 표시·선택하지 않는다.

지사 지역 배정과 회수는 개발자가 Firestore 일반 계정 문서의 `areas` 필드를 직접 관리한다. 앱에서는 기존 사용자 정보를 편집해도 최신 서버 문서의 `areas`, `divisions`, `currentArea`, `selectedArea`를 보존한다. 지역 배정 변경은 사용자 데이터의 재조회 또는 재로그인 후에 반영하며, 기존 실행 세션에 대한 즉시 실시간 권한 회수는 별도로 보장하지 않는다.

### 11.4 관리 기능 외의 화면·운영 정책

`single` 관리 메뉴는 계정 관리 권한에 따라 표시하고, 리더/필드 화면은 공통 역할의 필드 화면 분류를 사용한다. 대시보드 관리 메뉴 및 보고서의 기존 `fieldCommon` 분기는 신규 역할의 관리 메뉴 여부로 대체한다. 정기 주차 버튼 및 실행은 모두 관리 권한 `monthly`와 지역 capability가 있어야 허용한다. 일반 계정에서 타인의 음성 메시지 삭제는 `ceo`, `headAdmin`, `branchProAdmin`에게 허용하며 태블릿 계정의 기존 `admin` 삭제 허용은 유지한다. 본인 메시지 삭제도 기존 규칙을 유지한다. 이 항목들은 7개 관리 기능 외에 코드의 명시적 보수적 운용 정책이며, 별도 운영 권한표가 확정되면 다시 조정해야 한다.

개발자 관련 `local`, `backend`, `area`는 일반 계정 7개 관리 기능에 포함되지 않는다. 기존 DevAuth 모드 및 개발자 승인 기능을 독립적으로 유지하며, 개발자 모드가 꺼져 있으면 해당 메뉴에 접근하지 않는다. 개발자 `STATUS` 다이얼로그는 역할 및 지역 권한 판정 기록을 `debugPrint(...)` 코드로 복사할 수 있다. 로그는 개발자 모드 ON에서만 수집·표시하고 복사 시점에도 개발자 모드를 재확인한다. 역할 선택 전환과 기존 STATUS 다이얼로그는 모션 감소 옵션을 반영해 애니메이션을 표시한다. 신규 힌트 텍스트 및 주석은 삽입하지 않는다.

### 11.5 기존 계정 DB 직접 변경 및 개발 초기화

기존 계정의 DB 역할값은 운영자가 직접 수정한다. 앱 안에서 기존 11개 문자열을 신규 7개 문자열로 변환하거나 마이그레이션하는 코드는 작성하지 않는다. 알 수 없는 일반 계정 `role` 값의 로그인은 거절하고, 관리 기능 권한을 자동 승격하지 않는다. 계정 편집 화면도 알 수 없는 기존 역할을 임의의 신규 역할로 저장하지 않는다. 저장 데이터의 `role` 필드명은 유지한다.

개발용 `divisions/dev`, `areas/dev-dev`, `name=dev`, `initialAdminAccountId`는 변경하지 않는다. 새로 생성하는 개발용 일반 계정의 역할은 `headAdmin`으로 설정한다. 기존 개발 계정이 이 역할과 다르면 앱에서 덮어쓰지 않고 검증 실패로 처리한다. 기존 계정의 DB 역할값 수동 수정은 운영자의 책임이다.

### 11.6 변경 위치

| 파일 | 개편 내용 |
| --- | --- |
| `lib/app/models/account_role.dart` | 단일 일반 역할 모델·한글 표시명·본사 범위·특수 UI 권한 |
| `lib/shared/secondary/application/secondary_info.dart`, `secondary_state.dart` | 관리 기능 7종별 역할 판정과 개발자 모드 분리 |
| `lib/features/account/pages/user/sheets/` | 7개 역할의 생성·편집·저장 및 미인식 역할 거부 |
| `lib/shared/secondary/pages/sheets/tabs/user_account_tab.dart` | 개발자 관리 계정 목록 및 신규 역할 선택 |
| `lib/features/dashboard/side_docks/common/` | 정기 주차 표시와 실행 권한 일치, 운영 메뉴 정책 |
| `lib/features/mode_single/page/single_inside_screen.dart` | 역할별 단일 화면 분기와 관리 메뉴 |
| `lib/features/voice/controllers/voice_runtime_controller.dart` | 명시적 음성 메시지 삭제 조건 |
| `lib/features/dashboard/side_docks/common/headquarter_work_area_side_dock.dart` | 회사 전체 지사 표시와 `areas` 미배정 지사 잠금 |
| `lib/features/headquarter/application/navigation/headquarter_context_navigation_coordinator.dart` | Snapshot 회사 검증 및 `areas`에 배정된 업무 지역 이동 |
| `lib/features/launcher/application/terminal_auth_coordinator.dart` | 미인식 역할 차단, 본사 검증 및 `areas` 기반 업무 진입 검사 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | 새 개발용 일반 계정 역할 `headAdmin` 적용 |
| `lib/app/models/account_role_diagnostics.dart`, `lib/app/utils/status_dialog.dart` | 개발자 모드의 권한 로그 수집 및 코드 복사 |

### 11.7 제외 및 검증 상태

Firestore Security Rules와 기존 DB 계정값은 수정하지 않는다. 기존 계정의 자동 마이그레이션, 개인 계정 및 태블릿 역할 체계, 회사·지사 문서 ID, 실제 Firebase Rules 배포, 서버 권한 강화 작업은 포함하지 않는다. 제공된 소스에는 Flutter 프로젝트 루트(`pubspec.yaml`, Android/iOS 빌드 설정)가 포함되어 있지 않으므로 실제 컴파일, Firebase 연동 테스트, 실기기 동작, 49개 관리 권한 전수 UI 테스트는 별도 검증이 필요하다. 소스 파일 변경과 런타임 검증 완료는 구분한다.

### 11.8 기존 지역 필드와 세션 접근의 실제 기준

| 필드 또는 검증값 | 역할 | 예시 |
| --- | --- | --- |
| `role` | 일반 계정 7개 역할 | `headStaff` |
| `divisions` | 계정이 속한 회사명 배열 | `["ABC회사"]` |
| `areas` | 개발자가 DB에서 직접 지정하는 허용 지역 | `["ABC회사", "강남지사"]` |
| `selectedArea` | 현재 선택한 지역. 권한 자체가 아님 | `"ABC회사"` |
| `currentArea` | 현재 업무 지역. 권한 자체가 아님 | `"ABC회사"` |
| 지역 문서 `isHeadquarter` | 실제 본사 확인 | `true` |
| 지역 문서 `modes` | 해당 지역에서 지원하는 업무 모드 | `["single", "double"]` |

계정 역할 `headStaff`는 7개 운영 관리 기능을 모두 허용하나, 지사 업무 모드 진입은 `areas`와 지역 모드 지원 여부로 제한한다. `areas=["ABC회사", "강남지사"]`라면 ABC회사는 본사 세션 진입 대상으로 검증하고 강남지사는 지사 업무 선택이 가능하다. 같은 회사의 서초·송파지사는 목록에 보이더라도 잠금 상태가 된다.

### 11.9 지역 목록, 안내 애니메이션 및 진단 기록

| 화면 또는 경로 | 수정 정책 |
| --- | --- |
| 최초 런처 지역 목록 | SQLite Snapshot에서 해당 회사의 전체 지역 표시, 배정 여부로 활성/잠금 분류 |
| 런처의 서버 대체 조회 | `getAreasByDivision`으로 회사 전체 지역을 조회하고 배정 여부 분류. 단일 지역만 가져오는 낡은 대체 경로 제거 |
| 런처 자동 선택 및 텍스트 명령 | 잠금 지역 자동 선택 금지. 직접 입력으로 선택해도 거절 |
| 본사 지역 사이드독 | 모든 회사 소속 지사 표시, 미배정 카드 반투명·잠금 및 터치 시 말풍선 |
| `double`, `triple`, `minor`의 지역 시트 | 지역 마스터 전체 목록을 공통 UI로 표시, 배정·모드 미충족 지역 잠금 |
| 실제 이동·활성화 함수 | 카드 선택 여부와 독립적으로 계정 `areas` 배정과 회사·본사·모드 검증 수행 |
| 미허용 지역 안내 우선순위 | 계정의 `areas`에 미배정된 지역은 업무 모드 지원 여부와 무관하게 `현재 계정에 허용되지 않은 지역입니다.`를 표시한다. 배정된 지역에서만 모드 미지원 안내를 사용한다. |
| 말풍선 배치 | 최초 런처, 본사 사이드독, 공통 지역 선택 시트는 같은 `AreaDeniedBubble` 컴포넌트를 사용한다. 안내는 선택한 지역 항목에 따라 이동하며 카드 크기와 스크롤 목록의 배치를 바꾸지 않는다. |
| 플로팅 형태 | 카드 중앙을 우선하되 루트 오버레이의 좌우·상하 안전 여백 12dp 안으로 위치를 보정한다. 글꼴 배율·줄바꿈 높이와 위아래 가용 공간을 비교해 방향·최대 높이를 계산한다. 내용이 표시 높이를 초과하면 말풍선 내부를 스크롤해 원문 전체를 읽을 수 있으며 닫기 버튼을 제공한다. 수평으로 이동해도 삼각형 꼬리는 대상 카드를 향한다. |
| 모션 정책 | 잠금 카드의 `AnimatedOpacity`/`AnimatedContainer`를 유지하고 말풍선은 약 180ms Fade+Slide 등장, 일반 높이에서는 약 2초 후 약 140ms 퇴장한다. 높이가 제한된 긴 안내는 읽는 도중 자동으로 사라지지 않도록 2초 타이머를 설정하지 않으며 닫기 버튼·목록 스크롤·화면 종료 시 닫는다. 모션 감소 시 전환 시간 없이 표시한다. |
| 반복 터치·화면 종료 | 일반 말풍선 반복 터치는 자동 닫힘 시간을 다시 시작한다. 목록의 스크롤이 시작되면 즉시 닫고 타이머·스크롤 감지를 해제한다. 다른 지역을 선택하면 이전 말풍선을 제거하며 화면이 해제되면 오버레이·타이머·감시 리스너를 정리한다. 최초 런처처럼 별도 스크롤 목록이 없는 화면은 기존 동작을 유지한다. |
| 개발자 모드 ON | 허용/차단·말풍선 등장·가로/세로 위치 보정·높이 제한 여부 및 스크롤 시작으로 닫힌 사유를 `debugPrint`로 기록하며 STATUS 다이얼로그에서 `debugPrint(...)` 코드를 클립보드로 복사한다. 복사 시 개발자 모드를 다시 확인한다. |
| 개발자 모드 OFF | 개발자 권한 진단 기록 및 STATUS 복사 기능을 제한한다. |

말풍선은 카드에 따라 움직이는 일시적인 루트 오버레이로 표시한다. 지역 목록의 가장 가까운 `Scrollable`에서 스크롤이 시작되면 즉시 종료하여 카드 이동 중 오래된 화면 경계 보정을 유지하지 않는다. 높이가 제한된 말풍선 안에서의 안내 스크롤만 터치를 허용하고 일반 말풍선은 기존처럼 터치를 통과시킨다. 화면 회전·뷰포트 크기 변화 시 기존 말풍선을 제거하고 새 위치에서 다시 표시할 수 있도록 한다. 입력 위젯의 `hintText`나 `helperText`를 추가하지 않는다. 개발자 진단 기록은 이름, 계정 코드번호, 이메일 등의 개인정보를 저장하지 않으며 역할 코드와 허용 여부 위주의 이벤트를 기록한다. `AreaMasterSelectableData`는 `assignedAreas`로 미배정 여부를 먼저 판정하며, 지역 접근 허용·거부 조건과 계정 업무 모드 권한은 변경하지 않는다.

### 11.10 DB 수동 배정·계정 수정·검증 시나리오

계정 신규 생성은 본사 또는 현재 선택 지역을 기본 배정하며, 기존 계정의 지사 배정과 회수는 개발자가 DB에서 직접 수행한다. 앱의 계정 편집과 운영 계정 편집은 최신 서버 문서를 읽어 `areas` 배열을 보존한다. 별도의 역할 또는 지역 마이그레이션 코드는 생성하지 않는다. Firestore Rules 변경은 이번 수정에 포함되지 않는다. 현행 Rules는 앱의 `areas` 기반 업무 선택 제한을 서버에서 강제하지 않는다.

| 검증 시나리오 | 예상 결과 |
| --- | --- |
| `headStaff`가 회사명과 같은 본사 지역에 배정, 지역 문서 `isHeadquarter=true` | 본사 세션 허용 |
| 배정되지 않은 회사 소속 지사 | 목록 표시·잠금·탭 안내, 업무 진입 차단 |
| 배정된 회사 소속 지사에서 지원 모드 존재 | 해당 업무 모드 진입 허용 |
| 배정됐으나 모드 미지원인 지사 | 목록 잠금과 모드 미지원 안내 |
| 다른 회사의 지사 | 목록 제외 및 직접 진입 거부 |
| 최초 로그인, 세션 복원, 터미널 직접 명령 | 똑같이 지역 배정 판정 |
| 계정의 역할·이름 수정 | DB에 배정한 지역 배열이 보존됨 |
| DB에서 지역 배정 수정 | 계정 정보 재조회 또는 재로그인 후 목록 잠금 상태 변경 |
| 개발자 모드 ON/OFF | ON일 때만 역할/지역 진단 코드 복사 허용 |
| 감소된 모션 설정 | 말풍선과 선택 카드 애니메이션 시간 0 |
| 기존 관리 권한 7×7과 태블릿·개인 계정 | 변경하지 않음 |


SQLite 지역 목록 및 DB 동시 수정 관련 기존 정책은 이번 변경의 범위에서 제외한다. 공통 지역 선택 시트는 로컬 Snapshot이 없으면 기존 지역 마스터 갱신 안내를 표시하며, 재로그인이 반드시 전체 지역 Snapshot을 생성한다고 보장하지 않는다. 계정 편집 시 DB의 `areas` 배열을 최신 조회로 보존하는 현재 방식은 그대로 두고, 조회와 저장 사이 개발자가 `areas`를 수정하는 경쟁 상황에는 덮어쓰기 가능성이 남아 있음을 명시한다. 이미 DB에 덮어써진 배열은 재로그인만으로 복구되지 않는다.

이 패치의 소스는 빌드 설정 없는 코드 스냅샷에서 변경한 것이므로 실제 `flutter analyze`, 단말 실행, Firestore 연동 및 STATUS 클립보드 동작 검증을 완료했다고 주장하지 않는다. 지역 조회가 Snapshot 부재로 서버 조회로 전환되는 경우 회사별 지역 문서 개수에 따른 읽기가 추가 발생할 수 있다. 이를 비용 계측으로 별도 관찰한다.

### 11.11 지역 접근 안내 및 플로팅 말풍선 개선 검증

| 시나리오 | 예상 결과 |
| --- | --- |
| `areas`에 없는 지역이며 업무 모드도 미지원 | `현재 계정에 허용되지 않은 지역입니다.`로 안내 통일 |
| `areas`에 없는 지역이지만 업무 모드 지원 | 같은 미허용 지역 안내 및 실제 진입 차단 |
| `areas`에 있는 지역이지만 업무 모드 미지원 | 기존 업무 모드 미지원 안내 유지 |
| 최초 런처 잠금 지역 터치 | 터치한 행에 연결된 플로팅 말풍선, 기존 선택 상태 유지 |
| 본사 사이드독 잠금 지역 터치 | 같은 안내 컴포넌트 사용, 업무 지역 이동 없음 |
| `double`·`triple`·`minor` 선택 시트 잠금 지역 터치 | 말풍선만 표시하고 선택·업무 실행하지 않음 |
| 반복 터치 | 여러 말풍선이 겹치지 않고 자동 종료 시간 재시작 |
| 다른 지역 터치 및 화면 종료 | 기존 말풍선 닫힘, 오버레이·타이머 정리 |
| 화면 상단의 잠금 지역 선택 | 실제 말풍선 높이와 사용 가능한 공간을 비교해 아래쪽으로 전환 |
| 화면 좌우 가장자리의 잠금 지역 선택 | 말풍선이 좌우 12dp 안전 여백을 넘어가지 않으며 삼각형 꼬리는 원래 카드를 향함 |
| 화면 하단의 잠금 지역 선택 | 실제 상하 공간을 계산해 말풍선의 위치와 방향 보정 |
| 글꼴 확대·여러 줄 안내 | 텍스트 너비·높이를 측정하고 화면 내 최대 높이로 제한해 줄바꿈 유지. 넘치는 내용은 내부 스크롤로 전체 열람 |
| 긴 안내에 대한 종료 | 제한된 높이의 말풍선은 2초 자동 닫힘 대신 내부 스크롤과 닫기 버튼 제공 |
| 본사 사이드독의 목록 스크롤 시작 | 말풍선 즉시 제거, 기존 2초 타이머 취소 및 스크롤 리스너 정리 |
| `double`·`triple`·`minor` 지역 목록 스크롤 시작 | 말풍선 즉시 제거, 이동 중 화면 밖으로 따라가지 않음 |
| 스크롤 후 다른 잠금 지역 터치 | 새 위치에서 말풍선 표시 및 새로운 종료 시간 적용 |
| 원래 스크롤 목록이 없는 최초 런처 | 추가 스크롤 감지 없이 기존 말풍선 정책 유지 |
| 화면 회전·뷰포트 크기 변경 | 기존 오버레이를 안전하게 제거하고 다음 터치에서 새 크기 기준으로 재계산 |
| 모션 감소 설정 | 말풍선 Fade·Slide 전환 없이 표시·제거 |
| 개발자 모드 ON | 접근 거부 및 말풍선 진단이 `debugPrint`에 기록되며 STATUS에서 `debugPrint(...)` 코드 복사 가능 |
| 개발자 모드 OFF | 개발자 진단 기록·복사 제한 |
| 지역 배정·SQLite·계정 편집·Firestore Rules | 기존 접근·동기화·DB 저장 정책 그대로 유지 |

`lib/shared/page/widget/picker_sheet/area_denied_bubble.dart`가 세 지역 선택 화면의 플로팅 UI와 루트 오버레이 좌우·상하 경계 보정, 방향 꼬리 위치, 기존 Fade·Slide 애니메이션 및 개발자 모드의 진단 기록을 담당한다. `lib/features/headquarter/application/area/area_master_cache.dart`의 `rejectionReason()`은 지역 배정을 먼저 확인한다. 기존 인라인 안내는 `common_area_picker_sheet.dart`, `headquarter_work_area_side_dock.dart`, `parkinworkin_terminal_screen.dart`에서 제거한다. 변경 파일의 신규 주석과 `hintText`·`helperText`는 추가하지 않는다. 현재 소스 스냅샷에는 `pubspec.yaml`과 Flutter SDK/프로젝트 빌드 환경이 포함되어 있지 않으므로 완전한 Dart 컴파일·실행 테스트 및 실제 기기 애니메이션 검증은 별도로 수행해야 한다.


### 2026-11-04 말풍선 화면 경계 보정 변경

`261104 2041.zip`을 기준으로 공통 말풍선 위젯의 위치 계산과 이 README만 변경한다. 기존 7개 일반 역할·49개 관리 권한, `areas` 지역 접근 검사, 최초 런처·본사 사이드독·공통 지역 시트의 호출 구조, SQLite 동기화, DB 계정 저장, Firestore Rules 및 개발자 STATUS 다이얼로그의 복사 구현은 수정하지 않는다.

| 검증 항목 | 결과 또는 확인 경계 |
| --- | --- |
| 공통 말풍선의 가로 경계 계산 | 루트 오버레이 좌우 안전 여백 안으로 위치를 보정하고 삼각형 꼬리 위치도 조정 |
| 세로 위치 결정 | 글자 크기와 실제 측정한 안내 높이 및 가용 공간으로 계산 |
| 화면 회전 및 화면 크기 변경 | 기존 오버레이를 정리하고 재표시 시 새 크기로 계산 |
| 애니메이션·자동 종료 | 기존 180ms 등장, 140ms 퇴장, 2초 자동 닫힘 및 모션 감소 유지 |
| 진단 코드 복사 | 기존 `AccountRoleDiagnostics`가 개발자 모드 ON일 때만 `debugPrint` 기록. 기존 `status_dialog.dart`가 해당 코드 복사 |
| 소스 검사 | 수정된 전체 Dart 원문·상대 import·주석·`hintText` 및 `helperText` 존재 여부 확인 |
| 실행 검증 | Flutter SDK와 `pubspec.yaml`이 없는 소스 스냅샷이므로 Flutter 컴파일 및 단말별 렌더링은 미검증 |


### 2026-11-04 큰 글씨 및 스크롤 중 말풍선 보완

`261104 2123.zip`을 기준으로 `lib/shared/page/widget/picker_sheet/area_denied_bubble.dart`와 이 README의 전체 파일만 수정한다. 일반 지역 안내의 180ms Fade·Slide 등장, 140ms 퇴장, 2초 자동 닫힘 및 화면 좌우 12dp 경계 보정은 유지한다. 말풍선 자연 높이가 사용 가능한 공간보다 크면 최대 표시 높이를 적용하고 내부 스크롤과 명시적인 닫기 버튼을 제공하여 글씨를 임의로 줄이거나 원문을 잘라내지 않는다. 이 경우 원문을 읽는 동안 2초 타이머로 자동 닫지 않는다. 가장 가까운 지역 목록이 스크롤을 시작하면 말풍선을 즉시 제거하고 스크롤 리스너도 해제한다.

| 검증 항목 | 확인 기준 |
| --- | --- |
| 큰 글자 및 낮은 화면 | 말풍선 높이가 루트 오버레이의 안전 영역 이내이며 내부 스크롤로 안내 원문을 읽을 수 있음 |
| 일반 글자 및 화면 크기 | 기존 모양·터치 통과·2초 자동 종료·Fade·Slide 유지 |
| 상위 지역 목록 스크롤 시작 | 즉시 말풍선 제거, 타이머 취소, 감시 리스너 정리 |
| 말풍선 내부 내용 스크롤 | 지역 목록 스크롤과 구분되어 안내 내용 스크롤 가능 |
| 반복 터치 및 화면 종료 | 오버레이·타이머·감시 리스너 중복 또는 잔존 없음 |
| 개발자 모드 ON/OFF | ON에서만 높이 제한·스크롤 종료 진단 `debugPrint` 기록, 기존 STATUS 코드 복사 경로 유지 |
| 비대상 기능 | 일반 역할 7종 및 권한 49개, 지사 접근 정책, SQLite, DB 계정 저장, Firestore Rules 변경 없음 |
| 검증 범위 | 정적 코드 검사와 실제 Flutter SDK 기반 컴파일·접근성·스크롤 동작 검증을 구별함 |


## 12. 지역별 중첩 Map 기반 계정 CRUD·Count 표시 전용 정책 (2026-11-05)

### 12.1 적용 범위 및 저장 계약

일반·개발자 계정의 최초 생성, 신규 생성, 수정, 지역 이동, 활성 상태 전환, 삭제, 관리 목록 조회, 개발자 기존 계정 복구에 동일한 구조를 사용한다. 계정 원본인 `user_accounts/{userId}`에는 근무시간·휴무·권한 등 기존 전체 필드를 유지하며, 코드번호 예약 `user_account_codes/{codeNumber}`도 유지한다. 계정 View는 **지역별 문서 `user_accounts_show/{division}-{area}` 내부의 `users` Map 필드**에 저장한다. 하위 컬렉션 `users/{userId}`에 신규 계정을 생성하지 않는다.

```text
user_accounts/{userId}                         계정 Root 원본
user_account_codes/{codeNumber}                 코드번호 예약
user_accounts_show/{division}-{area}            지역별 View 문서
  division, area, updatedAt
  totalCount, activeCount, inactiveCount         표시용, CRUD에서 변경 금지
  usersMapComplete                               신규 지역은 true
  users (Map)
    {userId} (Map)
      name, codeNumber, email, role, position
      modes, isActive, areas, divisions
      updatedAt, disabledAt(비활성인 경우)
```

`UserAccountViewProjection.fromUser` 또는 `fromMap`이 9개 목록용 기본 필드만 생성하며, `UserAccountShowMap`이 문서 내부 Map의 읽기, 특정 계정 Map의 전체 교체, 개별 계정의 상태 변경, 계정 키 삭제를 담당한다. `SetOptions(mergeFields: [FieldPath(['users', userId]), 'updatedAt'])` 또는 `FieldPath` 기반의 필드 업데이트를 사용하여 **다른 사용자 Map과 Count 세 필드를 덮어쓰지 않는다.** 사용자 ID에 점(`.`)이 포함되더라도 필드 경로를 문자열 결합으로 조립하지 않는다.

### 12.2 Count와 Limit 정책

지역 문서의 `totalCount`, `activeCount`, `inactiveCount`는 **명시적인 표시 전용 값**이다. 새 회사·지역의 메타 문서를 생성할 때 0으로 초기화하지만, 이후 계정 생성·수정·지역 이동·활성 전환·삭제·초기 개발자 복구에서 자동 계산하거나 갱신하지 않는다. 실제 계정 수와 다른 값이 표시될 수 있다. `activeLimit`, `totalLimit`, Count 재집계·제한 검증 기능은 제거한다. 기존 DB의 Limit 필드는 별도 관리 작업 전까지 물리적으로 남아 있을 수 있다. `전체/활성/비활성` 필터는 각 사용자 Map의 `isActive` 기준으로 계속 동작한다.

### 12.3 최초 회사·지역 및 개발자 계정 생성

`DevAreaSettingsDraft.accountMetaPayload`는 `division`, `area`, Count 세 값, 빈 `users` Map, `usersMapComplete=true`, `updatedAt`을 기록한다. 최초 개발자 계정 생성은 Root·예약·**`dev-dev` 지역 문서의 `users.{accountId}` Map**에 원자적 Batch 3건을 기록한다. Root가 기존에 있는데 Map 항목만 없는 경우 `DevBootstrapService`는 Root의 이름·이메일·코드번호·Role(`headAdmin`)·소속·활성 상태를 검증하고 해당 Map 항목만 트랜잭션으로 복구한다. 기존 Map 항목이 충돌하면 자동 덮어쓰지 않는다. 신규 회사·본사·메타 3건과 계정 Batch 3건을 모두 생성하는 경우 `writeOperations=6`이며, Map 항목만 복구하는 경우 1건으로 계산한다.

기존 하위 컬렉션 데이터는 자동으로 일괄 삭제하지 않는다. 새 초기화와 일반·개발자 계정 CRUD는 더 이상 하위 문서에 신규 View를 저장하지 않으며, 기존 계정의 수정·상태 변경은 해당 계정을 Map에 반영하고 필요 시 이전 하위 문서를 정리한다.

### 12.4 일반·개발자 계정 생성 비용 및 STATUS

| 저장 작업 | 일반 신규 생성 | 개발자 신규 생성 |
| --- | --- | --- |
| 코드번호 예약 중복 확인 | 서버 GET 1회 | 서버 GET 1회 |
| Root 계정 존재 확인 | 생성 과정의 별도 GET 없음 | 서버 GET 1회 |
| Root 전체 계정 문서 | Batch SET 1건 | Batch SET 1건 |
| 코드번호 예약 문서 | Batch SET 1건 | Batch SET 1건 |
| `user_accounts_show/{division}-{area}`의 사용자 Map 항목 | Batch SET 1건 | Batch SET 1건 |
| 기본 작업 합계 | **1 Read + 3 Writes** | **2 Reads + 3 Writes** |

자동 코드번호 충돌 재시도, 사전 검증, 기존 데이터 및 Firestore 트랜잭션 재시도는 위 최소 건수에 포함하지 않는다. 지역 View 상위 문서를 쓰므로 기존의 '상위 메타 쓰기 없음'이라는 표현을 사용하지 않는다. 상위 문서의 사용자 Map만 변경하며 **Count 값은 변경하지 않는다.** 계정 수 제한 기능도 되살리지 않는다.

`user_setting.dart`는 실제 코드번호 서버 검사 전에 **향후 실행할 작업**으로 `코드번호 중복 여부를 확인하고, 중복이 없으면 계정 원본·예약 인덱스·지역 Map View 3건을 동일 Batch로 저장합니다.`를 기록한다. 검사의 실제 결과와 Batch 커밋 성공은 별도의 진단으로 확인한다.

### 12.5 계정 수정·활성 변경·지역 이동·삭제

| 동작 | Map 변경 | Root·예약 처리 |
| --- | --- | --- |
| 기존 계정 수정 | `users.{userId}` 경량 Map 교체 | 근무시간·휴무·활성 상태 보존, 코드 예약 소유권 검증 |
| 계정 ID 또는 지역 변경 | 이전 Map 키 삭제 및 새 지역 Map 키 생성 | 기존 Root 이전 및 코드 예약 갱신 |
| 활성/비활성 변경 | 해당 계정 Map의 `isActive`, `disabledAt`, `updatedAt` 변경 | Root `isActive`·스케줄 정합성 유지 |
| 계정 삭제 | 해당 계정 Map 키 삭제 | Root 및 소유 코드번호 예약 삭제 |

이동·수정 중 기존 하위 사용자 문서가 남아 있다면 동일 트랜잭션에서 이전 문서를 제거한다. 읽기 단계에서 대상 Map 및 기존 하위 문서의 ID 충돌을 검사한다. 동일 지역의 다른 계정 Map을 덮어쓰지 않으며, 이전·새 지역이 다를 경우 양쪽 문서의 변경을 원자적으로 처리한다. 문서 크기 제한, 동시 편집 시 재시도, 보안 규칙 검사에 따른 실패는 정상적으로 오류로 처리한다.

활성·비활성 변경은 `UserAccountShowMap.statusPayload()`와 `statusOptions()`를 사용해 `users.{userId}.isActive`, `updatedAt`, `disabledAt`만 선택적으로 SET한다. 계정 삭제는 `deletePayload()` 및 `deleteOptions()`로 해당 Map 항목에 `FieldValue.delete()`를 적용한다. ID가 바뀌거나 동일 지역에서 이동하는 경우 `movePayload()`와 `moveOptions()`를 사용해 이전 키 삭제와 새 키 추가를 한 번의 트랜잭션 문서 쓰기로 처리한다. 상태 Backfill은 `passwordDeletePayload()`와 `passwordDeleteOptions()`로 오래된 View `password` 필드만 정리한다. 이 부분 쓰기는 모두 `Map<String, dynamic>`과 `SetOptions(mergeFields: [FieldPath(...)])`를 이용하며 다른 사용자 Map 및 표시용 Count를 변경하지 않는다.

### 12.6 목록 조회·원본 상세 조회·전환기 호환성

신규 지역은 `usersMapComplete=true`이므로 지역 View 문서 **1회 GET으로 계정 목록을 구성**한다. 계정 30개를 읽더라도 문서 읽기 1건이지만 전체 Map이 전송된다. 기존 지역에 마이그레이션 완료 표시가 없다면 기존 `users/{userId}` 하위 컬렉션을 추가로 읽고, Map의 동일 ID 항목을 우선하여 병합한다. 따라서 전환기에는 목록 조회가 1 Read로 줄어든다고 보장하지 않는다. 활성 계정 조회는 Map 및 필요 시 구형 View를 병합한 뒤 앱에서 `isActive=true`로 필터링한다.

관리 목록은 경량 Map으로 표시하되, 일반·개발자 계정의 **상세 수정은 Root 원본을 서버에서 먼저 읽은 다음** 진행한다. Root 조회 실패 시 근무 일정·휴무를 빈 값으로 대체한 편집 화면을 열지 않는다. 회사·지역 삭제는 새 Map과 구형 하위 컬렉션 어느 쪽에든 계정이 있으면 차단한다. 기존 Root와 연결되는 업무 기능, 로그인, Role 7종·권한 49종, 지역 접근, 태블릿, SQLite는 기존 계약을 유지한다.

### 12.7 개발자 모드 ON의 진단·클립보드·애니메이션

`AccountRoleDiagnostics.record`는 개발자 모드 ON일 때만 `debugPrint`를 출력하고 STATUS에 복사 가능한 `debugPrint(...)` 코드를 쌓는다. `DeveloperOperationTrace` 역시 기존 STATUS 다이얼로그의 클립보드 복사 기능과 개발자 모드 재확인 절차를 그대로 사용한다. 신규 View 진단은 `view=map`으로 기록하고, 초기 개발 환경의 `dev_bootstrap_map_complete`는 생성·복구 문서 수를 기록한다. 이메일·원문 코드번호·인증정보를 새 진단에 기록하지 않는다.

| 진단 단계 | 의미 |
| --- | --- |
| 신규 생성 예정 진행 안내 | 검사 및 저장 이전, 성공 확정 아님 |
| `user_create_code_check reads=1 duplicate=false` | 해당 코드번호 예약 문서 검증 |
| `user_create_batch_start writes=3 view=map` | Root·예약·지역 Map 3개 문서 Batch 요청 |
| `user_create_batch_committed writes=3 view=map` | Batch 커밋 성공 |
| `user_show_map_read_complete` | 지역 Map 목록 파싱 완료, 레거시 병합 여부 포함 |
| `dev_user_map_list_loaded` | 개발자 계정 Map 목록 조회, 레거시 병합 여부 포함 |
| `dev_bootstrap_map_complete` | 최초 개발 환경 생성·복구의 계산상 문서 쓰기 횟수 |

기존 저장 진행률 및 STATUS Fade·Scale 애니메이션, 상태 `AnimatedSwitcher`, 입력 상태 문구 Fade·Slide, Root 상세 로딩 전환을 유지한다. 개발자 계정 목록의 지역 변경·새로고침에는 **Fade·Slide `AnimatedSwitcher`**를 추가하고, 기존 행별 `CommonAnimatedReveal` 및 원본 로딩 `AnimatedSwitcher`도 유지한다. `MediaQuery.disableAnimations`가 활성화되면 추가된 전환 시간이 0이 된다. 수정 Dart에는 주석을 넣지 않으며 `hintText`, `helperText`를 추가하지 않는다.

런처 개발자 로그인 성공·실패 시 별도 STATUS를 자동 생성하지 않고 `login_session_sync_succeeded`/`login_session_sync_failed` 진단만 기록한다. 인증창은 `launcher_auth_dialog_route_popped`와 `launcher_auth_dialog_overlay_removed`를 구분하고, `launcher_dialog_phase_changed ... closed` 이후 런처가 최상단일 때 대시보드 전환을 진행한다. 수동 STATUS가 위에 있다면 강제 닫지 않고 사용자가 종료한 뒤 `TransitionRoute.completed`까지 기다려 재개한다. `launcher_navigation_deferred`·`launcher_navigation_resumed`·`launcher_dashboard_navigation_requested`의 기록은 기존 개발자 STATUS의 `debugPrint(...)` 복사에 포함되며, 모드 ON 및 복사 직전 권한 검사 정책은 그대로 유지한다.

개발자 STATUS의 `debugPrint` 기록 건수 라벨에도 220ms Fade·Slide `AnimatedSwitcher`를 적용한다. 기록이 늘어날 때 라벨만 전환되며 기존 진행률·성공/실패·복사 버튼은 유지한다. `MediaQuery.disableAnimations`가 활성화되면 로그 건수 전환도 0ms로 처리한다. `AccountRoleDiagnostics`와 `DeveloperOperationTrace`가 수집한 코드는 개발자 모드 ON에서만 기존 STATUS 복사 경로로 제공하고, 복사 직전에 모드를 재확인한다.

### 12.8 비용·확장성·보안 유의사항

| 작업 | 과거 개별 View | 신규 중첩 Map |
| --- | --- | --- |
| 동일 지역 사용자 30명 전체 조회 | 30개 사용자 문서 읽기 | **완료 표시가 있는 지역은 1개 지역 문서 읽기** |
| 일반 계정 하나 신규 생성 | Root·코드·사용자 View 3 Writes | Root·코드·지역 Map 3 Writes |
| 계정 활성 상태 갱신 | Root + 사용자 View 2 Writes | Root + 지역 Map 2 Writes, 레거시 이전 시 추가 가능 |
| 계정 수정·지역 이동·삭제 | 개별 하위 문서 처리 | Map 필드 변경, 레거시 정리 시 추가 처리 |

Firestore 단일 문서는 최대 **1MiB**이므로 지역별 사용자가 과도하게 증가하면 더 이상 중첩 Map을 확장할 수 없다. 목록을 일부만 보여주더라도 문서 1개 전체를 전송한다. 특정 지역 문서의 동시 쓰기 집중, 문서 인덱스 및 FieldPath, 지역 문서 전체에 걸친 Rules 읽기 권한을 배포 전에 점검해야 한다. 구형 하위 View에만 허용한 Rules로는 상위 Map 읽기·쓰기가 실패할 수 있다. 프로젝트에 포함되지 않은 실제 운영 Rules는 이 패치가 자동으로 수정하지 않는다.

### 12.9 회귀 검증 기준

| 시나리오 | 성공 조건 |
| --- | --- |
| 개발자 최초 생성 | `user_accounts_show/dev-dev` 문서 내부 `users` Map에 개발자 계정이 생성됨 |
| 최초 개발자 복구 | Root·예약 검증 후 `users` Map 항목만 복구, Count 불변 |
| 일반/개발자 계정 생성 | 새 계정 Map 추가, 기존 항목 손실 없음, Batch 3문서 |
| 동일 지역 계정 수정 | 해당 ID의 Map만 변경, 다른 계정과 Count 보존 |
| 지역 이동 및 ID 변경 | 이전 Map 키 삭제, 대상 Map 키 추가, 중복 없음 |
| 활성 상태·삭제 | Map/Root/예약 동기화, Count 불변 |
| 상태 변경 `mergeFields` SET | `flutter analyze` 타입 오류 없음, 대상 계정의 상태 필드만 변경, `COMMITTED_BATCH` 쓰기 건수 기록 |
| 계정 이동 `mergeFields` SET | 같은 문서에서 기존 사용자 키 제거와 새 키 추가, 다른 사용자 및 Count 보존 |
| 계정 삭제 `mergeFields` SET | 특정 계정만 Map에서 삭제, 문서 내부 필드 삭제는 WRITE로 집계 |
| 상태 Backfill `mergeFields` SET | 대상 Map의 `password` 필드만 삭제, 다른 사용자와 Count 불변 |
| STATUS 로그 건수 애니메이션 | 220ms Fade·Slide 전환, 모션 감소 시 0ms, 클립보드 복사 유지 |
| 동일 지역 동시 사용자 생성 | 양쪽 사용자 Map이 유지되거나 충돌 시 명확한 오류 |
| 신규 지역 목록 조회 | 지역 문서 1 GET로 목록 구성, 활성 필터 정상 |
| 구형 지역 목록 조회 | Map 우선 및 하위 View 폴백으로 기존 계정 누락 없음 |
| 기존 계정 상세 수정 | Root GET 후 근무시간·휴무 보존 |
| 회사·지역 삭제 | Map 또는 레거시 하위 View에 계정 있으면 차단 |
| 개발자 모드 ON | STATUS의 `debugPrint(...)` 코드 복사에 Map 진단 포함 |
| 모션 감소 | 새로운 Fade·Slide 전환이 0ms로 처리됨 |
| 보안 및 비용 | Firestore Rules 허용·거부, 1MiB, 청구 리포트 확인 |

## 13. 지역별 계정 Map 스키마와 정합성

### 13.1 단일 지역 문서의 Map 구조

`user_accounts_show/{division}-{area}` 안의 `users`는 Map이며, `users.{userId}`의 값도 경량 Map이다. `users` 하위 컬렉션을 신규 저장 대상으로 사용하지 않는다. 신규 지역에만 `usersMapComplete=true`를 기록하고, 그 지역의 읽기에서는 레거시 폴백을 생략한다. 기존 지역은 자동 완료 처리하지 않는다.

### 13.2 쓰기 및 읽기의 정합성

Root가 전체 계정의 원본이다. Map은 목록 표시용 복제 자료이므로 편집 초기값으로 사용하지 않는다. 계정 항목 쓰기·상태 갱신·삭제·이동은 문자열 키의 계층형 Map과 `SetOptions(mergeFields: [FieldPath(['users', userId]), ...])`를 함께 사용해 해당 계정 필드만 변경한다. `FieldPath` 객체를 `Transaction.update()` 또는 `WriteBatch.update()`의 Map 키로 사용하지 않는다. 다른 계정 Map이나 표시용 Count 세 값은 갱신하지 않는다. 트랜잭션·Batch 원자성은 복수 문서의 변경을 함께 처리하는 데 사용한다.

문서 내부 Map 필드 변경과 레거시 비밀번호 필드 삭제는 `Map<String, dynamic>` 계층형 데이터 및 `SetOptions.mergeFields`의 `FieldPath`로 수행한다. 계측 Batch 래퍼는 실제 SDK의 `Map<String, dynamic>` 계약을 유지한다. Region Map 스키마, Count 관리 정책, 원자적 저장 및 기본 문서 작업 건수는 변경하지 않는다.

### 13.3 데이터 보호 정책

이전 하위 View 문서를 읽을 수 있어도 자동 일괄 삭제하거나 Root 전체를 덮어쓰지 않는다. 사용자 작업으로 해당 계정을 수정하거나 상태를 변경할 때 기존 하위 문서를 Map으로 이전할 수 있으며, 별도 전체 마이그레이션은 배포 승인과 원본 대조가 선행되어야 한다. 기존 Count 값은 실제 계정 수와 다를 수 있다.

### 13.4 배포 전 확인

정적 코드 검토는 Flutter 컴파일·Firebase 실환경 권한·단말기 클립보드 및 성능 검증을 대신하지 않는다. SDK가 있는 프로젝트에서 `flutter analyze`, 실제 신규/복구/수정/이동/삭제, Rules, 1MiB 제한, 동시 쓰기 및 STATUS 동작을 확인한다.

## 14. 기존 하위 View에서 중첩 Map으로의 수동 전환

1. 운영 DB의 `user_accounts`, `user_account_codes`, `user_accounts_show` 메타 및 각 지역의 기존 `users` 하위 문서를 백업한다.
2. 각 하위 사용자 ID를 Root 및 예약 인덱스와 대조하고 코드번호·활성 상태·소속·Role 불일치나 중복을 확인한다.
3. 지역별 경량 Projection으로 구성한 Map의 Firestore 문서 크기가 1MiB 이하인지, 동시 쓰기와 Rules 접근 정책이 허용되는지 검증한다.
4. 지역 문서의 다른 사용자 Map과 Count를 보존하면서 누락된 `users.{userId}` 항목만 기록한다. 기존 항목이 Root와 충돌하면 덮어쓰지 않고 중단한다.
5. 전환 전·후 계정 ID와 중요 필드를 교차 검증한다. 모든 계정이 옮겨졌고 구형 문서 정리까지 끝난 경우에만 해당 지역의 `usersMapComplete=true`를 승인된 별도 작업으로 기록한다.
6. 검증 실패 시 Root·예약·구형 View는 삭제하지 않는다. 기존 하위 컬렉션 정리와 완료 플래그 변경을 앱 실행 또는 계정 목록 조회 중 자동으로 수행하지 않는다.

신규 회사·지역과 초기 개발자 생성은 이미 Map에 쓰므로 새로 생성된 지역의 수동 이전은 필요하지 않다. `usersMapComplete`가 없는 기존 지역은 목록 조회 시 Map과 구형 하위 컬렉션을 병합하므로, 이전이 끝날 때까지 **읽기 비용이 1문서로 줄어든다고 가정하지 않는다.**
