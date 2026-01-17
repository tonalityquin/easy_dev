// 로거에서 사용하는 한글 상태 문자열
const kStatusEntryRequest  = '입차 요청';
const kStatusEntryDone     = '입차 완료';
const kStatusExitRequest   = '출차 요청';
const kStatusExitDone      = '출차 완료';

String doublePlateTypeToKorean(String t) {
  switch (t) {
    case 'parking_requests':   return kStatusEntryRequest;
    case 'parking_completed':  return kStatusEntryDone;
    case 'departure_requests': return kStatusExitRequest;
    case 'departure_completed':return kStatusExitDone;
    default: return t;
  }
}
