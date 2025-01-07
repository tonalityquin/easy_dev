// Flutter 패키지 및 커스텀 위젯(CommonField) 임포트
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// `NumFieldBack4` 위젯
/// 4자리 숫자를 입력받는 텍스트 필드로, 입력값 검증 기능 포함.
///
/// 필드 상태를 관리하는 StatefulWidget 구조 사용.
class NumFieldBack4 extends StatefulWidget {
  /// 텍스트 입력 값을 관리하기 위한 컨트롤러
  final TextEditingController controller;

  /// 필드가 탭되었을 때 호출되는 콜백
  final VoidCallback? onTap;

  /// 읽기 전용 필드 설정 (기본값: false)
  final bool readOnly;

  /// 생성자: 필수 입력값은 `controller`
  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  @override
  NumFieldBack4State createState() => NumFieldBack4State();
}

/// `NumFieldBack4State`
/// 입력값을 검증하고 에러 메시지를 관리하는 State 클래스
class NumFieldBack4State extends State<NumFieldBack4> {
  /// 입력값이 유효하지 않을 경우 표시할 에러 메시지
  String? _errorText;

  /// 입력값 검증 함수
  /// - 입력값이 비었거나 4자리가 아닌 경우 에러 메시지 설정
  /// - 유효한 경우 에러 메시지 초기화
  void _validateInput(String value) {
    if (value.isEmpty || value.length != 4) {
      setState(() {
        _errorText = '정확히 4자리 숫자를 입력하세요.'; // 에러 메시지
      });
    } else {
      setState(() {
        _errorText = null; // 에러 없음
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 좌측 정렬
      children: [
        // 4자리 입력 필드 (CommonField 사용)
        CommonField(
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
          // 탭 이벤트
          onChanged: (value) => _validateInput(value), // 입력값 변경 시 검증 호출
        ),
        // 에러 메시지 표시 (유효하지 않은 경우)
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 에러 텍스트 간격 설정
            child: Text(
              _errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12), // 에러 텍스트 스타일
            ),
          ),
      ],
    );
  }
}
