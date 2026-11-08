# ParkinWorkin — 기술 명세 및 개발 초기화

**2026-11-07 Double·Triple·Minor 입차 완료 `plates` 초기 조회 제거(28장, 현행):** `261107 1901.zip`의 세 PlateState `_initDefaultLoads()`에서 `parkingCompleted` 자동 조회 호출만 각 1줄 삭제한다. 기존 `parking_completed_view` 실시간 테이블, 출차 완료 `plates` 초기 조회, Triple·Minor 주행 복구, TTS, Single, 화면 애니메이션과 개발자 모드 ON STATUS `debugPrint(...)` 클립보드 복사는 유지한다. 초기 `plates` QUERY는 Single 0, Double 2→1, Triple 3→2, Minor 3→2회(기본 화면 초기화 경로 기준; TTS·리스너 별도)로 예상한다. 다른 명시적 입차 완료 조회 경로 및 화면 선택 상태는 삭제하지 않으며, 정적 코드 점검 외 실제 기기·과금 검증은 미완료다.

**2026-11-07 계정 관리·생성·수정 결과 정합성 리팩터링(27장, 현행):** 기준은 `261107 1730.zip`이다. Firebase Custom Claims, 추가 권한 발급 도구, Cloud Functions 및 기존 데이터 이관 없이 기존 Google 인증과 앱 Role 7종을 유지한다. 계정 관리 허용 Role 4종의 일반·운영 관리 생성/수정 경로에 앱 내부 Role 검사를 적용하고 개발 초기 계정 생성은 별도 호출로 유지한다. 서버 커밋과 로컬 목록·캐시 후처리를 구분하며, 검증된 목록은 추가 조회 없이 갱신하고 불완전한 목록에 한해 선택한 회사·지역의 View를 다시 읽는다. 캐시는 회사·지역 조합으로 분리한다. 개발자 모드 ON의 STATUS `debugPrint(...)` 복사와 기존 애니메이션을 유지하고 계정 목록 Fade·Slide·Scale 전환을 보완한다. `firestore.rules`는 이전 버전 그대로이며 서버의 업무 Role별 직접 쓰기 차단은 여전히 미완료다. Flutter·Emulator·실기기·운영 비용 검증은 별도다.

**2026-11-07 신규 View Map 단일 조회·구형 하위 문서 의존성 제거(26장):** 현재 계정 관리 목록은 `user_accounts_show/{division}-{area}`의 `users` Map을 단일 조회 원본으로 사용한다. `usersMapComplete`를 요구하지 않으며 과거 하위 `users` 컬렉션의 조회·삭제·이관을 수행하지 않는다. View 누락과 잘못된 Map 형식은 오류로 구분한다. 직원 행 선택은 로컬 처리하고 상세 수정 시에만 `user_accounts/{userId}` Root를 조회한다. 새 목록 상태 Fade·Slide와 계정 변경 비식별 진단을 유지·보강하고 개발자 모드 ON의 STATUS Dialog에서 `debugPrint(...)` 코드로 복사할 수 있다. 기존 데이터의 이관·하위 호환은 범위에서 제외하며 기존 저장 데이터의 자동 삭제는 수행하지 않는다. 실제 Flutter 실행·Firestore Rules 배포·실기기 복사는 별도 검증 대상이다.

**2026-11-07 계정 목록 View 단일 조회 리팩터링(25장, 이력):** 25장의 이관 완료 플래그 검증과 관리자 이관 도구는 당시 설계의 기록이며 현재 실행 정책이 아니다. 26장이 최신 기준이다.

**2026-11-07 계정 생성 권한·표시명 리팩터링(24장):** CEO를 포함해 기존 계정 관리 허용 4개 Role이 개발자 모드 OFF·STATUS 미진입에서도 계정을 만들 수 있도록, `user_accounts_show` 상위 문서가 없을 때 단일 사용자 Projection에 한해 CREATE를 허용하는 Rules 초안을 추가했다. 기존 1회 예약 GET과 3건 Batch는 유지하고, 실패 당시의 비식별 생성 이벤트를 개발자 모드 ON 후 STATUS Dialog에서 확인·`debugPrint(...)` 형식으로 복사하도록 기록 경로를 보강했다. `headStaff` 표시명 공백을 1칸으로 맞췄다. 기존 문서 초기화·Role 저장코드·애니메이션 접근성·UI 힌트 정책은 유지하며 Rules 배포·에뮬레이터·실기기 검증은 별도다.

**2026-11-06 easydev Google 인증 기반 전체 Firestore Rules 갱신안:** 대상은 개발 프로젝트 `easydev-97fb6`만이며, 2026-11-05의 회사·지역 개발자 전용 정책을 보존하면서 모든 **기존에 허용된** Firestore 작업의 공통 인증 조건을 Google 제공자로 Firebase Authentication에 로그인하고 이메일이 검증된 사용자로 강화한다. 최상위 및 중첩 `plates`의 공개 읽기를 제거한다. 미사용 `usage_daily`의 전용 허용 규칙·검증 함수를 삭제하고 기본 거부 정책에 맡긴다. Cloud Functions·Custom Claims·UID 매핑·새 인증 컬렉션 및 Flutter Dart 수정 없이 `firestore.rules`, `README.md` 두 파일만 변경한다. **이번 초안은 코드 작성·정적 검토 단계이며 실제 easydev Rules 게시·Emulator 테스트는 별도로 해야 한다.** 현행 정책과 비용·보안 한계는 7장·8장·9장·10장 및 신규 16장을 우선 참고한다.

**2026-11-05 회사·지역 서버 권한 규칙 작성:** `261105 1845.zip`의 개발자 Gmail 사전 검사에 맞추어, 사용자가 제공한 Firestore Security Rules 전체를 검토하고 프로젝트 루트 `firestore.rules`를 신규 추가했다. `divisions`·`areas` 생성·수정·삭제는 인증되고 이메일 검증된 `surge1868@gmail.com`만 허용한다. `user_accounts_show`의 최상위 구조 메타 생성·삭제와 사용자 Map 수정 권한은 구분한다. 기존 회사·지역 Transaction/Batch와 계정 CRUD, UI 애니메이션, 개발자 모드 ON의 STATUS `debugPrint(...)` 복사는 보존한다. **이 파일을 덮어써도 서버 Rules는 자동 배포되지 않으며 운영 배포·Rules 컴파일·Emulator 검증은 미완료다.** 전체 변경과 권한·비용·회귀 검증은 7~10장 및 15장에 기록한다.

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
| `lib/features/dev/application/developer_account_authorization.dart` | 허용된 개발자 Gmail `surge1868@gmail.com` 단일 기준, 기존 승인·Debug 정책 |
| `lib/features/dev/application/developer_structure_write_guard.dart` | 회사·지역 쓰기 직전 개발자 모드·실제 Firebase 인증 토큰 이메일 및 검증 상태 확인, 로컬 진단 기록 |
| `firestore.rules` | easydev 전체 허용 업무 경로에서 Google 기반 Firebase 인증·이메일 검증을 요구하고, 개발자 전용 회사·지역 변경 및 `user_accounts_show` 메타 보호를 유지. 중첩 `plates` 공개 읽기 제거·미사용 `usage_daily` 허용 제거; 자동 배포 아님 |
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

**App Check 실행 상태(사용자 확인):** App Check 관련 동작은 모두 수행 완료했다. 이 기록은 실행 동작의 완료 상태를 뜻하며, Firebase 서비스별 강제 적용(Enforcement) 및 미인증 외부 요청 차단 시험의 별도 검증 완료를 의미하지 않는다.

**2026-11-06 easydev Console 확인:** 사용자가 제공한 Firebase Console 화면에서 개발 프로젝트 `easydev-97fb6`의 **Cloud Firestore App Check 강제 적용(적용됨)** 및 정상 검증 요청이 확인됐다. 같은 화면에서 Storage는 **적용되지 않음**으로 표시됐다. 이는 확인 시점의 서비스별 콘솔 상태일 뿐, 독립적인 외부 공격 차단 시험이나 프로덕션 프로젝트의 강제 적용 상태까지 증명하지 않는다.

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

**최신 적용 기준(2026-11-06 easydev 수정안, 서버 게시 미확인):** 일반 Firestore 클라이언트 요청은 기존 `_isSignedIn()`을 통해 `request.auth != null`, `request.auth.token.firebase.sign_in_provider == 'google.com'`, `request.auth.token.email_verified == true`를 모두 검사한다. 일반 업무 컬렉션의 기존 허용 범위는 유지하되, 비로그인·익명·다른 로그인 제공자만 사용한 요청은 차단한다. **이 조건은 ParkinWorkin 등록 업무 계정과 Firebase 인증 이메일의 일치 여부를 서버에서 검증하지 않는다.** 이메일 일치 검사는 기존 앱 로그인 경로에만 존재한다.

| 경로·기능 | 2026-11-05 제공된 기존 Rules | 2026-11-06 easydev 수정안 | 보존·변경 근거 |
| --- | --- | --- | --- |
| 공통 `_isSignedIn()` | Firebase 인증 존재만 검사 | Google 제공자 로그인 + 이메일 검증 | 추가 Firestore 종속 문서 READ 없이 익명·다른 제공자 차단 |
| `_isDeveloper()` | 이메일 검증된 단일 개발자 Gmail | `_isSignedIn()`과 `surge1868@gmail.com` 일치 | 개발자 전용 구조 변경 보호 유지·Google 인증 강화 |
| `user_accounts`, `user_account_codes` | 로그인 사용자 읽기·쓰기 | Google 인증 사용자 읽기·쓰기 | 기존 업무 계정 3문서 Batch·Transaction 유지, Role별 서버 제한 없음 |
| `tablet_accounts`, `personal_accounts` | 로그인 사용자 읽기·쓰기 | Google 인증 사용자 읽기·쓰기 | 기존 계정 유형별 Firebase 인증 방식과 호환성 확인 필요 |
| `commute_user_logs`, `plate_status`, 각종 View·정산·차량 컬렉션 | 로그인 사용자 읽기·쓰기 | Google 인증 사용자 읽기·쓰기 | 기존 데이터 작업 수·규모 및 일반 Role 간 동일한 접근 범위 유지 |
| `user_accounts_show/{scopeId}` 읽기 | 로그인 사용자 | Google 인증 사용자 | 목록·메타 조회 기본 조건 강화 |
| `user_accounts_show/{scopeId}` 생성·삭제 | 개발자 Gmail만 | Google 인증된 개발자 Gmail만 | 기존 구조 메타 보호 유지 |
| `user_accounts_show/{scopeId}` 수정 | 개발자 또는 `users`·`updatedAt`만 변경하는 로그인 사용자 | 개발자 또는 `users`·`updatedAt`만 변경하는 Google 인증 사용자 | 상위 메타 필드 보호 유지; 내부 사용자별 Role 보호는 별도 |
| `user_accounts_show/{scopeId}/users/{userId}` | 로그인 사용자 읽기·쓰기 | Google 인증 사용자 읽기·쓰기 | 레거시 View 경로 호환 |
| `divisions/{document=**}`, `areas/{document=**}` 읽기 | 로그인 사용자 | Google 인증 사용자 | 기존 회사·지역 목록 유지 |
| `divisions/{document=**}`, `areas/{document=**}` 생성·수정·삭제 | 단일 개발자 Gmail만 | Google 인증된 동일 개발자 Gmail만 | 회사·지역 구조 권한 확대 금지 |
| 최상위 `plates/{document=**}` | 로그인 사용자 읽기·쓰기 | Google 인증 사용자 읽기·쓰기 | 공개 읽기 우회 규칙도 동시에 교체 |
| `/{path=**}/plates/{plateDocId}` | 모든 사용자의 공개 읽기 `true` | Google 인증 사용자의 읽기만 | `collectionGroup('plates')` 및 중첩 문서 호환성 유지하면서 공개 읽기 차단 |
| `usage_daily/{date}/tenants/{tenant}/users/{user}` 및 `events` | 제한된 카운터·이벤트 쓰기 허용 | 전용 규칙 제거, 기본 거부 | 사용 종료, 서버 쓰기 남용 방지, 저장된 문서는 보존 |
| 기본 `/{document=**}` | 읽기·쓰기 전부 거부 | 변경 없음 | 미지정 경로 기본 거부 |

**미사용 `usage_daily`의 의미:** 기존 카운터·이벤트 경로에 대한 허용은 제거돼 해당 경로는 마지막 기본 거부 정책을 따른다. 서버에 남아 있는 기존 문서는 자동 삭제되지 않는다. 다만 전체 경로에 적용되는 `/{path=**}/plates/{plateDocId}`는 중첩된 이름이 `plates`인 문서의 Google 인증 읽기를 허용하므로, 예외 경로가 중복되는 경우 `allow false`가 다른 허용을 덮어쓰지 않는다는 점을 감사해야 한다.

**중복 match 규칙:** Firestore는 한 문서에 일치하는 어느 `allow`든 참이면 접근을 허용한다. 따라서 공개 `plates` 읽기 규칙은 단순히 별도 인증 규칙을 추가하는 것이 아니라 기존 `allow read: if true`를 직접 대체했다. 별도 Firebase Storage 및 GCS `publicRead` 정책은 Firestore Rules와 다르므로 이번 파일에서 변경하지 않는다.

**보안 한계:** 인증된 Google 사용자가 ParkinWorkin의 등록 업무 계정인지 서버에서 재확인하지 않으므로, Firebase 프로젝트에 인증된 미등록 Google 사용자도 일반 업무 데이터에 접근할 수 있다. 등록된 사용자에 대한 업무 Role·회사·지역별 세부 서버 권한 제한도 이번 범위에 없다. 앱의 7종 Role과 지역 진입 제한은 별개이며, 사용자 Map 내부의 다른 직원 항목 변경도 기존 정책상 허용될 수 있다. App Check 강제 적용은 위조 클라이언트의 악용을 줄이지만 등록 사용자 여부를 증명하는 수단은 아니다.

**기존 데이터 저장 구조:** 회사 생성 Transaction은 회사·본사·계정 메타 3문서를, 지역 생성 Transaction은 지역·계정 메타 2문서를 유지한다. 일반 계정의 Root·코드 예약·지역 Map Batch도 유지한다. 개발자가 아닌 사용자가 메타 문서가 없는 지역에 계정을 생성하면, 상위 메타 문서의 `create`가 거부돼 Batch 전체가 실패할 수 있는 기존 제약도 그대로다.

**서버 배포:** 이 README는 수정 파일을 설명하며 Firebase Console의 실제 서버 Rules를 자동으로 게시하지 않는다. 정적 검토와 Rules 컴파일·Emulator/단말 실행 시험, 개발 프로젝트 게시 완료는 각각 구분한다.

## 8. 비용·사용량 평가

**2026-11-06 easydev Google 인증 기반 Rules 증분 비용:** `_isSignedIn()`과 `_isDeveloper()`는 이미 포함된 Firebase 인증 토큰의 제공자·이메일 검증·개발자 Gmail 문자열만 비교한다. 이번 `firestore.rules`에는 다른 문서를 읽는 `get()`, `exists()`, `getAfter()` 호출을 추가하지 않았다. 따라서 **인증 검사를 위한 추가 Firestore 종속 문서 READ/WRITE는 0건**이다. 기존 Firestore 조회·쓰기·삭제·실시간 구독의 기본 사용량, 쿼리의 최소 읽기, 재연결 및 다른 서비스의 과금은 별개다. 미사용 `usage_daily` 카운터·이벤트 저장을 허용하지 않지만, 앱에서 사용하지 않으므로 정상 업무 작업량이 줄었다고 단정하지 않는다. 과금 자체의 감소나 일일 총액을 검증 완료했다고 기록하지 않는다.


**회사·지역 서버 권한 수정 비용:** 변경된 `firestore.rules`에서 Gmail·이메일 검증은 Firebase 인증 토큰 필드 비교이며 별도 Firestore 문서 READ/WRITE를 만들지 않는다. 따라서 정상 회사 생성의 사전 GET 3건·확정 3 Writes, 지역 생성의 사전 GET 2건·확정 2 Writes 및 저장 후 목록 조회는 기존과 같다. 지역 수정·회사/지역 삭제의 Transaction·Batch·연관 계정 검사도 변경하지 않는다. 단, 빈 GET·쿼리, 동시 재시도, Rules 이외의 호출, 인증 토큰 갱신 및 실제 청구 단위는 별개다. `request.auth` 비교 자체에 따른 **추가 Firestore 문서 GET은 0건**으로 목표하며 Firebase Console의 실제 사용량 검증을 생략하지 않는다. 권한 거부 전에 호출한 조회가 있다면 그 비용은 남을 수 있다.

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

**2026-11-06 easydev Google 인증 Rules 검증(작성된 테스트 계획, 실행 결과 아님):**

| 요청·상황 | 기대 결과 | 확인 방법 |
| --- | --- | --- |
| Google 제공자로 Firebase 인증·이메일 검증 완료 | 일반 업무 컬렉션의 기존 허용 작업 정상 | Emulator, 실제 개발 앱 단말 |
| Firebase 미로그인 | 모든 기존 비공개 경로와 `plates` 읽기 거부 | Rules 단위 시험 |
| Firebase 익명 인증 | 일반 업무 경로 읽기·쓰기 거부 | 디버그 개발자 특수 로그인 회귀 포함 |
| 이메일/비밀번호만으로 Firebase 로그인 | 일반 업무 경로 거부 | provider 조건 시험 |
| 이메일 검증 상태 false | 일반 업무 경로 거부 | 토큰 검증 시험 |
| 미등록 Google 인증 사용자 | 현재 Rules상 일반 업무 접근 가능 | 설계 한계를 확인하는 보안 시험 |
| 중첩 `plates` 및 collectionGroup 조회 | Google 인증 시 성공, 비인증 시 거부 | Plate TTS 및 Firestore 조회 경로 재현 |
| 개발자 Gmail 회사·지역 CRUD | 정상 개발자 Google/Firebase 세션에서 성공 | 기존 Transaction·Batch 회귀 |
| 다른 Gmail로 회사·지역 쓰기 | permission-denied | 서버 Rules 단위 시험 |
| 사용자 Map의 허용 필드만 수정 | Google 인증이면 기존 update 범위에서 성공 | 메타 변조 거부와 구분 |
| 미사용 `usage_daily` 카운터 및 이벤트 경로 | 읽기·생성·수정·삭제 거부 | 경로별 Rules 테스트 |
| 기존 일반 계정 3문서 Batch | 지역 메타가 존재하면 기존대로 수행 | 앱·Emulator 회귀 |
| STATUS Dialog·기존 애니메이션·debugPrint 복사 | 개발자 모드 ON의 기존 UI 동작 유지 | 실제 Flutter 단말 확인 |
| 실제 Firebase 인증·App Check·Console 게시 | 클라이언트·서버 설정 일치 | easydev 프로젝트만 확인 |


**추가된 개발자 전용 Rules 회귀 시험:** 수정 파일을 운영 배포하기 전에 Firestore Emulator/Rules Playground에서 아래 항목을 검증해야 한다.

| 실행 주체·작업 | 기대 결과 | 검증 초점 |
| --- | --- | --- |
| 검증된 `surge1868@gmail.com`으로 회사 생성 | 3문서 Transaction 성공, 목록 갱신 | 회사·본사·상위 계정 메타 3경로가 모두 허용 |
| 동일 개발자 Gmail로 지역 생성·수정·삭제 | 기존 2문서 생성, 수정 Transaction 및 삭제 Batch 성공 | 연관 사용자 검사·기존 데이터 보존 |
| 동일 개발자 Gmail로 회사 삭제 | 연관 계정 검사 통과 시 회사·지역·메타 삭제 | 대량 Batch 및 종료 상태 |
| 다른 인증된 Gmail로 회사·지역 create/update/delete 직접 요청 | **모두 permission-denied** | 앱 UI가 아닌 서버 Rules 평가 |
| 이메일 미검증·익명 Firebase 사용자·미로그인 사용자 | **회사·지역 쓰기 거부** | `email_verified`, 인증 토큰 확인 |
| Debug 개발자 모드 ON + 실제 Firebase Gmail 불일치 | 앱 사전 차단 및 서버 직접 쓰기 거부 | 디버그 승인 우회와 서버 권한 분리 |
| 일반 계정 관리자가 기존 지역의 사용자 Map 수정 | 계정 Root·코드·상위 Map 변경 성공 | 기존 `user_accounts_show` 최상위 update 경로 |
| 상위 계정 메타가 없는 지역에서 일반 계정 Batch | 상위 문서 create 거부 예상, 3문서 Batch 전체 실패 | 개발자 초기화·복구 절차 확인 |
| 일반 인증 사용자가 상위 메타의 회사·지역 필드 수정·문서 삭제 | 거부 | 변경 필드 제한 및 메타 보존 |
| 일반 인증 사용자가 `users` Map 내부 타 계정 항목 수정 시도 | 현재 수정안에서 허용 가능 | **잔여 서버 계정 권한 위험으로 기록** |
| 개발자 STATUS 코드 복사 | 모드 ON에서 권한 검사·진단 포함, OFF에서 제한 | `debugPrint(...)`·Clipboard·애니메이션 |
| 사용자 모션 감소 설정 | 기존 Fade·Scale·Slide 전환 시간이 0 | 원래 UX 보존 |
| Rules Emulator·Firebase Console 게시 | 직접 검증·게시 로그 확인 전까지 미완료 | 정적 코드 검사와 운영 서버 적용을 구분 |

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

**2026-11-06 easydev 신규 Google 인증 Rules 작업:** 기존 `aa.zip`에는 프로젝트 루트의 `README.md` 및 `firestore.rules`가 없으므로, 최신 대화에서 확인된 전체 README(2026-11-05 App Check 완료 기록 포함)와 제공된 기존 279행 Rules를 기준으로 두 파일을 **완전한 파일 형태로 제공**한다. 기존 Flutter Dart 코드는 수정하지 않았다. Google 인증 공통 함수·개발자 함수 교체, 공개 `plates` 읽기 제한, 미사용 `usage_daily` 제거 및 README 최신 정책 반영의 **정적 검토는 가능하지만**, Firestore Rules 컴파일·Emulator 실행·실제 `easydev-97fb6` 서버 게시 및 단말 권한 검증은 완료하지 않았다. 기존 2026-11-05의 Rules 작성·기타 개발 이력은 당시의 상태로 해석하고 **최신 정책은 7장 및 16장을 우선**한다.


**2026-11-05 `261105 1845.zip` 기반 Firestore Rules 통합:** 사용자 제공 전체 Rules를 프로젝트 루트 `firestore.rules`로 추가하고, 7장의 회사·지역 개발자 전용 권한과 계정 메타 상위 문서 제한을 반영했다. `README.md`와 `firestore.rules`만 수정/추가했다. **파일 작성 및 정적 구조 검토는 완료했으나 Firebase Rules 컴파일, Emulator·실제 Firebase 조회·쓰기 시험, 서버 배포 및 사용자 계정 회귀 시험은 미완료다.** 프로젝트 스냅샷에는 `firebase.json`·Flutter 빌드 설정이 없으므로 배포 설정과 Firebase 프로젝트 ID를 추정해 추가하지 않는다. 기존 1845 Dart 코드·애니메이션·STATUS 클립보드 복사는 바이트 단위로 유지한다.

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




### 2026-11-05 개발자 계정 목록 반복 읽기 최적화 — `261105 1445.zip` 기준

15:06~15:11의 개발자 워크플로우 Firebase Activity 기록에서 `user_account_tab.dart`에 귀속된 GET 428건·QUERY 429건(총 857건, 약 58초)이 관찰됐고, 결과 0개 호출이 848건이었다. 앱 Activity 기록 수는 실제 Firestore 청구 읽기 수와 다르며, 빈 쿼리의 최소 읽기와 인덱스 비용, 캐시·Rules 동작은 별도 확인한다. 동일 실행에서 정상 계정 생성은 기존 Batch 3문서 쓰기로 유지됐으므로 생성 저장 로직은 변경하지 않는다.

| 구분 | 기존 구현 | 이번 수정 후 | 검증 기준 |
| --- | --- | --- | --- |
| `user_account_tab.dart`의 `FutureBuilder` | `build()` 중 `_fetchUsersForArea(division, area)`를 직접 호출 | 회사·지역별 `_usersForArea`의 동일 Future 재사용 | 동일 UI 재빌드 20회에 추가 목록 GET·QUERY 0회 |
| 진행 중인 동일 지역 요청 | 재빌드마다 중복 Firestore 호출 가능 | 동일 범위의 비동기 Future 공유 | 같은 범위 동시 서버 조회 1묶음 |
| 반환 사용자 0명 | 정상 빈 결과여도 다시 조회 가능 | 빈 결과 Future도 유지 | 정상 빈 목록 재빌드에서 추가 호출 0회 |
| 조회 실패 | 실패한 Future가 화면마다 새로 생성될 수 있음 | 실패 캐시 제거, 새로고침으로 재시도 | 오류 상태에서 수동 재시도 가능 |
| 캐시 범위·메모리 | 목록 Future 캐시 없음 | 회사·지역별 키, 최대 12개 범위 보관·오래된 범위 교체 | 영역을 옮겨도 다른 범위 결과 혼합 없음 |
| 계정 생성 성공 | 기존 Batch 3 Writes, `_refreshTick++` | 기존 저장 유지, 생성 지역 캐시만 무효화한 뒤 화면 갱신 | 새 계정 정상 표시, 타 지역 캐시 보존 |
| 계정 수정 성공 | 기존 Root·Map 업데이트 후 `_refreshTick++` | 저장 성공 시 이전·대상 지역 캐시 무효화 | 수정 반영, 실패 시 캐시 보존 |
| 수동 갱신 | 재빌드로 비의도적 재조회가 발생 가능 | 신규 계정 행의 새로고침 아이콘으로 현재 지역만 명시적 재조회 | 실제 사용자가 요청한 경우에만 추가 조회 |
| UI 재빌드 | Role·선택·애니메이션 상태 변경으로 목록 GET·QUERY 반복 위험 | UI 상태 변경과 목록 비동기 요청 분리 | 상태 변경만으로 서버 요청 증가 없음 |
| 레거시 호환 | `usersMapComplete`가 true가 아니면 기존 하위 `users` 조회 | 동일한 Map 우선 병합과 레거시 조회 1회 유지, 결과 Future 재사용 | 이전 계정 누락 없음; 완료 표시 자동 변경 금지 |
| 개발자 진단 | `dev_user_map_list_loaded` 및 Firebase Activity 기록 | fetch 시작·재사용·완료·실패·무효화·최대 12개 캐시 축출 기록 | 모드 ON에서 기존 STATUS `debugPrint(...)` 복사 포함 |
| 애니메이션 | 사용자 목록 Fade·Slide, 행별 Reveal, 저장 중 AnimatedSwitcher | 기존 애니메이션 유지, 수동 새로고침 아이콘 Fade·Scale 추가 | 모션 감소 시 추가 애니메이션 0ms |

**조회 계약:** `_usersForArea()`는 캐시에 저장된 동일 Future를 `FutureBuilder`에 전달한다. UI 빌드 중 이 메서드를 호출하더라도 기존 Future가 있으면 서버 조회를 다시 시작하지 않는다. 완료된 빈 결과도 유효한 데이터로 재사용한다. 조회 실패 시 해당 Future를 제거해 수동 재시도가 가능하도록 한다. 같은 범위의 서버 조회가 진행 중이면 수동 새로고침의 중복 요청을 건너뛴다. 최대 12개 회사·지역 범위를 보관하며 제거된 범위의 다음 접근은 새 요청이다. 외부 기기에서 계정이 변경된 경우에는 사용자가 새로고침을 실행해 최신 목록을 요청할 수 있다.

**저장 계약:** `DevUserWriteService.createUser`·`updateUser`의 Firestore 쓰기 본문, Root 계정 상세 GET, 코드번호 예약, Region Map, Count 표시 전용 값, Role·권한은 변경하지 않는다. 서버 쓰기가 정상 완료된 뒤 해당 지역의 목록 Future만 무효화한다. 수정 시 회사·지역이 다른 경우 이전 지역과 대상 지역 모두 무효화한다. 저장 실패 시 캐시를 유지한다. 기존 사용자 Map을 업데이트한 후에도 `usersMapComplete`는 검증 없이 true로 변경하지 않으며 기존 레거시 결과를 우선 삭제하지 않는다.

**진단 계약:** 개발자 모드 ON에서는 `AccountRoleDiagnostics.record`로 `dev_user_list_fetch_started`, `dev_user_list_fetch_reused`, `dev_user_list_fetch_completed`, `dev_user_list_fetch_failed`, `dev_user_list_cache_invalidated`, `dev_user_list_cache_evicted`, `dev_user_list_refresh_skipped` 이벤트를 기록한다. 요청 ID, 실행시간, 결과 수, 재사용 횟수와 비식별 범위 해시를 남기며 원문 UID·이메일·코드번호는 추가하지 않는다. 재사용 로그는 최초 1회와 이후 50회마다 기록해 디버그 로그 자체도 과도하게 늘리지 않는다. 기존 `DeveloperOperationTrace`와 터미널 STATUS는 `AccountRoleDiagnostics.debugPrintCode`를 포함하므로 개발자 모드 ON에서 클립보드 코드 복사가 가능하고 복사 직전 권한 재확인은 유지한다.

**회귀 검증:** 첫 지역 진입 시 완료된 Map 지역은 GET 1회, 레거시 지역은 Map GET + 레거시 QUERY 각 1회가 기본이다. 목록 20회 재빌드, Role 선택, Root 상세 로딩 및 애니메이션으로 추가 목록 GET·QUERY가 생기지 않는지 확인한다. 계정 생성·수정 후 정확한 지역의 최신 목록만 다시 읽고, 생성은 여전히 Batch 3 Writes인지 검사한다. 새로고침 버튼을 눌렀을 때만 선택 지역 조회를 다시 시작한다. `flutter analyze`, 실제 Firestore SDK 호출 수 및 Firebase Console 청구 수치는 실환경에서 별도 확인하며 이번 정적 검토만으로 실제 요금 감소를 확정하지 않는다.

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

`DevAreaSettingsDraft.accountMetaPayload`는 `division`, `area`, Count 세 값, 빈 `users` Map과 `updatedAt`을 기록한다. 최초 개발자 계정 생성은 Root·예약·**`dev-dev` 지역 문서의 `users.{accountId}` Map**에 원자적 Batch 3건을 기록한다. Root가 기존에 있는데 Map 항목만 없는 경우 `DevBootstrapService`는 Root의 이름·이메일·코드번호·Role(`headAdmin`)·소속·활성 상태를 검증하고 해당 Map 항목만 트랜잭션으로 복구한다. 기존 Map 항목이 충돌하면 자동 덮어쓰지 않는다. 신규 회사·본사·메타 3건과 계정 Batch 3건을 모두 생성하는 경우 `writeOperations=6`이며, Map 항목만 복구하는 경우 1건으로 계산한다.

신규 회사·지역과 초기 계정은 상위 `users` Map만 사용한다. 일반·개발자 계정 CRUD는 구형 하위 `users` 컬렉션을 조회하거나 정리하지 않는다. 기존 데이터의 이관·호환성은 26장 기준으로 고려하지 않으며, 계정 원본·코드 예약·View Map의 신규 쓰기 정합성은 유지한다.

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

계정 이동·수정 시 원본 Root·코드 예약·현재 View Map을 검사한다. 구형 하위 `users` 문서의 읽기·삭제는 수행하지 않는다. 동일 지역의 다른 계정 Map을 덮어쓰지 않으며, 이전·새 지역이 다를 경우 양쪽 View 문서 변경을 원자적으로 처리한다. 문서 크기 제한, 동시 편집 시 재시도, 보안 규칙 검사에 따른 실패는 정상적으로 오류로 처리한다.

활성·비활성 변경은 `UserAccountShowMap.statusPayload()`와 `statusOptions()`를 사용해 `users.{userId}.isActive`, `updatedAt`, `disabledAt`만 선택적으로 SET한다. 계정 삭제는 `deletePayload()` 및 `deleteOptions()`로 해당 Map 항목에 `FieldValue.delete()`를 적용한다. ID가 바뀌거나 동일 지역에서 이동하는 경우 `movePayload()`와 `moveOptions()`를 사용해 이전 키 삭제와 새 키 추가를 한 번의 트랜잭션 문서 쓰기로 처리한다. 상태 Backfill은 `passwordDeletePayload()`와 `passwordDeleteOptions()`로 오래된 View `password` 필드만 정리한다. 이 부분 쓰기는 모두 `Map<String, dynamic>`과 `SetOptions(mergeFields: [FieldPath(...)])`를 이용하며 다른 사용자 Map 및 표시용 Count를 변경하지 않는다.

### 12.6 목록 View 단일 조회·편집 시 Root 조회

계정 관리 목록은 선택 회사·지역의 `user_accounts_show/{division}-{area}` 문서를 단 한 번 GET하고 `UserAccountShowMap.validatedEntries()`로 `users` Map을 파싱한다. `usersMapComplete`를 읽거나 요구하지 않고 구형 `users` 하위 컬렉션으로 폴백하지 않는다. View가 없으면 `USER_ACCOUNT_VIEW_MISSING`, `users`가 Map이 아니면 `USER_ACCOUNT_VIEW_USERS_INVALID`를 반환하며 실제 빈 `users` Map은 직원 0명으로 처리한다.

운영 관리의 지역별 Future 캐시 최대 12개, 캐시 무효화·새로고침·오류 Future 제거 구조는 유지한다. 일반 계정 관리의 로컬 캐시는 회사·지역 조합을 키로 분리하고, View 서버 조회 성공 여부 및 조회 범위를 별도로 판정한다. 유효한 목록은 생성·수정 성공 후 로컬 갱신하며, 이전 목록이 유효하지 않을 때만 View를 다시 조회한다. 직원 목록의 검색·필터·행 선택은 로컬 처리한다. 별도 `상세 수정` 버튼을 누를 때만 Root `user_accounts/{userId}`를 조회하며, 원본 조회가 실패하면 편집기를 열지 않는다. Root의 근무시간·휴무일과 계정 코드 예약, 생성 3건 Batch는 유지한다.

활성 상태가 없는 Root를 복구하는 경우에는 현재 View Map만 참고하며 옛 `users` 하위 문서를 조회하지 않는다. 신규 계정 CRUD 및 관리 동작에서도 하위 `users` 레거시 경로는 사용하지 않는다. `documentGetRequests=1`과 `fromCache`를 구분해 계측하며 요청 수를 서버 청구량으로 단정하지 않는다.

### 12.7 개발자 모드 ON의 진단·클립보드·애니메이션

`AccountRoleDiagnostics.record`는 개발자 모드 ON일 때만 일반 권한 이벤트를 기록한다. `recordCreation`과 `recordList`는 개발자 모드 OFF에서도 비식별 생성·수정·목록 이벤트를 기록하고, 개발자 모드 ON에서 STATUS의 `debugPrint(...)` 코드로 복사할 수 있다. 사용자 목록 캐시는 요청 시작·1회/50회 재사용·완료·실패·범위 무효화·캐시 축출을 함께 기록하며 Firestore에 진단용 추가 조회를 만들지 않는다. `DeveloperOperationTrace` 역시 기존 STATUS 다이얼로그의 클립보드 복사 기능과 개발자 모드 재확인 절차를 그대로 사용한다. 신규 View 진단은 `view=map`으로 기록하고, 초기 개발 환경의 `dev_bootstrap_map_complete`는 생성·복구 문서 수를 기록한다. 이메일·원문 코드번호·인증정보를 새 진단에 기록하지 않는다.

| 진단 단계 | 의미 |
| --- | --- |
| 신규 생성 예정 진행 안내 | 검사 및 저장 이전, 성공 확정 아님 |
| `user_create_code_check reads=1 duplicate=false` | 해당 코드번호 예약 문서 검증 |
| `user_create_batch_start writes=3 view=map` | Root·예약·지역 Map 3개 문서 Batch 요청 |
| `user_create_batch_committed writes=3 view=map` | Batch 커밋 성공 |
| `user_show_map_read_complete` | 지역 Map 목록 파싱 완료, 레거시 병합 미사용 |
| `dev_user_map_list_loaded` | 개발자 계정 Map 목록 조회, 레거시 병합 미사용 |
| `dev_bootstrap_map_complete` | 최초 개발 환경 생성·복구의 계산상 문서 쓰기 횟수 |

기존 저장 진행률 및 STATUS Fade·Scale 애니메이션, 상태 `AnimatedSwitcher`, 입력 상태 문구 Fade·Slide, Root 상세 로딩 전환을 유지한다. 개발자 계정 목록의 지역 변경·새로고침에는 **Fade·Slide `AnimatedSwitcher`**를 추가하고, 기존 행별 `CommonAnimatedReveal` 및 원본 로딩 `AnimatedSwitcher`도 유지한다. `MediaQuery.disableAnimations`가 활성화되면 추가된 전환 시간이 0이 된다. 수정 Dart에는 주석을 넣지 않으며 `hintText`, `helperText`를 추가하지 않는다.

런처 개발자 로그인 성공·실패 시 별도 STATUS를 자동 생성하지 않고 `login_session_sync_succeeded`/`login_session_sync_failed` 진단만 기록한다. 인증창은 `launcher_auth_dialog_route_popped`와 `launcher_auth_dialog_overlay_removed`를 구분하고, `launcher_dialog_phase_changed ... closed` 이후 런처가 최상단일 때 대시보드 전환을 진행한다. 수동 STATUS가 위에 있다면 강제 닫지 않고 사용자가 종료한 뒤 `TransitionRoute.completed`까지 기다려 재개한다. `launcher_navigation_deferred`·`launcher_navigation_resumed`·`launcher_dashboard_navigation_requested`의 기록은 기존 개발자 STATUS의 `debugPrint(...)` 복사에 포함되며, 모드 ON 및 복사 직전 권한 검사 정책은 그대로 유지한다.

개발자 STATUS의 `debugPrint` 기록 건수 라벨에도 220ms Fade·Slide `AnimatedSwitcher`를 적용한다. 기록이 늘어날 때 라벨만 전환되며 기존 진행률·성공/실패·복사 버튼은 유지한다. `MediaQuery.disableAnimations`가 활성화되면 로그 건수 전환도 0ms로 처리한다. `AccountRoleDiagnostics`와 `DeveloperOperationTrace`가 수집한 코드는 개발자 모드 ON에서만 기존 STATUS 복사 경로로 제공하고, 복사 직전에 모드를 재확인한다.

### 12.8 비용·확장성·보안 유의사항

| 작업 | 과거 개별 View | 신규 중첩 Map |
| --- | --- | --- |
| 동일 지역 사용자 30명 전체 조회 | 30개 사용자 문서 읽기 | **`users` Map이 유효한 지역은 지역 문서 GET 1회** |
| 일반 계정 하나 신규 생성 | Root·코드·사용자 View 3 Writes | Root·코드·지역 Map 3 Writes |
| 계정 활성 상태 갱신 | Root + 사용자 View 2 Writes | Root + 지역 Map 2 Writes, 레거시 조회·삭제 없음 |
| 계정 수정·지역 이동·삭제 | 개별 하위 문서 처리 | Root·예약·Map 기준 검증과 부분 쓰기, 레거시 하위 요청 없음 |

2026-11-05에는 `user_accounts_show/{scopeId}` 최초 CREATE를 개발자 전용으로 제한했으나, 24장 이후의 현재 소스 `firestore.rules`는 개발자 이외의 Google 인증 사용자에게도 `users` 1개 항목과 `updatedAt`으로 구성된 제한적 최초 CREATE를 허용한다. UPDATE 역시 `users`·`updatedAt` 필드 수준의 제한만 있다. 이 조건은 업무 Role 4종·소속 지역·내부 사용자 Map 값을 서버에서 검증하지 못하며, `user_accounts`와 `user_account_codes`도 Google 인증에 따른 쓰기 허용을 유지한다. Custom Claims나 별도 서버 권한 저장소는 도입하지 않았으므로 앱 내부 Role 검사와 서버 직접 요청 보호를 동일시하지 않는다. 실제 서버에 Rules가 배포됐는지와 계정 CREATE/UPDATE 허용·거부는 별도 검증한다.

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
| `usersMapComplete` 없는 정상 View | `users` Map이 유효하면 View GET 1회로 목록 표시 |
| 사용자 관리 목록 Future 캐시 | 동일 지역 20회 재빌드에서 추가 목록 GET·QUERY 없음, Row 선택은 Root GET 0, 명시적 편집 진입에만 Root GET 1회 |
| 사용자 관리 빈 목록 | `users` 빈 Map은 정상 0명, View 누락·형식 오류만 구분 |
| 사용자 관리 새로고침 | 수동 아이콘 사용 시 현재 선택 회사·지역의 View GET만 다시 요청 |
| 계정 생성·수정 후 목록 갱신 | 서버 커밋 성공과 캐시 결과 분리, 유효한 목록은 추가 GET 0회, 불완전한 목록만 View 복구 GET |
| 허용 Role 4종의 일반·운영 관리 계정 생성 | 개발자 모드 OFF에서 앱 내부 검사 통과, 저장 성공 후 중복 제출 없음 |
| 거부 Role 3종의 계정 생성·수정 | 앱 내부에서 Firestore 호출 전에 거부, 서버 직접 접근의 별도 한계 명시 |
| 서버 저장 성공 후 로컬 캐시 실패 | 저장 성공을 실패로 안내하지 않음, 비식별 `cache_failed` 기록 |
| 기존 목록 오류 후 신규 생성 | 유효하지 않은 목록이면 View 복구 GET, 성공 시 오류 해제 |
| 동일 지역명·서로 다른 회사 | 로컬 사용자 캐시가 회사·지역별로 분리됨 |
| 사용자 목록 서버 조회 오류 | 실패 Future 자동 제거, 새로고침으로 재시도 가능 |
| 사용자 목록 진단 복사 | ON에서 시작·재사용·완료·무효화 진단을 STATUS `debugPrint(...)`로 복사 가능 |
| 기존 계정 상세 수정 | Root GET 후 근무시간·휴무 보존 |
| 회사·지역 삭제 | 현재 View Map 및 관련 Root에 계정이 남으면 차단, 레거시 QUERY 0회 |
| 개발자 모드 ON | STATUS의 `debugPrint(...)` 코드 복사에 Map 진단 포함 |
| 모션 감소 | 새로운 Fade·Slide 전환이 0ms로 처리됨 |
| 보안 및 비용 | Firestore Rules 허용·거부, 1MiB, 청구 리포트 확인 |

## 13. 지역별 계정 Map 스키마와 정합성

### 13.1 신규 스키마

`user_accounts_show/{division}-{area}`는 지역별 `users` Map을 포함한다. `users.{userId}`에 경량 Projection을 저장하며 구형 `users` 하위 컬렉션은 신규 읽기·쓰기·삭제 대상이 아니다. `usersMapComplete`는 현재 스키마에 필요하지 않다. `division`, `area`, 표시용 Count 3개, `updatedAt`은 회사·지역 생성 시 기록될 수 있으나 일반 계정의 제한된 최초 View CREATE는 `users`와 `updatedAt`만 기록한다. 목록을 읽는 데 필요한 공통 계약은 문서 존재와 `users is Map`이다.

### 13.2 Root·예약·View 쓰기의 정합성

Root는 근무시간·휴무 등을 포함한 전체 계정 원본이다. View는 목록 표시용 Projection이다. 생성에는 기존 Root·코드 예약·View의 3문서 Atomic Batch를 사용한다. 수정·이동은 Transaction으로 Root·예약·View의 사용자 항목을 동기화하고, 활성 상태 전환·삭제에서는 현재 View Map 항목의 존재와 예약 문서 소유자를 확인한다. `SetOptions(mergeFields: [FieldPath(['users', userId]), ...])`로 다른 사용자 Map과 Count를 덮어쓰지 않는다. 원본과 View 항목이 불일치하면 조용히 삭제하거나 새로 만들지 않고 오류로 처리한다.

### 13.3 데이터 정책

과거 데이터 이관, 구형 View 하위 문서 조회·삭제, `usersMapComplete` 완료 플래그 관리는 현재 리팩터링 범위에서 제외한다. 기존 운영 데이터를 자동 삭제하거나 전체 초기화하지 않는다. 신규 계정 관리 동작에서는 Root·코드 예약·현재 View Map의 일관성을 보장한다. 실제 Map이 빈 경우에만 계정 0명으로 처리하며 문서 누락과 타입 오류는 정상 빈 목록으로 위장하지 않는다.

### 13.4 검증 경계

계정 생성 허용 4개 Role의 UI 검사는 유지되지만 현재 `firestore.rules`는 해당 4개 Role을 서버에서 독립적으로 검증하지 못하므로 보안 보완이 별도로 필요하다. `firestore.rules` 파일 덮어쓰기만으로 서버에 배포되지 않는다. 신규 지역 생성·계정 생성·편집·이동·삭제·활성 전환, View 문서 누락·형식 오류, 단일 1MiB 문서 크기, 캐시 및 동시성 검증을 실환경에서 시험해야 한다. 정적 확인을 Flutter 컴파일·Firebase Emulator·실기기 검증으로 표현하지 않는다.

## 14. 구형 하위 View 수동 전환 — 과거 이력, 현행 미사용

이전 이관 절차와 `tool/migrate_user_accounts_show.mjs`는 25장 작성 당시의 호환성 설계였으며, **현재 26장의 신규 데이터 정책에서는 사용하지 않는다.** 신규 View Map의 목록 조회, 계정 수정·삭제, 지역·회사 관리에서는 구형 하위 사용자 컬렉션을 조회하지 않는다. 기존 데이터의 자동 이관과 삭제도 수행하지 않는다. 별도 수동 이관 실행이나 관리자 CLI 설치를 배포 전제 조건으로 요구하지 않는다.

## 15. 회사·지역 구조 변경 권한 개발자 전용 정책 — 2026-11-05

**이력 주의:** 이 15장은 2026-11-05에 작성된 당시 Rules 오버레이와 실행 상태의 기록이다. 당시의 `usage_daily` 정책 유지와 공개 `plates` 읽기 유지 설명은 **2026-11-06 easydev 최신 수정안에 적용되지 않는다**. 최신 유효 소스 설계는 7장과 16장을 우선 참조한다. 이 이력의 파일 작성 완료는 2026-11-06 수정안의 서버 게시 완료를 뜻하지 않는다.


### 15.1 정책 및 기존 계약

회사(`divisions`) 및 지역(`areas`) 문서의 생성·수정·삭제는 Firebase Authentication에서 검증된 `surge1868@gmail.com` 한 계정만 수행할 수 있어야 한다. 이전 개발자 허용 목록의 `qperfectusofficial@gmail.com`은 이번 버전에서 제외한다. 일반 업무 역할 7종에 `dev` 역할을 추가하지 않는다. Firebase 인증 UID를 업무 계정 문서 ID 또는 업무 accountId로 변경하지 않으며, Cloud Functions도 새로 도입하지 않는다. 기존 회사·지역 읽기 UX, 회사 생성 Transaction 3 GET·3 Writes, 지역 생성 Transaction 2 GET·2 Writes, 지역 수정 Transaction, 삭제 전 사용자 연관성 검사, 삭제 Batch, 개발자 초기화, 일반·개발자 계정 CRUD와 계정 Future 캐시는 유지한다. 앱 개발자 모드는 화면 접근 상태이며 서버의 보안 권한 증명으로 취급하지 않는다.

### 15.2 Flutter 코드 변경 전후

| 위치 | 이전 | 이번 수정 | 유의사항 |
| --- | --- | --- | --- |
| `lib/features/dev/application/developer_account_authorization.dart` | 허용 Gmail 2개 | `surge1868@gmail.com` 한 개 | Debug 승인 우회는 기존 개발자 UI 테스트 동작으로 유지하며 서버 권한을 의미하지 않음 |
| `lib/features/dev/application/developer_structure_write_guard.dart` | 없음 | 앱 개발자 모드·기존 승인 상태·현재 Firebase 사용자의 이메일·인증 토큰 `email` 및 `email_verified` 일치 검사 | 권한 검사는 Firebase 인증 토큰 조회로 수행하며 추가 Firestore GET·WRITE 없음 |
| `lib/shared/secondary/pages/sheets/area_management.dart` | 생성·삭제 함수는 상위 dev 화면 접근에 의존 | 회사 생성·삭제의 첫 Firestore 조회 전에 공통 개발자 권한 검증 | 기존 목록 조회, 중복 검사, 3문서 Transaction, 삭제 전 연관 계정 검사와 Batch 유지 |
| `lib/shared/secondary/pages/sheets/tabs/add_area_tab.dart` | 생성·수정·삭제 함수는 상위 dev 화면 접근에 의존 | 지역 생성·수정·삭제의 첫 Firestore 조회 전에 공통 개발자 권한 검증 | 기존 2문서 Transaction, 수정 Transaction, 삭제 검사와 Batch 유지 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | Google 승인 및 연결 계정 비교 | 개발 환경 초기화 실행 전 동일한 실제 Firebase 토큰 Gmail 검증 추가 | 초기화 도움말은 개발자 모드가 켜지기 전에도 실행 가능하므로 모드 자체가 아닌 기존 승인과 인증 Gmail을 검증 |
| 개발자 `STATUS` | 기존 진행·성공·실패 애니메이션 및 `debugPrint(...)` 복사 | 각 작업 Trace에 권한 확인 및 허용·거부 로그 추가, `AccountRoleDiagnostics`에도 인증 결과 기록 | 개발자 모드 ON에서만 진단 기록 수집 및 클립보드 복사 가능, 비밀 토큰은 기록하지 않음 |

회사 수정 UI는 현재 존재하지 않으므로 새로운 수정 화면을 추가하지 않았다. 향후 추가되는 회사 수정 함수도 동일한 공통 권한 검사와 서버 Rules의 `update` 제한을 적용해야 한다. `DeveloperStructureWriteGuard`의 클라이언트 검사만으로 Firestore 직접 SDK 요청을 막을 수는 없다. 실제 서버 보호는 배포된 Firestore Security Rules에 달려 있다.

### 15.3 프로젝트 루트 `firestore.rules` 전체 반영

2026-11-05 사용자가 기존 전체 Rules 텍스트를 제공했다. 제공 원본을 기준으로 프로젝트 루트에 **완전한 `firestore.rules` 파일을 신규 작성**했다. 파일은 독립된 Security Rules 원본이며, 내용 생략·주석 삽입 없이 다른 컬렉션의 기존 권한과 `usage_daily` 카운터 검증, 공개 `plates` 조회, 기본 거부 규칙을 유지했다. 이전에 이 소스 ZIP에 Rules가 없었다는 설명은 **1845 기준의 과거 상태**를 말한다. 이번 오버레이에는 Rules 원본이 포함된다.

| 보안 항목 | 기존 원본 | 신규 전체 파일 | 검증 상태 |
| --- | --- | --- | --- |
| 개발자 신원 함수 | 없음 | `_isDeveloper()`에서 Firebase 인증 토큰의 `email_verified`와 단일 Gmail 비교 | 파일 작성 |
| `divisions/{document=**}` | `read, write: _isSignedIn()` | `read: _isSignedIn()`, `create/update/delete: _isDeveloper()` | 파일 작성 |
| `areas/{document=**}` | `read, write: _isSignedIn()` | `read: _isSignedIn()`, `create/update/delete: _isDeveloper()` | 파일 작성 |
| `user_accounts_show/{scopeId}` | 모든 문서와 하위 경로 로그인 사용자 읽기·쓰기 | 최상위 create/delete 개발자 전용, update는 개발자 또는 `users`·`updatedAt` 한정, read 로그인 사용자 | 파일 작성 |
| `user_accounts_show/{scopeId}/users/{userId}` | 이전 재귀 허용 | 레거시 사용자 하위 문서의 로그인 사용자 읽기·쓰기 유지 | 파일 작성 |
| `user_accounts`, `user_account_codes` | 로그인 사용자 쓰기 | 유지 | 계정 업무 권한 별도 보강 필요 |
| 그 외 규칙 | 기존 사용자 제공 정책 | 변경 없음 | 프로젝트별 회귀 검증 필요 |

기존의 포괄적인 `allow read, write: if _isSignedIn()`을 동일 구조 문서 경로에 유지하지 않도록 **그 규칙 자체를 대체**했다. Rules는 일치하는 모든 `allow` 조건 중 하나라도 참이면 허용하기 때문이다. 단순히 `_isDeveloper()` 함수를 추가하는 것으로 보안이 강화되는 것은 아니다.

회사 생성은 `divisions/{division}`, `areas/{division}-{division}`, `user_accounts_show/{division}-{division}` 3문서를, 지역 생성은 `areas/{division}-{area}`, `user_accounts_show/{division}-{area}` 2문서를 하나의 Transaction으로 처리한다. 기존 중복 검사, 수정·삭제 전 계정 검사와 Batch를 변경하지 않는다. 1개 문서라도 Rules가 거부하면 해당 Transaction/Batch 전체가 실패한다. 따라서 권한을 허용할 실제 Firebase 계정이 `surge1868@gmail.com`이고 이메일이 검증됐는지 운영 테스트에서 확인해야 한다.

`_isAccountProjectionUpdate()`는 기존 메타 문서의 **최상위 필드 차이만** 검사한다. 회사·지역 메타 필드 변경은 막지만 로그인 사용자가 `users` Map 내부의 타 계정을 수정하지 못하도록 하는 Role 단위 검사는 아니다. `user_accounts_show` 상위 메타가 없는 기존 지역에서 일반 관리자가 신규 계정을 생성하면 Batch의 부모 create가 거부될 수 있으므로 사전에 메타를 개발자 경로로 준비해야 한다. 일반 계정 권한 강화는 이번 회사·지역 정책 범위 밖이며 별도 감사가 필요하다.

프로젝트 ZIP에는 `firebase.json`과 완전한 Flutter 빌드 루트가 없고, 현재 작업 환경에는 Firebase Rules 배포 권한/CLI 및 Emulator가 없다. **`firestore.rules` 파일을 덮어쓰는 것만으로 실제 서버가 변경되지 않는다.** 실제 Firebase 프로젝트와 배포 설정에서 Firestore Rules 원본 경로를 확인한 뒤 Emulator 및 실환경 회귀 테스트를 거쳐 게시해야 한다. 운영 배포 여부는 여전히 `미확인`이다.

### 15.4 비용 비교 및 사용자 경험

| 동작 | 기존 계측 | 변경 후 예상 |
| --- | --- | --- |
| 회사 생성 | 중복 확인 GET 3건 + 확정 Writes 3건 | 동일 |
| 지역 생성 | 중복 확인 GET 2건 + 확정 Writes 2건 | 동일 |
| 지역 수정 | 기존 Transaction 조회·수정 | 동일 |
| 지역·회사 삭제 | 연관 계정 검사 읽기 + 기존 Batch 삭제 | 동일 |
| 권한 비교 | 서버에서 dev 전용 조건 없음 | Rules에서 ID 토큰의 이메일/검증 상태 확인; 추가 Firestore 문서 GET 0건 |
| 앱 사전 검사 | 없음 | 현재 인증 토큰 확인; Firestore 문서 GET·WRITE 0건, 필요하면 Firebase Auth 토큰 갱신 네트워크 요청은 발생 가능 |
| 권한 거부 | 직접 Firestore 쓰기 허용 위험 | 앱에서 먼저 안내하고 서버에서도 직접 쓰기 거부 (Rules 실제 배포 후) |

개발자는 기존과 같은 입력·확인 Dialog, 모션 감소 지원, Transaction·Batch, 성공 후 목록 갱신을 사용한다. 일반 사용자는 기존과 같이 개발자 메뉴가 보이지 않으며, 실제 서버 Rules 배포 후에는 직접 SDK 경로로 회사를 생성·수정·삭제하거나 지역을 생성·수정·삭제할 수 없어야 한다. 개발자 모드 ON에서도 인증 이메일이나 Firebase 토큰이 다르면 데이터 변경을 중단한다. `permission-denied`와 네트워크 실패, 중복 이름 오류는 구별해 진단한다.

### 15.5 배포 및 회귀 검증

이번 제공물에서 확인 가능한 상태는 **1845 Flutter 사전 검사 구현 완료, 전체 Rules 작성 완료, README 내용 반영 완료**까지다. Firebase Console 게시·실제 권한 적용·실기기 STATUS Clipboard 및 모션은 별도 검증이 필요하다. 이미 제공된 Rules 수정안과 파일 구조가 일치하더라도 운영 DB가 이 권한을 사용하고 있다는 뜻은 아니다.

| 검증 항목 | 목표 결과 | 현재 상태 |
| --- | --- | --- |
| 허용된 개발자 Gmail 회사 생성·삭제 | 기존 3문서 생성 및 삭제 전 검증 정상 | 정적 코드 수정, 실환경 미검증 |
| 허용된 개발자 Gmail 지역 생성·수정·삭제 | 기존 생성·수정·삭제 및 애니메이션 정상 | 정적 코드 수정, 실환경 미검증 |
| 다른 Google/Firebase 이메일 | 회사·지역 구조 변경 거부 | 클라이언트 검사와 전체 Rules 작성 완료, 서버 배포 미확인 |
| Debug 모드 ON + 다른 Firebase 계정 | 구조 변경 거부 | 코드상 이메일·토큰 검사 구현, 단말기 미검증 |
| 개발자 초기화 도움말 | 허용된 인증 Gmail만 기존 구조를 초기화 | 코드상 검사 구현, 실환경 미검증 |
| `user_accounts_show` 초기 생성·삭제 및 일반 계정 Map CRUD | 구조 메타는 개발자 전용, 메타가 존재할 때 기존 Map 수정 허용 | Rules 작성 완료, Emulator/실환경 회귀 미검증 |
| STATUS `debugPrint` 복사 | 개발자 모드 ON에서 권한 검증·성공·오류 기록 복사 | 기존 복사 구현 재사용, 실기기 미검증 |
| Firestore 읽기·쓰기 비용 | 기존 GET·Write 횟수 유지, 불필요한 추가 GET 없음 | SDK·서버 비용 실측 미검증 |
| `flutter analyze` 및 Android 실행 | 구문·타입·화면·권한 회귀 검사 통과 | 이 환경에는 Flutter/Dart SDK가 없어 미실행 |

배포 순서는 프로젝트에 포함한 `firestore.rules`와 실제 서버의 Rules 내용·배포 경로 확인 → 원본 백업 → Firebase Emulator에서 허용 Gmail·일반 Gmail·익명·비로그인 요청 및 기존 계정 CRUD·Map 없는 지역 테스트 → 서버 Rules 게시 → 인증된 개발자 Firebase 토큰 재확인 → 앱의 회사·지역 생성·수정·삭제 실기기 시험 및 실제 Firebase Activity 사용량 확인이다. README의 기존 7장과 10~14장은 당시 설계 및 수정 이력을 보존하며 이번 15장은 신규 권한 강화 작업의 적용 범위와 배포 미확인 사항을 분리한 기록이다.

### 15.6 1845 Rules 오버레이 적용 결과와 주의사항

| 대상 파일 | 전체 파일 제공 여부 | 적용 방법 | 코드 변경 후 비용 |
| --- | --- | --- | --- |
| `firestore.rules` | 전체 279행, 주석 없음 | 실제 프로젝트 루트에 덮어쓰기, Firebase 배포 설정과 경로 연결 후 별도 게시 | 인증 이메일 Rules 비교로 추가 Firestore GET·WRITE 없음 |
| `README.md` | 기존 문서 전부 보존·수정, 새 정책 및 검증표 반영 | 프로젝트 루트에 덮어쓰기 | 없음 |
| 기존 1845 Flutter Dart | 이 오버레이에서 변경하지 않음 | 1845 상태 그대로 유지 | 기존 Transaction·Batch 그대로 |

기존 UI의 회사·지역 Dialog 및 목록 애니메이션, `DeveloperOperationTrace` STATUS 진입 Fade·Scale, 진행률·로그 건수 Fade·Slide·Scale 전환과 `MediaQuery.disableAnimations` 지원, 개발자 모드 ON의 `AccountRoleDiagnostics.record()` 및 STATUS `debugPrint(...)` 클립보드 복사 기능은 1845 소스에서 유지한다. 서버 Rules는 UI를 렌더링하지 않으므로 `firestore.rules`에 애니메이션 코드를 새로 넣지 않는다. 이 오버레이는 Dart 파일을 수정하지 않아 신규 주석·`hintText`·`helperText`도 추가하지 않는다.

**최종 판정:** 전체 Rules 및 README 파일 패치 **작성**, 정적 구조 검사 **통과**, Firebase Rules 컴파일·Emulator·운영 게시 **미완료**, 실기기 앱 회귀 **미검증**.

## 16. easydev Google 인증 기반 전체 Firestore Rules — 2026-11-06

### 16.1 목적과 적용 범위

이 수정안은 Firebase 개발 프로젝트 `easydev-97fb6`의 사용 중인 Firestore 컬렉션에 대한 **기존 허용 작업**에만 Google 기반 Firebase Authentication 인증을 필수로 요구한다. 프로덕션 프로젝트 `parkinworkin`은 대상에서 제외한다. 최종 서버 배포 상태는 확인 전이다.

- Firebase Authentication의 Google 로그인 제공자 `google.com`과 검증된 이메일 `email_verified == true`를 확인한다.
- Google 인증 사용자라는 사실만 확인한다. 실제 ParkinWorkin 업무 계정에 등록된 Gmail과 같은지를 Rules에서 조회하지 않는다.
- 일반 업무 Role 7종의 서버 접근 차등 제한과 회사·지역별 일반 업무 제한을 새로 도입하지 않는다.
- 회사·지역의 생성·수정·삭제는 기존의 단일 개발자 Gmail 전용으로 유지한다.
- Cloud Functions·Custom Claims·새 컬렉션·업무 accountId와 Firebase UID 매핑을 도입하지 않는다.
- Firestore DB 데이터, 기존 Flutter 계정 CRUD, Plate TTS, GCS 공개 이미지 정책 및 Firebase Storage Rules를 변경하지 않는다.

### 16.2 Rules 전체 변경 전후

| 구분 | 기존 제공 Rules | 최신 수정안 | 비고 |
| --- | --- | --- | --- |
| 공통 사용자 검사 | `request.auth != null` | `request.auth != null && request.auth.token.firebase.sign_in_provider == 'google.com' && request.auth.token.email_verified == true` | 다른 Firestore 문서 조회 없음 |
| 개발자 검사 | 검증 이메일 + `surge1868@gmail.com` | 공통 Google 인증 + 동일한 Gmail | 개발자 전용 작업 유지 |
| 일반 컬렉션 | 로그인 사용자 접근 허용 | Google 인증 사용자 접근 허용 | `allow read, write` 자체는 그대로 사용 |
| 상위 계정 View | 개발자 생성·삭제 및 `users`/`updatedAt` 부분 수정 | 기존 제한 + Google 인증 | 내부 Map 사용자별 Role 제한 추가 안 함 |
| `plates` 최상위·중첩 읽기 | 중첩 `plates` 공개 읽기 `true` | 인증된 Google 사용자만 읽기 | collection group 경로 보존 |
| `usage_daily` 카운터·이벤트 | 조건을 만족하면 신규 쓰기 허용 | 관련 match 2개와 검증 함수 7개 삭제 | 기본 거부 유지, 기존 데이터 삭제 없음 |
| 기본 거부 | `allow read, write: if false` | 유지 | 임의 경로 신규 개방 없음 |

`usage_daily` 관련 검증 함수는 `_isNumberOrNull`, `_hasOnlyCounterKeys`, `_pathMatches`, `_delta`, `_numCountersSetAtMostOne`, `_countersAreValid`, `_updatedAtIsOk`이다. 해당 7개 함수는 다른 컬렉션에서 사용하지 않는다. 기존 명시적인 카운터·이벤트 경로는 기본 거부한다. 전체 경로를 포괄하는 중첩 `plates` 읽기 규칙은 이름이 `plates`인 하위 문서에 별도 일치할 수 있으므로, 실제 `usage_daily`에 이러한 하위 경로가 있는 경우 별도 경로 감사가 필요하다.

### 16.3 비용·운영 영향

| 동작 | 변경 전 | 변경 후 |
| --- | --- | --- |
| 일반 Firestore 요청의 인증 검사 | 별도 종속 문서 GET 없음 | **추가 보안 확인용 READ 0건** |
| 차량 문서 1건 GET | 기존 데이터 조회 비용 | 동일, 인증 토큰만 비교 |
| 차량 목록 쿼리 및 Plate TTS 구독 | 기존 문서 읽기·구독 비용 | 동일한 요청 구조의 과금 정책, 부적격 인증 거부 가능 |
| 일반 계정 생성 | 기존 3문서 Batch | 기존 코드 변경 없음, 정상 인증·기존 메타 조건에서 동일 |
| 회사·지역 Transaction/Batch | 개발자 권한에 의존 | Google 인증된 개발자 토큰 필요, 기존 문서 수 보존 |
| 미사용 `usage_daily` | 일부 이벤트·카운터 기록 허용 | 클라이언트 기록 거부, 기존 문서 그대로 |
| Functions 실행 | 없음 | 신규 도입 없음 |

토큰의 조건 비교 자체는 Firestore 종속 문서 `get()`·`exists()`·`getAfter()`를 호출하지 않는다. 단, 실제 업무 데이터 읽기·쓰기·삭제, 실시간 구독 재연결, 인증·App Check 및 서비스별 과금은 별개다. Rules로 거부되는 신규 요청은 앱 로직에 따라 오류 처리되므로 실제 정상 업무 호환성을 시험해야 한다.

### 16.4 사용자 경험·기존 UI 보호

- Google 기반으로 Firebase Authentication에 인증돼 있고 이메일이 검증된 정상 사용자는 기존 로그인 화면과 앱 세션을 그대로 사용한다. 작업마다 Google 로그인을 반복하지 않는다.
- 앱의 계정 이메일 일치 검사는 그대로 유지되지만 서버 Rules가 그 결과를 알게 되는 것은 아니다. 미등록 Google 사용자에 대한 서버 접근 제한이 완성됐다고 기록하지 않는다.
- 기존 디버그 개발자 로그인 경로의 Firebase 익명 인증은 Google 제공자가 아니므로 신규 Rules에 의해 일반 데이터 작업이 거부될 수 있다. 개발자 모드 ON 자체는 서버 인증을 우회하지 않는다.
- 개인·태블릿 계정도 Firestore에 접근하는 Firebase 인증 경로가 Google 제공자를 사용하지 않는다면 거부될 수 있다. 앱의 해당 로그인 경로를 확인해야 한다.
- 기존 플로팅 안내, Dialog, 헤더·Activity Center 표시, Fade·Scale·Slide·AnimatedSwitcher·모션 감소 지원 애니메이션은 이번 패치에서 변경하지 않는다. 이 규칙 변경으로 새 UI를 만들거나 `hintText`·`helperText`를 추가하지 않는다.
- `lib/app/utils/developer_operation_status_dialog.dart`의 개발자 모드 ON 진단 Trace, `debugPrint(...)` 코드 생성 및 `Clipboard.setData` 복사 기능과 `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart`의 STATUS·저널 병합 복사 기능을 그대로 유지한다. 서버 Rules의 직접 외부 요청이 해당 앱 STATUS에 자동 기록되는 것은 아니다.
- 앱에서 권한 거부가 발생하면 기존 Flutter 호출의 오류가 반환될 수 있다. 별도의 Dart 오류 메시지·로그 개선 코드는 이번 파일 변경에 포함하지 않는다.

### 16.5 App Check와 서비스별 경계

2026-11-06 사용자가 제공한 easydev Firebase Console 화면에는 Cloud Firestore App Check가 **적용됨**으로 표시됐고 확인된 요청이 관측됐다. 같은 화면의 Storage는 **적용되지 않음** 상태다. 스크린샷으로 확인한 개발 프로젝트 Firestore 강제 적용은 이 Rules 변경과 독립된 보안층이다. 이 기록은 프로덕션 App Check 상태나 GCS 공개 URL의 보호를 뜻하지 않는다.

### 16.6 배포 및 회귀 검증

실제 게시 전에 Firebase Console에서 `easydev-97fb6` 프로젝트가 선택돼 있는지 확인하고 기존 Rules를 백업한다. `firestore.rules`의 컴파일 및 Emulator 또는 Rules Playground 시험, 개발자 Gmail 회사·지역 Transaction, 일반 계정 3문서 Batch, 중첩 `plates` collection group 및 Plate TTS, 개인·태블릿 로그인, 개발자 디버그 익명 인증 차단 영향, 사용 종료된 `usage_daily` 경로 거부를 순서대로 확인한다. 실제 Firebase Console에서 별도로 Rules를 게시한 뒤 재시험한다. 프로덕션 프로젝트는 수정하지 않는다.

| 확인 항목 | 이번 수정 제공물의 상태 |
| --- | --- |
| 기존 전체 Rules 기반 전체 파일 작성 | 완료 |
| 기존 전체 README 보존 및 최신 정책 반영 | 완료 |
| Flutter Dart 파일 수정 | 없음 |
| Cloud Functions·Custom Claims·UID 매핑 도입 | 없음 |
| 신규 Rules의 정적 경로·제거 대상 점검 | 수행 |
| Firebase Rules 컴파일·Emulator 실행 | 미수행 |
| 개발 프로젝트 Rules 실제 게시 | 미수행 |
| Android 실기기 로그인·차량·관리·STATUS 회귀 테스트 | 미수행 |

**최종 판단:** 이 작업은 기존에 허용된 Firestore 경로의 Google 인증 조건을 강화하고, 공개 `plates` 읽기와 미사용 `usage_daily` 쓰기 허용을 제거하는 정적 파일 수정이다. 미등록 Google 사용자와 등록된 내부 직원의 악의적 변조까지 막는 최종 업무 신원 검증은 포함하지 않는다.


## 17. Firestore 인증·요청·Rules 관측 진단 — 2026-11-06

### 17.1 범위 및 원칙

현재 프로젝트 루트 `firestore.rules` 148행을 유지하고, 그 파일의 SHA-256 앞 16자는 `e998c52342c2aeee`이다. 이 식별자는 로컬 소스 기준이며 Firebase 운영 서버에 동일 Rules가 배포되었음을 보증하지 않는다. 기존 1~16장과 과거 Rules 변경 이력은 삭제하지 않는다. 진단은 `DEBUG 모드 ON → STATUS → debugPrint 코드 복사`에 결합한다. Google 인증 방식, 업무 CRUD, Firestore 문서 스키마와 서버 Rules 자체는 바꾸지 않는다.

### 17.2 인증 진단

- `lib/app/diagnostics/firebase_auth_rules_diagnostics.dart`: `FirebaseAuth.instance.currentUser.getIdTokenResult()`를 조회하여 `signInProvider`, `email_verified`, ID 토큰 이메일의 개발자 주소 일치 여부를 별도 원천 `[FIREBASE_AUTH_AUDIT]`으로 기록한다. 개발자 주소를 비롯한 이메일 원문·UID·ID 토큰 값은 신규 로그에 저장하지 않는다.
- Firebase 인증은 클라이언트의 조건 비교(`CLIENT_TOKEN`)이며 Rules의 서버 승인 결과가 아니다. 값이 없거나 검사에 실패했으면 임의로 성공으로 처리하지 않는다.
- Firebase 인증 Bridge의 로그인 성공·기존 세션 재사용·개발용 익명 로그인·로그아웃에서 개발자 모드가 ON일 때 인증 진단을 갱신한다. STATUS 열기와 복사 시에도 갱신한다. 인증 결과 캐시는 동일 UID에 한해 최대 10분 동안 정책 예상에 사용하며, UID 변경·검사 실패 시 사용하지 않는다.
- 인증 진단 로그는 메모리 최대 240행이며 `debugPrint(...)` 문자열로 STATUS 복사에 포함된다. 개발자 모드가 OFF면 진단 출력이 발생하지 않는다.

### 17.3 Firestore 요청 추적

- `lib/app/diagnostics/firebase_activity_meter.dart`: 계측된 Future의 요청마다 `requestId`를 생성하여 `operation`, `source`, `result`, `firebaseCode`, `collection`, `pathTemplate`, `responseSource`를 연결한다. `FirebaseException.code`가 없으면 `firebaseCode`를 임의 생성하지 않는다.
- 원래 `trackFirestore(operation, source)` API는 그대로 허용하며 정확한 컬렉션을 알 수 있는 호출부에만 `collection:` 및 필요한 경우 `pathTemplate:`을 전달한다. 문서 읽기가 성공하면 반환된 `DocumentSnapshot.reference.path`에서 개인정보가 포함된 문서 ID를 `*`로 바꾼 경로 템플릿과 최상위 컬렉션도 추출한다. 쿼리 결과 문서만으로 쿼리의 원본 경로를 추측하지 않는다. 콜사이트가 제공하지 않으면 누락값은 `UNKNOWN`으로 처리하고 특정 컬렉션을 추측하지 않는다.
- `runFirestore(action: ...)`는 Future 생성 이전부터 추적할 필요가 있는 신규 호출을 위한 옵션이다. 계측되지 않은 직접 SDK 호출과 별도 Isolate 내부 요청은 자동 추적 대상이 아니다.
- `FirebaseActivityJournal`의 JSONL 신규 기록은 `schemaVersion=3`이고 과거 `schemaVersion=2` 비용 합산을 유지한다. Activity Center 보관·복사·COST 계산 방식은 유지하며, `security/RULES_COMPARE` 이벤트는 Firestore 읽기·쓰기 과금 수치에 더하지 않는다.
- 기존 Batch Wrapper 및 Transaction Wrapper는 커밋 실패 이벤트를 추가 기록한다. 기존 확정 쓰기 수 계산을 유지한다. `Future.trackFirestore`로 별도 중복 계측하는 호출의 기존 문제는 이 작업만으로 제거되지 않는다.

### 17.4 Rules 예상 정책과 관측 결과 비교

- `lib/app/diagnostics/firestore_rules_audit.dart`: 현재 제공된 Rules의 공통 Google 제공자·이메일 검증, 개발자 전용 areas/divisions, user_accounts_show 루트의 특수 필드 업데이트, 중첩 users, 공통 업무 컬렉션과 plates 읽기 정책을 해석한다.
- 계측 정보가 부족한 경우 `expected=UNKNOWN`을 반드시 사용한다. SET의 CREATE/UPDATE 불확실성, Batch/Transaction의 문서별 조건, 컬렉션 미지정, 미검증 세션, 로컬/운영 Rules 버전 불일치는 정상 판정으로 간주하지 않는다.
- 서버 SDK 성공과 `permission-denied`는 관측된 결과만 의미한다. `fromCache=true`는 서버 승인 여부를 검증하지 않으며, 클라이언트 단독으로 Rules의 실제 거부 원인을 특정할 수 없다.
- `[FIREBASE_ACTIVITY]`와 같은 `requestId`로 `[FIREBASE_ACTIVITY] service=security operation=RULES_COMPARE` 이벤트를 보관한다. 비교 결과는 `CONSISTENT`, `UNEXPECTED_ALLOW`, `UNEXPECTED_DENY`, `NOT_VERIFIED`로 구분한다.

### 17.5 STATUS 및 UI

- `parkinworkin_terminal_diagnostics.dart`에서 인증 진단 240행을 기존 메모리 원천에 추가하며, 복사 직전에 토큰 검사를 갱신한 뒤 기존 Journal을 결합한다.
- `status_dialog.dart`의 기존 복사 버튼과 개발자 모드 복사 전후 재검사를 유지한다. 인증 상태와 최근 Rules 비교 건수를 별도 보안 진단 카드에 표시한다. 카드 페이드·슬라이드·컨테이너 전환 애니메이션은 기존 `CommonUiMotion`과 `MediaQuery.disableAnimations` 설정에 따라 적용한다. 힌트 텍스트는 추가하지 않는다.
- 기록 원천의 순서와 보관 기한, 메모리 상한, 개인정보 마스킹 정책은 기존 설계에 따른다. 기존 DEBUG 콘솔 출력 전체가 자동 수집되는 것은 아니다.

### 17.6 검증·배포 경계

- 신규 `test/firestore_rules_audit_test.dart`는 인증 거부, 개발자 쓰기, 계정 View 필드 제한, 캐시, 정상 거부, 예기치 않은 허용을 순수 정책 비교로 검증하도록 작성하였다. `test/rules/firestore.rules.test.cjs`, `firebase.json`, `package.json`에는 Firestore Emulator용 서버 Rules 허용·거부 테스트와 `npm run test:firestore-rules` 실행 계약을 작성하였다. Emulator 포트는 8080이다.
- 이 환경에는 Flutter/Dart 실행 바이너리가 없어 테스트 실행, `flutter analyze`, Android 컴파일 및 기기 클립보드 실측은 수행하지 않았다. 따라서 해당 결과는 **미검증**이다.
- Firestore Emulator의 실제 Rules 평가, 운영 프로젝트의 배포 Rules 버전·App Check 정책 검증 역시 미수행이다. 운영 데이터에서 거부 정책 테스트를 수행하지 않는다.
- 루트 Rules는 수정하지 않았다. 기존 README 15장에 있는 과거 Rules 행 수는 과거 버전 이력이며 현재 제공본은 148행이다.

## 18. Firestore Rules 진단 정확도 보완 — 2026-11-06 1449 기준 후속 리팩터링

### 18.1 기준 및 변경 범위

이번 절은 17장의 1차 진단 구현을 대체하지 않고 그 이후의 보완 내역을 기록한다. 기준 소스는 사용자가 제공한 `261106 1449.zip`이며, Rules의 기준 원문은 사용자가 별도로 제공한 `rules_version = '2'`의 148행 정책이다. 서버 Rules의 Google 제공자·이메일 검증·개발자 전용 쓰기·계정 View 필드 제한·중첩 plates 읽기·기본 거부 정책은 변경하지 않는다. 1449 ZIP에는 루트 `firestore.rules`와 `pubspec.yaml`이 포함되지 않았으므로 이 파일이 필요한 Flutter 빌드·Firebase CLI 사용 시 별도로 정확한 원본을 구성해야 한다. 본 덮어쓰기 패키지에도 원본 Rules와 변경하지 않은 설정 파일을 중복 포함하지 않는다.

이번 리팩터링은 `FirestoreRulesAudit`, `FirebaseActivityMeter`, `FirebaseAuthRulesDiagnostics`, 계정 관리·차량·지역·근무 보고 관련 Firestore 호출부, STATUS 보안 진단 카드 및 이 README를 수정한다. 업무 CRUD의 실제 쓰기 대상·데이터·사용자 역할·Rules 배포 상태는 바꾸지 않는다.

### 18.2 계정 View의 CREATE·UPDATE·DELETE 진단

`user_accounts_show/{scopeId}`의 생성과 삭제는 개발자 인증이 필요하다. 일반 Google 인증 사용자의 UPDATE는 Firestore Rules가 계산한 `request.resource.data.diff(resource.data).affectedKeys()`가 `users`와 `updatedAt`에 한정될 때만 허용된다. `user_accounts_show/{scopeId}/users/{userId}`는 별도 일반 Google 인증 허용 경로이다.

`SET`의 `merge` 또는 `mergeFields`만으로는 기존 문서 존재를 확정할 수 없다. 일반 사용자의 해당 View 문서 병합 SET은 문서가 없으면 CREATE이므로 `DENY`이고, 기존 문서가 확인되고 변경 필드가 허용 범위에 한정되면 `ALLOW`이다. 존재 여부를 확인할 수 없으면 `UNKNOWN`이다. 계정 등록 Batch에 진단을 이유로 새로운 Firestore 사전 읽기를 발생시키지 않는다.

명시적으로 전달한 `changedKeys`는 실제 변경된 최상위 필드 집합으로 취급한다. 자동 계측에서 쓰기 Payload의 필드 이름만 아는 경우 실제 `affectedKeys()`를 모두 알 수 없으므로, 허용된 두 최상위 필드만 건드리는 병합 SET·UPDATE는 허용 후보로 계산하되 다른 필드가 포함되면 확정된 DENY로 간주하지 않고 `UNKNOWN`으로 둔다. 원격 서버에서 실제로 어떤 조건이 거부를 일으켰는지는 SDK 실패만으로 단정하지 않는다.

### 18.3 Batch·Transaction 문서별 진단

`FirebaseActivityWriteBatch`는 `set`, `update`, `delete`를 등록할 때 대상 문서의 경로 템플릿, 작업 유형, 확인 가능한 변경 필드만 메모리에 기록한다. 커밋 성공 또는 실패 후 각 항목을 `service=security operation=RULES_ITEM`으로, 묶음의 전체 예상·관측 결과를 `operation=RULES_COMPARE`로 기록한다. 같은 `requestId`를 사용하며 원본 문서 ID나 Payload 값을 출력하지 않는다. 일부 항목이 확정 DENY이면 묶음의 예상도 DENY이고, 확정 DENY는 없지만 UNKNOWN이 있으면 전체 예상은 UNKNOWN이다.

`runTrackedActivityTransaction()`은 실제 트랜잭션을 위임하는 추적 래퍼를 사용한다. 이 래퍼는 `get` 결과의 문서 존재 상태와 `set`·`update`·`delete` 대상 경로를 트랜잭션 시도별로 수집한다. 재시도 중간 단계의 쓰기를 중복 확정하지 않고 최종 결과에 대응하는 마지막 시도의 항목을 기록한다. 기존 코드의 `STAGE_*` 이벤트와 기존 확정 쓰기/삭제 집계는 유지하되 추적 래퍼가 활성화된 트랜잭션에서 동일 수를 이중 합산하지 않는다. 실제 실패 문서가 특정되지 않으면 항목 로그는 예상 정책 후보일 뿐 서버의 원인 확정 기록이 아니다.

기존 원본 `runTransaction()`·`batch()`를 직접 호출하는 코드 및 `trackFirestore()`가 감싸지 않은 SDK 요청은 이 문서별 추적의 대상이 아니다. 전체 코드베이스의 모든 Firestore 요청을 추적한다고 주장하지 않는다.

### 18.4 요청 경로 메타데이터

수정된 계정 관리·차량·지역·근무 보고 Repository의 정적으로 확인 가능한 쿼리·문서 조회에 `collection`과 `pathTemplate`을 전달한다. 일반 조회 쿼리는 `QUERY`로 구분하고, 문서 경로 템플릿은 `user_accounts/*`, `user_accounts_show/*`, `user_accounts_show/*/users/*`처럼 실제 문서 ID를 `*`로 치환한다. Batch와 추적 Transaction은 SDK의 실제 DocumentReference 경로를 사용하므로 실패 후에도 대상 패턴을 확인할 수 있다.

성공한 DocumentSnapshot의 실제 경로 추출 기능은 기존대로 유지한다. 호출부에서 경로를 확보하지 못한 Query·리스너·Future는 추측하지 않고 미확인으로 기록한다. 계정 관리 호출부 외의 모든 미명시 요청에 대한 일괄 전환은 포함하지 않는다.

### 18.5 인증 스냅샷과 정확한 개발자 비교

ID 토큰의 이메일은 `request.auth.token.email == 'surge1868@gmail.com'`과 동일하게 원문 문자열로 비교한다. 이메일 대소문자 변환이나 앞뒤 공백 제거를 개발자 여부 판정에 사용하지 않는다. 기존 Google 로그인·익명 로그인·로그아웃 절차는 변경하지 않는다.

개발자 모드 ON에서 계측 시작 시 확인 가능한 인증 스냅샷을 요청에 연결하고, 요청 완료 시 다른 UID로 바뀌었다면 정책 비교 결과를 `AUTH_CHANGED` 및 `NOT_VERIFIED`로 표시한다. 스냅샷이 없거나 오래됐으면 `expected=UNKNOWN`이다. 이미 생성된 Future에 `.trackFirestore()`를 부착하는 API의 캡처 시점은 부착 시점이며, 이것이 서버가 실제 평가한 ID 토큰과 동일함을 보증하지 않는다. 필요 시 실행 함수를 받는 `runFirestore()`를 사용해 계측 전에 캡처한다. 클라이언트 토큰 스냅샷은 서버 Rules의 배포 버전이나 실제 거부 조건의 증명이 아니다.

### 18.6 전체 경로·중첩 plates·기본 거부

Rules 예상 계산에서는 정확하게 식별된 `pathTemplate`의 최상위 컬렉션, 경로 깊이, 중첩된 `plates` 컬렉션 및 계정 View 하위 `users`를 검사한다. 다른 허용 규칙에 일치하지 않는 확정된 경로는 기본 거부(`DENY`)를 예측한다. 예를 들어 `unknown_collection/*`는 거부 대상이고 `unknown_collection/*/plates/*` 읽기는 Google 인증 조건을 충족하면 허용 대상이다. 경로가 확인되지 않은 경우에는 무조건 DENY로 바꾸지 않고 `UNKNOWN`을 유지한다.

정책 비교의 출력은 `expected`, `observed`, `comparison`, `verification`으로 분리한다. 캐시 읽기(`CACHE_ONLY`), 호출 전 동기 예외(`NOT_SENT`), 인증 세션 변경(`AUTH_CHANGED`), 정보 부족은 정상 서버 검증으로 표시하지 않는다. 실제 Firebase SDK의 `permission-denied`는 관측된 오류이며 어느 Rules 조건의 평가 결과인지를 직접 반환하지 않는다.

### 18.7 DEBUG STATUS·복사·애니메이션

`DevAuth.devModeEnabled` 및 비동기 `DevAuth.isDevModeEnabled()` 검사를 유지한다. 개발자 모드 ON에서 `ParkinWorkinTerminalDiagnostics.showStatus()`를 통해 STATUS를 열고 `debugPrint 코드 복사`를 누르면 `debugPrintCodeWithJournal()`이 인증 진단, 기존 메모리 원천, Firestore Activity 저널의 `RULES_ITEM`, `RULES_COMPARE` 기록을 결합하여 `debugPrint(...)` 형태로 클립보드에 전달한다. 복사 전후 개발자 모드 검사는 유지한다. 모든 콘솔 출력이 별도 자동 수집되는 것은 아니다.

`StatusDialog`의 기존 페이드·스케일·슬라이드·컨테이너 전환 효과는 유지하고 보안 진단 텍스트에 `AnimatedSize`, `AnimatedSwitcher`, 페이드 및 슬라이드 전환을 추가한다. `MediaQuery.disableAnimations`가 참이면 해당 전환 시간을 0으로 처리한다. 신규 `hintText`·`helperText`, 화면 안내 문구, 코드 주석을 삽입하지 않는다.

### 18.8 계측 성능·보안 경계

진단 목적의 Firestore 읽기·쓰기 요청은 추가하지 않는다. Batch·Transaction의 문서 참조 및 일부 기존 GET 결과를 메모리에서 사용하며, 경로 출력에서 문서 ID와 Payload 값은 제외한다. 기존 Firebase Activity Journal의 JSONL 스키마와 비용 집계 계약은 유지한다. 신규 보안 이벤트는 `service=security`로 저장하여 Firestore READ/WRITE 과금 요약에 산입하지 않는다. 과거 저널의 보관·기록 유실 가능성은 기존 계약과 동일하다.

### 18.9 회귀 검증 대상

| 검증 항목 | 기대 결과 |
| --- | --- |
| Google 인증·이메일 미인증·익명 인증 | 기존 Rules의 공통 인증 조건을 반영하고 미검증 정보는 UNKNOWN |
| 개발자 이메일 대소문자 차이 | Rules와 동일한 정확 문자열 비교 |
| 계정 View 기존 문서의 허용 필드 병합 SET | 존재 확인 시 예상 ALLOW |
| 계정 View 최초 생성 | 일반 Google 사용자 예상 DENY |
| 계정 View 존재 불명 병합 SET | 예상 UNKNOWN |
| 실제 `affectedKeys`에 제한 외 필드 포함 | 정확한 변경 필드가 확보되면 예상 DENY |
| Batch의 문서별 정책 및 최종 커밋 | 항목별 후보와 전체 결과를 동일 requestId로 추적 |
| Transaction 재시도·실패 | 마지막 시도의 후보와 최종 결과를 구분하며 확정 쓰기 중복 집계 금지 |
| 쿼리 실패·중첩 plates·미정의 경로 | 확인된 경로에서만 정책 계산 |
| 인증 계정 전환 중 요청 완료 | AUTH_CHANGED, NOT_VERIFIED |
| 캐시 조회 및 SDK 동기 예외 | CACHE_ONLY 또는 NOT_SENT |
| DEBUG ON → STATUS 복사 | 인증·Rules·기존 로그를 debugPrint 구문으로 클립보드 복사 |
| DEBUG OFF·모션 감소 | 복사 차단 및 애니메이션 비활성화 |

### 18.10 검증 상태와 전달 파일

이번 제공물은 변경된 전체 Dart 파일과 README만 포함하는 덮어쓰기용 오버레이이다. 원본 1449 ZIP의 나머지 파일, `firebase.json`, 별도로 제공된 `firestore.rules`, 예전에 작성된 선택적 JavaScript/Dart Rules 테스트 파일은 넣지 않는다. 기존 README 1~17장은 원문 그대로 유지한다. 코드 경로·수정 대상·주석·힌트 텍스트·괄호 및 상대 import 구조는 정적으로 검사한다. 이 환경에 Flutter/Dart SDK가 없고 1449 ZIP에는 `pubspec.yaml`이 없으므로 `flutter analyze`, Flutter 테스트, Android 빌드, 실기기 STATUS 복사, Firebase Emulator 및 운영 Rules 배포 확인은 **미수행·미검증**이다. 실제 실행 검증 없이 운영 배포 완료라고 기록하지 않는다.

## 19. Firestore Rules 진단·STATUS 실시간 갱신 보완 — 2026-11-06 1549 기준

### 19.1 변경 목적 및 보호 범위

이번 변경은 사용자가 제공한 `261106 1549.zip`을 기준으로 하고, 1~18장의 원문 기록과 서버 Firestore Rules 정책을 변경하지 않는 후속 작업이다. 기존 계정·지역·차량·업무 데이터의 생성·조회·수정·삭제 동작을 유지한다. 진단만을 위한 Firestore 읽기·쓰기 호출을 추가하지 않는다. 신규 화면 힌트 문구, 코드 주석, 별도 STATUS 복사 버튼을 만들지 않는다. 개발자 모드 ON인 경우에만 기존 STATUS에서 인증·요청·Rules 진단의 `debugPrint(...)` 구문을 복사하는 기능을 유지한다.

### 19.2 View 문서 존재 및 Batch·Transaction 판정

최상위 `user_accounts_show/{scopeId}`는 현재 Rules상 CREATE·DELETE가 개발자 전용이고, 일반 Google 인증자의 UPDATE는 변경 후 상위 필드 차이가 `users`, `updatedAt`에 한정되어야 한다. `set(merge: true)`는 대상 문서 존재 여부에 따라 CREATE 또는 UPDATE가 되므로 SET 자체만으로 권한을 확정하지 않는다. 계정 생성의 3건 Batch는 기존과 동일하게 실행하며 View 최초 생성 권한에 따른 실패 가능성도 바꾸지 않는다.

`FirebaseActivityWriteBatch`는 등록된 문서 참조로 경로 패턴과 작업 종류를 기록한다. `observeDocument(snapshot)`은 업무에서 이미 확보한 Snapshot만 선택적으로 받을 수 있다. Batch 이전 Snapshot은 커밋 시점의 서버 상태를 보장하지 않으며 `documentEvidence=PREEXISTING_SNAPSHOT`, `fieldEvidence=PRIOR_SNAPSHOT_DIFF`와 같이 추정 근거로 기록한다. Snapshot이 없으면 `documentExists=unknown`으로 둔다. 기존 계정 View 비밀번호 정리 경로는 미리 조회된 View Snapshot을 재사용한다. 계정 신규 등록 시 View를 추가 조회하지 않으므로 존재 여부 불명은 계속 `UNKNOWN`이 가능하다.

`runTrackedActivityTransaction()`은 같은 Transaction 시도 안에서 `get`으로 확인한 문서의 존재 여부와 변경 전 Map을 이용한다. 문서별 쓰기 범위, 가능한 경우의 변경 전후 차이, 전체 커밋 결과를 연결한다. 같은 시도에서 동일 문서에 여러 쓰기가 발생하면 최초 읽기 상태로 이후 쓰기의 실제 차이를 확정하지 않는다. 재시도 중간 단계의 쓰기 수를 확정 쓰기로 중복 집계하지 않는다. 일반 SDK의 `runTransaction()`·`batch()`에 대한 추적 범위는 기존 한계를 유지한다.

### 19.3 Firestore 경로 기록 확대

이전 1549 소스에서 `.trackFirestore()` 호출 302곳 가운데 `collection:` 명시 호출은 131곳이었다. 이번 변경은 참조 대상이 확인된 102곳에 `collection` 및 경로 정보를, 추가 8곳에 `documentReference`를 연결했다. 현재 302곳 중 명시 컬렉션 233곳, 문서 참조로 식별하는 호출 8곳이며, 나머지 61곳은 단일 대상 경로를 명시하지 않는다. 전체 경로가 확인되지 않는 다중 컬렉션 Batch·Transaction 전체 결과는 하나의 컬렉션으로 임의 지정하지 않는다. 기존에 쓰이던 `operation`, `source`, `requestId`, `firebaseCode`는 유지한다. 문서 ID는 `*`로 치환하며 데이터 본문·검색값을 새 로그에 저장하지 않는다.

경로를 얻을 수 있는 문서 참조는 `documentReference:`로 전달하고, 요청 실패 후에도 추적 대상 패턴을 남긴다. 기존 문서 GET 성공 시 Snapshot 참조에서 경로를 추출하는 동작과 리스너 계측을 유지한다. 차량의 동적 View 컬렉션은 호출자가 실제 전달한 컬렉션명을 기록하며, 다수 컬렉션을 함께 쓰는 Transaction에는 잘못된 단일 경로를 부여하지 않는다. `trackFirestoreSnapshots()`의 차량 View·월정기 구독에는 실제 구독 컬렉션도 연결한다. 일부 호출은 여전히 명시 경로가 없어 요청별 `UNKNOWN`이 가능하다.

### 19.4 `affectedKeys()` 비교 근거 구분

`FirestoreRulesAudit.affectedKeysFromKnownState()`는 이미 확보된 변경 전 Map과 쓰기 Payload가 모두 확인되고, 결과를 안전하게 재구성할 수 있는 일부 작업에 한해서 최상위 변경 키 차이를 계산한다. 문서 전체 SET의 삭제된 필드도 계산 범위에 포함한다. 병합 SET의 중첩 Map, 단순 UPDATE, Map·List의 일반 값 비교를 구분한다. `FieldValue.serverTimestamp()`, `FieldValue.delete()`, `arrayUnion()` 등 서버 변환과 복잡한 필드 경로를 포함하여 정확한 결과를 복원할 수 없는 경우에는 실제 변경 필드라고 주장하지 않는다.

변경 전 문서가 없거나 변환 결과가 불명확할 때에는 Payload가 허용 필드만 건드리는 범위를 `WRITE_SCOPE`로 기록한다. 이는 실제 `affectedKeys()` 전체를 직접 확인한 결과가 아니라 허용 필드의 상한 범위를 설명하는 근거이다. 변경 필드를 계산하지 못하는 경우에도 임의로 `DENY`라고 확정하지 않는다. 보안 감사 이벤트에서는 `fieldEvidence`, `documentEvidence`, `changedKeysKnown`과 `expected`를 구별한다. 클라이언트의 추정은 서버가 거부한 정확한 원인을 증명하지 않는다.

### 19.5 DEBUG STATUS 진단 카드 갱신

기존 `FirebaseActivityMeter.summary`는 약 120ms로 알림을 묶어서 발생시킨다. STATUS가 열린 동안 이 알림과 `FirebaseAuthRulesDiagnostics.revision`의 인증 진단 변경 알림을 구독한다. 인증 상태 및 최근 메모리 범위의 Rules 비교 집계를 다시 계산하여 `StatusDialog` 보안 카드에 전달한다. 다이얼로그가 닫히면 등록된 구독을 해제한다. 변경된 요약은 기존 `AnimatedSwitcher`, `AnimatedSize`, Fade·Slide·Scale 및 `CommonUiMotion`의 전환을 사용하며, `MediaQuery.disableAnimations`가 참이면 전환 시간을 0으로 적용한다.

STATUS 화면 카드의 Rules 집계는 **최근 메모리 이벤트 최대 500건**을 대상으로 한다. 클립보드 복사는 버튼을 누르는 시점에 메모리 진단과 **현재 세션의 Firebase Activity Journal**을 결합한다. 두 수집 범위가 달라 전체 사건 건수는 같지 않을 수 있다. 새 실시간 구독은 Firestore 조회를 추가로 일으키지 않는다.

### 19.6 코드 변경 전·후 및 사용자 경험

| 항목 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 일반 사용자 View 최초 병합 SET | CREATE/UPDATE를 알 수 없어 UNKNOWN 가능 | 이미 존재 상태가 확인된 작업은 근거를 기록하고, 확인 불가하면 UNKNOWN 유지 |
| 계정 View의 실제 변경 필드 | Payload 키의 허용 범위 중심 | 기존 Snapshot이 있는 안전한 경우 실제 최상위 변경 키 계산, 그 외는 WRITE_SCOPE 또는 UNKNOWN |
| Batch·Transaction 문서별 정책 | 문서별 경로·상태·변경 범위 일부 누락 | Snapshot 근거 수준까지 포함하여 RULES_ITEM/RULES_COMPARE 출력 |
| Firestore 요청 경로 | 컬렉션 명시 131/302곳 | 식별 가능한 요청 호출의 메타데이터 확대, 일부 다중 컬렉션 결과는 미지정 유지 |
| 실시간 Listener | 일부 구독 경로 미지정 | 확인 가능한 차량 View·월정기 Listener 경로 명시 |
| STATUS 보안 카드 | 다이얼로그를 연 순간의 값 고정 | 새 Activity·인증 이벤트에 따라 값 갱신 |
| STATUS 복사 | 복사 순간 Journal 재수집 | 기존 버튼·개발자 모드 복사 전후 검사 유지 |
| 애니메이션 | 카드 표시·전환 효과 | 갱신된 값에도 기존 페이드·슬라이드·크기 전환 적용 |

일반 사용자의 계정 등록·검색·수정 화면은 변경하지 않는다. 직원 등록 중 View 문서가 존재하지 않는다면 서버의 기존 권한 거부가 발생할 수 있으며, 이는 진단 개선으로 자동 해결되지 않는다. DEBUG 모드 ON의 개발자가 STATUS를 열면 최신 진단 수치를 확인하고 `debugPrint 코드 복사`를 누를 때 기존 메모리 로그 및 보관된 현재 세션 기록을 확보할 수 있다.

### 19.7 테스트 및 검증 경계

| 검증 대상 | 기대 결과 | 상태 |
| --- | --- | --- |
| View 존재 미확인 병합 SET | UNKNOWN 유지 | 정적 코드 경로 확인 |
| Transaction 내 이미 읽은 View 문서 | 존재 상태·안전한 차이 계산의 근거 연결 | 정적 코드 경로 확인 |
| FieldValue 변환이 포함된 변경 | 실제 차이 미확정 시 UNKNOWN 또는 WRITE_SCOPE | 정적 코드 경로 확인 |
| 실패한 Query의 경로 | 호출부에서 전달된 실제 컬렉션 확인 | 정적 코드 경로 확인 |
| 다중 컬렉션 Batch·Transaction | 개별 RULES_ITEM 사용, 단일 컬렉션 오분류 금지 | 정적 코드 경로 확인 |
| STATUS 열린 동안 로그 추가 | 메모리 보안 카드 갱신, 애니메이션 적용 | 정적 코드 경로 확인 |
| DEBUG ON → STATUS 복사 | 기존 로그 및 RULES_ITEM·RULES_COMPARE 클립보드 복사 | 실기기 미검증 |
| DEBUG OFF | 클립보드 복사 차단 | 실기기 미검증 |
| Flutter 정적 분석·Android 빌드 | 기존 업무 흐름 유지 | Flutter/Dart SDK 부재로 미실행 |

실제 단말에서 STATUS UI 변경과 클립보드 복사의 실행 성공, 운영 Firebase의 권한 평가 결과는 이 정적 수정만으로 확정할 수 없다. 기존 기록의 보관 한도와 과금 추정 규칙은 변경하지 않는다.

### 19.8 전달 범위

덮어쓰기 ZIP에는 기존 `261106 1549.zip`에서 실제로 내용이 바뀐 README와 Dart 파일만 전체 원문 형태로 보관한다. 각 파일의 프로젝트 상대 경로를 보존한다. 원본 ZIP의 수정하지 않은 다른 소스·데이터·설정 파일을 포함하지 않는다. 기존 1~18장과 서버 Rules는 변경하지 않는다.
## 20. Firestore 요청 진단 경로·QUERY 분류 정정 및 STATUS 보존 — 2026-11-06 1704 기준

### 20.1 기준 파일과 보존 계약

기준 프로젝트는 사용자가 제공한 `261106 1704.zip`이다. README 1~19장의 원문은 변경하지 않는다. 최신 Firestore Security Rules의 `_isSignedIn`, `_isDeveloper`, `_isAccountProjectionUpdate`, 컬렉션별 허용·거부와 기본 거부 조건도 변경하지 않는다. 기존 로그인, 계정·지역·차량·근무·음성 업무 CRUD, 기존 서버 데이터와 문서 경로, Firebase 호출 횟수는 그대로 유지한다. 이번 변경은 요청의 실제 참조 경로와 로그용 메타데이터의 일치, 요청 유형의 성공·실패 일치, 확보 가능한 단일 문서 참조 정보 확장에 집중한다.

### 20.2 계정 코드 예약 조회 메타데이터 정정

`lib/features/account/data/services/user_code_reservation_backfill_service.dart`에서 `_reservations`가 참조하는 컬렉션은 `user_account_codes`이다. 이전 버전의 `tx.get(reservationRef)`는 로그에 `collection=user_accounts`, `pathTemplate=user_accounts/*`를 전달하여 요청 대상을 잘못 표시했다. 이를 `collection=user_account_codes`, `pathTemplate=user_account_codes/*`로 수정한다. `tx.get(reservationRef)` 자체, 예약 확인, 커밋 및 실패 처리 동작은 변경하지 않는다.

| 비교 | 이전 | 변경 후 |
| --- | --- | --- |
| 실제 읽는 문서 | `user_account_codes/{code}` | 동일 |
| STATUS에 남는 컬렉션 | `user_accounts` | `user_account_codes` |
| STATUS 경로 템플릿 | `user_accounts/*` | `user_account_codes/*` |
| 사용자 계정 코드 복구 동작 | 기존 동작 | 동일 |

### 20.3 QUERY와 GET의 실행 전 구분

`DocumentReference.get`으로 문서 한 개를 읽는 작업은 `GET`, `Query.get`과 컬렉션 조회·조건 검색·Collection Group 검색은 `QUERY`로 전달한다. 이전에는 여러 Query 호출이 `.trackFirestore('GET', ...)`로 전달되고, 성공할 때에만 `QuerySnapshot` 결과를 인식해 `QUERY`로 변경되었다. 이번 변경은 실제 Query로 확인한 호출 56곳을 `QUERY`로 변경하여 성공·실패에 관계없이 같은 작업 종류로 기록한다. `firebase_activity_meter.dart`의 성공 시 `QuerySnapshot` 보정과 기존 오류 코드, 요청 ID, Rules 비교 체계는 유지한다. 이미 올바르게 `QUERY`로 기록되는 호출은 변경하지 않는다.

| 실제 작업 | 이전 | 변경 후 |
| --- | --- | --- |
| 문서 GET 성공·실패 | GET | GET |
| 조건 검색 성공 | 결과가 QuerySnapshot이면 QUERY | QUERY |
| 조건 검색 실패 | GET으로 남을 수 있음 | 수정한 호출부는 QUERY |
| Collection Group 조회 | 원래 GET이었다면 성공 후 보정 | 실제 쿼리 시작 시 QUERY |

특히 Query의 `pathTemplate`은 문서 한 개를 뜻하는 `collection/*`와 구분한다. 컬렉션 쿼리는 해당 컬렉션 경로를, Collection Group 쿼리는 `**/collectionName` 식의 범위 식별값을 사용한다. 컬렉션 그룹에는 단일 최상위 문서 경로를 임의로 지정하지 않는다. 일부 기존 호출이나 직접 SDK 요청이 이번 변경 범위 밖에 남아 있으면 모든 요청의 분류가 완전하다고 주장하지 않는다.

### 20.4 경로 미명시 호출 재분류

이전 정적 조사에서 `.trackFirestore()` 302곳 중 명시 컬렉션 233곳, 문서 참조 8곳, 미명시 61곳이었다. 이번에는 단일 문서의 실제 `DocumentReference`를 구할 수 있는 GET 18곳과 DELETE 1곳에 `documentReference`를 추가하고, 확인된 Collection Group 조회 두 곳에 해당 컬렉션 이름과 경로 범위를 연결한다. 나머지 Batch·Transaction 전체 결과에는 여러 컬렉션이 포함될 수 있으므로 임의의 단일 컬렉션을 붙이지 않는다.

| 정적 집계 | 이전 1704 ZIP | 이번 수정본 |
| --- | ---: | ---: |
| `.trackFirestore()` 전체 호출 | 302 | 302 |
| `collection:` 직접 명시 | 233 | 235 |
| `documentReference:` 직접 명시 | 8 | 27 |
| 위 두 방식 모두 미명시 | 61 | 40 |
| `QUERY`로 명시된 호출 | 16 | 72 |

위 값은 소스 호출부의 인수 수준 정적 집계이며 실제 로그 건수가 아니다. 미명시 호출 40곳은 Batch·Transaction 집계와 같이 단일 문서 경로가 부적절한 호출을 포함한다. Query Group 범위의 `**`는 실제 문서 ID가 아니라 로그 전용 범위 표기이며, 서버가 어떤 문서를 평가했는지의 증거로 해석하지 않는다. 오류 로그에도 민감한 문서 ID·검색값·본문을 새로 저장하지 않는다.

### 20.5 Batch의 View 문서 존재 상태

`user_accounts_show/{scopeId}`는 현재 Rules상 CREATE·DELETE가 개발자 전용이고, 일반 Google 인증자의 UPDATE는 변경 가능한 최상위 필드가 `users`, `updatedAt`로 제한된다. 병합 SET은 커밋 시 문서 존재 여부에 따라 CREATE 또는 UPDATE가 되므로, 문서 존재 상태를 확정할 근거가 없으면 `expected=UNKNOWN`을 유지한다. 기존 `FirebaseActivityWriteBatch.observeDocument`와 추적 Transaction의 읽기 스냅샷 활용은 그대로 유지한다. 진단 목적으로 View 문서를 추가 읽거나 자동 생성하지 않는다. 일반 관리자가 아직 없는 View 문서를 최초 생성하려는 경우에는 서버 권한 거부로 Batch 전체가 실패할 수 있으며, 이는 로그 오기입 수정으로 해결되지 않는 업무상 정책 조건이다.

### 20.6 `affectedKeys()` 근거 수준

서버 Rules의 `request.resource.data.diff(resource.data).affectedKeys()`는 요청 Payload의 키 목록과 다르다. 이미 확보한 변경 전 문서와 안전한 변경 후 결과를 비교할 수 있으면 기존 `affectedKeysFromKnownState` 결과를 사용한다. 그렇지 않으면 허용된 필드에 쓰기를 제한하는 `WRITE_SCOPE` 또는 `UNKNOWN`으로 구분한다. 이전 Snapshot이 최신이라는 보장, 서버에서 확정되는 필드 변환, 동시 변경 여부를 알 수 없으면 서버 판정과 동일하다고 주장하지 않는다. 현재 Rules나 업무 Payload 생성 방식은 변경하지 않는다.

### 20.7 DEBUG STATUS·애니메이션·클립보드

`DevAuth.devModeEnabled`와 비동기 `DevAuth.isDevModeEnabled()` 검사, 기존 `ParkinWorkinTerminalDiagnostics.showStatus()` 및 `StatusDialog`를 유지한다. 개발자 모드 ON에서 STATUS의 `debugPrint 코드 복사` 버튼을 누르면 `debugPrintCodeWithJournal()`이 기존 메모리 진단, Firebase Auth 진단, Firestore 요청 및 `RULES_ITEM`·`RULES_COMPARE` Activity Journal을 `debugPrint(...)` 코드로 결합해 클립보드로 복사한다. 복사 전후 개발자 모드 재검사를 유지한다. 모든 임의 콘솔 `debugPrint` 호출을 자동 수집하는 구조는 아니다.

보안 카드의 Activity·인증 변경 알림 구독, 약 120ms 이벤트 묶음 갱신, `AnimatedSize`, `AnimatedSwitcher`, Fade·Slide·Scale·AnimatedContainer 전환을 보존한다. 모션 감소 설정에서는 전환 시간을 0으로 유지한다. 새 힌트 문구·코드 주석·별도 복사 버튼을 삽입하지 않는다. 이미 연결된 실시간 갱신 코드를 중복으로 추가하지 않는다.

### 20.8 메모리 카드와 Journal 복사 범위

STATUS 보안 카드의 Rules 수치는 최근 메모리 이벤트 최대 500건을 대상으로 하고, 클립보드 복사는 현재 세션의 보관 Journal을 복사 시점에 함께 읽는다. 따라서 양쪽 사건 건수가 다를 수 있으며 오류로 간주하지 않는다. 저널 보관 정책, 과금 집계, 이벤트 스키마는 변경하지 않는다.

### 20.9 변경 전·후 사용자 경험 및 확인 항목

| 상황 | 이전 | 수정 후 기대 |
| --- | --- | --- |
| 계정 코드 예약 문서 GET 실패 | `user_accounts` 오류로 오인 가능 | `user_account_codes` 경로 표시 |
| 직원 목록 QUERY 실패 | GET 오류로 기록 가능 | 수정 호출부는 QUERY 오류 표시 |
| 여러 컬렉션을 묶은 커밋 실패 | 전체 요청만으로 정확한 한 문서 단정 불가 | 단일 경로 오기입 없이 기존 RULES_ITEM 근거 보존 |
| View 최초 생성 권한 미보유 | Batch 실패 가능 | 서버 정책 및 업무 결과 변경 없음 |
| 변경 전후 상태 미확정 | UNKNOWN | UNKNOWN 유지 |
| STATUS를 연 동안 새 인증·보안 이벤트 | 실시간 구독 코드 연결 | 동일한 구독·애니메이션 경로 유지 |
| DEBUG ON → STATUS → 복사 | 메모리·저널 복사 | 동일한 버튼으로 개선된 대상·유형 로그 복사 |
| DEBUG OFF → 복사 | 권한 검사로 차단 | 동일 |

정적 검증에서는 실제 컬렉션 상수와 메타데이터 일치, 302개 호출의 종류·대상 인수 재집계, 수정 파일의 전체성·경로·구문 균형·상대 import·주석·힌트 추가 여부를 확인한다. 이 정적 검사만으로 Flutter 빌드, Android 실기기 복사·애니메이션, Firebase 운영 서버의 실제 허용·거부를 검증했다고 기록하지 않는다.

### 20.10 제공 파일 및 검증 경계

이번 전달 ZIP에는 기준 `261106 1704.zip`과 바이트 내용이 실제로 달라진 **수정 완료 파일의 전체 내용**과 본 README만 프로젝트 상대 경로로 포함한다. 변경되지 않은 파일과 이전에 제공된 Rules 파일은 포함하지 않는다. 기존 README 1~19장의 원문은 보존한다. Flutter/Dart SDK가 현재 작업 환경에 없어 `flutter analyze`, 빌드 및 Android 실기기 검증은 수행하지 못했다. 정상 실행 여부는 별도 검증이 필요하다.

## 21. 개발자 초기화 경로 5곳 및 잔여 QUERY 3곳 정정 — 2026-11-06 1746 기준

### 21.1 기준 및 변경 불변 조건

이번 수정은 사용자 제공 `261106 1746.zip`을 기준으로 한다. 기존 README 1~20장과 Firestore Security Rules 원문, Google 인증 조건, 개발자 초기화·계정 이전·본사 메모·월별 차량 관리의 실제 Firestore 요청 및 데이터 구조를 변경하지 않는다. 변경 대상은 기존 요청에 연결된 DEBUG STATUS 진단 메타데이터 여덟 곳뿐이다. 신규 Firestore 읽기·쓰기·삭제, 인증 조건 완화, 사용자 화면의 신규 힌트 텍스트와 코드 주석을 추가하지 않는다.

### 21.2 개발자 초기화의 실제 문서 참조와 로그 경로 일치

`lib/features/launcher/application/dev_bootstrap_service.dart`에서 읽는 문서의 `DocumentReference`와 수동으로 입력한 `collection` 및 `pathTemplate`이 다섯 곳에서 일치하지 않았다. 실제 문서 읽기나 Transaction은 유지하면서 `trackFirestore` 인수만 실제 문서 참조를 넘기는 `documentReference`로 교체한다. 경로는 기존 `FirebaseActivityFutureTracking.trackFirestore`와 `FirestoreRulesAudit.collectionFor`·`pathTemplateFor`가 참조에서 도출한다.

| 변경 전 위치 | 실제 참조 | 기존 잘못된 경로 | 변경 후 경로 템플릿 |
| --- | --- | --- | --- |
| `dev_bootstrap_service.dart:146` | `areaRef` | `divisions/*` | `areas/*` |
| `dev_bootstrap_service.dart:147` | `metaRef` | `areas/*` | `user_accounts_show/*` |
| `dev_bootstrap_service.dart:274` | `showUserRef` | `user_account_codes/*` | `user_accounts_show/*` |
| `dev_bootstrap_service.dart:391` | `codeRef` | `user_accounts/*` | `user_account_codes/*` |
| `dev_bootstrap_service.dart:392` | `metaRef` | `user_account_codes/*` | `user_accounts_show/*` |

위 행 번호는 수정 전 `261106 1746.zip` 기준이다. 변경 후 호출은 모두 기존 `'GET'` 작업 유형을 유지하며, 실제 대상 문서·사용자 정보·조회 옵션·예외 처리·커밋 동작을 바꾸지 않는다. 기존 오류는 실제 Firebase 읽기 대상이 아니라 진단 로그의 컬렉션과 경로 템플릿을 잘못 표시하던 문제였다.

### 21.3 컬렉션 목록 조회의 QUERY 유형 정정

`CollectionReference.get()`과 `Query.get()`은 단일 문서 `DocumentReference.get()`과 구분하여 요청 시작부터 `'QUERY'`로 계측한다. 이전 공통 계측은 성공 반환값이 `QuerySnapshot`인 경우에만 GET을 QUERY로 보정할 수 있어, 실패한 목록 조회가 GET으로 남을 수 있었다. 다음 세 호출은 실제 컬렉션 목록 조회이므로 `.trackFirestore('QUERY', ...)`를 적용한다.

| 수정 전 위치 | 조회 대상 | 이전 기록 | 수정 후 기록 |
| --- | --- | --- | --- |
| `legacy_account_code_number_migration_service.dart:88` | `tablet_accounts` 또는 `personal_accounts` 전체 컬렉션 | 실패 시 `GET` 가능 | 성공·실패 모두 `QUERY` |
| `head_memo.dart:918` | `head_memo_libraries/{libraryId}/books` 컬렉션 | 실패 시 `GET` 가능 | 성공·실패 모두 `QUERY` |
| `firestore_plate_repository.dart:1690` | `monthly_plate_status_view` 전체 컬렉션 | 실패 시 `GET` 가능 | 성공·실패 모두 `QUERY` |

특히 `firestore_plate_repository.dart`의 기존 1555행은 `.collection(...).doc(safeArea).get()`으로 **단일 문서 GET**이므로 `'GET'`으로 유지한다. 비슷한 로그 문자열이더라도 호출 대상이 문서인지 컬렉션인지 확인한 뒤 구분한다. 일반 단일 문서 조회의 GET, 실제 업무 데이터와 쿼리 필터, 조회 결과 처리는 변경하지 않는다.

### 21.4 진단 정보 변경 방식

개발자 초기화의 문서 GET 다섯 곳은 `collection`·`pathTemplate` 수동 문자열 대신 `documentReference`를 전달한다. 계정 이전·본사 메모·월별 차량 View의 목록 조회 세 곳은 `'GET'`만 `'QUERY'`로 바꾼다. `FirebaseActivityMeter`, `FirestoreRulesAudit`, Activity Journal의 구조와 이벤트 스키마는 변경하지 않는다. 문서 ID나 검색 키, 사용자 정보가 포함된 실제 참조 경로를 로그에 새로 기록하지 않고 기존 `pathTemplate` 방식의 와일드카드 경로만 사용한다.

`user_accounts_show` 병합 SET의 CREATE/UPDATE 구분과 변경 필드 `affectedKeys()`에 대한 기존 근거 수준은 그대로 유지한다. 문서 존재 여부나 서버 변경 결과를 모르면 `UNKNOWN`을 유지하며, 이번 로그 수정으로 서버의 허용·거부가 달라졌다고 주장하지 않는다.

### 21.5 사용자 경험의 수정 전·후

| 실제 이용 상황 | 수정 전 STATUS 또는 복사 로그 | 수정 후 STATUS 또는 복사 로그 | 실제 업무 동작 |
| --- | --- | --- | --- |
| 개발자 초기화에서 지역 조회 실패 | `divisions` 문제로 오인 가능 | `areas` 조회 오류로 정확히 표시 | 유지 |
| 개발자 초기화에서 View 메타 조회 실패 | `areas`·`user_account_codes` 등으로 오인 가능 | `user_accounts_show`로 정확히 표시 | 유지 |
| 개발자 예약 코드 조회 실패 | `user_accounts` 문제로 오인 가능 | `user_account_codes`로 정확히 표시 | 유지 |
| 기존 계정 코드번호 이전 중 전체 목록 조회 실패 | 문서 GET 오류처럼 표시 가능 | 컬렉션 QUERY 오류로 표시 | 유지 |
| 본사 메모 책 목록 조회 실패 | 문서 GET 오류처럼 표시 가능 | 책 컬렉션 QUERY 오류로 표시 | 유지 |
| 월별 차량 View 전체 목록 조회 실패 | 문서 GET 오류처럼 표시 가능 | 월별 View QUERY 오류로 표시 | 유지 |
| 월별 차량 View 특정 지역 문서 조회 | 단일 문서 GET | 단일 문서 GET 유지 | 유지 |

수정된 로그는 일반 사용자 화면의 안내문을 바꾸지 않고 개발자 모드의 DEBUG STATUS 및 클립보드 복사 결과에서 오류의 실제 대상과 읽기 유형을 더 정확하게 보여준다. 실제 Firestore 권한 오류가 발생한다면 로그의 정확도가 높아지더라도 해당 오류 자체는 별도 원인 검토가 필요하다.

### 21.6 기존 STATUS·`debugPrint` 복사·애니메이션 보존

`ParkinWorkinTerminalDiagnostics.showStatus`와 기존 `StatusDialog`의 개발자 모드 ON 확인, 복사 직전·직후 권한 재확인, `debugPrintCodeWithJournal`의 현재 메모리 진단 및 세션 Journal 결합, `Clipboard.setData`를 그대로 유지한다. 복사되는 텍스트는 기존 수집 경로에서 생성하는 `debugPrint(...)` 코드이며 임의 콘솔 출력 전체를 자동으로 캡처하는 구조는 아니다. 잘못된 컬렉션과 GET/QUERY 기록의 수정 결과는 새로 기록되는 진단 이벤트 및 복사 시점의 로그에 반영된다. 과거 Journal에 이미 저장된 문자열을 소급 수정하지 않는다.

`StatusDialog`의 Activity·인증 변경 알림 구독, 페이드·슬라이드·스케일 전환, `AnimatedSize`, `AnimatedSwitcher`, 모션 감소 시 전환 시간 0의 기존 구현을 보존한다. 동일 애니메이션과 복사 버튼을 중복 삽입하지 않는다. STATUS 관련 Dart 파일은 이번 변경에서 내용이 달라지지 않으므로 변경 파일 전용 ZIP에도 중복 포함하지 않는다.

### 21.7 계측 호출 정적 집계의 변화

| 정적 집계 항목 | 기준 `1746.zip` | 이번 수정 후 | 변화 |
| --- | ---: | ---: | ---: |
| `.trackFirestore()` 호출 | 302 | 302 | 0 |
| `collection:` 직접 명시 | 235 | 230 | -5 |
| `documentReference:` 직접 명시 | 27 | 32 | +5 |
| 위 두 형태로 대상 정보 명시 | 262 | 262 | 0 |
| 대상 정보 직접 미명시 | 40 | 40 | 0 |
| `'QUERY'` 직접 지정 | 72 | 75 | +3 |

컬렉션 문자열 다섯 곳을 실제 문서 참조로 바꾸기 때문에 직접 `collection:` 수치는 감소하지만, 전체 경로 식별 범위는 줄어들지 않는다. 위 수치는 정적 호출부 집계이며 실제 Firestore 요청 실행 횟수 또는 성공 건수가 아니다. 이번 변경은 확인된 여덟 호출의 정확도 개선이고, 모든 프로젝트 호출의 경로·작업 유형이 완전무결하다고 보장하지 않는다.

### 21.8 수정 파일과 검증 결과

| 파일 | 변경 내용 | 정적 확인 범위 |
| --- | --- | --- |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | GET 다섯 곳을 실제 `documentReference`로 교체 | 실제 참조명과 로그 인수 연결 |
| `lib/features/account/data/services/legacy_account_code_number_migration_service.dart` | 목록 조회 GET → QUERY | `collection.get()` 유지 |
| `lib/features/headquarter/page/sheets/head_memo.dart` | 원격 책 목록 GET → QUERY | `_remoteBooksRef.get()` 유지 |
| `lib/shared/plate/data/repositories/firestore_plate_repository.dart` | 월별 View 전체 목록 GET → QUERY | 문서 단일 GET과 구분 |
| `README.md` | 기존 1~20장 뒤에 21장 신설 | 기존 원문 보존 |

검증 기준에는 각 수정 호출의 실제 참조 일치, 성공·실패 QUERY 분류, 단일 문서 GET 보존, 원본과 비교한 변경 파일 전체성, ZIP CRC 및 바이트 일치, 상대 import·구문 괄호 구조, 새 주석 및 `hintText`·`helperText` 부재를 포함한다. Flutter/Dart SDK가 없는 환경에서 `flutter analyze`, 빌드 및 Android 실기기의 STATUS·클립보드·애니메이션 실행은 확인하지 못했으므로 그 결과를 성공으로 기록하지 않는다. 배포되는 Firestore Security Rules나 기존 업무 권한 정책은 변경하지 않는다.

## 22. 장기 유지 Listener의 인증 근거 갱신 및 Transaction 중복 감사 정리 — 2026-11-06 1816 기준

### 22.1 기준·수정 목적과 원본 보존

기준 프로젝트는 `261106 1816.zip`이다. README 1~21장 1,686행은 내용과 순서를 변경하지 않고 후속 분석 결과를 22장에 추가한다. 실제 실행 로그의 세션 `hnwljntuzh`에서 먼저 시작된 Listener `:166`, `:182`는 뒤늦게 STATUS 인증 검사가 통과한 후에도 `expected=UNKNOWN`이었고, 같은 시점 새 Listener에서는 `expected=ALLOW`, `comparison=CONSISTENT`가 관측됐다. 차량 생성에서는 하나의 전용 Transaction `:318`에 문서별 `RULES_ITEM`과 `ALLOW/CONSISTENT` 종합 감사가 생성된 반면, 외부 Future 계측 `:319`에 별도의 `UNKNOWN/NOT_VERIFIED`가 남았다. 이 두 현상은 서버의 권한 거부나 업무 실패가 아니라 앱의 진단 근거 관리 및 중복 계측 문제다.

현재 Firestore Security Rules, 실제 CRUD, 인증 방식, 문서 구조, Query 필터, Transaction 본문의 쓰기 대상과 작업 순서, 기존 STATUS·Journal의 클립보드 데이터 형식은 변경하지 않는다. 추가 Firestore 읽기·쓰기나 Listener 강제 재구독을 도입하지 않는다. Dart 수정 파일에는 코드 주석과 UI 힌트 텍스트를 새로 넣지 않는다.

### 22.2 기존 Listener의 인증 상태 고정 원인

기존 `lib/app/diagnostics/firebase_activity_meter.dart`의 `observeSnapshots()`는 구독을 시작할 때 `FirebaseAuthRulesDiagnostics.captureForRequest()`를 한 번 실행하고 이를 `authAtStart`에 보관했다. 이후의 정상 Snapshot과 오류 콜백은 그 값을 반복 사용했다. STATUS에서 추가 인증 검사를 완료해도 이미 만들어진 Listener의 인증 근거는 바뀌지 않아 이후 새 서버 Snapshot에도 `UNKNOWN`이 남을 수 있었다. 반면 `FirebaseAuthRulesDiagnostics.current`는 현재 UID가 같고 검사 시점이 10분 이내인 결과만 유효하게 반환한다.

| 비교 항목 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 구독 시작 상태 | `authAtStart` 한 번 보관 | 구독이 시작된 UID를 별도로 기억 |
| 후속 Snapshot 인증 | 처음 보관한 결과 재사용 | 이벤트 시점의 `captureForRequest()`를 다시 확인 |
| UID가 다른 사용자로 변경 | 오래된 최초 인증 근거가 남을 수 있음 | 현재 UID와 구독 시작 UID가 다르면 인증 근거 제거, `AUTH_CHANGED` 판정 |
| 최초 구독 UID가 불명 | 후속에도 불확실 | 보수적으로 `UNKNOWN` 유지 |
| 인증 검사 유효기간 경과 | 최초 결과를 재사용할 가능성 | 최신 유효 결과가 없으면 `UNKNOWN` 유지 |
| 실제 Firestore 구독 | 기존 SDK Listener 사용 | 동일한 구독을 유지하고 인증 진단만 갱신 |

새 인증 결과는 **이후에 실제로 수신한 Snapshot과 오류 이벤트에만** 적용한다. 과거 이벤트나 Journal을 소급해 ALLOW로 바꾸지 않는다. UID 비교만으로 로그인·로그아웃 후 같은 UID로 다시 접속한 모든 세션 변화를 증명할 수는 없으므로, 실제 서버 Rules를 독립 검증했다는 의미로 기록하지 않는다. 캐시 결과나 인증 근거가 없는 경우에도 `UNKNOWN`을 유지한다.

### 22.3 Listener의 GET·QUERY 유형 구분

기존 Snapshot 감사는 성공·실패 모두 `firestoreOperation=GET`으로 고정되어 Query Listener의 유형이 부정확할 수 있었다. `snapshotReceived()`는 실제 `QuerySnapshot`을 `QUERY`, `DocumentSnapshot`을 `GET`으로 구분하고, Snapshot이 없는 초기 오류에서도 요청 유형을 확인할 수 있도록 각 명시적 호출에서 작업 유형을 전달한다. 식별하지 못한 유형은 근거 없는 GET 추정 대신 `SNAP`으로 기록하여 정책 예상값을 보수적으로 `UNKNOWN` 처리한다.

| 대상 | 원래 감사 유형 | 변경 후 | 추가 메타데이터 |
| --- | --- | --- | --- |
| `firestore_plate_repository.dart`의 특정 지역 View 문서 구독 | `GET` | `GET` | `operation: 'GET'` |
| `firestore_plate_repository.dart`의 월별 상태 컬렉션 Query 구독 | `GET` | `QUERY` | `operation: 'QUERY'` |
| `firestore_voice_message_repository.dart`의 채널별 메시지 Query 구독 | `GET` | `QUERY` | `operation: 'QUERY'`; 컬렉션 경로 `voice_channels/*/messages`로 바로잡음 |

특히 기존 로그에서 `parking_requests_view`의 `:166`, `:182`는 단일 문서 Listener이므로 `GET`이 맞다. 이 사례의 핵심 원인은 유형이 아니라 오래된 인증 근거였다.

### 22.4 Transaction 중복 감사의 실제 원인

`runTrackedActivityTransaction()`은 내부에서 `COMMITTED_TRANSACTION`과 쓰기 대상별 `RULES_ITEM`, 종합 `RULES_COMPARE`를 기록한다. 그런데 일부 업무 호출은 이 Future에 `.trackFirestore('TRANSACTION', ...)`을 다시 연결하여 별도 `requestId`와 일반 감사가 생겼다. 일반 감사는 개별 쓰기 대상을 전달받지 않으므로 `expected=UNKNOWN`, `comparison=NOT_VERIFIED`가 발생할 수 있다. 이를 `ALLOW`로 임의 보정하지 않고, 이미 상세 감사가 있는 경우 바깥쪽 중복 계측만 제거한다.

| 사용자 작업 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 차량 등록 Transaction | 내부 상세 감사 `ALLOW/CONSISTENT` + 외부 일반 감사 `UNKNOWN/NOT_VERIFIED` | 내부 상세 감사와 실제 커밋 기록만 유지 |
| 실제 Transaction 실행 | 서버 커밋 한 번 | 동일한 한 번 |
| 실제 쓰기 대상·개수 | 예시에서 3개 | 동일한 3개 |
| STATUS 오류 분석 | 하나의 작업에 서로 다른 두 비교 결과 | 실제 문서별·종합 감사 중심으로 확인 |
| 일반 `runTransaction()` 호출 | 단독 일반 계측 2곳 존재 | 전용 계측이 없으므로 보존 |

### 22.5 중복 계측 제거 26곳의 수정 범위

다음은 `1816.zip`에서 `runTrackedActivityTransaction()`의 반환값에 별도 `.trackFirestore('TRANSACTION', ...)`가 연결된 26곳이다. 전용 계측 함수 자체와 콜백 본문은 수정하지 않는다. 후속 `.timeout(...)`, 예외 전파, 커밋 순서도 유지한다.

| Dart 파일 | 제거한 중복 래퍼 | 개수 |
| --- | --- | ---: |
| `lib/features/account/data/services/user_write_service.dart` | 전용 Transaction 반환 Future의 일반 계측 | 3 |
| `lib/features/dashboard/data/repositories/end_work_report_firestore_repository.dart` | 동일 | 1 |
| `lib/features/location/data/services/location_write_service.dart` | 동일 | 6 |
| `lib/shared/plate/data/repositories/firestore_plate_repository.dart` | 동일 | 5 |
| `lib/shared/plate/domain/services/plate_creation_service.dart` | 동일 | 1 |
| `lib/shared/plate/domain/services/plate_status_service.dart` | 동일 | 4 |
| `lib/shared/plate/domain/services/plate_write_service.dart` | 동일 | 2 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 동일 | 1 |
| `lib/shared/secondary/pages/sheets/area_management.dart` | 동일 | 1 |
| `lib/shared/secondary/pages/sheets/tabs/add_area_tab.dart` | 동일 | 2 |
| **합계** | | **26** |

`plate_write_service.dart`의 일반 `runTransaction()` 1곳과 `end_work_report_firestore_repository.dart`의 일반 `runTransaction()` 1곳에 붙은 추적 코드는 중복이 아니므로 제거하지 않는다. 실제 작업이 아닌 진단 래퍼만 구분해 변경한다.

### 22.6 메모리·Journal Transaction 건수 보존

기존 `FirebaseActivityMeter`의 Transaction 집계는 성공 `TRANSACTION`만 세고, `FirebaseActivityJournal.readCost()`도 동일하게 계산했다. 전용 계측의 외부 래퍼를 제거하는 대신 두 집계가 `COMMITTED_TRANSACTION` 성공 이벤트도 Transaction 실행 1건으로 계산하도록 한다. 일반 `runTransaction()`의 성공은 기존 `TRANSACTION` 이벤트로 계속 집계한다. 전용 Transaction에서 쓰기가 0개인 읽기 전용 성공도 `COMMITTED_TRANSACTION`을 기록하되 `committedWrites=0`, `committedDeletes=0`으로 유지한다.

| 항목 | 수정 전 | 수정 후 집계 기준 |
| --- | --- | --- |
| 전용 Transaction 성공 | 내부 커밋 이벤트와 별도 일반 성공 기록 가능 | 전용 `COMMITTED_TRANSACTION` 한 건 |
| 일반 Transaction 성공 | `TRANSACTION` 한 건 | 기존대로 한 건 |
| 읽기 전용 전용 Transaction 성공 | 커밋 이벤트 생략 가능 | 쓰기 0건인 성공 이벤트 기록 |
| 메모리·Journal 집계 | `TRANSACTION` 성공만 사용 | 두 작업 유형의 성공을 합산 |
| 문서별 권한 감사·커밋 쓰기 수 | 전용 계측에서 산출 | 동일하게 보존 |

기존 Journal의 과거 중복 이벤트를 소급 삭제·합병하지는 않는다. **과거에 저장된 세션 기록의 집계에는 예전 중복이 일부 포함될 수 있다.** 개선 효과는 수정 후 새 실행에서 확인해야 한다. `COMMITTED_TRANSACTION`은 성공 실행을 기록하며, 오류 이벤트는 별도의 `errors` 통계로 집계한다.

### 22.7 사용자 경험과 DEBUG STATUS 보존

일반 사용자에게 차량 목록의 실시간 갱신, 지역·차량 등록, 출퇴근 처리, 보고서 저장 동작은 이전과 같다. 개발자 모드 ON에서 STATUS를 열고 `debugPrint 코드 복사`를 사용하면 **새로 발생한** Listener Snapshot은 유효한 최신 인증 근거에 따른 비교 결과를 제공하고, Transaction의 중복 UNKNOWN 감사가 사라지는 것을 목표로 한다. 동일 UID·10분 유효 조건, 실제 문서 상태·캐시 여부 등 검증 근거가 부족하면 여전히 UNKNOWN을 유지한다.

`lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart`의 `debugPrintCodeWithJournal`, `securitySummaryChanges`, 개발자 모드 복사 제한과 `lib/app/utils/status_dialog.dart`의 복사 전후 권한 검사, `Clipboard.setData`, 페이드·슬라이드·스케일 애니메이션, `AnimatedSwitcher`, `AnimatedSize`, `MediaQuery.disableAnimations`은 모두 기존 코드대로 유지한다. 같은 버튼·애니메이션을 중복 생성하지 않고, 변경되지 않은 STATUS 소스는 덮어쓰기 패키지에 포함하지 않는다. 주석과 새로운 힌트 텍스트도 삽입하지 않는다.

### 22.8 수정 파일 구성 및 검증 기준

| 변경 영역 | 파일 수 | 내용 |
| --- | ---: | --- |
| 계측·Journal | 2 | `firebase_activity_meter.dart`, `firebase_activity_journal.dart` |
| 전용 Transaction 중복 래퍼 제거 | 10 | 22.5절의 업무 Dart 파일 |
| 음성 메시지 Query Listener | 1 | `firestore_voice_message_repository.dart` |
| 변경 이력 | 1 | `README.md` 22장 신규 추가 |
| **총합** | **14** | **Dart 13개 + README 1개** |

정적 검사는 ZIP 무결성 및 전체 파일 내용 일치, 기존 README 1~21장 원문 보존, 중복 래퍼 26곳 제거, 일반 Transaction 래퍼 2곳 유지, Snapshot별 GET/QUERY, Transaction 통계 경로, 상대 import, 구문 토큰 균형, 주석 및 신규 힌트 텍스트 부재를 기준으로 한다. 진단 코드 수정은 Firestore 서버 권한 정책의 실효성을 독립 입증하는 것이 아니다.

### 22.9 실제 실행 후 회귀 검증

| 재현 조건 | 정상으로 볼 근거 |
| --- | --- |
| 인증 진단보다 먼저 같은 UID로 Listener 시작 후 STATUS 인증 검사 | 이후 서버 Snapshot에서 유효 인증 근거에 따른 ALLOW·CONSISTENT 가능 |
| 10분 초과 또는 UID 변경 | 이전 인증을 재사용하지 않고 UNKNOWN 또는 AUTH_CHANGED |
| 문서 Listener / Query Listener 수신 | 각각 GET / QUERY로 감사, 최초 Snapshot 이전 오류도 올바른 유형 |
| 차량 생성 전용 Transaction | 실제 커밋 기록, 대상별 RULES_ITEM, 종합 RULES_COMPARE 보존 |
| 위 전용 Transaction의 외부 UNKNOWN 기록 | 새로운 별도 일반 Transaction 감사가 생기지 않음 |
| 성공한 읽기 전용 전용 Transaction | 성공 이벤트 한 번, 커밋 쓰기 0건 |
| 일반 runTransaction, .timeout, 예외 경로 | 기존 계측과 동작 유지 |
| DEBUG STATUS 열기·복사 및 애니메이션 | 개발자 모드 ON, 최신 Journal 포함 코드 복사, 기존 모션 효과 유지 |

위 표는 **수정 후 실기기에서 확인해야 할 합격 기준**이다. 정적 검사만으로 이 조건들이 실제 Android 장치에서 통과했다고 주장하지 않는다. Flutter/Dart SDK를 이용한 분석·빌드 및 실제 서버 응답 기반 회귀 검사는 별도 실행 전에는 미검증으로 남긴다.

## 23. STATUS23 — 인증 세션 판정 세분화 및 Transaction 읽기·쓰기 대상 감사 — 2026-11-06 2021 기준

### 23.1 기준 및 변경하지 않는 항목

본 장의 기준 소스는 `261106 2021.zip`이며, 2026-11-06 20:54~21:06 앱 실행 기록과 사용자가 제공한 `rules_version = '2'` Firestore Security Rules 원문을 기준으로 한다. 이전 1~22장 원문은 보존하고 변경 이력만 이 장에 추가한다. 서버에 배포된 Security Rules 원문을 수정하지 않으며, 실제 업무 CRUD·반환값·Transaction 재시도·실시간 구독 구조, UI 라우팅, 개발자 STATUS의 모션 및 클립보드 복사 기능을 보존한다.

이번 수정은 Firebase 서버에 배포된 정책 전체를 독립 검증하는 기능이 아니라, **클라이언트의 로컬 예상 정책과 SDK 관측 결과를 비교하는 진단 정확도 개선**이다. 정책 버전 표기인 `localRules`는 클라이언트 감사 모델의 식별자이며 서버에 배포된 Rules와의 동일성을 입증하지 않는다.

### 23.2 증거 로그 및 목표

| 구분 | 수정 전 실제 로그 근거 | 수정 후 목표 |
| --- | --- | --- |
| 오래 유지된 단일 문서 Listener | `hnwomki4qp:21`, `:23`, `:25`의 후속 서버 Snapshot에서 `AUTH_CHANGED` 10건, 데이터 수신 성공 | 시작 UID 부재·로그아웃·서로 다른 UID·같은 UID의 새 로그인 세션을 구분, 근거 부족 시 UNKNOWN |
| 독립 일반 Transaction | `hnwomki4qp:105`, `:129`에서 거래 성공 후 `expected=UNKNOWN` | 업무 동작을 유지한 채 문서별 읽기·쓰기 감사 후 종합 비교 |
| 전용 Transaction 정상 사례 | `hnwomki4qp:41`, `:78`에서 실제 커밋 3건·2건과 `CONSISTENT` | 기존 감사 유지, 별도 일반 TRANSACTION 중복 래퍼 생성 금지 |
| Journal | 저장 오류·유실 0건 | 저장·일반 사용자 기능 유지 |

### 23.3 Listener 인증 상태의 안전한 구분

| 상태 | 수정 전 | 수정 후 진단 이유 |
| --- | --- | --- |
| Listener 시작 당시 UID 부재 | 현재 UID와 다르면 `AUTH_CHANGED` | `AUTH_AT_START_UNAVAILABLE` |
| 로컬 인증 상태 관찰 불가 | `AUTH_CHANGED`로 뭉뚱그림 | `AUTH_UNAVAILABLE` |
| Listener 시작 후 로그아웃 | `AUTH_CHANGED` | `AUTH_SIGNED_OUT` |
| 시작 UID와 현재 UID 불일치 | `AUTH_CHANGED` | `AUTH_CHANGED` 유지 |
| 같은 UID로 로그인 세션이 다시 생성됨 | UID 비교만으로 구분 어려움 | Auth 상태 이벤트 세대값 차이가 관찰되면 `AUTH_SESSION_CHANGED` |
| UID와 세대값이 같고 최근 인증 검사가 유효 | 인증 근거 사용 | 같은 조건에서 인증 근거 사용 |
| 세션 확인 불가·인증 결과 만료 | 보수적 UNKNOWN | 보수적 UNKNOWN 유지 |

`lib/app/diagnostics/firebase_auth_rules_diagnostics.dart`에는 Firebase Auth 상태 스트림을 한 번 관찰하고 `sessionGeneration`을 부여하는 로컬 세션 식별 기능을 추가했다. `lib/app/diagnostics/firebase_activity_meter.dart`는 구독 시작 시점의 로컬 식별 정보를 보존하고, 이후 Snapshot마다 현재 식별 정보와 비교해 `verification` 및 개인정보를 포함하지 않는 `authStartUidPresent`, `authCurrentUidPresent`, `authSessionMatches`를 기록한다. 로컬 Auth 상태 이벤트가 놓친 중간 전환까지 완벽하게 식별한다고 가정하지 않으며, 확인할 수 없는 상황을 ALLOW로 채우지 않는다. 기존 `.snapshots()` 구독은 재시작하지 않는다.

### 23.4 Transaction 대상별 감사 방식

| 파일 및 범위 | 수정 전 | 수정 후 |
| --- | --- | --- |
| `firebase_activity_meter.dart` · `_TrackedFirestoreTransaction.get` | 기존 `tx.get()` 결과로 문서 존재·기존 데이터 저장 | 기존 호출이 반환한 같은 Snapshot에서 GET 대상 경로·존재 여부를 읽기 대상으로 기록 |
| `firebase_activity_meter.dart` · Transaction 성공 및 finally | 쓰기 대상만 `RULES_ITEM`·종합 평가 | 현재 시도의 GET 대상과 SET·UPDATE·DELETE 대상 순서로 `RULES_ITEM`, 전체 대상 `expectedTransaction` 평가 |
| `firestore_rules_audit.dart` · `expectedTransaction` | 없음 | 읽기와 쓰기 대상의 ALLOW·DENY·UNKNOWN을 보수적으로 종합 |
| `plate_write_service.dart` · `transitionPlateType` | 일반 `runTransaction` + 별도 `trackFirestore('TRANSACTION')` | 전용 `runTrackedActivityTransaction`으로 교체하고 일반 래퍼 제거 |
| `end_work_report_firestore_repository.dart` · 보고서 제출 | 일반 `runTransaction` + 별도 일반 래퍼 | 전용 추적으로 전환하고 기존 제출 분기·`bool` 결과 보존 |

전용 Transaction의 SDK 호출 `runTransaction()`은 한 번만 유지한다. 기존 `tx.get`, `tx.set`, `tx.update`, `tx.delete`를 그대로 사용하며 감사 목적으로 문서를 추가 조회하거나 작성하지 않는다. Transaction 실패·재시도 시에는 해당 시도의 대상과 최종 커밋 성공을 구분하고, 커밋되지 않은 쓰기를 성공한 쓰기 수에 포함하지 않는다. 전용 Transaction의 성공 기록은 `COMMITTED_TRANSACTION` 한 건으로 집계하며, 단독 일반 `TRANSACTION` 감사를 중복 생성하지 않는다.

### 23.5 현재 Rules의 정책 대응 및 불확실성

사용자가 제공한 운영 Rules에서 `_isSignedIn()` 조건은 Firebase 인증 사용자, `sign_in_provider == 'google.com'`, `email_verified == true`를 모두 요구한다. `_isDeveloper()`는 이 조건에 개발자 이메일 일치를 추가한다. 다음은 사용자가 제공한 규칙의 로컬 진단 대응이며, 전제가 불명확한 경우 UNKNOWN을 유지한다.

| 대상과 작업 | 일반 인증 사용자 | 개발자 | 로컬 진단 기준 |
| --- | --- | --- | --- |
| `areas/{document=**}` GET·QUERY | ALLOW | ALLOW | 인증 조건 확인 |
| `areas/{document=**}` CREATE·UPDATE·DELETE | DENY | ALLOW | 개발자 인증 조건 확인 |
| `divisions/{document=**}` GET·QUERY | ALLOW | ALLOW | 인증 조건 확인 |
| `divisions/{document=**}` CREATE·UPDATE·DELETE | DENY | ALLOW | 개발자 인증 조건 확인 |
| `user_accounts_show/{scopeId}` GET·QUERY | ALLOW | ALLOW | 인증 조건 확인 |
| `user_accounts_show/{scopeId}` CREATE·DELETE | DENY | ALLOW | 개발자 권한 확인 |
| `user_accounts_show/{scopeId}` UPDATE | `users`, `updatedAt`만 실제 영향이면 ALLOW | ALLOW | 전후 값 또는 안전한 필드 범위가 충분할 때만 판정 |
| `user_accounts_show/{scopeId}/users/{userId}` READ·WRITE | ALLOW | ALLOW | 인증 조건 확인 |
| `plates`, `parking_requests_view`, `plate_status` 등 명시된 일반 경로 | ALLOW | ALLOW | 인증 조건 확인 |
| 그 외 명시되지 않은 경로 | DENY | DENY | 경로·작업이 확정돼야 판단 |

`request.resource.data.diff(resource.data).affectedKeys()`는 단순 입력 필드명과 다를 수 있다. 특히 기존 문서 상태를 모르거나 서버 Transform 이후 변경을 확정할 수 없는 SET 작업에는 `UNKNOWN`을 유지한다. 일반 사용자 대상 `user_accounts_show` 생성·삭제를 허용하는 것으로 오판하지 않는다. 부정확한 경로나 쓰기 대상이 불명확한 일반 감사는 ALLOW로 간주하지 않는다.

### 23.6 추가 Firestore 요청 금지 및 UX 유지

| 사용자 기능 | 유지할 동작 | 변경되는 진단 |
| --- | --- | --- |
| 장시간 열어 둔 차량 화면 | 서버 Snapshot 정상 수신, 기존 Listener 유지 | 세션 불일치 이유를 정확히 분류 |
| 차량 유형 변경 | 같은 사용자 조작·실제 문서 변경 | 읽기·쓰기별 `RULES_ITEM` 및 단일 종합 감사 |
| 근무 종료 보고서 제출 | 기존 제출·재제출 분기 및 반환값 | 실제 분기에 따라 GET·SET 문서 감사 |
| STATUS 진단 및 복사 | 개발자 모드 ON 검사, `debugPrint(...)` 생성, `Clipboard.setData` | Journal에 신규 분류·대상별 감사 내용이 포함됨 |
| STATUS 애니메이션 | 기존 페이드·슬라이드·스케일, `AnimatedSwitcher`, `AnimatedSize`, 모션 감소 설정 | 기존 구현 보존, 중복 UI 생성 없음 |

Auth 상태 스트림을 활용한 세대값 추적은 로컬 Firebase Auth의 상태 관찰이며 Firestore 문서 요청이 아니다. 데이터 조회·쓰기·보안 Rules 원문을 변경하지 않는다. 신규 `hintText`, `helperText`, Dart 주석은 삽입하지 않는다.

### 23.7 수정 파일과 검증 구분

| 변경 파일 | 주요 내용 |
| --- | --- |
| `lib/app/diagnostics/firebase_auth_rules_diagnostics.dart` | 인증 세션 세대값·유효성·UID 검사 |
| `lib/app/diagnostics/firebase_activity_meter.dart` | Listener 이유·비식별 상태값, Transaction GET 대상 기록·문서별 감사 |
| `lib/app/diagnostics/firestore_rules_audit.dart` | 보수적 쓰기 경로 확인 및 읽기·쓰기 종합 정책 평가 |
| `lib/shared/plate/domain/services/plate_write_service.dart` | `transitionPlateType()`의 일반 Transaction을 전용 추적으로 변경 |
| `lib/features/dashboard/data/repositories/end_work_report_firestore_repository.dart` | 보고서 제출 Transaction을 전용 추적으로 변경 |
| `README.md` | 23장 추가; 이전 장 원문 보존 |

정적 검증은 ZIP 무결성, 원본 파일 대비 수정 범위, 기존 README 유지, Dart 주석·힌트 텍스트 부재, 메서드·콜백 연결, 전용 Transaction 중복 래퍼 제거, STATUS·애니메이션 코드의 기존 파일 일치를 확인한다. Dart SDK 기반 `flutter analyze`·Android 빌드·실제 Firebase 권한 테스트를 수행하지 않은 상태에서는 이를 성공했다고 기록하지 않는다.

### 23.8 수정 후 실기기 확인 항목

| 시나리오 | 기대 기록 |
| --- | --- |
| UID 미확보 상태에서 구독 후 로그인 | `AUTH_AT_START_UNAVAILABLE`, `NOT_VERIFIED` |
| 구독 후 UID 변경·로그아웃 | `AUTH_CHANGED` 또는 `AUTH_SIGNED_OUT`, `NOT_VERIFIED` |
| 같은 UID 재로그인 이벤트 관찰 | `AUTH_SESSION_CHANGED`, `NOT_VERIFIED` |
| 동일 세션·10분 내 STATUS 인증 후 서버 Snapshot | 근거가 충분하면 `ALLOW`·`CONSISTENT` |
| 차량 유형 변경 | 실제 GET 및 UPDATE `RULES_ITEM`, 성공 시 종합 비교 한 건 |
| 근무 종료 보고서 저장 | 실제 제출 분기의 GET 및 SET `RULES_ITEM` |
| 일반 사용자 `areas`·`divisions` 쓰기 | 로컬 예상 DENY |
| 개발자 `areas`·`divisions` 쓰기 | 로컬 예상 ALLOW |
| 일반 사용자 `user_accounts_show` 필드 제한 | 바뀐 필드가 확정되면 ALLOW 또는 DENY, 불명확하면 UNKNOWN |
| STATUS 열기·복사 | 개발자 조건 검사 후 Journal 포함 `debugPrint(...)` 텍스트 복사 |
| 애니메이션·모션 감소 | 기존 모션 유지, 모션 감소 활성 시 기존 Duration.zero 처리 |

이 표는 실행 후 검사할 목표이며, 본 코드 변경만으로 실기기 결과까지 입증했다고 주장하지 않는다.


## 24. 일반 계정 생성의 최초 Projection CREATE 허용·진단 보강·Role 표시명 정정 — 2026-11-07

### 24.1 사용자 경험과 오류 증거

2026-11-07 `ceo` 계정으로 개발자 모드 OFF에서 계정을 생성한 1차 시도는 14:49:22 `user_account_codes/*` 서버 GET 성공 이후 `COMMITTED_BATCH writes=3`가 `permission-denied`로 실패했다. 이후 개발자 모드를 ON하고 14:49:50 Google 개발자 인증 성공, DEBUG STATUS Dialog 진입·종료 후 14:51:02 세 건의 Batch가 성공했다. 전후의 `user_accounts_show/*` 조회는 문서 0건으로 기록됐다. 로그에는 해당 범위의 실제 문서 ID와 실패 당시 토큰이 남아 있지 않아 `user_accounts_show` CREATE만이 거부됐다고 최종 단정할 수는 없다.

### 24.2 계정 관리 가능 Role과 서버 보안의 범위

| Role 코드 | 표시명 | 현행 계정 관리 가능 | 수정 후 UI 권한 |
| --- | --- | --- | --- |
| `ceo` | 대표자 | 예 | 유지 |
| `headAdmin` | 본사 관리자 | 예 | 유지 |
| `headStaff` | 본사 직원 | 예 | 유지 |
| `branchProAdmin` | 지사 심화 관리자 | 예 | 유지 |
| `branchAdmin` | 지사 관리자 | 아니요 | 유지 |
| `branchStaff` | 지사 직원 | 아니요 | 유지 |
| `branchProStaff` | 지사 심화 직원 | 아니요 | 유지 |

`RoleType.canManageAccounts` 및 `secondary_info.dart`의 `kRolePolicy`가 앱 권한의 근거다. `UserState.addUserCard()`에서 Role을 Firestore 요청 이전에 검증하므로 일반 계정 등록 경로에서 권한 없는 Role의 불필요한 네트워크 호출을 막는다. 다만 **Firestore Rules는 현재 사용자의 업무 Role을 서버에서 독립적으로 검증할 수 있는 Custom Claims 또는 신뢰할 수 있는 UID→업무계정 연결을 제공받지 않는다**. 따라서 이 변경은 모든 7개 Role의 서버 측 쓰기 분리를 완성하지 않는다. 기존에도 Google 인증 사용자에게 `user_accounts`, `user_account_codes` 및 View의 일부 수정이 허용되어 있었다. 임의의 직접 Firestore SDK 호출까지 기존 4개 허용 Role로 엄격하게 제한하려면 인증·식별자 매핑 계약과 Rules의 별도 설계가 필요하다.

### 24.3 Firestore Rules 변경 전·후

| 경로 및 작업 | 기존 규칙 | 수정 파일의 규칙 | 의미 |
| --- | --- | --- | --- |
| `user_accounts_show/{scopeId}` CREATE | 개발자 Google 인증만 허용 | 개발자 또는 단일 사용자 Projection 형태의 검증된 Google 인증 CREATE | 부모 View가 비어 있는 최초 계정 저장 지원 |
| 같은 문서 UPDATE | 개발자 또는 변경 필드가 `users`, `updatedAt`에 한정된 Google 인증 | 유지 | 기존 메타 보호 |
| 같은 문서 DELETE | 개발자만 허용 | 유지 | 일반 사용자 삭제 차단 |
| `areas`, `divisions` WRITE | 개발자 전용 | 유지 | 회사·지역 구조 설정 보호 |
| `user_accounts`, `user_account_codes` | Google 인증 사용자 WRITE | 유지 | 기존 요청·기능 보존 |

새 `_isAccountProjectionCreate()` 함수는 인증 제공자·이메일 검증, 최상위 필드가 정확히 `users`, `updatedAt`인지, `users`가 Map이며 그 최상위 항목이 정확히 1개인지, `updatedAt`가 서버 요청 시각인지 확인한다. 일반 사용자의 기존 회사·지역 메타 필드 CREATE는 허용하지 않는다. 최초 생성 시 `usersMapComplete`는 기록하지 않는다. 현행 26장 목록 읽기에서는 `users` Map만 검증하므로 이 완료 플래그가 없어도 정상 목록을 표시한다. 이 제한은 일반 사용자에 의한 스키마 오염 범위를 줄이지만, 업무 Role을 서버에서 검증하는 대체 수단은 아니다.

Rules는 ZIP에 포함된 `firestore.rules`를 Firebase에 **별도 배포한 후에만 적용**된다. 파일 덮어쓰기만으로 1차 실패 원인이 해소되지는 않는다.

### 24.4 저장·읽기 비용의 변화

| 항목 | 변경 전 | 변경 후 코드 기준 |
| --- | --- | --- |
| 일반 계정 중복 확인 | 예약 문서 서버 GET 1회 | 동일 |
| 정상 계정 생성 | 원본·코드 예약·View 3건 Batch | 동일 |
| View 부모 문서 누락 | 개발자 인증 없으면 전체 Batch 실패 가능 | 제한된 형태의 최초 CREATE 시 성공 가능 |
| 계정 관리 권한이 없는 Role의 요청 | UI 진입 권한에 의존 | `UserState`에서 Role 재확인 후 Firestore 요청 전 차단 |
| 추가 Firestore 조회 | 없음 | 없음 |
| 기존 지역의 레거시 폴백 | `usersMapComplete` 없으면 QUERY 발생 | 25장 당시 목록 차단으로 변경, 이후 26장에서 완료 플래그 의존성 제거 |

실제 과금은 SDK의 캐시·쿼리·인덱스·재연결 및 서버 규칙 평가 결과에 따라 달라진다. 새 규칙 함수는 Firestore `get()`·`exists()`를 호출하지 않는다. 등록 실패 원인 추적을 위해 추가 읽기 작업을 넣지 않았다.

### 24.5 개발자 STATUS Dialog 및 로그 복사

`AccountRoleDiagnostics.recordCreation()`은 계정 생성 시작·중복 코드 확인·허용 Role·Batch 요청·커밋 성공·실패 사유를 비식별 문자열로 메모리에 최대 160개 보존한다. 개발자 모드 OFF에서 발생한 최초 실패도 기록하므로, 나중에 개발자 인증을 완료한 후 STATUS Dialog에서 최근 생성 진단 3개를 확인할 수 있다. `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()`의 기존 복사 공급자는 이 기록을 `debugPrint(...)` 코드로 합쳐 클립보드에 제공한다. 복사 직전과 직후의 개발자 모드 재검증, Firebase Activity Journal, 인증 상태 요약 및 기존 민감정보 마스킹을 유지한다. 계측 전용 Firestore 호출은 추가하지 않는다.

### 24.6 UI 애니메이션과 표시명

| 부분 | 변경 전 | 변경 후 |
| --- | --- | --- |
| `headStaff` Role 표시 | 원본 ZIP `본사   직원` | `본사 직원` (공백 1칸) |
| Firestore의 Role 값 | `headStaff` | 동일 |
| 계정 설정 저장 오류 영역 | `AnimatedSize` | `AnimatedSize` + Fade/Slide `AnimatedSwitcher` |
| 운영 계정 생성 버튼 | 진행·기본 페이드 전환 | Fade/Scale `AnimatedSwitcher` |
| 개발자 STATUS 보안 정보 | Fade/Slide/Size 전환 | 기존 애니메이션 유지, 계정 생성 진단 변경 시 갱신 |
| 접근성 애니메이션 비활성화 | `MediaQuery.disableAnimations` 사용 | 동일, duration 0 처리 |
| 화면 힌트 텍스트 | 기존 화면 설계 | 신규 `hintText`·`helperText` 미추가 |

수정 Dart 파일에 주석을 새로 삽입하지 않았으며, 소스 파일 전체를 원본 구조로 유지한다.

### 24.7 수정 대상 파일

| 파일 | 변경 요지 |
| --- | --- |
| `firestore.rules` | 단일 Projection에 한정된 View 최초 CREATE 규칙 추가 |
| `lib/app/models/account_role.dart` | `headStaff` 표시 공백을 하나로 정정 |
| `lib/app/models/account_role_diagnostics.dart` | 개발자 모드 OFF에서도 보존되는 비식별 계정 생성 로그·revision 추가 |
| `lib/features/account/applications/user_state.dart` | `canManageAccounts` 검사로 일반 계정 생성 전 권한 차단 |
| `lib/features/account/data/services/user_write_service.dart` | 일반 생성 경로의 실패·커밋 추적을 계정 생성 저널에 연결 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 운영 관리 생성 경로의 성공·실패 추적을 동일 저널에 연결 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | STATUS 보안 카드에 최근 계정 생성 진단 표시 및 변경 구독 |
| `lib/app/diagnostics/firestore_rules_audit.dart` | 제한적 CREATE의 로컬 규칙 판정: 충분한 요청 데이터 없으면 UNKNOWN 유지 |
| `lib/features/account/pages/user/sheets/user_setting.dart` | 권한 및 서버 실패 안내 분리, 오류 영역 Fade/Slide 전환 |
| `lib/shared/secondary/pages/sheets/tabs/user_account_tab.dart` | 생성 로딩 아이콘 Fade/Scale 전환 |
| `README.md` | 해당 장 신설, 근거·규칙·비용·사용자 경험·검증 경계 기록 |

### 24.8 검증 상태 및 적용 절차

1. 수정 전체 파일은 원래 상대경로대로 ZIP으로 구성하고 다른 프로젝트 소스는 포함하지 않는다.
2. Firestore 서버 Rules는 별도 배포 전까지 기존 정책 그대로다. 소스가 바뀌어도 Rules가 배포되지 않으면 일반 사용자 View CREATE는 계속 거부될 수 있다.
3. 정적 스크립트 검증은 Role 코드, 권한, 3건 Batch, 진단 로그 연결, 주석·힌트 텍스트 미추가 및 파일 경로에 한정한다.
4. 실제 Rules 컴파일·Emulator 허용/거부 시험, Android Flutter 빌드, 운영 Firebase 읽기/쓰기와 청구 지표 확인, 4개 허용 Role의 개발자 모드 OFF 재현은 이번 로컬 작업 범위에서 실행되지 않았다.
5. 운영 배포 전 Firebase Emulator에서 개발자 없는 상위 View 최초 CREATE, 기존 View UPDATE, 임의 메타 CREATE 거부, 허용되지 않은 계정 관리자 UI, 3문서 Batch 원자성, 레거시 읽기 유지 및 STATUS 클립보드 코드를 확인해야 한다.
6. 이 변경은 앱 인증 Role과 서버 인증을 완전히 동일하게 만드는 보안 설계가 아니다. 업무 Role의 악의적 SDK 우회 차단까지 요구하는 경우, 신뢰할 수 있는 서버 측 Role 매핑을 먼저 설계한 뒤 Rules를 다시 강화해야 한다.


## 25. 계정 목록 View 단일 조회·명시적 상세 편집·안전 이관 — 2026-11-07 (과거 이력, 26장에서 대체)

이 장의 `usersMapComplete` 검사, 이전 자료 보호·관리자 이관 도구 안내는 25장 작성 당시 정책으로 보존하는 이력이다. 신규 View Map 구조의 현행 실행·검증 기준은 26장을 따른다. 아래 `tool/migrate_user_accounts_show.mjs`는 이번 덮어쓰기 파일에 포함하지 않으며 실행을 요구하지 않는다.

### 25.1 범위 및 불변 계약

기준은 `261107 1606.zip`이다. 기존 7개 Role, 계정 관리 허용 4개 Role, `user_accounts` Root 전체 계정 원본, 코드 예약, 생성 3건 Batch, View Map 부분 쓰기, 개발자 모드·STATUS 복사, 애니메이션 및 1MiB 제한은 유지한다. 목록을 위한 조회만 `user_accounts_show/{division}-{area}` GET 한 번으로 고정한다. 기존 1~24장의 당시 작업 이력은 남겨 두며, 이 장을 현재 목록 정책으로 우선 적용한다.

### 25.2 수정 전·후와 사용자 경험

| 사용자 동작 | 수정 전 | 수정 후 코드 경로 | 예상 Firestore 효과 |
| --- | --- | --- | --- |
| 완료된 지역 목록 열기 | View GET 1회 | 동일 | 변화 없음 |
| 완료 플래그 없는 지역 목록 열기 | View GET + 레거시 하위 컬렉션 QUERY | View GET 뒤 `USER_ACCOUNT_VIEW_MIGRATION_REQUIRED` 명시 | 레거시 반복 QUERY 0회, 대신 관리 이관 필요 |
| View 상위 문서가 없는 지역 | GET 후 레거시 QUERY 가능 | `USER_ACCOUNT_VIEW_MISSING` 명시 | 임의 빈 목록·레거시 반복 조회 방지 |
| 목록의 이름·Role·활성 상태 검색 | 로컬 상태 | 동일 | 추가 Firestore 호출 없음 |
| 운영 관리에서 직원 행 선택 | 즉시 Root GET 후 편집기 확장 | View 목록 기준 선택만 수행 | 단순 선택 Root GET 0회 |
| 운영 관리의 `상세 수정` | 행 선택 즉시 편집 | 버튼 누를 때 Root GET 후 편집기 확장 | 실제 편집 시에만 Root GET 1회 |
| 상세 Root 조회 실패 | 편집기 열지 않음 | 동일, 오류 표시 | 정합성 유지 |
| 신규 계정 생성 | 예약 GET과 3건 Batch | 동일 | 저장 비용 구조 유지 |
| 개발자 모드 ON STATUS | 생성 진단 복사 | 생성 진단 + 비식별 목록 진단 및 Activity Journal 복사 | Firestore 추가 조회 없음 |

단일 View 문서는 반환 크기만큼 전송되며 읽기 수 감소를 전체 네트워크 요금 절감과 동일시하지 않는다. `Source.serverAndCache`는 SDK 응답원이 캐시일 수도 있으므로 `documentGetRequests=1`, `fromCache`로 기록한다. 목록 GET과 다른 업무·편집·코드 검사 GET은 분리하여 분석한다.

### 25.3 코드별 변경 사항

| 전체 파일 경로 | 변경 내용 |
| --- | --- |
| `lib/features/account/data/services/user_account_show_map.dart` | `completeEntries()`로 문서 누락 및 이관 미완료 상태 구분 |
| `lib/features/account/data/services/user_read_service.dart` | 일반·활성 계정 목록의 레거시 QUERY 삭제, View GET 1회, 활성 필터 로컬 처리·비식별 진단 |
| `lib/features/account/applications/user_state.dart` | 회사·지역 불명확 시 Root 컬렉션 QUERY 대체 금지, 오류 상태 보존 |
| `lib/features/account/pages/user/user_management.dart` | 미완료·누락 View를 빈 계정 목록 대신 오류 상태로 표시 |
| `lib/shared/secondary/pages/sheets/tabs/user_account_tab.dart` | View 단일 조회, 지역 Future 캐시 유지, 단순 행 선택과 `상세 수정` Root GET 분리, Fade·Slide 전환 유지·확장 |
| `lib/app/models/account_role_diagnostics.dart` | 개발자 모드 OFF에서도 비식별 목록 이벤트를 최대 160건 보관하고 STATUS 복사용 `debugPrint(...)`로 직렬화 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | 개발자 모드 ON의 STATUS 보안 카드에 목록 요약 표시, 변경 감지, 기존 클립보드 코드를 통합 |
| `tool/migrate_user_accounts_show.mjs` | 신규 1회 관리자 이관 도구, 기본 dry-run, 명시적 `--apply`와 충돌·용량 점검 |
| `README.md` | 12·13·14장 현재 계약 정정, 24장 CEO 표현 정정, 25장 이력 추가 |

### 25.4 데이터 이관·배포 순서

1. 사용자를 등록·수정하는 쓰기 작업을 일시 중단하고, 대상 지역의 Root·예약·현재 View·하위 레거시 문서를 백업한다.
2. 운영 Firebase의 관리자 자격 증명을 외부 환경 변수 `GOOGLE_APPLICATION_CREDENTIALS`에 설정한다. 프로젝트 소스나 ZIP에 인증키를 넣지 않는다. Node 환경에서 Firebase Admin SDK를 사용할 수 있어야 한다.
3. `node tool/migrate_user_accounts_show.mjs --division "회사명" --area "지역명"`으로 dry-run한다. 이 도구는 `user_accounts` 전체를 1회 조회하고 대상 View·레거시 하위 컬렉션을 확인한다. **이관은 일회성 읽기 비용이 발생한다.**
4. Root의 주 소속 회사·지역, View Map·레거시 사용자 ID, 9개 Projection 필드와 기존 Map 충돌 여부를 확인한다. 오브젝트 예상 크기 760000바이트 초과, 불일치, Root 누락, 소속 불일치 시 도구가 자동 적용을 거부한다.
5. 충돌이 없고 운영 데이터를 확인한 뒤 `node tool/migrate_user_accounts_show.mjs --division "회사명" --area "지역명" --apply`를 **관리자 승인하에** 실행한다. 변경된 View 문서의 updateTime이 사전 확인 시점과 다르면 Transaction은 중단한다.
6. 도구는 대상 View의 `users` Map과 `usersMapComplete=true`를 한 문서에 기록한다. 다른 Root·예약·레거시 하위 문서는 삭제하지 않고, 성공 후 View를 재조회해 사용자 항목을 검증한다. 마이그레이션이 끝나면 일반 목록 로딩은 View GET 한 번으로 처리한다.
7. 신규 지역·기존 지역·빈 지역·이관 전 지역·View 누락 지역을 실환경에서 각각 확인한다. 관리자용 CLI는 실제 서비스 데이터의 소속 의미를 추정해 정정하지 못하므로 충돌 지역은 수동 대조 후 별도 승인한다. 이관하지 않은 지역은 새 코드에서 목록 오류를 보일 수 있으므로 **선이관 후 배포**가 필요하다.

이 도구는 `firebase-admin`에 의존한다. 프로젝트 루트에 Firebase 설정 패키지 자체가 포함되어 있지 않으므로 Node 환경에서 해당 패키지를 설치해야 하며, 이 패치는 인증 자격 증명이나 `node_modules`를 제공하지 않는다. App용 `firestore.rules`를 Admin SDK가 우회한다는 점을 감안해 별도 최소 권한 관리자 환경에서만 사용한다.

### 25.5 로그·복사·모션

`AccountRoleDiagnostics.recordList()`는 계정 목록 GET 시작·완료·실패, 단순 행 선택, 편집 Root GET의 요청·결과를 비식별 문자열로 기록한다. 개발자 모드가 OFF여도 당일 세션 내 최근 기록은 메모리에 남으며, ON 상태에서 `ParkinWorkinTerminalDiagnostics.showStatus()`의 STATUS 보안 요약에 최근 3건이 표시된다. 기존 `debugPrintCodeWithJournal()`는 새로운 목록 기록도 `debugPrint(...)` 코드로 포함하며 복사 시 개발자 모드 여부를 다시 확인한다. 민감한 이메일·계정 원문 ID·코드번호를 새 목록 진단에 출력하지 않는다.

운영 관리 목록은 기존 FutureBuilder Fade·Slide, 행 Reveal·회전·로딩 AnimatedSwitcher를 유지한다. 행 선택 후 상세 수정 버튼과 편집기 전환에 Fade·Slide AnimatedSwitcher를 추가하고 `MediaQuery.disableAnimations`가 참이면 전환 시간을 0으로 만든다. 신규 `hintText`·`helperText` 및 소스 주석은 추가하지 않는다.

### 25.6 보안·과금·검증 경계

현재 Rules의 `_isAccountProjectionCreate()`는 조건을 만족하는 Google 사용자 전체에 제한적 View CREATE를 허용하며 업무 Role 4개를 서버에서 직접 검증하지 않는다. 이 읽기 최적화 패치에서는 Rules나 Role, 3건 Batch를 변경하지 않았다. 이전 24장에서 지적한 서버 Role 검증 범위와 `DevUserWriteService`의 내부 Role 검사 일관성 문제는 아직 해결 완료로 표시하지 않는다.

정적 소스 차이, 모든 변경 파일의 전체 코드 포함, Node CLI의 구문 검사는 로컬에서 확인할 수 있다. 그러나 Firebase Admin SDK와 실제 프로젝트 인증, Flutter/Dart SDK, Firebase Emulator가 없는 환경에서는 마이그레이션 실행, Rules 컴파일·실제 과금량·Flutter 빌드·실기기 클립보드 및 모션 시험을 검증할 수 없다. 위 항목들은 운영 적용 전에 별도로 확인해야 한다. 변경은 덮어쓰기용 전체 파일로 제공하고 원본 ZIP은 보존한다.


## 26. 신규 View Map 단일 원본·레거시 의존성 제거 — 2026-11-07

### 26.1 목적 및 확정 전제

기준은 `261107 1656.zip`이다. 기존 데이터의 이관·하위 호환성은 설계에서 제외한다. 신규 데이터 삭제·초기화는 수행하지 않으며 기존 7개 Role, 계정 관리 허용 4개 Role, Root 전체 데이터, 코드 예약, 생성 3문서 Batch, 상세 편집 Root GET, 회사·지역의 원자적 저장과 화면 기능은 유지한다. `firestore.rules`는 이번 리팩터링에서 변경하지 않는다.

### 26.2 계정 목록 계약 및 사용자 경험

| 상황 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 정상 `users` Map, 완료 플래그 없음 | `USER_ACCOUNT_VIEW_MIGRATION_REQUIRED` 오류 | View GET 결과로 목록 표시 |
| `users` Map이 비어 있음 | 완료 플래그 없으면 오류 | 정상 직원 0명 표시 |
| View 문서 없음 | `USER_ACCOUNT_VIEW_MISSING` | 동일 오류 유지 |
| `users` 필드가 Map이 아님 | `USER_ACCOUNT_VIEW_USERS_INVALID` | 동일 오류 유지 |
| 완료 플래그가 존재하는 문서 | 조건부 허용 | 검사하지 않음 |
| 목록 검색·필터·직원 선택 | View 기반 로컬 처리 | 유지, 추가 Root GET 없음 |
| `상세 수정` 실행 | Root 서버 GET | 유지, 상세 설정 정확성 보존 |
| 저장 후 오류 상태 | 기존 화면 흐름 | 기존 오류·새로고침 흐름 유지 |

목록은 선택한 회사·지역의 `user_accounts_show/{division}-{area}` 문서 GET 1회를 기준으로 하고 `validatedEntries()`가 `users` Map과 하위 항목 형식을 검사한다. 일반 사용자 목록·활성 사용자 목록·운영 관리 탭의 목록 3경로에 동일한 판정이 적용된다. 회사·지역 조회, 계정 코드 중복 확인, 실제 Root 편집과 쓰기까지 모두 없앴다는 의미는 아니다.

### 26.3 구형 하위 컬렉션 의존성 제거

| 코드 영역 | 수정 전 | 수정 후 |
| --- | --- | --- |
| `user_account_show_map.dart` | `usersMapComplete` 확인 | 완료 플래그 제거, `validatedEntries` |
| `user_read_service.dart` | Root 활성 상태 누락 시 구형 단일 사용자 GET 가능 | 현재 상위 View Map만 확인 |
| `user_active_state_backfill_service.dart` | 필요 시 구형 전체 사용자 QUERY 및 비밀번호 정리 | 현재 View Map만 검사·정리, 구형 QUERY 없음 |
| `user_write_service.dart` | 수정·상태·삭제 시 구형 View GET/DELETE | Root·예약·현재 Map 검증과 부분 쓰기만 사용 |
| `dev_user_write_service.dart` | 운영 관리 수정 Transaction에서 구형 GET/DELETE | 현재 Root·예약·Map 기준 Transaction |
| `area_management.dart`, `add_area_tab.dart` | 회사·지역 삭제 시 구형 하위 QUERY | 현재 View Map 및 관련 Root 계정 검사 유지 |
| `dev_bootstrap_service.dart` | 초기화 시 구형 하위 사용자 GET | Root와 상위 View 메타 존재 상태로 검사 |
| `dev_management_common.dart` | 신규 View에 `usersMapComplete=true` | 완료 플래그 미작성 |

구형 문서를 제거하기 위해 별도 DELETE를 추가하지 않는다. 계정 수정·이동에서 원본 Map 항목 누락 시 `SHOW_USER_DOC_MISSING`으로 중단하고 다른 사용자 Map을 덮어쓰지 않는다. 코드번호 예약의 소유자 검사와 Root 존재 확인은 유지한다. 최신 저장 정책에서 부가적인 DB 읽기·쓰기 없이 데이터를 일관되게 관리하도록 한다.

### 26.4 비용·보안 경계

| 업무 | 이전 코드의 비용 발생 후보 | 이번 구조의 예상 동작 |
| --- | --- | --- |
| 목록 GET | Map + 완료 여부 판단 | View GET 1회, 추가 레거시 QUERY 0회 |
| 사용자 단순 선택 | 이전 25장부터 Root 조회 없음 | 추가 Root GET 0회 유지 |
| 실제 상세 편집 | Root GET | Root GET 유지 |
| 계정 변경·이동 | 일부 구형 하위 GET/DELETE | 관련 구형 요청 0회 |
| 계정 삭제·활성 상태 | 구형 하위 GET 및 조건부 DELETE | 관련 구형 요청 0회 |
| 회사·지역 삭제 사전 검사 | 구형 빈 QUERY 발생 가능 | 구형 QUERY 0회 |
| 신규 계정 생성 | 코드 예약 GET 1회 및 Batch 3건 | 유지 |

정확한 비용 감소율은 SDK 캐시·서버 응답·Firestore 인덱스·과금 지표로 확인해야 하며, GET 횟수를 실제 청구 건수와 동일시하지 않는다. View 단일 문서 최대 1MiB 크기와 문서 핫스팟 가능성은 그대로 존재한다. 현재 Rules의 제한된 View 최초 CREATE는 업무 Role 4개를 서버 측에서 독립적으로 검사하지 못하므로 별도 보안 과제로 남긴다.

### 26.5 진단, STATUS 복사 및 애니메이션

`AccountRoleDiagnostics.recordList()`가 비식별 계정 목록·활성 상태 보정·수정·삭제의 `map_only` 및 `legacyViewReads=0` 기록을 `debugPrint`와 메모리 진단에 남긴다. 개발자 모드 OFF에서 쌓인 비식별 진단도 개발자 모드 ON 뒤 STATUS Dialog에서 최근 기록을 확인할 수 있다. 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()`는 로그를 `debugPrint(...)` 코드로 직렬화하고 `StatusDialog`의 클립보드 복사 공급자에 제공한다. 열기·복사 시 개발자 모드를 다시 검사하며 진단을 위해 추가 Firestore 읽기를 실행하지 않는다.

일반 계정 목록의 결과 전환에는 180ms Fade·Slide를 적용한다. 운영 관리 계정 목록과 상세 편집의 기존 AnimatedSwitcher·Fade·Slide·AnimatedSize는 유지한다. 모든 신규 전환은 `MediaQuery.disableAnimations` 활성 시 `Duration.zero`로 변경한다. 수정 Dart 파일에 코드 주석과 신규 `hintText`·`helperText`를 삽입하지 않는다.

### 26.6 수정된 전체 파일

| 파일 경로 | 변경 요지 |
| --- | --- |
| `lib/features/account/data/services/user_account_show_map.dart` | 완료 플래그 의존 제거·유효 Map 검사 |
| `lib/features/account/data/services/user_read_service.dart` | 목록·활성 상태 Map 기준 통일 |
| `lib/features/account/data/services/user_active_state_backfill_service.dart` | 구형 하위 QUERY/정리 제거 |
| `lib/features/account/data/services/user_write_service.dart` | 수정·상태·삭제의 구형 GET/DELETE 제거, 진단 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 운영 관리 수정의 구형 GET/DELETE 제거, 진단 |
| `lib/shared/secondary/pages/sheets/tabs/dev_management_common.dart` | 신규 완료 플래그 미작성 |
| `lib/shared/secondary/pages/sheets/tabs/user_account_tab.dart` | 완료 플래그 없는 View 목록 로딩·오류 안내 정정 |
| `lib/features/account/pages/user/user_management.dart` | 이관 안내 제거·목록 Fade/Slide 추가 |
| `lib/shared/secondary/pages/sheets/area_management.dart` | 회사 삭제의 구형 QUERY 제거 |
| `lib/shared/secondary/pages/sheets/tabs/add_area_tab.dart` | 지역 삭제의 구형 QUERY 제거 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | 초기 메타 검증의 구형 GET 제거 |
| `README.md` | 현재 12~14장 정정, 25장 과거 이력 표시, 26장 추가 |

### 26.7 검증 계획과 미완료 항목

정적 코드 검사에서는 `usersMapComplete`, `USER_ACCOUNT_VIEW_MIGRATION_REQUIRED`, 구형 `user_accounts_show/*/users` 클라이언트 요청이 남지 않아야 한다. 수정 파일의 원래 상대 경로·원문 전체 포함, 신규 힌트 텍스트·주석 미삽입 및 ZIP CRC를 검사한다. Flutter/Dart SDK와 Firebase Emulator가 없는 환경에서는 실제 컴파일·Rules 권한·계정 4개 허용 Role/3개 차단 Role·데이터 정합성·클립보드·화면 애니메이션·과금 감소 여부는 미검증으로 표시해야 한다. 운영 데이터 삭제나 DB 초기화, Rules 배포는 이 덮어쓰기 패키지에 포함되지 않는다.


## 27. Google 인증 유지 상태의 계정 관리·생성·수정 결과 정합성 — 2026-11-07

### 27.1 기준 및 제외 사항

기준 압축본은 `261107 1730.zip`이며, 현재 정책은 26장의 `user_accounts_show/{division}-{area}` 단일 목록 View와 Root 상세 편집을 유지한다. 기존 7개 Role 및 계정 관리 허용 Role `ceo`, `headAdmin`, `headStaff`, `branchProAdmin`를 유지한다. 개발자 모드와 STATUS Dialog는 업무 권한을 부여하지 않는다. Firebase Custom Claims, Claims 발급 CLI, Cloud Functions, 신규 UID 매핑, 기존 데이터 마이그레이션 도구 및 운영 DB 삭제는 수행하지 않는다. `firestore.rules`도 변경하지 않는다.

### 27.2 발견된 문제와 사용자 경험

| 문제 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 생성 성공 뒤 로컬 캐시 오류 | 서버 저장이 끝났어도 전체 생성 실패로 안내될 수 있음 | 서버 커밋 성공을 확정하고 캐시 실패를 비식별 이벤트로 분리 |
| 수정 성공 뒤 로컬 캐시 오류 | 저장 완료 후 `false`를 반환할 수 있음 | 서버 수정 성공을 유지하고 후처리 오류만 기록 |
| 목록 조회 실패 후 생성 성공 | 이전 `_userListLoadError`가 남아 새 계정이 가려질 수 있음 | 이전 목록이 완전했으면 로컬 갱신·오류 제거, 불완전하면 View 복구 조회 |
| 회사가 다른 동일 지역명 | 사용자 로컬 캐시가 지역명만으로 구분될 수 있음 | `division|area` 조합으로 캐시 키·유효 범위 분리 |
| 운영 관리 생성·수정 | 서비스 진입점에서 요청자의 Role 검사를 생략 | 호출 화면과 일반 관리 서비스에서 업무 Role 검사. 초기 개발 계정 생성 별도 처리 |
| 오류·정상 목록 전환 | 기존 Fade·Slide | Fade·Slide·Scale 유지·보완, 모션 감소 시 0ms |

### 27.3 계정 관리 화면의 View·캐시 계약

`UserState.refreshUsersBySelectedAreaAndCache()`는 지정한 회사·지역의 `user_accounts_show/{division}-{area}` GET으로 목록을 읽고 그 범위를 검증된 목록으로 기록한다. 검증된 상태의 생성·수정에는 메모리 목록을 반영하고 추가 GET을 호출하지 않는다. 이전 GET이 실패했거나 선택 범위가 달라 검증되지 않은 목록이라면 서버 저장 성공을 취소하지 않고 해당 View를 다시 GET한다. 복구 조회가 실패해도 저장 성공은 유지하며 목록 오류를 별도로 보인다. `user_read_service.dart`의 SharedPreferences 사용자 캐시는 회사·지역 복합 키를 사용하고, 서버 GET 성공 후 로컬 캐시 기록에 실패하더라도 서버 응답 결과를 목록 오류로 오인하지 않는다. 로그인 보조 로컬 캐시를 읽는 영역 전환 또한 같은 복합 키를 사용한다.

### 27.4 계정 생성의 성공 기준

`UserState.addUserCard()`는 `RoleType.canManageAccounts`를 확인한 후 Root·코드 예약·View 3문서 Batch를 요청한다. 서버 저장 예외는 실제 생성 실패로 전달하지만, 커밋 이후 로컬 캐시·목록 재동기화 오류를 동일한 실패로 전달하지 않는다. `UserSettingWorkspace`는 서버 저장 성공 시 성공 안내를 유지하며 이미 저장된 계정의 중복 재제출을 유도하지 않는다. 코드번호 자동 재발급은 서버에서 실제 `CODE_NUMBER_ALREADY_EXISTS`를 반환한 경우의 기존 동작을 유지한다.

### 27.5 계정 수정의 성공 기준

`UserState.updateUserCardAsAdmin()`은 실제 Firestore 원본 수정의 성공 여부를 반환한다. 로컬 목록·캐시 반영은 후처리로 구분한다. `UserAccountsTab`의 운영 수정은 기존 Root GET 및 `DevUserWriteService.updateUser()` Transaction을 유지한다. 운영 생성·수정에서 서버 커밋 성공 후 화면 이동, Dialog 또는 캐시 무효화 중 예외가 발생해도 저장 실패로 표시하지 않고 비식별 후처리 이벤트를 남긴다. 요청자 Role 4종의 앱 내부 검사는 정상 초기 개발 계정 생성과 구분한다.

### 27.6 일반·운영 관리 Role 계약과 서버 보안 한계

| Role | 앱 내부 일반 계정 관리 |
| --- | --- |
| `ceo`, `headAdmin`, `headStaff`, `branchProAdmin` | 생성·수정 허용 |
| `branchAdmin`, `branchStaff`, `branchProStaff` | 생성·수정 거부 |

`DevUserWriteService.createUser()`와 `updateUser()`의 일반 경로는 호출자가 제공한 업무 세션 Role을 확인하고 서버 조회 이전에 권한이 없으면 중단한다. 개발자 초기화용 `createBootstrapUser()`는 `DevBootstrapService`의 기존 Firebase 인증 검증을 거친 후에만 호출한다. 이는 **클라이언트 내부 정책**이며 신뢰된 서버 Role 인증이 아니다. 현재 `firestore.rules`의 Google 인증 기반 쓰기 허용과 제한적 최초 View CREATE는 직접 Firestore SDK를 호출하는 업무 Role 미허용 사용자를 서버에서 구별하지 못한다. 이를 보완했다고 선언하지 않는다. 특히 신규 Claims, 발급 도구, 권한 문서 없이 Role을 서버에서 검증할 수 있다고 가정하지 않는다.

### 27.7 비용 및 호출 변화

| 업무 | 수정 전 | 수정 후 코드상 목표 |
| --- | --- | --- |
| 정상 목록 최초 진입 | View GET 1회 | View GET 1회 |
| 정상 목록에서 생성 후 복귀 | 유효 목록도 실패 상태가 남을 가능성 | 로컬 목록 갱신, 목록 추가 GET 0회 |
| 이전 목록 오류에서 생성 성공 | 로컬 일부 항목 또는 오류 잔존 | 해당 View 복구 GET 필요 시 1회 시도 |
| 일반 신규 생성 | 예약 GET 1회 + Batch 3건 | 유지 |
| 운영 신규 생성 | 코드·Root GET 2회 + Batch 3건 | 유지 |
| 상세 편집 | Root GET 및 정합성 Transaction | 유지 |
| 거부 Role의 정상 앱 요청 | 경로별 검사 불일치 | 서비스 진입점에서 서버 조회 이전 차단 |
| 개발자 STATUS 로그 | 로컬 진단·클립보드 | 로컬 이벤트 추가, Firestore 진단용 추가 GET 없음 |

위 수치는 코드의 요청 경로 기준이며, 서버 청구량·인덱스 읽기·Firestore SDK 자동 재시도·캐시 반환에 따라 실제 과금은 달라진다.

### 27.8 디버그프린트와 모션

생성·수정의 역할 허용·거부, 서버 커밋, 로컬 캐시 성공·실패, 목록 유효성·복구 성공·실패, 운영 화면의 커밋 후 예외를 `AccountRoleDiagnostics.recordCreation()`·`recordList()`의 비식별 `debugPrint` 기록으로 남긴다. 개발자 모드 OFF에서도 해당 비식별 이벤트를 세션 내 메모리에 수집한다. ON 상태의 STATUS Dialog에서 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()`을 통해 `debugPrint(...)` 문장과 Activity Journal을 클립보드로 복사하고, 복사 직전에 모드를 재검사한다. 이메일·계정 ID·코드번호·토큰 원문을 신규 진단에 추가하지 않는다. 계정 관리의 기존 Fade·Slide 전환에 미세한 Scale 효과를 결합한다. `MediaQuery.disableAnimations`가 참이면 애니메이션 시간을 0으로 한다. 신규 `hintText`·`helperText`와 수정 Dart 파일의 코드 주석은 삽입하지 않는다.

### 27.9 전체 수정 파일과 책임

| 수정 파일 | 작업 |
| --- | --- |
| `lib/features/account/applications/user_state.dart` | View 목록 검증 범위, 성공 후 로컬 목록/캐시/재동기화 분리, 생성·수정 결과 진단, 로컬 캐시 복합 키 |
| `lib/features/account/data/services/user_read_service.dart` | View GET 성공과 SharedPreferences 기록 실패 분리, 지역별 캐시 키 회사·지역 조합으로 기록 |
| `lib/features/account/pages/user/user_management.dart` | 생성 후 서버 재조회 생략 시 현재 목록 완전성 확인, 목록 Fade·Slide·Scale |
| `lib/features/account/pages/user/sheets/user_setting.dart` | 서버 저장 성공과 캐시 후처리의 로그 의미 구분 |
| `lib/shared/secondary/pages/sheets/tabs/user_account_tab.dart` | 일반 운영 생성·수정 요청자 Role 검사, 서버 커밋 후 UI 예외 분리 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 일반 생성·수정 Role 검사 및 초기 개발 계정 전용 생성 메서드 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | 기존 초기 인증 검사를 유지한 채 전용 생성 메서드 호출 |
| `README.md` | 현행 12장·27장 정정 및 변경 이력 추가 |

`firestore.rules`, STATUS Dialog 본체 및 계정 저장 Batch는 수정하지 않는다. 각 기존 기능의 복사·모션 연결을 재사용해 불필요한 파일 변경을 억제한다.

### 27.10 정적 확인과 미검증 항목

수정 파일 전체를 원래 상대 경로로 포함하고 신규 `hintText`·`helperText`, 코드 주석, Custom Claims와 관리용 `tool/` 추가가 없는지 확인한다. `user_accounts_show` 목록 조회, 계정 생성 3건 Batch, 운영 관리 요청자 Role 검사, 초기 개발 계정 생성 전용 경로, 개발자 모드 ON 상태의 STATUS 복사 및 모션 감소 분기를 정적 검사한다. Flutter/Dart SDK와 Firebase Emulator가 없는 환경에서는 `flutter analyze`, 실제 계정 4개 허용 Role 및 거부 Role 테스트, Firebase Rules 실행, Android 클립보드, 애니메이션 프레임, 운영 Firestore 과금 감소를 검증할 수 없다. 실행·배포 완료로 기록하지 않는다.


## 28. Double·Triple·Minor 입차 완료 `plates` 초기 조회 제거 — 2026-11-07

### 28.1 기준·범위·제외

본 변경 기준은 사용자 제공 `261107 1901.zip`이다. 세 모드의 *최초 화면 활성화 때* 실행되는 `PlateType.parkingCompleted` 원본 `plates` 조회를 제거하며, `PlateType.departureCompleted` 초기 조회는 유지한다. Single 모드는 해당 초기 조회가 원래 없으므로 수정하지 않는다. 출차 완료 지연 로딩·기간 제한·페이지네이션, 주행 복구, TTS Baseline·리스너, 기존 View 구독, Firestore Rules, 사용자 계정 기능, Firebase Custom Claims 도입 및 관리용 도구는 수정 범위에서 제외한다. 화면 표시와 선택 상태 처리의 기능 회귀는 별도 실기기 시험 대상으로 남긴다.

### 28.2 발견 근거와 조회 경로

`2026-11-07T20:01:08.701`의 Firebase Activity Journal에는 `firestore_plate_repository.dart` 발행 `plates` 서버 QUERY 3회가 모두 `documents=0`으로 기록됐다. Minor 화면 기본 완료 유형 2건과 DrivingRecoveryGate의 선택 차량 복구 1건이라는 코드 경로에 부합하지만, Journal은 각 QUERY 필터를 기록하지 않으므로 요청 ID별 필터를 로그만으로 확정할 수는 없다. 화면 초기화 경로의 조회 구조는 `TypePageShell`의 `enableForTypePages(withDefaults: true)` → 모드별 `*PlateState._initDefaultLoads()` → `*SubscribeType()` → `*RefreshType()` → `PlateRepository.fetchPlatesByTypeAndArea()`로 확인한다. `*SubscribeType()`은 유형을 `_activeTypes`에 넣고 즉시 서버 조회를 시작한다. 현재의 초기 `parkingCompleted` 조회는 조건에 맞는 `plates` 문서를 제한 없이 가져올 수 있어 해당 지역의 문서 누적량과 함께 읽기가 증가한다.

### 28.3 모드별 수정 전후 — 초기 `plates` QUERY

| 모드 | 입차 완료 원본 조회 전→후 | 미정산 출차 완료 원본 조회 전→후 | 주행 복구 전→후 | 초기 합계 전→후 |
| --- | --- | --- | --- | --- |
| Single | 0→0 | 0→0 | 0→0 | **0→0** |
| Double | **1→0** | 1→1 | 0→0 | **2→1** |
| Triple | **1→0** | 1→1 | 1→1 | **3→2** |
| Minor | **1→0** | 1→1 | 1→1 | **3→2** |

숫자는 해당 모드의 기본 화면 활성화 경로를 기준으로 한 예상 SDK QUERY 실행 횟수다. Plate TTS의 별도 Baseline·실시간 Listener, `parking_completed_view`·다른 View 구독, 검색·상세 화면에서 명시적으로 요청한 조회, 서버 재시도 및 실제 Firestore 과금은 별개다. 초기 화면에서 해당 문서가 없더라도 빈 QUERY의 최소 읽기 과금이 생길 수 있고, 조건에 맞는 문서가 수십·수백 개라면 원본 쿼리의 읽기 규모도 그만큼 커질 수 있다.

### 28.4 수정 파일 및 정확한 변경

| 전체 상대경로 | 수정 전 `_initDefaultLoads()` | 수정 후 `_initDefaultLoads()` | 유지할 경로 |
| --- | --- | --- | --- |
| `lib/shared/plate/application/double/double_plate_state.dart` | `doubleSubscribeType(PlateType.parkingCompleted);` + `doubleSubscribeType(PlateType.departureCompleted);` | `doubleSubscribeType(PlateType.departureCompleted);`만 실행 | Double 출차 완료 조회 |
| `lib/shared/plate/application/triple/triple_plate_state.dart` | `tripleSubscribeType(PlateType.parkingCompleted);` + `tripleSubscribeType(PlateType.departureCompleted);` | `tripleSubscribeType(PlateType.departureCompleted);`만 실행 | Triple 출차 완료 및 주행 복구 |
| `lib/shared/plate/application/minor/minor_plate_state.dart` | `minorSubscribeType(PlateType.parkingCompleted);` + `minorSubscribeType(PlateType.departureCompleted);` | `minorSubscribeType(PlateType.departureCompleted);`만 실행 | Minor 출차 완료 및 주행 복구 |

세 Dart 파일은 해당 자동 호출 **각 1줄만 삭제**한다. `parkingCompleted` Enum, 허용 유형 집합, 명시적 조회·선택 함수, 정산 관련 코드는 삭제하지 않는다. `_activeTypes`에 초기 입차 완료가 추가되지 않기 때문에 최초 조회뿐 아니라 이후 지역 변경과 상태 동기화 시 그 *초기 활성 유형*에 의한 자동 재조회도 발생하지 않는다. 추후 다른 코드에서 해당 유형을 명시적으로 다시 활성화하면 그 요청은 기존대로 실행될 수 있다.

### 28.5 기존 화면·선택 상태·모션·STATUS 유지

세 모드의 입차 완료 실시간 표는 `parking_completed_view`를 데이터 원본으로 사용한다. View Listener 및 상세 조회, 검색, 화면 전환 애니메이션, `MediaQuery.disableAnimations`에 따른 접근성 처리는 변경하지 않는다. 모드별 `*ParkingCompletedPage._handleWillPop()`과 공통 `TypePageShell.clearCurrentSelection`에는 PlateState의 `*GetSelectedPlate(PlateType.parkingCompleted, ...)`를 참조하는 기존 경로가 남는다. 이 경로는 원본 목록 `_data[parkingCompleted]`가 비어 있으면 선택된 번호판을 반환하지 않는다. 실시간 테이블의 `RealTimeTabbedTableBackController.consumeBack()`가 우선 처리하는 화면 내부 뒤로가기와 이 보조 선택 해제 경로를 구분해야 한다. 기존 선택 해제의 실제 회귀 여부는 실기기 테스트로 확인할 것이며, 이를 이유로 전체 원본 QUERY를 복구하지 않는다.

기존 `debugPrint` 이벤트 기록 및 개발자 모드 ON일 때 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()` → `StatusDialog` `copyTextProvider` → 클립보드 복사 흐름은 유지한다. 초기 입차 완료 원본 QUERY가 빠졌다는 사실은 향후 Firebase Activity Journal에서 해당 조회 이벤트가 없고 출차 완료·주행 복구 이벤트는 남아 있는지 비교해 확인한다. 새로운 상태 화면, 사용자 힌트 텍스트, 불필요한 UI 애니메이션 및 별도 Firestore 진단 조회는 추가하지 않는다. 수정된 Dart 파일은 코드 주석 없이 유지한다.

### 28.6 Firestore 비용 전후 및 사용자 경험

| 사용자 행동 | 변경 전 | 변경 후 목표 |
| --- | --- | --- |
| Double 진입 | `plates` 입차 완료·미정산 출차 완료 각 1 QUERY | 입차 완료 원본 0, 출차 완료 1 QUERY |
| Triple 진입 | 완료 유형 2 QUERY + 주행 복구 1 QUERY | 출차 완료 1 QUERY + 주행 복구 1 QUERY |
| Minor 진입 | 완료 유형 2 QUERY + 주행 복구 1 QUERY | 출차 완료 1 QUERY + 주행 복구 1 QUERY |
| Single 진입 | 해당 초기 QUERY 없음 | 변경 없음 |
| 입차 완료 목록 보기 | 기존 `parking_completed_view` 실시간 표 | 동일한 View 표시 경로 유지 |
| 미정산 출차 완료 업무 | 기존 초기 데이터 이용 | 초기 조회 및 기존 메모리 데이터 이용 유지 |
| 검색·상세·선택 해제·뒤로가기 | 기존 구현 | 기존 경로 변경 없음, 선택 해제 동작 실기기 회귀 검증 대상 |
| 개발자 STATUS 로그 복사 | 개발자 모드 ON에서 `debugPrint(...)` 코드 복사 | 기존 연결 유지; 진단용 추가 DB 요청 없음 |

조건에 맞는 입차 완료 원본 문서가 30개였다면 기존 모드 진입에서 해당 쿼리로 최대 30개 문서가 반환될 수 있었지만 변경 후에는 **그 초기 원본 QUERY 자체가 없다**. 비어 있는 쿼리의 최소 읽기 비용 역시 해당 초기 호출에 대해 제거된다. 다만 전체 앱의 과금 절감 수치는 리스너·인덱스·다른 요청 등과 분리해 실제 Firebase 청구 지표로 확인해야 한다.

### 28.7 검증 및 운영 적용 경계

원본 압축본 대비 세 PlateState는 `parkingCompleted` 초기 구독 문장 각 1줄 삭제 외에는 변경이 없어야 하고, `departureCompleted` 초기 호출과 `parking_completed_view` 구독 및 Triple·Minor 주행 복구가 그대로여야 한다. README 수정과 함께 변경된 **전체 파일 4개만** 프로젝트 상대경로 그대로 덮어쓰기 ZIP에 포함한다. ZIP CRC·내용 해시, 변경 Dart 파일 주석·신규 `hintText`·`helperText` 부재, 초기 호출 패턴, 애니메이션·개발자 STATUS 연결의 정적 상태를 확인한다. Flutter/Dart SDK와 Firebase Emulator·실기기가 없는 환경에서는 컴파일, 조회 횟수 실측, 선택 해제·애니메이션 렌더링·클립보드 결과 및 과금 절감을 검증할 수 없으므로 완료로 표시하지 않는다. `firestore.rules` 변경이나 운영 데이터 삭제·배포는 수행하지 않는다.

## 29. 사용자 행동별 Firebase·TTS·View 정밀 추적 — 2026-11-08

### 29.1 기준, 목적 및 변경 경계

본 장의 기준은 사용자 제공 `261107 2230.zip`이며, 28장의 Double·Triple·Minor 입차 완료 초기 `plates` QUERY 제거가 포함된 상태다. 실제 테스트는 번호판 **3개만 반복 사용**하면서 `type` 변경과 `주행 중` 시작·취소를 왕복한 Minor 모드 세션이다. 따라서 동일 번호판의 다수 GET·UPDATE·View SET은 요청 목적과 행동 ID가 확인되기 전에는 중복 비용으로 판정하지 않는다. 기존 로그에서 직접 GET 51회, QUERY 3회, 커밋 문서 쓰기 46건, SNAP 54회가 관측됐으며 이 수치는 실시간 리스너의 최종 청구 단위나 서버 인덱스 비용을 확정하지 않는다.

본 작업의 목적은 **비용을 직접 줄이는 것이 아니라 기존 동작을 보존하면서 비용 발생 원인을 설명할 수 있게 하는 것**이다. Firestore 추가 읽기·쓰기, 새 컬렉션, 새로운 Custom Claims·UID Role 연결, Firestore Rules 변경, `tool/` 관리 스크립트는 도입하지 않는다. UI 텍스트 입력 힌트·도움말 텍스트를 추가하지 않는다. 변경한 Dart 파일은 코드 주석 없이 유지한다.

### 29.2 공통 행동 추적 구조

`FirebaseActivityMeter`에 비동기 실행 문맥(Zone)을 사용하는 `traceAction<T>()`, `traceStep()`, `plateRefFor()`를 도입한다. 사용자 상태창 동작과 세부 조회에서 `ACTION_START`·`ACTION_COMPLETE`·`ACTION_BLOCKED`·`ACTION_PARTIAL`·`ACTION_FAILED`가 같은 `actionId`로 기록된다. `MovementPlate`가 중첩된 경우 별개의 상위 행동 ID를 만들지 않고 `ACTION_NESTED` 단계로 표시하여 실제 사용자 동작 수가 중복 계산되지 않도록 한다. `PlateWriteService` 내부 Transaction Zone은 상위 Zone을 상속하므로 `readPurpose`, `requestId`, `operationId`, `actionId`가 같이 출력된다. `plateRef=P-1` 등의 세션 내부 익명 별칭만 새 추적 필드에 남기고 원본 번호판을 새 로그 항목으로 출력하지 않는다. 기존 로그에 원본 번호판이 포함되는 부분은 이 장에서 변경하지 않는다.

| 이벤트 필드 | 목적 | 예 |
| --- | --- | --- |
| `actionId` | 한 행동에서 발생한 요청 연결 | `session:123` |
| `actionKind` | 어떤 행동인지 | `TYPE_CHANGE_REQUESTS_TO_COMPLETED`, `DRIVING_START`, `PLATE_DETAIL_OPEN` |
| `plateRef` | 세션 내 같은 번호판 구별 | `P-1`, `P-2`, `P-3` |
| `readPurpose` | 동일 컬렉션의 조회 원인 구별 | `TRANSACTION_STATE_VALIDATION`, `TTS_VIEW_REFRESH` 또는 `VIEW_DOCUMENT_FETCH`, `PARKING_OCCUPANCY_CHECK` |
| `parentOperationId` | 추후 상위 작업의 참조가 필요한 호출에 사용 가능한 선택 필드 | 값이 없는 이벤트는 생략 |
| `requestId`·`operationId` | 이미 존재하던 Firestore 작업 식별자 | 기존 규격 보존 |

직접 연결할 수 없는 별도 Isolate·서버 외부 변경의 SNAP은 사용자 행동 ID를 임의로 부여하지 않는다. `REALTIME_LISTENER`와 `listener requestId`로 출처를 설명한다. 이 구조에서 미연결 이벤트는 실제로 미연결임을 나타내며 추정으로 강제 귀속하지 않는다. Zone 기반 행동 추적은 비동기 코드 경계에서 전달되지만, 다른 Isolate로 전송되는 SDK 내부 인과관계 전부를 복원한다는 의미는 아니다.

### 29.3 수정한 전체 소스 파일 및 실제 변경

| 프로젝트 상대 경로 | 수정 전 | 수정 후 | 사용자 경험 |
| --- | --- | --- | --- |
| `lib/app/diagnostics/firebase_activity_meter.dart` | 이벤트별 요청·세션 ID, 조회 횟수 기록 | 행동 스코프·익명 번호판 별칭·조회 목적·행동 단계·에러 결과를 Journal에 포함 | 기존 화면·Firebase 연산 유지 |
| `lib/app/diagnostics/firebase_activity_journal.dart` | JSONL 스키마 3 | JSONL 스키마 **4**, 행동 필드 추가 및 스키마 2·3·4 요약 읽기 호환 | 기존 7일·20MB 보관 기준 유지 |
| `lib/app/diagnostics/firebase_activity_bridge.dart` | 포그라운드 이벤트의 요청 ID 전달 | 행동 ID·조회 목적·번호판 별칭도 원래 IPC에 실어 전달 | 기존 포그라운드 수명주기 유지 |
| `lib/shared/real_time_table/real_time_table_body.dart` | 상세 문서 GET만 실행 | `PLATE_DETAIL_OPEN` 행동 ID 아래 동일 GET 실행 | 상세 Side Dock·기존 정렬·모션 유지 |
| `lib/features/mode_double/parking_completed_package/widgets/double_parking_completed_status_bottom_sheet.dart` | `_runPrimary()` 작업 실행 | 상태 처리 행동 ID가 기존 Future 실행을 감쌈 | 버튼·정산·애니메이션 유지 |
| `lib/features/mode_triple/parking_completed_package/widgets/triple_parking_completed_status_bottom_sheet.dart` | `_runPrimary()`·`_runPrimaryBool()` 실행 | 일반·bool 상태 처리 행동 ID 기록 | 기존 모드별 기능·애니메이션 유지 |
| `lib/features/mode_minor/parking_completed_package/widgets/minor_parking_completed_status_bottom_sheet.dart` | 상태 처리 시작 시 업무 단계별 Firebase ID 분리 | 선택·주행·이동의 같은 행동 ID를 중첩 서비스까지 전달 | 테스트했던 Minor 조작 방식 유지 |
| `lib/shared/plate/application/common/movement_plate.dart` | 6개 유형 이동에서 예상 작업 수만 별도 출력 | 유형 이동 행동 ID, 기존 View REMOVE/UPSERT의 시작·성공·실패, 개발자 View STATUS의 `actionId` 기록 | 전환 순서·기존 STATUS 유지 |
| `lib/shared/plate/domain/services/plate_query_service.dart` | 원본 GET·QUERY의 목적이 로그에 없음 | 상세·업무 전 조회 및 4자리 검색 종류를 `readPurpose`로 기록 | 실제 조회 수·조건 유지 |
| `lib/shared/plate/domain/services/plate_write_service.dart` | Transaction GET·커밋은 별도 기록 | 유형 변경·주행 시작/취소·일반 업데이트·등록·삭제 행동 ID, 유형/선택 전후 상태, Transaction GET 목적 기록 | 동시성 검증 및 실제 쓰기 동작 유지 |
| `lib/shared/plate/data/repositories/firestore_plate_repository.dart` | View GET의 공통 `source`만 기록 | TTS 이벤트가 연결된 View GET과 일반 View GET·주차 점유 View·주행 복구 Query·유형별 Query를 구별 | 읽기·쓰기·필터·구독 변경 없음 |
| `lib/shared/page/pages/common/type_page.dart` | TTS 이벤트의 250ms 디바운스 뒤 View 조회 | 수신 이벤트 개수·원인·전체/출차 전용 갱신 행동 ID 기록 | 기존 250ms·발화 정책 유지 |
| `lib/shared/tts/services/page/tts_view_refresh_service.dart` | 전체 3개 View·출차 1개 View GET, 기존 쿨다운 | 기존 GET을 그대로 호출하면서 시작·완료·쿨다운 생략을 기록 | **TTS 재생·조회·쿨다운 변경 없음** |
| `lib/shared/plate/application/common/driving_recovery_gate.dart` | 선택된 주행 중 차량 초기 조회 | `DRIVING_RECOVERY` 행동 ID와 별도 QUERY 목적 기록 | 복구 UI 유지 |
| `lib/shared/plate/application/common/view_doc_rows_store.dart` | Store 변경 시 기존 debugPrint와 notifyListeners | 동일 적용 뒤 `VIEW_STORE_UPDATED` 이벤트 기록 | Store 알림·실시간 화면 표시 유지 |
| `README.md` | 1~28장 | 1~28장 원문 보존, 본 29장 맨 끝 추가 | 실행 동작과 무관 |

### 29.4 행동별 원본→View→화면 데이터 흐름

| 테스트 행동 | 기존 로그 | 변경 후 진단 로그 | Firebase 호출 변경 |
| --- | --- | --- | --- |
| 번호판 상세 열기 | `plates GET` | `PLATE_DETAIL_OPEN` + 동일 `GET`, 익명 `plateRef` | 없음 |
| 입차 요청 → 입차 완료 | Transaction·PR SET·PC SET 개별 기록 | 같은 `actionId`로 Transaction 상태 검증·View REMOVE/UPSERT 단계 연결 | 없음 |
| 입차 완료 → 출차 요청 및 복귀 | Transaction·PC/DR SET 개별 기록 | 각 방향에 독립 `actionId`, `beforeType`, `afterType`, View 동기화 성공·실패 구분 | 없음 |
| 주행 중 시작·취소 | Transaction GET·UPDATE·해당 View SET | `DRIVING_START`·`DRIVING_CANCEL`, `beforeSelected`·`requestedSelected` | 없음 |
| 일반 `plates` 업데이트 | GET·UPDATE·View SET | `PLATE_UPDATE`, `PLATE_UPDATE_STATE`에 유형·선택 상태 기록 | 없음 |
| 주차 위치 점유 확인 | PC·DR GET | `readPurpose=PARKING_OCCUPANCY_CHECK` | 없음 |
| TTS 전체 View 새로고침 | 3개 View GET | `TTS_EVENT_RECEIVED` 고유 ID, 디바운스로 합쳐진 이벤트 ID, `TTS_FULL_REFRESH`, 각 View GET | **3회 그대로** |
| TTS 출차 전용 새로고침 | DR GET 또는 쿨다운 생략 | `TTS_DEPARTURE_REFRESH`, `TTS_VIEW_SKIP` | **기존 쿨다운 그대로** |
| 주행 복구 | `plates` QUERY | `DRIVING_RECOVERY` + `readPurpose` | 없음 |
| 유형별 초기/수동 QUERY | 필터 없는 Activity Journal QUERY | `TYPE_AREA_QUERY_<type>`으로 유형 표기, 초기/수동 호출을 로그 맥락과 대조 | 없음 |
| 리스너 SNAP·Store 반영 | `SNAP`과 Store debugPrint 분리 | `readPurpose=REALTIME_LISTENER`, `VIEW_STORE_UPDATED` | 추가 구독 없음 |

단일 호출에서 `readPurpose`만 달라져도 그 호출의 Firebase 비용이 감소한 것은 아니다. `SNAP` 횟수는 청구 읽기와 동일하지 않으며, Transaction `STAGE_UPDATE/SET` 역시 커밋 쓰기에 중복 합산하지 않는다.

### 29.5 TTS 및 사용자 경험 불변 원칙

TTS 이벤트의 원래 수신 조건, `250ms` 디바운스, 전체/출차 전용 분기, View GET의 `force` 및 쿨다운, 발화 순서·음성 내용·중복 방지·백그라운드 처리를 변경하지 않는다. `_lastDataByKey` 및 TTS 조회를 제거하지 않는다. TTS 발화 완료를 이번 변경으로 계측했다고 주장하지 않는다. TTS View GET 15회는 이 테스트에만 해당하는 관측량이며, 각 호출 원인을 이후 동일한 세 번호판 테스트에서 새 이벤트와 비교한다. 기타 타입 변경·주행 중·선택 해제·정산·알림·화면 전환도 업무 코드 순서를 유지한다.

기존 `StatusDialog`는 Fade·Slide·Scale 전환과 `MediaQuery.disableAnimations`에 따른 모션 감소 처리를 이미 제공한다. 본 작업은 이 애니메이션·공통 UI를 재사용하고, 개발자 STATUS에서 추가 Journal을 `debugPrint(...)` 코드로 복사하도록 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()` 경로를 유지한다. `MovementPlate.viewUpsert.success`의 기존 개발자 STATUS에도 `actionId`가 포함된다. 개발자 모드 OFF에서는 기존 정책에 따라 STATUS 진단창을 띄우지 않으며, 로그를 위한 새 애니메이션·힌트·팝업은 추가하지 않는다. 즉, 기존 화면 애니메이션은 포함·보존하되 TTS나 사용자 조작에 영향을 주는 신규 애니메이션은 삽입하지 않는다.

### 29.6 개인정보·진단 보관량·예외 처리

새 추적 ID는 세션 내 별칭이며 원본 번호판과 `selectedBy` 문자열을 새 구조화 필드로 쓰지 않는다. 원래 존재했던 디버그 로그는 별도 변경 범위다. 행동별 이벤트는 로컬 Journal에 기록하여 Firestore에서 별도 비용이 생기지 않도록 한다. Journal 메모리 500개 이벤트, 7일·20MiB 파일 보관, 대기열 4,096개, `droppedEvents`, `writeErrors` 계측은 유지한다. 추가 로그로 보관량이 늘 수 있으므로 장시간 실사용에서 상태창 복사와 로그 누락을 검증해야 한다. `ACTION_PARTIAL`은 기존 View 오류 삼키기 동작에서 일부 동기화 실패를 드러낸다. `ACTION_FAILED`, `VIEW_WRITE_FAILED`는 로컬 진단 단계의 오류이며 동일 실패가 Firestore의 실제 오류 카운트와 함께 보일 수 있으므로 오류 발생 **이벤트 수**와 실패한 **사용자 행동 수**를 구분한다.

### 29.7 수정 전후 품질 검증 및 제한

| 검증 항목 | 수정 전 | 수정 후 목표 및 정적 검증 경계 |
| --- | --- | --- |
| 한 행동 내부 식별 | timestamp로 추정 | `actionId`·`plateRef`·조회 목적을 출력하도록 구현 |
| 번호판 3개 반복 | 반복 GET을 오인할 위험 | 동일 별칭의 서로 다른 `actionId`를 구분 가능 |
| Transaction 충돌 검증 | 기존 서버 GET | 삭제·단축하지 않고 `actualType`, `expectedType`, 선택 상태 기록 |
| View 동기화 | SET·SNAP 별도 | REMOVE/UPSERT 실행 결과를 기존 행동 문맥에 연결 |
| TTS | 기존 250ms·3개/1개 GET | 기존 동작 유지, 새로고침 이벤트 계측만 추가 |
| 실시간 UI | 기존 Store 업데이트 | 기존 `notifyListeners()` 이후 변경 결과 기록 |
| Firebase 비용 | 기존 비용 발생 | 원래 읽기·쓰기 경로 유지, 진단용 신규 Firestore 요청 0개 목표 |
| 개발자 STATUS | 디버그 코드 복사 | 새로운 Activity Journal 필드도 코드 복사 대상 |
| 모션 | 상태창 Fade·Slide·Scale 및 reduceMotion | 기존 구현 유지, 변경 범위에서 삭제 없음 |
| README | 28장 종료 | 29장 append-only |

수정 ZIP에는 **변경된 전체 Dart 파일과 전체 README만** 원래 상대경로로 포함한다. 수정된 Dart 파일은 주석이 없고 신규 `hintText`·`helperText`를 포함하지 않는지 확인한다. `firestore.rules`, 인증/권한 파일, 데이터 모델·컬렉션 구조, TTS 엔진의 발화 코드, STATUS Dialog 본체, 애니메이션 구성 파일은 변경하지 않는다. Flutter·Dart SDK와 Android/Firestore 테스트 환경이 없는 이 작업 환경에서는 `flutter analyze`·실기기 타이핑/애니메이션·TTS 발화 동등성·Android STATUS 클립보드·운영 Billing 수치·Firebase 에뮬레이터를 실행 검증하지 못했으므로 완료라고 적지 않는다. 실제 테스트는 동일한 세 번호판으로 요청 시나리오를 반복해 각 행동 ID와 Firebase 비용 작업을 대조해야 한다.

## 30. 신규 차량 등록·상태 이력 조회의 Firebase 행동 추적 완결성 — 2026-11-08

### 30.1 기준본·실사용 근거·구현 목적

기준 프로젝트는 `261108 0440.zip`이며 1~29장은 변경하지 않았다. 2026-11-08 12:51~12:54 실사용 Journal에서 신규 등록의 `PlateCreationService.addPlate` Transaction은 GET 4건(`plates`, `monthly_plate_status`, `plate_status` 현재 월·이전 월), 커밋 SET 3건, 재시도 1회로 성공했다. 그러나 Transaction에는 `actionId`가 없었다. 입력 중 `plate_status` 조회는 현재 월·이전 월 2회가 같은 `source`로 기록됐고, `getPlate`의 `readPurpose=PLATE_DETAIL_OR_PRE_ACTION`은 상세 보기와 상태 변경 후 재조회를 구별하지 못했다. 이 상황은 **불필요한 중복 조회가 입증된 것이 아니며**, 각 과금 후보 요청이 발생한 원인을 기록하는 계측의 결손이다.

이번 수정 목표는 원래 Transaction GET·SET·UPDATE·DELETE, 월별 상태 메모 보호, 번호판 중복 방지, 기존 화면과 TTS 및 애니메이션의 실행 경로를 유지하면서 **업무 행동 → 조회 이유 → 대상 문서 유형 → 커밋 → 완료/실패**를 연결하는 것이다. 진단만을 위한 신규 Firebase 조회·쓰기, Firestore Rules·인증·권한 구조 변경, 새로운 실시간 리스너는 도입하지 않는다.

### 30.2 입력 화면에서 등록 행동 ID 생성

`InputPlateScreen._handleSubmit()`이 `FirebaseActivityMeter.instance.traceAction<bool>`을 사용하여 `PLATE_REGISTER`를 시작하고, 기존 `InputPlateController.submitPlateEntry()` 호출을 같은 비동기 문맥에서 실행한다. `plateId`는 기존 번호판과 지역을 조합해 전달하되 Journal에는 `plateRefFor`가 만든 세션 내 익명 `P-n`만 구조화 필드로 기록한다. 입력값 또는 사용자 이름을 새로운 Activity 필드에 기록하지 않는다.

`InputPlateController`는 `REGISTER_SUBMIT_BEGIN`, 상태 정보 미조회·번호판 불완전 차단의 `REGISTER_SUBMIT_BLOCKED`, `REGISTER_IMAGE_UPLOAD_RESULT`, `REGISTER_SERVICE_RESULT`를 기존 처리 단계에서만 출력한다. `InputPlateService.registerPlateEntry()`는 기존 Provider → `InputPlate.commonRegisterPlateEntry()` 호출을 그대로 유지하면서 `REGISTER_PERSIST_START`, `REGISTER_PERSIST_RESULT`, 예외 유형을 나타내는 `REGISTER_PERSIST_FAILED`를 추가한다. 결과가 `false`면 기존 `traceAction`에서 `ACTION_BLOCKED`로 기록되고, 예외면 `ACTION_FAILED`로 기록된다. 기존 사진 업로드·업로드 실패 정리·OCR 학습 커밋·화면 닫기 순서와 UI 문구는 변경하지 않는다.

`PlateCreationService.addPlate()`는 Transaction 자체도 `PLATE_REGISTER_TRANSACTION` 행동으로 감싼다. 상위 `PLATE_REGISTER` 문맥이 이미 있으면 기존 `ACTION_NESTED`를 통해 같은 행동 ID를 이어받고, 등록 경로가 다른 호출자에서 직접 실행돼도 Transaction에 새 행동 ID가 생긴다. 이 중첩 기록은 별도 사용자 클릭 또는 별도 과금 작업을 뜻하지 않는다. Transaction 처리 로직과 `runTrackedActivityTransaction`의 실제 읽기·쓰기·재시도 기본값을 변경하지 않는다.

### 30.3 신규 등록 Transaction GET 목적

| 기존 GET | 수정 후 `readPurpose` | 실제 의미 |
| --- | --- | --- |
| `plates/*` | `REGISTER_DUPLICATE_AND_REENTRY_CHECK` | 현재 활성 차량 중복 및 출차 완료 차량 재입차 가능 여부 검증 |
| `monthly_plate_status/*` | `REGISTER_MONTHLY_STATUS_VALIDATION` 또는 `REGISTER_MONTHLY_CONFLICT_VALIDATION` | 정기 상태 유효성 또는 일반 상태 저장 전 정기 상태 충돌 검증 |
| `plate_status/*/months/*/plates/*` 현재 월 | `REGISTER_HISTORY_CURRENT_MONTH_REVALIDATION` | 화면에서 확인한 상태 메모가 등록 직전 변경됐는지 검증 |
| `plate_status/*/months/*/plates/*` 이전 월 | `REGISTER_HISTORY_PREVIOUS_MONTH_REVALIDATION` | 직전 월 상태와 현재 월 상태의 동시 변경 여부 검증 |

조건에 따라 어떤 GET은 실행되지 않을 수 있다. 로그에는 **실제로 실행된 GET만** 기록한다. Transaction의 모든 `STAGE_*` 또는 `REGISTER_WRITE_TARGET` 기록은 준비 중인 단계이며 커밋 시의 문서 쓰기에 다시 합산하지 않는다. `COMMITTED_TRANSACTION`의 `committedWrites`, `reads`, `attempts`를 실제 성공한 Transaction을 판정하는 기준으로 사용한다.

### 30.4 Transaction 쓰기 대상 상세 계측

`PlateCreationService`의 기존 `transaction.set/update/delete` 실행 직전에 업무 진단 이벤트 `REGISTER_WRITE_TARGET`을 추가했다. `plates` 원본, `parking_requests_view`, `parking_completed_view`, 조건부 `plate_counters`, 일반·정기 상태 메모, 해당 월 상태 삭제 및 `PlateBillingCountService.incrementInTransaction()`의 `plate_billing_counts` 집계가 대상이다. `purpose`는 실제 분기에 따라 `UPSERT`, `REMOVE`, `INCREMENT`, `CURRENT_MONTH_STATUS_SAVE` 등으로 나뉜다. 기존 상태 메모 저장/삭제 정책과 `FieldValue.serverTimestamp()`, `SetOptions(merge:true)`는 그대로 사용한다.

`REGISTER_WRITE_TARGET`은 `service=workflow`이고 Transaction 성공 이전에도 출력될 수 있다. Transaction이 예외로 종료되면 이 이벤트가 있더라도 **서버 쓰기 성공을 뜻하지 않는다.** 실제 Firestore 비용 합계에는 성공한 Transaction의 커밋 쓰기만 포함한다. 예컨대 2026-11-08 신규 등록의 커밋 쓰기 3건은 원본 `plates`, 입차 요청 View, `plate_billing_counts`로 대조된다. 등록 유형·상태 메모 조건에 따라 이후 실행에서는 정확한 쓰기 대상과 수가 달라질 수 있다.

### 30.5 일반 상태 조회 현재 월·이전 월 및 정기 상태 구분

`PlateRepository.lookupPlateStatus`에 선택적 `readPurpose`를 추가하고 `FirestorePlateRepository.lookupPlateStatus`에서 기존 월별 조회를 동일한 순서로 유지한다. `PlateStatusScope.monthly`는 `<callerPurpose>_MONTHLY`, 일반 이력은 `<callerPurpose>_CURRENT_MONTH` 및 `<callerPurpose>_PREVIOUS_MONTH`로 기록한다. 결과 `found`, `not_found`, `inactive`, `error`는 `STATUS_LOOKUP_RESULT`에 구분해 기록한다. 조회 시점·실패 처리·해당 월 조회가 성공하면 전월 조회를 생략하는 로직은 그대로 유지한다.

입력 화면은 `INPUT_HISTORY_LOOKUP`, `INPUT_MONTHLY_STATUS_LOOKUP`, 수정 화면은 `MODIFY_STATUS_CONTEXT`를 전달한다. 호출자가 목적을 제공하지 않은 상태 조회는 추측하지 않고 `STATUS_LOOKUP`/`UNCLASSIFIED_CALLER`로 표시한다. 월별 GET에서 `documents=0`이라는 결과는 정상적인 부재 판단일 수 있으며 중복 비용 또는 조회 오류로 해석하지 않는다. 동일 익명 `plateRef`가 여러 행동에 걸쳐 나타나는 것은 반복 조작의 증거일 수 있지만 자체로 중복 작업은 아니다.

### 30.6 단일 plates GET 목적 전파

`PlateRepository.getPlate(String, {String readPurpose})` → `FirestorePlateRepository.getPlate()` → `PlateQueryService.getPlate()`의 매개변수를 같은 이름으로 확장했다. 기존 `.get()` 및 `10초 timeout`, 문서 미존재 처리, 모델 파싱은 변경하지 않는다. 호출자가 제공한 목적이 실제 `trackFirestore('GET')`에 전달된다. 호출자를 구분할 수 없으면 `PLATE_READ_UNCLASSIFIED`로 남기며 임의로 상세 보기로 단정하지 않는다.

| 호출 화면·경로 | `readPurpose` | 사용자 동작과의 관계 |
| --- | --- | --- |
| RealTimeTable · 탭 목록 | `PLATE_DETAIL_OPEN` | 차량 상세 열기 |
| 상태 미리보기 화면 | `PLATE_STATUS_PREVIEW_OPEN` | 미리보기 상세 요청 |
| 주행 복구 게이트 | `DRIVING_RECOVERY_DETAIL_CHECK` | 주행 상태 복구 중 서버 원본 재확인 |
| Double·Triple·Minor PlateState | `DEPARTURE_COMPLETED_VIEW_RECONCILE` | 출차 완료 View에서 제거된 문서의 상태 확인 |
| Double·Triple·Minor 정산 완료 화면 | `POST_BILLING_SETTLEMENT_REFRESH` | 정산 뒤 갱신된 차량 원본 확인 |
| Double·Triple·Minor 정산 취소 화면 | `POST_BILLING_CANCEL_REFRESH` | 정산 취소 뒤 갱신된 차량 원본 확인 |
| 추후 신규 호출자(미지정) | `PLATE_READ_UNCLASSIFIED` | 목적 미확인임을 명시 |

`PlateQueryService.getPlate`의 `traceAction`은 상위 행동이 있으면 기존 ID를 계승하고, 없으면 `PLATE_READ` 단독 진단 행동을 만든다. 이는 읽기 수행 이력이며 **사용자 버튼 하나가 있었다는 단정이 아니다.** UI의 목록/상태 처리 순서, 정산 금액·잠금 정책, 주행 복구 알고리즘은 바꾸지 않는다.

### 30.7 개발자 STATUS Dialog · debugPrint 코드 · 애니메이션

기존 `DeveloperOperationTrace`는 내부 진행 로그만 클립보드에 복사하므로 Activity Journal의 등록 `actionId`가 복사되지 않는 문제가 있었다. `DeveloperOperationTrace.debugPrintCodeWithJournal()`이 기존 진행 로그와 `FirebaseActivityMeter.exportJournalCode()`를 결합하도록 했다. 개발자 모드 ON에서 기존 등록 진행 STATUS의 복사 버튼 또는 실패/상태 스냅샷 복사 버튼을 누르면 `debugPrint(...)` 코드가 함께 복사된다. 복사 시 `DevAuth.devModeEnabled`와 `DevAuth.isDevModeEnabled()`를 다시 확인하며, Firebase를 추가 조회하지 않는다. 개발자 모드 OFF에서는 원래 개발자 STATUS 표시/복사 제한을 유지한다. 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCodeWithJournal()`도 변경하지 않는다.

`DeveloperOperationStatusDialog`의 기존 진입 Fade·Scale, 상태 변경 Fade·Slide, `AnimatedSwitcher` 복사 성공 표시와 `MediaQuery.disableAnimations` 기반 모션 감소 동작을 **수정 없이 재사용**한다. 등록 버튼 또는 음성 처리를 위한 새로운 힌트 텍스트·도움말·알림 팝업·대기 시간·음성 발화를 추가하지 않는다. 기존 사용자 화면 애니메이션은 제거되지 않았고, 개발자용 STATUS에는 이미 필요한 전환 애니메이션이 포함되어 있다.

### 30.8 실제 수정 파일 전체 목록

수정된 Dart 파일은 모두 프로젝트의 원래 상대경로를 유지하며 덮어쓰기 ZIP에 **각 파일의 전체 내용**이 포함된다. 파일별 작업 요약은 아래와 같다.

| 수정 범주 | 파일/위치 | 내용 |
| --- | --- | --- |
| 등록 행동 시작 | `lib/shared/page/input/pages/input_plate_screen.dart` | `PLATE_REGISTER` 행동 ID, 입력 이력 목적 |
| 입력 검증 | `lib/shared/page/input/controllers/input_plate_controller.dart` | 등록 차단·업로드·서비스 결과 진단 |
| 등록 서비스 | `lib/shared/page/input/application/input_plate_service.dart` | 저장 시작·결과·예외 단계를 행동 ID에 연결 |
| 등록 Transaction | `lib/shared/plate/domain/services/plate_creation_service.dart` | 중복·정기·월별 GET 목적, Transaction 및 쓰기 대상 연결 |
| 등록 집계 | `lib/shared/plate/domain/services/plate_billing_count_service.dart` | 집계 SET의 대상 컬렉션과 목적 진단 |
| 상태·차량 Repository | `lib/shared/plate/domain/repositories/plate_repository.dart` | 기존 호출과 호환되는 선택적 조회 목적 인자 |
| Firestore Repository | `lib/shared/plate/data/repositories/firestore_plate_repository.dart` | 목적 전달, 월별 GET 목적과 조회 결과 분류 |
| 차량 단건 조회 | `lib/shared/plate/domain/services/plate_query_service.dart` | 상세 조회 원인에 맞는 GET 목적·조회 행동 ID |
| 수정 화면 | `lib/shared/page/modify/controllers/modify_plate_controller.dart` | 정기/일반 이력 조회 목적 명시 |
| 실시간 조회 | `lib/shared/real_time_table/real_time_table_body.dart`, `real_time_status_preview_body.dart`, `real_time_tabbed_table.dart` | 각각 상세/미리보기 GET 목적 명시 |
| 주행 복구·모드 상태 | `lib/shared/plate/application/common/driving_recovery_gate.dart`, `double/double_plate_state.dart`, `minor/minor_plate_state.dart`, `triple/triple_plate_state.dart` | 복구/출차 완료 View 조정에 따른 조회 목적 기록 |
| 정산 후 조회 | Double·Triple·Minor의 `parking_completed_status_bottom_sheet.dart`, `departure_completed_status_bottom_sheet.dart` 및 출차 완료 검색용 상태창 | 정산 완료와 취소 후 서버 원본 재조회 분리 |
| 개발자 STATUS | `lib/app/utils/developer_operation_status_dialog.dart` | 복사 시 기존 진행 로그 + 전체 Activity Journal 코드 결합, 기존 모션·복사 완료 애니메이션 유지 |

### 30.9 수정 전후 비용·동작 비교

| 검증 시나리오 | 변경 전 Firebase 동작 | 변경 후 설계 | 사용자 경험 |
| --- | --- | --- | --- |
| 신규 입차 등록 | 조건부 GET·커밋 SET | **동일한 Firebase 동작**, `PLATE_REGISTER` 및 각 readPurpose 추가 | 기존 등록·중복 방지 유지 |
| 현재 월·이전 월 상태 조회 | 필요한 월별 GET 수행 | **같은 수·순서의 GET**, 조회 월과 이유 명시 | 기존 상태 메모 보호 유지 |
| 상세 열기 | `plates` GET | **기존 GET 유지**, 상세/미리보기/복구 등 목적 분리 | 기존 상세 보기 유지 |
| 정산·정산 취소 | 변경 후 `plates` GET | **기존 GET 유지**, 완료/취소 목적 기록 | 기존 정산·잠금·금액 유지 |
| 집계 문서 갱신 | Transaction SET | 기존 SET 유지, 업무 진단 `REGISTER_WRITE_TARGET` 추가 | 결과 동일 |
| View SNAP·TTS | 기존 리스너 및 TTS 새로고침 | **미변경** | TTS 음성 내용·순서·중복 방지·디바운스 동일 목표 |
| 개발자 STATUS | 진행 로그만 복사 | 기존 진행 로그 + 로컬 Journal 코드 복사 | 팝업·복사 완료 애니메이션 유지 |

11월 8일 선행 실측의 GET 29회·QUERY 2회·커밋 쓰기 16건은 당시 요청한 작업의 관측값이며, 새 테스트의 기대 고정 수치가 아니다. **동일 행동 시퀀스를 재현**해서만 원래 비용과 비교한다. Firestore GET의 `documents=0`도 유료 읽기일 수 있고, 실시간 SNAP 수는 과금 문서 읽기와 일치하지 않으며, `REGISTER_WRITE_TARGET`, `STAGE_SET`, `RULES_ITEM`은 커밋 쓰기로 중복 합산하지 않는다.

### 30.10 정적 검사·실기기 검증 및 미확인 사항

정적 검사에서는 29장까지 README 원문이 완전히 보존됐는지, 원본 `261108 0440.zip`에서 바뀐 Dart만 포함됐는지, 변경 코드에 주석·신규 `hintText`·`helperText`가 없는지, 추가 import 경로·조회 목적 전달·등록 추적의 시작과 종료·STATUS 복사 연결이 유효한지 확인한다. 기존 데이터 스키마·Rules·인증·TTS 엔진은 변경하지 않는다. 원래 Activity Journal의 7일·20MiB 및 제한 수치를 유지한다. 로그 보강으로 기록량이 증가할 수 있으므로 `droppedEvents`, `writeErrors`, `pending`은 장시간 실사용에서 별도 확인한다.

Flutter·Dart SDK가 없는 이 작업 환경에서 `flutter analyze`, Android 실행, 사용자 동작 후 실제 로그의 행동별 연결, TTS 발화/백그라운드 동등성, 정산·상태 메모 동시성 경합, 클립보드 복사, 실기기 애니메이션 및 실제 Firebase 청구량은 **실행 검증하지 못했다**. 이들 항목을 정적 검사만으로 완료라고 표시하지 않는다. 배포 전에는 개발자 모드 ON/OFF, 동일 번호판 3개 반복 조작, 신규 등록과 중복 등록, 월별 상태 조회, 정기주차·정산·주행 중, TTS 화면 이탈·재진입·백그라운드, STATUS 코드 복사 및 모션 감소 설정을 각각 확인한다.

## 31. 전역 Firestore GET 원인 추적 및 행동 결과 정합성 보강 — 2026-11-08

### 31.1 기준본·목적·안전 범위

기준본은 `261108 1824.zip`이며 1~30장 원문은 수정하지 않았다. 이전 31장 설계에서 `lib/` 내 명시적 `.trackFirestore('GET', ...)` 127곳 중 `readPurpose`를 직접 지정하지 않은 **114곳, 25개 Dart 파일**을 식별했다. 이는 실제 Firebase GET 114회 또는 비용 낭비 114건을 의미하지 않고 **소스상의 계측 지점 수**이다. 기존에는 컬렉션·성공 여부만 기록돼 수납·연장·삭제·메모 충돌·계정 중복 검증 등의 이유를 로그만으로 구별하기 어려웠다.

이번 변경은 기존 GET·QUERY·SET·UPDATE·DELETE·Transaction의 실행·분기·재시도·제한 시간을 변경하지 않고 진단 인자 및 로컬 이벤트만 추가한다. 앱의 인증·역할 정책, Firebase Rules, TTS 250ms 디바운스와 발화·백그라운드 로직, 화면 전환·애니메이션·모션 감소 처리, 위치 점유 확인은 기존 구조를 유지한다. 실제 GET이 필요 없는지 입증하기 전에는 읽기 비용 절감 명목으로 코드를 삭제하지 않는다.

### 31.2 GET 목적 명시 범위와 분류 원칙

| 항목 | 기존 | 이번 수정 후 정적 상태 | 주의 사항 |
| --- | --- | --- | --- |
| 명시적 `.trackFirestore('GET', ...)` | 127곳 | 기존 114곳에 각기 실제 호출 이유를 나타내는 `readPurpose` 추가 | GET 수행 횟수를 의미하지 않음 |
| 기존 미계측 서버 GET | 계정 관리 저장 전 원본 GET 1곳 | 기존 `.get()`에 `.trackFirestore('GET', ...)` 1회 연결 | **새로운 Firestore GET 실행이 아님** |
| 명시적 GET 계측 지점 합계 | 127곳 | 128곳 모두 `readPurpose` 지정 | 소스 전체 SDK 내부·외부 GET의 절대 완전성 주장은 아님 |
| 정기주차 View 빈 데이터 fallback QUERY | View GET 후 원본 QUERY가 구분 없이 이어짐 | `MONTHLY_LIST_FALLBACK_QUERY` 및 `MONTHLY_VIEW_FALLBACK_REQUIRED` | 정상적인 빈 결과가 곧 오류는 아님 |
| `readPurpose` 미지정 요청의 전역 표시 | NULL이 가능 | `UNCLASSIFIED_CALL_SITE`로 명시적 표시 | 모르는 원인을 임의로 사용자 버튼에 귀속하지 않음 |

목적은 임의의 일반 문자열로 통일하지 않고, 실제 메서드와 분기의 역할에 따라 `..._VALIDATION`, `..._FETCH`, `..._CONFLICT_CHECK`, `..._FALLBACK_...`로 구분한다. Transaction 안의 GET은 기존 동시성 검사에 사용되는 경우가 있으므로 유지한다. 같은 차량·계정에서 연속 GET이 발생했어도 같은 사용자 행동의 중복이라고 결론 내리지 않는다. `documents=0`은 정상적인 문서 부재일 수 있다.

### 31.3 차량·정기주차 관련 목적별 비교

| 사용자의 행동 | 수정 전 계측 | 수정 후 예시 `readPurpose` | 사용자 경험 |
| --- | --- | --- | --- |
| 차량 메모 저장·동시 수정 차단 | `plate_status` / `monthly_plate_status` GET | `STATUS_MEMO_SOURCE_CONFLICT_CHECK`, `STATUS_MEMO_CURRENT_HISTORY_REVALIDATION`, `STATUS_MEMO_MONTHLY_SCOPE_REVALIDATION` | 기존 충돌 안내·보호 유지 |
| 정기주차 메모 변경 후 목록 갱신 | `monthly_plate_status` GET | `MONTHLY_VIEW_SOURCE_SYNC` | View 동기화 유지 |
| 과거 차량 이력 열기 | `plates` GET | `PLATE_HISTORY_FETCH` | 이력 화면 유지 |
| 메모 저장 범위 판정 | 정기 상태 GET | `STATUS_MEMO_SCOPE_RESOLUTION` | 활성 정기주차 우선 판단 유지 |
| 정기주차 화면 열기 | View GET | `MONTHLY_LIST_VIEW_FETCH` | 목록·정렬 유지 |
| 정기주차 삭제 | Transaction GET | `MONTHLY_DELETE_STATE_VALIDATION` | 삭제 정책 유지 |
| 정기주차 수납 | Transaction GET | `MONTHLY_PAYMENT_STATE_VALIDATION` | 결제·연장 조건 유지 |
| 정기주차 기간 연장 | Transaction GET | `MONTHLY_EXTENSION_STATE_VALIDATION` | 기간 적용 유지 |
| 정기주차 메모 지우기 | Transaction GET | `MONTHLY_MEMO_CLEAR_STATE_VALIDATION` | 감사·기존 기록 유지 |
| 출차 완료 추가 건수 | `plate_counters` GET | `DEPARTURE_COMPLETED_EXTRA_COUNT_FETCH` | 건수 표시 유지 |

`fetchMonthlyPlateStatusView()`는 공통 `traceAction`으로 감싸 `MONTHLY_LIST_VIEW_LOAD`의 행동 문맥에서 기존 View GET을 실행한다. View에 사용 가능한 항목이 없으면 `MONTHLY_VIEW_FALLBACK_REQUIRED`를 기록하고 기존 원본 QUERY를 수행한다. QUERY는 `MONTHLY_LIST_FALLBACK_QUERY`로 식별한다. **실제 원본 문서가 없을 때도 정상적으로 빈 목록을 반환하며 새 QUERY를 만들지 않는다.** View 재생성은 기존 조건에서만 발생한다. 이 행동 ID는 앱 내부 수행 단위를 뜻하므로 단독 사용자 클릭이 있었다는 증거로 사용해서는 안 된다.

### 31.4 계정·근무·구역·보고·개발자 영역의 GET 목적

다음 파일은 기존 조회를 그대로 수행하면서 업무 목적 문자열만 추가했다. 실제 수정 파일 전체 내용은 덮어쓰기 ZIP에 원래 상대경로로 포함한다.

| 수정된 Dart 파일 (`lib/` 기준) | 보완한 GET 지점 수 | 목적·근거 |
| --- | ---: | --- |
| `features/account/data/services/legacy_account_code_number_migration_service.dart` | 2 | 기존 계정번호 이관의 출발·도착 문서 검증 |
| `features/account/data/services/user_code_reservation_backfill_service.dart` | 2 | 계정번호 복구 중 원본·예약 재검증 |
| `features/account/data/services/user_read_service.dart` | 8 | 사용자 원본·활성 상태·목록 Projection·영문 지역명 조회 |
| `features/account/data/services/user_write_service.dart` | 14 | 계정·태블릿 생성/수정/삭제 중복 및 View 정합성 |
| `features/commute/domain/repositories/commute_log_repository.dart` | 2 | 근무 이력 월별 조회·빈 월 문서 확인 |
| `features/commute/domain/repositories/commute_true_false_repository.dart` | 1 | 지역별 근무 상태 복원 조회 |
| `features/dashboard/data/repositories/end_work_report_firestore_repository.dart` | 2 | 일별 기록 중복·월별 마감 제출 검증 |
| `features/dashboard/domain/repositories/end_work_report_repository.dart` | 2 | 월별 보고 원본과 구형 데이터 대체 조회 |
| `features/dev/data/repositories/area_repo_package/firestore_area_repository.dart` | 3 | 본사 판정·지역 이름 조회, 서버 요청 구분 |
| `features/headquarter/page/sheets/head_memo.dart` | 6 | 본사 메모 장부 색인·메타·선호/대체 책 조회 |
| `features/launcher/application/dev_bootstrap_service.dart` | 11 | 개발자 초기화·초기 관리자·예약·View 일치 확인 및 복구 |
| `features/location/data/services/location_reservation_integrity_service.dart` | 1 | 다른 부모 구역의 예약 소유자 확인 |
| `features/location/data/services/location_write_service.dart` | 12 | 부모·자식 구역·주차면 예약 충돌 검증 |
| `features/login/controllers/personal/personal_login_controller.dart` | 2 | 개인 세션 복원·신규 계정 중복 검증 |
| `features/personal/application/personal_vehicle_status_service.dart` | 1 | 개인 차량 정기주차 유효 상태 확인 |
| `features/rule/data/repositories/firestore_rule_repository.dart` | 4 | 업무 규칙 조회 및 생성·변경·삭제 전 상태 확인 |
| `features/sector/data/services/sector_delete_service.dart` | 1 | 부서 삭제 전 대상 확인 |
| `features/sector/data/services/sector_write_service.dart` | 3 | 부서 생성·이름 변경·대상 중복 조회 |
| `shared/plate/data/repositories/firestore_plate_repository.dart` | 13 | 차량 메모 충돌·정기주차·이력·정기주차 View 조회 |
| `shared/plate/domain/services/plate_count_service.dart` | 1 | 출차 완료 추가 건수 집계 확인 |
| `shared/plate/domain/services/plate_status_service.dart` | 4 | 일반·정기 상태 저장 Transaction의 기존 상태 검증 |
| `shared/secondary/data/services/dev_user_write_service.dart` | 8 | 개발자 계정 생성·변경, 번호·View·원본 검증 |
| `shared/secondary/pages/sheets/area_management.dart` | 4 | 본사 생성 검증 및 지역별 계정 Projection 확인 |
| `shared/secondary/pages/sheets/tabs/add_area_tab.dart` | 4 | 지역 등록·수정·삭제 관련 중복·View 확인 |
| `shared/secondary/pages/sheets/tabs/user_account_tab.dart` | 3 | 계정 관리 화면의 지역·목록·수정 원본 조회 |

별도로 `shared/secondary/pages/sheets/tabs/user_account_tab.dart`의 `_saveChanges()`는 `user_accounts/*` 원본을 `GetOptions(source: Source.server)`로 조회하면서 **`.trackFirestore()`가 빠진 1개 경로**가 확인되었다. 이 기존 조회에 `readPurpose=USER_MANAGEMENT_EDIT_ORIGINAL_SERVER_VALIDATION`을 추가하였다. 조회 빈도나 대상은 변경되지 않는다. `location_write_service.dart`의 주차면 예약 GET 중 예약 문서를 `locations`로 표시하던 **진단 메타데이터 2곳**은 실제 `_reservationRef()`의 컬렉션 `locationSlotReservations`와 동일하게 수정하였다. 이 또한 Firestore 경로 자체를 바꾸지 않는다.

### 31.5 공통 행동 종료 판정과 부모 관계

`FirebaseActivityMeter.traceAction<T>()`에 선택적 `isFailureResult: bool Function(T result)?`를 추가했다. 이전에는 예외가 없고 반환형이 `bool false`도 아니면 실패 정보를 가진 결과 객체를 반환했어도 `ACTION_COMPLETE`로 기록될 수 있었다. `FirestorePlateRepository.lookupPlateStatus()`는 `PlateStatusLookupResult.isFailed`를 분류 함수에 전달한다. **단독 조회가 failed 결과를 반환하면 `ACTION_FAILED result=error`**, 조회 결과가 `found`, `inactive`, `not_found`이면 기존처럼 정상 판정한다. 예외를 사용자에게 새로 던지거나 화면의 기존 오류 표시를 변경하지 않는다.

상위 행동 내에서 상태 조회가 실패했을 때는 `ACTION_NESTED_RESULT_FAILED`를 기록하고 부모 행동의 `resultFailures`를 누적한다. 부모에서 대체 처리를 통해 반환값이 정상이라면 **`ACTION_PARTIAL`**로 남겨 하위 실패가 있었지만 최종 사용자 행동 실패까지 단정하지 않는다. 부모 자체의 분류 결과가 실패라면 `ACTION_FAILED`이다. `record()`는 기존 진단 필드 `parentOperationId`가 명시되지 않은 Firebase 요청이 현재 `traceAction` 문맥에 속할 때 상위 행동 ID를 기록한다. 요청이 어떤 행동에도 연결되지 않으면 ID를 임의로 발급하지 않는다. 또한 단일 GET·QUERY인데 목적이 누락된 호출은 `UNCLASSIFIED_CALL_SITE`로 표시해 차후 미분류를 발견할 수 있도록 한다.

| 결과 | 기존 기록 가능성 | 수정 후 해석 |
| --- | --- | --- |
| 상태 문서 미존재 | GET documents=0 | 유효한 `not_found`이며 실패로 오인하지 않음 |
| 정기주차 기간 만료 | inactive 반환 | 정상적인 업무 판정으로 유지 |
| 상태 조회에서 오류 객체 반환 | `STATUS_LOOKUP_RESULT error` 뒤 `ACTION_COMPLETE` 가능 | 해당 단독 행동은 `ACTION_FAILED` |
| 부모 행동에서 실패한 하위 조회를 회복 | 부모가 성공으로만 표시될 여지 | `ACTION_NESTED_RESULT_FAILED`와 부모 `ACTION_PARTIAL` |
| 현재 행동의 Firestore GET | requestId와 actionId 표기 | 기존 필드에 더해 `parentOperationId`로 상위 행동 연결 |

### 31.6 개발자 STATUS·debugPrint 복사·애니메이션

기존 `DeveloperOperationTrace.debugPrintCodeWithJournal()`은 개발자 모드 ON 시 내부 진행 로그와 로컬 Firebase Journal을 `debugPrint(...)` 코드로 내보내며, STATUS 버튼은 `Clipboard.setData()`를 사용한다. 이 기능을 그대로 유지하면서 `DeveloperOperationStatusDialog._copyDebugPrintCode()`에서 성공 시 문자 수, 실패 시 예외 유형을 **로컬 `debugPrint`로 기록**하도록 했다. 기록을 위해 Firebase 문서를 읽거나 쓰지 않는다. 개발자 모드 OFF일 때 기존 접근 제한·권한 판정은 그대로 적용된다.

기존 STATUS의 Fade·Slide·Scale, 회전·펄스 및 로그 목록 `AnimatedSwitcher`는 유지하고, 성공한 복사의 기존 버튼에만 **2% `AnimatedScale` 피드백**을 추가했다. `MediaQuery.disableAnimations` 또는 앱의 모션 감소 선택에서는 `Duration.zero`와 기존 상태 판정을 사용해 애니메이션이 즉시 완료된다. 새로운 `hintText`, `helperText`, 입력 안내 또는 새로운 대화상자는 추가하지 않았다. 기존 TTS·주차 업무 화면의 애니메이션은 변경하지 않았다.

### 31.7 Firestore 비용 및 요청 수에 대한 의미

| 작업 | 기존 | 수정 후 | 비용 판정 |
| --- | --- | --- | --- |
| 업무별 GET | 필요할 때 기존 GET 실행 | 동일 GET에 목적 인자만 추가 | 추가 GET 없음 |
| 계정 관리의 미계측 원본 GET | 서버 GET 1회, Journal 미계측 | **같은 서버 GET 1회**, Journal에 기록 | 과금 증가가 아니라 **관측 완전성 향상** |
| 정기주차 View fallback | 원본 QUERY는 조건부 발생 | 같은 조건의 QUERY에 목적/행동 기록 | QUERY 추가 없음 |
| 상태 조회 실패 객체 | 결과 메시지와 ACTION 요약 불일치 가능 | 실패/부분 처리 구별 | Firebase 요청 변화 없음 |
| 개발자 STATUS 복사 | 클립보드 복사 | 기존 복사 + 로컬 성공·실패 디버그 출력과 복사 애니메이션 | Firebase 요청 변화 없음 |
| TTS·뷰 실시간 반영 | 기존 음성/리스너 | 기존 코드 경로 유지 | 변경 작업의 직접 대상 아님 |

`STAGE_*`, `ACTION_*`, `MONTHLY_VIEW_FALLBACK_REQUIRED` 등의 진단 이벤트는 **문서 쓰기가 아니다**. 실제 커밋 건수는 성공한 Transaction의 커밋 기록으로 계산하고, SNAP은 리스너 콜백 횟수이지 동일한 과금 읽기 횟수의 증거가 아니다. 서버 요금은 Firestore Console·Billing에서 따로 검증해야 한다.

### 31.8 수정된 전체 파일과 검증·잔여 한계

기준 ZIP과 바이트 단위로 비교하여 **Dart 27개와 전체 `README.md` 1개**만 최종 덮어쓰기 ZIP에 포함한다. 그 외 소스·Firebase Rules·설정·스크립트는 포함하지 않는다. Dart 수정 파일의 전체 내용이 원래 상대경로로 들어 있으며, 변경된 Dart 파일의 주석과 신규 `hintText`, `helperText`가 없는지 정적으로 확인한다. 기존 1~30장 본문은 바이트 단위로 보존한다.

이번 정적 검증은 명시적 GET 128곳 전부의 `readPurpose` 지정, 수정 파일의 괄호·문자열 토큰 균형, import 보존, 기존 `.get()`, `.set()`, `.update()`, `.delete()` 호출 위치 수의 불변, 기존 STATUS 복사·모션 감소 경로 존재, ZIP CRC 및 파일별 덮어쓰기 내용을 포함한다. **`flutter analyze`, 실제 Android 화면/애니메이션, 클립보드 권한, SDK 동작, TTS 발화 내용·횟수·순서, 백그라운드, Firestore Rules, 동시성 경합 및 최종 Billing은 이 환경에 Flutter·Dart SDK와 실기기 실행 환경이 없어 검사하지 못했다.** 따라서 실행 검증 완료라고 표시하지 않는다.

모든 명시적 GET의 `readPurpose`가 지정되더라도 모든 원격 SDK 내부 요청·다른 기기 동작을 완벽히 추적했다는 뜻은 아니다. 상위 `traceAction` 없이 호출되는 시스템 복원·독립 업무 조회에는 `actionId`가 없을 수 있으며, 이때 원인 범위를 조작해 붙이거나 사용자 터치로 단정하지 않는다. Query/Listener, 읽기 과금, TTS 실제 재생은 독립적인 검증 대상이다. 실기기에서는 계정 로그인/복원·번호/지역 설정·주차 위치 저장·일별/월별 보고·정기주차 수납/삭제/연장·차량 이력·상태 메모 충돌·화면 이동·개발자 STATUS 복사·모션 감소·TTS 복귀 동작을 수정 전후 동일 시나리오로 비교한다.

## 32. Double·Triple·Minor 텍스트형 주차구역 점유 View GET 차단 및 도면형 동작 보존 — 2026-11-08

### 32.1 기준 및 결정된 요구사항

기준 전체 프로젝트는 `261108 2018.zip`, 기존 README는 1~31장 총 2,574행이다. 본 장은 기존 README를 수정·삭제하지 않고 덧붙인 이력이다. 변경 대상은 Double·Triple·Minor가 공통으로 사용하는 `lib/shared/plate/editor/workspaces/plate_parking_workspace.dart`이며, 사용자가 **Input Plate Side Dock에서 텍스트형(`plain`) 주차구역을 열거나 선택할 때 점유 확인용 Firestore View GET이 0회**가 되도록 한다. 같은 Workspace를 재사용하는 차량 수정 화면에도 동일한 정책이 적용된다.

이번 변경에서 `PARKING_OCCUPANCY_CHECK`는 `parking_completed_view`와 `departure_requests_view`의 지역별 문서 GET 각각 1회를 뜻한다. 기존에는 Dialog 최초 진입 시 GET 2회를 시작했다. 이 제약은 **주차구역 선택 Workspace의 점유 확인용 읽기**에 적용되며, 차량 원본 `plates` 저장, 업무상 View 동기화 쓰기, TTS가 독립적으로 수행하는 View GET, 다른 화면의 실시간 리스너를 차단한다는 뜻은 아니다. Firestore의 무료 할당량·네트워크 재시도·리스너/Rules 과금은 SDK 외부의 별도 검증 대상이다.

### 32.2 문제의 정확한 코드 경로

수정 전에는 `PlateParkingWorkspace.didChangeDependencies()` → `_syncArea()`에서 지역 문자열이 확인되면 `unawaited(_reloadOccupancy())`를 시작했다. 이 함수는 `_refreshOccupancy()`를 거쳐 `PlateRepository.fetchViewLocations()`를 두 번 호출했고, `FirestorePlateRepository`가 `parking_completed_view`와 `departure_requests_view`를 각각 GET했다. 반면 텍스트형·도면형 분기는 `_buildMain()`의 `PlateParkingAreaConfiguration.resolve(locations)`에서 이루어졌다. 즉 SQLite에 저장된 주차구역 타입을 구분하기 **전에** 점유 View GET을 시작한 것이 원인이었다.

지사 Side Dock에서 내려받은 구역 이름·유형·부모-자식 구조·도면/주차면 구성은 이미 SQLite → `LocationState.locations`로 제공된다. `PlateParkingAreaConfiguration.resolve()`는 `plain`·`diagram`·`mixed`·`empty`를 기존 로컬 데이터만으로 분류한다. `PlateParkingPlainSelector`는 `_blockedByLocation` 점유 Map 없이 기존 목록 선택을 처리하므로, 텍스트형 최초 진입에서 별도의 점유 GET을 요구하지 않는다. 도면형은 `_SpatialParentMap`·하위 주차면·기계식 자동 배정에서 `_blockedByLocation`을 사용하므로 서버 점유 확인 경로를 유지한다.

### 32.3 수정한 전체 파일과 메서드별 전후 비교

| 파일 및 위치 | 수정 전 | 수정 후 | 사용자 경험 |
| --- | --- | --- | --- |
| `lib/shared/plate/editor/workspaces/plate_parking_workspace.dart` · `_syncArea()` | 지역 진입 직후 유형과 무관하게 점유 View GET 2회 시작 | 지역 초기화·기존 점유 데이터 무효화만 하고 GET은 시작하지 않음 | 기존 지역 선택·초기화 유지 |
| 동일 · `build()`·`LocationState` 관측 | 타입 판단은 `_buildMain()` 화면 분기에만 사용 | SQLite 로딩 상태와 현재 지역 목록을 읽고 `resolve()` 결과에 따라 조회 정책 설정 | 텍스트형·도면형의 기존 목록·도면 유지 |
| 동일 · `_applyOccupancyPolicy()` | 해당 실행 정책 없음 | `plain`·`mixed`·`empty`는 GET을 예약하지 않음; `diagram`만 다음 프레임에 최초 GET 예약 | 텍스트형 불필요한 네트워크 점유 로딩 제거 |
| 동일 · `_refreshOccupancy()` | 호출 시 지역만 검사 후 두 View GET | 데이터 로딩 완료 및 `mode=diagram`을 검사한 뒤에만 두 GET 허용 | 도면형 점유 안전성 유지 |
| 동일 · 점유 응답 반영 | 늦게 온 응답이 새 구역 구성에 남을 가능성 | 지역·구역 구성 세대 번호가 달라지면 오래된 결과·오류 폐기 | 전환 중 잘못된 점유 정보 반영 방지 |
| 동일 · `_openChild()`·`_autoSelectTowerSlot()` | 도면 펼치기·기계식 자동 배정 직전 추가 점유 조회 | 호출 유지, `trigger`만 명시하여 조회 원인 기록 | 기존 주차면 검사·340ms 확대/축소 모션 유지 |
| 동일 · `_showDebugStatusDialog()`·`_debug()` | Workspace 진행 로그를 `debugPrint(...)` 코드로 복사 | 유형·로딩 상태·점유 조회 실행·생략·오래된 결과 폐기 로그를 기존 STATUS 복사에 포함 | 개발자 모드 ON에서만 기존 STATUS 및 복사 사용 |
| 동일 · `AnimatedSwitcher` | 점유 로딩/오류 전환 모션 존재 | 로컬 유형 화면의 교체에 190ms Fade·0.98→1.00 Scale을 추가; 모션 감소 시 0ms | 기존 화면 모션 유지, 유형 변경 때만 부드러운 전환 추가 |
| `README.md` | 기존 1~31장 | 기존 원문 완전 유지 + 본 32장 | 앱 동작과 관계없음 |

`PlateParkingAreaConfiguration`·`LocationState`·`PlateParkingPlainSelector`·`FirestorePlateRepository`·Double/Triple/Minor TypePage·Firebase Rules·TTS 관련 소스는 변경하지 않는다. 기존 Repository GET 메서드는 도면형 업무에 그대로 필요하다. 이번 덮어쓰기 ZIP에는 실제로 달라진 **전체 Dart 1개와 전체 README 1개**만 포함한다.

### 32.4 사용자 행동 및 컬렉션별 비용 비교

| 상황 | 수정 전 PC View GET | 수정 전 DR View GET | 수정 후 PC View GET | 수정 후 DR View GET |
| --- | ---: | ---: | ---: | ---: |
| Double 텍스트형 Dialog 최초 열기 | 1 | 1 | **0** | **0** |
| Triple 텍스트형 Dialog 최초 열기 | 1 | 1 | **0** | **0** |
| Minor 텍스트형 Dialog 최초 열기 | 1 | 1 | **0** | **0** |
| 텍스트형 선택·취소·재진입(재진입 1회 기준) | 1 | 1 | **0** | **0** |
| 도면형 최초 열기 | 1 | 1 | **1** | **1** |
| 도면형 하위 구역 펼치기로 갱신 1회 | 1 | 1 | **1** | **1** |
| 도면형 기계식 자동 슬롯 점유 갱신 1회 | 1 | 1 | **1** | **1** |
| 혼합형·사용 가능한 구역 없음 | 1 가능 | 1 가능 | **0** | **0** |
| 로컬 구역 캐시가 로딩 중 | 1 가능 | 1 가능 | **0** | **0** |

이 수치는 **단일 Workspace의 주차 점유 조회 경로에 대한 정적 예상값**이다. 이미 진행 중인 다른 화면의 실시간 SNAP, TTS의 View GET 또는 실제 차량 등록의 View SET/UPDATE는 이 표와 혼합하지 않는다. `STAGE_*`도 별도 커밋 쓰기로 합산하지 않는다. 주차구역 데이터 목록은 내려받은 SQLite를 사용하므로 타입 결정을 위해 추가 Firestore 쿼리를 만들지 않는다.

### 32.5 로컬 캐시·지역 전환·비동기 안전성

`LocationState.isLoading=true`인 동안 주차구역의 유형을 임의로 `plain`으로 단정하지 않으며 점유 조회를 보류한다. 캐시 로딩이 끝난 다음 현재 지역의 `locations`로 `PlateParkingAreaConfiguration.resolve()`를 실행한다. `plain`·`mixed`·`empty`에서는 점유 GET을 시작하지 않는다. 도면형의 최초 GET은 빌드 도중 직접 호출하지 않고 `WidgetsBinding.instance.addPostFrameCallback()`에서 예약하여 Flutter의 빌드/`setState` 충돌과 반복 조회를 피한다.

지역이 바뀌거나 `LocationState`의 지역별 목록 Snapshot이 교체되면 점유 조회 세대를 증가시키고 이전 점유 Map/로딩/오류 상태를 초기화한다. 이전 GET을 네트워크 수준에서 되돌릴 수 있는 것은 아니므로, **이미 요청한 서버 읽기가 자동으로 취소·환불된다고 주장하지 않는다.** 다만 이전 지역·유형의 조회 결과나 오류가 늦게 도착하면 새 화면에 적용하지 않도록 한다. 로컬 타입이 바뀌면 타입 판별을 다시 수행하고 도면형인 경우에만 해당 새 구성의 점유 확인을 시작한다.

### 32.6 개발자 STATUS, debugPrint 및 애니메이션

기존 `DevAuth.isDevModeEnabled()` 검사와 `StatusDialog.showSuccess()`·`copyText: _debugPrintCode` 경로를 보존한다. 개발자 모드 ON에서 주차구역 디버그 버튼을 누르면 `debugPrint(...)` 코드가 포함된 STATUS를 열고 클립보드에 복사할 수 있다. 개발자 모드 OFF에서는 기존처럼 버튼이 표시되지 않으며 STATUS 열기도 거부한다. 새 모니터링을 위해 사용자용 팝업·`hintText`·`helperText`·Firebase 요청을 추가하지 않는다.

진단 로그 예시(실행 확정 로그가 아님):

```text
[PlateParkingWorkspace] parking_area_configuration=resolved area=AREA_A mode=plain plainCount=5 diagramCount=0
[PlateParkingWorkspace] occupancyFetch=skipped reason=PLAIN_MODE area=AREA_A mode=plain source=sqlite_location_cache reads=0
[PlateParkingWorkspace] occupancyFetch=started reason=DIAGRAM_MODE area=AREA_B trigger=diagram_initial collections=parking_completed_view,departure_requests_view expectedGets=2
[PlateParkingWorkspace] occupancyFetch=deferred reason=LOCATION_CACHE_LOADING area=AREA_B source=sqlite_location_cache reads=0
[PlateParkingWorkspace] occupancyFetch=discarded reason=STALE_CONFIGURATION area=AREA_B trigger=diagram_initial
```

`skipped` 문자열만으로 Firestore 읽기 0회를 증명할 수는 없다. 같은 시간 구간의 Firebase Journal에서 `readPurpose=PARKING_OCCUPANCY_CHECK`가 실제로 0건인지 별도로 대조해야 한다. TTS 관련 View GET은 해당 리스너·음성 이벤트에 의한 다른 요청이므로 별도로 구분한다. 기존 도면형 하위 펼치기 340ms 애니메이션 및 `MediaQuery.disableAnimations` 지원을 유지하고, 유형 교체 시 190ms Fade·Scale 전환(모션 감소 시 즉시)을 추가한다.

### 32.7 정적 검증과 실행 검증 경계

정적 검증 대상: 원본 ZIP 대비 실제 수정 파일 식별, `_syncArea()`의 선행 GET 호출 제거, 타입 확인 전 점유 GET 경로 미존재, `_refreshOccupancy()`의 `diagram` 가드, 도면형 `Future.wait()`의 View 문서 두 GET 및 하위 펼치기/타워 갱신 유지, 오래된 조회 결과 폐기, 애니메이션·모션 감소·디버그 STATUS 코드 복사 유지, 주석 및 신규 `hintText`·`helperText` 없음, 기존 README 1~31장 원문 바이트 보존, 상대경로·ZIP CRC 및 내용 일치.

Flutter·Dart SDK 및 실제 Firebase/Android 실행 환경이 현재 작업 환경에 없으므로 `flutter analyze`, Android 앱 빌드, 실제 텍스트형 GET 0회·도면형 GET 2회, 주차면 표시/중복 배정 방지, 클립보드 복사, 애니메이션 렌더링, TTS 발화·백그라운드 동등성, Firestore Rules 및 최종 과금은 실행 검증하지 못했다. **정적 코드 검증을 실기기 검증 완료로 표시하지 않는다.**

실기기 확인 시 동일한 지역·번호판 조건으로 Double·Triple·Minor 각각 텍스트형 최초 열기/닫기/재진입/구역 선택, 도면형 최초 진입·하위 펼치기·기계식 슬롯 배정, 로컬 데이터 재다운로드 중/후, 지역 전환 및 개발자 STATUS `debugPrint(...)` 복사를 재현한다. 텍스트형에서는 해당 Workspace의 `PARKING_OCCUPANCY_CHECK` GET 0건, 도면형에서는 기존 검증 경로 동작 유지와 오류/화면 상태 동등성을 통과 기준으로 사용한다.

## 33. Double·Triple·Minor 주차구역 점유 View 중복 조회 통합·최신성 보호 — 2026-11-08

### 33.1 기준본, 요구사항 및 비변경 범위

기준 전체 프로젝트는 `261108 2249.zip`이다. `README.md`의 1~32장 원문을 바이트 단위로 보존하고 본 33장을 끝에 추가한다. Double·Triple·Minor Input Plate Side Dock과 차량 수정 화면이 재사용하는 공통 `PlateParkingWorkspace`에서 **텍스트형(`plain`) 점유 View GET 0회**를 유지하면서, **도면형(`diagram`)에 한해 동일 최신성의 동시 조회 통합**, 조작 이후 새 점유 확인을 요구하는 경우의 **후속 조회 1회 예약**, **오래된 응답 차단**, **현재 지역 SQLite 구역 구성에 따른 재조회 판단**을 추가한다.

이 장에서 `PARKING_OCCUPANCY_CHECK`는 `parking_completed_view/{area}`와 `departure_requests_view/{area}` 문서 GET 각각 1회를 뜻한다. 실제 차량 등록의 `plates` Transaction, 다른 업무 View 쓰기, TTS 읽기·음성 재생, 화면 실시간 구독, Firestore Rules, 권한·계정 정책은 변경하지 않는다. 문서 GET 호출 2개는 유지하고 실행 시점·중복 여부만 조정한다. 이미 서버로 전달된 읽기를 취소하거나 과금 사용량을 환불할 수 있다고 주장하지 않는다.

### 33.2 실제 수정 파일과 소스 근거

| 실제 수정 파일 | 기존 구현 | 변경 구현 | 사용자 경험 |
| --- | --- | --- | --- |
| `lib/shared/plate/editor/workspaces/plate_parking_workspace.dart` · `_syncArea()` | 지역 변경 때 점유 상태만 초기화 | 실행 중 Future·후속 최신 요청도 무효화, 유효하지 않은 응답은 반영 금지 | 다른 지역 점유 표시 혼입 방지 |
| 동일 · `_applyOccupancyPolicy()` | `identical(_occupancyLocationSnapshot, locationSnapshot)` 객체 동일성 검사 | 현재 지역의 `LocationModel.toCacheMap()` 구성값을 직렬화·정렬해 비교. 일시적 `isSelected`·`plateCount` 제외 | 동일 구역 데이터 재다운로드 시 불필요한 초기 GET 감소 |
| 동일 · `_resetOccupancyWhileLocationCacheLoads()` | 로딩 때 구성/점유 상태 무조건 초기화 | 이미 확인된 지역 구성이 같다면 유효한 점유 표시 상태를 유지, 진행 중 조회의 후속 검증 필요 여부만 표시 | SQLite 재다운로드 중 화면 깜박임/불필요한 재조회 감소 |
| 동일 · `_refreshOccupancy()` | 호출할 때마다 PC·DR View GET 2회 | 동일 최신성 요청은 진행 중 Future 공유, 조작 이후 새 데이터 필요 시 후속 1회 예약 | 도면형 점유 확인 유지, 중복 로딩 감소 |
| 동일 · `_startOccupancyFetch()`·`_canDispatchOccupancy()` | 없음 | 실제 GET 직전에 지역·모드·로컬 구성·로딩 상태 재검증 | 텍스트형으로 변경된 뒤 신규 GET 시작 차단 |
| 동일 · `_performOccupancyFetch()` | 구성 세대만 검사 | 구성 세대 + 요청 순번 확인; 최신 후속 조회가 예약됐으면 이전 결과를 최종 상태에 적용하지 않음 | 이전 정보로 최신 점유 상태 덮어쓰기 방지 |
| 동일 · `_openChild()` | 확대 완료 후 독립 GET | 기존 340ms 애니메이션 후 최신 조회 요청을 예약·통합 | 펼친 시점의 점유 확인 보존 |
| 동일 · `_autoSelectTowerSlot()` | 슬롯 배정 직전 서버 재조회 | 조작 이후 서버 조회가 필요한 경우 후속 GET 성공을 기다린 뒤 배정. 영역/구성 변경 시 배정 중단 | 기계식 슬롯 정확성 유지 |
| 동일 · `_showDebugStatusDialog()` | 개발자용 debugPrint 코드 복사 | 요청 통합·후속 요청·폐기·요청 순번을 같은 STATUS에서 확인 | 개발자 모드 ON에서만 기존 복사 가능 |
| 동일 · 점유 로딩 `AnimatedSwitcher` | Size·Fade 전환 | 기존 전환 유지 + 미세한 Scale 전환; 모션 감소 시 0ms | 점유 로딩에서 완료·오류로 바뀔 때 부드러운 모션 |
| `README.md` | 32장까지 | 이 33장 추가 | 앱 동작 영향 없음 |

**변경되지 않은 파일:** SQLite 다운로드·`LocationState`·주차구역 유형 판별·`FirestorePlateRepository`·TTS·Firebase Rules·Double/Triple/Minor 화면·공용 STATUS 구현. 수정 Dart의 주석을 제거하고 신규 `hintText`·`helperText`를 삽입하지 않는다.

### 33.3 요청 최신성 및 동시 실행 정책

| 요청 유형 | 기존 | 이번 정책 | GET 변화(가능한 시나리오) |
| --- | --- | --- | --- |
| 텍스트형 Dialog 처음 열기·재진입 | 32장 적용 후 점유 GET 0 | 기존 0 유지 | **0** |
| 도면형 최초 진입 | PC 1 + DR 1 | 동일 | **2** |
| 최초 조회 진행 중 동일 화면 표시 목적 요청 | 각 요청마다 GET 2회 가능 | 기존 Future 재사용, 새 GET 없음 | 4 → **2** 가능 |
| 도면형 하위 구역 펼치기 | 340ms 확대 후 최신 확인 | 진행 중 조회와 겹치면 완료 후 새 GET 1쌍 예약 | 최신성 필요 시 **추가 2** |
| 기계식 자동 배정 | 배정 직전 최신 조회 | 이전 조회가 진행 중이어도 그 완료 후 새 GET 1쌍 확인 | 안전 검증 필요 시 **추가 2** |
| 다수의 후속 최신 요청이 한 GET 진행 중 도착 | 겹치는 요청이 각각 서버 전송될 수 있음 | 후속 1쌍으로 통합하고 호출자가 완료를 기다림 | 4·6 이상 → **2+2** 가능 |
| 도면형 → 텍스트형 전환 | 이미 시작한 조회는 서버 비용 발생 가능 | 새 요청은 중단, 이전 응답은 폐기 | **전환 이후 신규 GET 0** |
| SQLite 같은 구성 재다운로드 | 리스트 객체가 새로워 초기 조회 반복 가능 | 현재 지역 구성 서명이 같으면 보존 | **추가 0** 가능 |
| 구역 유형·배치 실제 변경 | 최신 점유 재검증 | 구성 무효화 후 도면형이면 최초 GET | **2** |

동일한 컬렉션·지역을 읽는다고 무조건 중복은 아니다. 최초 화면 표시 요청과 **사용자 조작 이후 최신 점유 확인**은 다르게 다루며, 후속 최신 요청은 이미 실행 중인 조회의 결과만으로 만족시키지 않는다. 특히 기계식 자동 배정은 후속 조회 실패·구성/지역 변경 시 선택을 확정하지 않는다. 이 조회만으로 여러 단말 간 배정의 원자적 유일성이 보장되는 것은 아니므로 기존 등록 시점 정합성 검증을 약화시키지 않는다.

### 33.4 지역별 SQLite 변경 비교

기존 `_occupancyLocationSnapshot`은 전체 `LocationState.locations` 리스트가 같은 객체인지 비교했다. 개선 후에는 현재 지역으로 필터링한 `LocationModel.toCacheMap()`을 직렬화·정렬한 구성을 비교한다. `isSelected`와 `plateCount`는 위치 구조 자체의 변경이 아니므로 비교에서 제외한다. ID·이름·유형·부모/자식·수용량·주차 도면·슬롯 배열·주차면 배치 등은 비교에 포함된다. 다른 지역만 변경되거나 같은 지역을 SQLite에서 그대로 다시 내려받아 리스트 객체가 바뀌어도 재조회하지 않는다. 반면 현재 지역 구성에 실제 변화가 있으면 이전 요청 세대·후속 조회를 무효화하고 도면형에 한하여 새 GET을 예약한다.

로컬 캐시 로딩 중에는 유형 미확정 상태에서 GET을 시작하지 않는다. 진행 중인 조회가 있으면 구성이 바뀔 가능성을 고려해 응답 반영을 무효화하고 데이터 로딩 후 재검증한다. 네트워크로 이미 시작한 요청은 비용을 되돌릴 수 없다.

### 33.5 상태·오류·모션 보존

기존 `FadeTransition`·`SizeTransition`·`AnimatedSwitcher` 및 도면 하위 펼치기/접기 340ms 모션, 주차 위치/기계식 자동 배정 로직은 유지한다. 점유 로딩 완료/오류 전환에 `ScaleTransition`을 추가해 98.5%에서 100%로 부드럽게 표시한다. 시스템의 `MediaQuery.disableAnimations`가 설정되면 기존처럼 전환 시간이 `Duration.zero`가 된다. 새 고정 디바운스 지연을 추가하지 않으므로 도면형 첫 점유 표시를 의도적으로 늦추지 않는다.

도면형 최신 요청이 대기 중인 경우 이전 요청의 응답은 최종 점유 지도에 반영하지 않으며, 후속 GET 완료 후 결과를 적용한다. GET 실패 시 기존 오류/배정 차단 경로를 유지한다. 텍스트형은 계속 로컬 SQLite 구역 목록만 사용하며 점유 View GET을 실행하지 않는다. 기존 TTS·실시간 구독의 데이터 읽기/발화 경험에는 직접 변경을 주지 않는다.

### 33.6 개발자 STATUS·debugPrint 계측

`PlateParkingWorkspace._debug()`는 기존의 `debugPrint()`와 `_debugPrintCode` 문자열 생성 기능을 사용한다. `DevAuth.isDevModeEnabled()` ON에서만 디버그 STATUS 버튼을 표시하고 기존 `StatusDialog.showSuccess(copyText: _debugPrintCode)`를 통해 `debugPrint(...)` 코드를 클립보드로 복사한다. OFF일 때 일반 사용자 화면에 디버그 버튼을 노출하지 않는다. STATUS를 위한 Firestore 조회/쓰기를 추가하지 않는다.

| 이벤트 | 의미 | 과금 해석 |
| --- | --- | --- |
| `occupancyConfiguration=resolved` | 현재 지역·유형·구성 변경 식별 | 직접 GET 없음 |
| `occupancyFetch=cancelled_before_dispatch` | 해당 예약 요청의 서버 전송을 시작하지 않음 | 해당 요청 추가 GET 0 |
| `occupancyFetch=skipped` | 텍스트·혼합·빈 유형에서 점유 조회 차단 | 해당 요청 추가 GET 0 |
| `occupancyFetch=coalesced` | 기존 진행 중 GET 결과 공유 | 추가 GET 0 |
| `occupancyFetch=queued_fresh` | 조작 이후 최신 확인을 후속 1회 예약 | 후속 요청 실행 시 GET 2 |
| `occupancyFetch=started` | PC·DR View GET 전송 시작 | 예상 읽기 대상 2문서 |
| `occupancyFetch=discarded` | 구성 변경·늦은 결과·더 최신 확인이 존재해 결과 폐기 | 이미 시작한 읽기는 비용 발생 가능 |
| `occupancyFetch=completed` | 유효한 최신 점유 결과 반영 | 추가 GET 없음 |
| `occupancyFetch=failed` | 유효한 서버 점유 조회 실패 | 기존 오류/배정 중단 |

위 문자열은 이벤트 규격이며 실제 단말 실행 로그가 아니다. `started` 횟수와 Firebase Journal의 `PARKING_OCCUPANCY_CHECK` GET을 함께 비교하여 절감 효과를 확인해야 한다. 이전 요청이 실제 서버에 도달했는지는 SDK 실행 상황에 따라 달라지므로 `cancelled_before_dispatch`와 `discarded`를 혼동하지 않는다.

### 33.7 수정 파일·정적 검증·실기기 검증 기준

이 배포용 덮어쓰기 ZIP에는 `lib/shared/plate/editor/workspaces/plate_parking_workspace.dart`의 **생략 없는 전체 소스**와 기존 1~32장을 그대로 포함한 **전체 `README.md`**만 포함한다. 다른 코드·규칙·설정은 수정하지 않는다. 정적 검증은 기존 Firebase `.get/.set/.update/.delete` 호출 개수 불변, View 조회 호출 두 곳 유지, 도면형 가드, SQLite 구성 비교, Future 통합·후속 예약·요청 번호 및 지역/구성 보호, 애니메이션·모션 감소·개발자 STATUS 경로 유지, 주석/힌트 없음, README 원문 보존, ZIP CRC와 파일 내용 일치를 확인한다.

**Flutter SDK·Dart 분석기·Android/Firebase 실기기 검증 환경이 제공되지 않아 실제 `flutter analyze`, 빌드, Firebase 서버 읽기 과금, TTS 발화·백그라운드, 화면/애니메이션 렌더링, 클립보드 복사는 검증하지 못했다.** 정적 코드 경로 일치를 실행 성공으로 표시하지 않는다.

실기기에서는 Double·Triple·Minor 텍스트형 열기·선택·닫기·재진입에 대해 Workspace의 `PARKING_OCCUPANCY_CHECK` GET **0회**, 도면형 최초 진입 **2회**, 동일 시점 조회 중복 요청 통합, 하위 펼치기/기계식 최신 GET, 같은 구성 SQLite 재다운로드, 서로 다른 지역 전환, 타입 전환 중 늦은 응답, 네트워크 실패, STATUS `debugPrint(...)` 코드 복사를 같은 사용자 동작 기준으로 재현해 확인한다. 다른 화면 실시간 리스너와 TTS View 조회·등록 View 쓰기는 별도로 집계한다.
