// Flutter 패키지 및 커스텀 위젯(CommonPlateField) 임포트
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldBack4 위젯**
/// - 4자리 숫자를 입력받는 텍스트 필드 위젯
/// - 입력값 검증 및 에러 메시지 표시 기능 포함
///
/// **구조**:
/// - `StatefulWidget`으로 입력값 상태와 에러 메시지 상태 관리
class NumFieldBack4 extends StatefulWidget {
  /// **컨트롤러**
  /// - 텍스트 입력값을 관리
  final TextEditingController controller;

  /// **탭 이벤트 콜백** (선택적)
  /// - 필드가 탭되었을 때 호출
  final VoidCallback? onTap;

  /// **읽기 전용 설정** (기본값: false)
  /// - 필드가 읽기 전용인지 여부
  final bool readOnly;

  /// **NumFieldBack4 생성자**
  /// - [controller]: 텍스트 입력값을 관리하는 컨트롤러 (필수)
  /// - 선택적 매개변수로 [onTap], [readOnly] 설정
  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  @override
  NumFieldBack4State createState() => NumFieldBack4State();
}

/// **NumFieldBack4State 클래스**
/// - 입력값을 검증하고 에러 메시지 상태를 관리하는 State 클래스
class NumFieldBack4State extends State<NumFieldBack4> {
  /// **에러 메시지**
  /// - 입력값이 유효하지 않을 경우 설정
  String? _errorText;

  /// **입력값 검증 함수**
  /// - [value]: 입력값
  /// - 입력값이 비어 있거나 4자리가 아닌 경우 에러 메시지 설정
  /// - 유효한 경우 에러 메시지를 초기화
  void _validateInput(String value) {
    if (value.isEmpty || value.length != 4) {
      setState(() {
        _errorText = '정확히 4자리 숫자를 입력하세요.'; // 에러 메시지 설정
      });
    } else {
      setState(() {
        _errorText = null; // 에러 메시지 초기화
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 좌측 정렬
      children: [
        // **4자리 입력 필드**
        CommonPlateField(
          controller: widget.controller,
          // 입력값 컨트롤러
          maxLength: 4,
          // 최대 입력 길이: 4
          keyboardType: TextInputType.number,
          // 숫자 키패드 사용
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // 숫자만 허용
          labelText: '4-digit',
          // 필드 라벨
          hintText: 'Enter',
          // 힌트 텍스트
          readOnly: widget.readOnly,
          // 읽기 전용 여부
          onTap: widget.onTap,
          // 탭 이벤트 콜백
          onChanged: (value) => _validateInput(value), // 입력값 변경 시 검증 호출
        ),
        // **에러 메시지 표시**
        if (_errorText != null) // 에러 메시지가 있는 경우만 표시
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 에러 텍스트와 필드 간격 설정
            child: Text(
              _errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12), // 에러 텍스트 스타일
            ),
          ),
      ],
    );
  }
}
