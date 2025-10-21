// lib/parking_completed_package/services/status_mapping.dart
const kStatusEntryRequest  = '입차 요청';
const kStatusEntryDone     = '입차 완료';
const kStatusExitRequest   = '출차 요청';
const kStatusExitDone      = '출차 완료';

String plateTypeToKorean(String t) {
  switch (t) {
    case 'parking_requests':   return kStatusEntryRequest;
    case 'parking_completed':  return kStatusEntryDone;
    case 'departure_requests': return kStatusExitRequest;
    case 'departure_completed':return kStatusExitDone;
    default: return t;
  }
}
