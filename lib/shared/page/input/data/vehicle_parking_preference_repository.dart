import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'vehicle_parking_preference.dart';

class VehicleParkingPreferenceRepository {
  VehicleParkingPreferenceRepository._();

  static final VehicleParkingPreferenceRepository instance =
  VehicleParkingPreferenceRepository._();

  static const String _dbName = 'vehicle_parking_preferences.db';
  static const int _dbVersion = 5;
  static const int _seedVersion = 5;
  static const String tableName = 'vehicle_parking_preferences';
  static const String _metaTableName = 'vehicle_parking_meta';

  static const List<_VehicleParkingPreferenceSeed> _seedRows =
  <_VehicleParkingPreferenceSeed>[
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '캐스퍼',
      priority1SlotKey: ParkingSlotPreferenceKey.compact,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '베뉴',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '아반떼',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '쏘나타',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '그랜저',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '코나',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '투싼',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '넥쏘',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '싼타페',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '팰리세이드',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '스타리아',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: 'ST1',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '포터 II',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '아이오닉 5',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '아이오닉 6',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '현대',
      modelName: '아이오닉 9',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '모닝',
      priority1SlotKey: ParkingSlotPreferenceKey.compact,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '레이',
      priority1SlotKey: ParkingSlotPreferenceKey.compact,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'K5',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '셀토스',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '니로',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '스포티지',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'K8',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'K9',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '쏘렌토',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '카니발',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'PV5',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: '봉고Ⅲ',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'EV3',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'EV4',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'EV6',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'EV5',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '기아',
      modelName: 'EV9',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'G70',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'G80',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'GV70',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'G90',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'GV80',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '제네시스',
      modelName: 'GV60',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'KGM',
      modelName: '티볼리',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'KGM',
      modelName: '코란도',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'KGM',
      modelName: '토레스',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'KGM',
      modelName: '액티언',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'KGM',
      modelName: '렉스턴',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '르노코리아',
      modelName: '아르카나',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '르노코리아',
      modelName: '그랑 콜레오스',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '르노코리아',
      modelName: '세닉',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '쉐보레',
      modelName: '트랙스 크로스오버',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '쉐보레',
      modelName: '트레일블레이저',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'A-Class',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'C-Class',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'E-Class',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'GLA',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'GLB',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'GLC',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'S-Class',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'GLE',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'GLS',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'G-Class',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'EQB',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '메르세데스-벤츠',
      modelName: 'EQE',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '1시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '2시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '3시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '4시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '5시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X1',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X2',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X3',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X4',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: '7시리즈',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X5',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X6',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'X7',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'i3',
      priority1SlotKey: ParkingSlotPreferenceKey.evCompact,
      priority2SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority3SlotKey: ParkingSlotPreferenceKey.standard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'i4',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'i5',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'iX1',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'iX2',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'iX3',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'i7',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BMW',
      modelName: 'iX',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'MINI Cooper',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'MINI Cooper 5-Door',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'MINI Aceman',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'MINI Countryman',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'All-Electric MINI Cooper',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'All-Electric MINI Countryman',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A3',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A5',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A6',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A7',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q3',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q5',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A8',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q7',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q8',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q6 e-tron',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'Q8 e-tron',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '아우디',
      modelName: 'A6 e-tron',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폭스바겐',
      modelName: 'Golf',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폭스바겐',
      modelName: 'Touareg',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폭스바겐',
      modelName: 'Atlas',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폭스바겐',
      modelName: 'ID.4',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폭스바겐',
      modelName: 'ID.5',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'S60',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'XC40',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'V60 Cross Country',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'XC60',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'S90',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'V90 Cross Country',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'XC90',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'EX30',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'EX40',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'EC40',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '볼보',
      modelName: 'EX90',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폴스타',
      modelName: 'Polestar 2',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폴스타',
      modelName: 'Polestar 4',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '폴스타',
      modelName: 'Polestar 3',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '테슬라',
      modelName: 'Model 3',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '테슬라',
      modelName: 'Model Y',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '테슬라',
      modelName: 'Model S',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '테슬라',
      modelName: 'Model X',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Prius',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Camry',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Crown',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'RAV4',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Highlander',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Alphard',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '토요타',
      modelName: 'Sienna',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'UX',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'NX',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'ES',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'RX',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'LS',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'LM',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '렉서스',
      modelName: 'RZ',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '혼다',
      modelName: 'Accord',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '혼다',
      modelName: 'CR-V',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '혼다',
      modelName: 'Pilot',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '혼다',
      modelName: 'Odyssey',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '지프',
      modelName: 'Wrangler',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '지프',
      modelName: 'Grand Cherokee L',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '푸조',
      modelName: '308',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.compact,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '푸조',
      modelName: '408',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '푸조',
      modelName: '3008',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '푸조',
      modelName: '5008',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Discovery Sport',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Range Rover Evoque',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Range Rover Velar',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Defender',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Discovery',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '랜드로버',
      modelName: 'Range Rover Sport',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '캐딜락',
      modelName: 'XT4',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '캐딜락',
      modelName: 'XT5',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '캐딜락',
      modelName: 'XT6',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '캐딜락',
      modelName: 'Escalade',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '캐딜락',
      modelName: 'Lyriq',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '포드',
      modelName: 'Explorer',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '포드',
      modelName: 'Bronco',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '포드',
      modelName: 'Expedition',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '링컨',
      modelName: 'Corsair',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '링컨',
      modelName: 'Nautilus',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '링컨',
      modelName: 'Aviator',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: '링컨',
      modelName: 'Navigator',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.compact,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BYD',
      modelName: 'Dolphin',
      priority1SlotKey: ParkingSlotPreferenceKey.evCompact,
      priority2SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority3SlotKey: ParkingSlotPreferenceKey.standard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BYD',
      modelName: 'Atto 3',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BYD',
      modelName: 'Seal',
      priority1SlotKey: ParkingSlotPreferenceKey.evStandard,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.evExtended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'BYD',
      modelName: 'Sealion 7',
      priority1SlotKey: ParkingSlotPreferenceKey.evExtended,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
      priority3SlotKey: ParkingSlotPreferenceKey.evStandard,
    ),
  ];

  static const List<({String manufacturerName, String modelName})>
  _obsoleteSeedKeys = <({String manufacturerName, String modelName})>[
    (manufacturerName: '제네시스', modelName: 'G80'),
    (manufacturerName: '현대', modelName: '그랜저 HG'),
    (manufacturerName: '현대', modelName: '그랜저 HG330'),
    (manufacturerName: '현대', modelName: '그랜저HG'),
    (manufacturerName: '현대', modelName: '그랜저HG330'),
    (manufacturerName: '현대', modelName: 'Grandeur'),
    (manufacturerName: '현대', modelName: 'Grandeur HG'),
    (manufacturerName: '현대', modelName: 'Grandeur HG330'),
    (manufacturerName: 'Hyundai', modelName: 'Grandeur'),
    (manufacturerName: 'Hyundai', modelName: 'Grandeur HG'),
    (manufacturerName: 'Hyundai', modelName: 'Grandeur HG330'),
    (manufacturerName: 'Hyundai', modelName: 'Sonata'),
    (manufacturerName: 'Hyundai', modelName: 'Grand Starex'),
    (manufacturerName: 'Hyundai', modelName: 'Staria'),
    (manufacturerName: '현대자동차', modelName: '그랜저 HG330'),
    (manufacturerName: '현대자동차', modelName: 'Grandeur HG330'),
    (manufacturerName: '현대', modelName: 'Sonata'),
    (manufacturerName: '현대', modelName: '쏘나타 DN8'),
    (manufacturerName: '현대', modelName: '아반떼 CN7'),
    (manufacturerName: '현대', modelName: '싼타페 TM'),
    (manufacturerName: '현대', modelName: '싼타페 MX5'),
    (manufacturerName: '현대', modelName: '투싼 NX4'),
    (manufacturerName: '현대', modelName: '스타렉스'),
    (manufacturerName: '현대', modelName: '그랜드 스타렉스'),
    (manufacturerName: 'Kia', modelName: 'Carnival'),
    (manufacturerName: 'Kia', modelName: 'K5'),
    (manufacturerName: 'Kia', modelName: 'K8'),
    (manufacturerName: 'Kia', modelName: 'K9'),
    (manufacturerName: 'Kia', modelName: 'Bongo III'),
    (manufacturerName: 'Kia', modelName: 'Bongo 3'),
    (manufacturerName: '기아', modelName: 'Carnival'),
    (manufacturerName: '기아', modelName: '카니발 KA4'),
    (manufacturerName: '기아', modelName: '봉고3'),
    (manufacturerName: '기아', modelName: '봉고 3'),
    (manufacturerName: 'Genesis', modelName: 'G70'),
    (manufacturerName: 'Genesis', modelName: 'G80'),
    (manufacturerName: 'Genesis', modelName: 'G90'),
    (manufacturerName: 'Genesis', modelName: 'GV60'),
    (manufacturerName: 'Genesis', modelName: 'GV70'),
    (manufacturerName: 'Genesis', modelName: 'GV80'),
    (manufacturerName: 'Chevrolet', modelName: 'Matiz'),
    (manufacturerName: '쉐보레', modelName: 'Matiz'),
    (manufacturerName: '쉐보레', modelName: '마티즈'),
    (manufacturerName: 'Chevrolet', modelName: 'Trailblazer'),
    (manufacturerName: 'Chevrolet', modelName: 'Trax Crossover'),
    (manufacturerName: 'MINI', modelName: 'Cooper'),
    (manufacturerName: 'MINI', modelName: 'Countryman'),
    (manufacturerName: 'Mini', modelName: 'Cooper'),
    (manufacturerName: 'KG Mobility', modelName: 'Tivoli'),
    (manufacturerName: 'SsangYong', modelName: 'Tivoli'),
    (manufacturerName: '쌍용', modelName: '티볼리'),
    (manufacturerName: '쌍용', modelName: '렉스턴'),
    (manufacturerName: 'Renault Korea', modelName: 'Arkana'),
    (manufacturerName: 'Renault Korea', modelName: 'Grand Koleos'),
    (manufacturerName: '르노', modelName: '아르카나'),
    (manufacturerName: 'Mercedes-Benz', modelName: 'A Class'),
    (manufacturerName: 'Mercedes-Benz', modelName: 'C Class'),
    (manufacturerName: 'Mercedes-Benz', modelName: 'E Class'),
    (manufacturerName: 'Mercedes-Benz', modelName: 'S Class'),
    (manufacturerName: 'Benz', modelName: 'E-Class'),
    (manufacturerName: '벤츠', modelName: 'E클래스'),
    (manufacturerName: 'Audi', modelName: 'A6'),
    (manufacturerName: 'Volkswagen', modelName: 'Golf'),
    (manufacturerName: 'VW', modelName: 'Golf'),
    (manufacturerName: 'Volvo', modelName: 'XC60'),
    (manufacturerName: 'Tesla', modelName: 'Model 3'),
    (manufacturerName: 'Toyota', modelName: 'Camry'),
    (manufacturerName: 'Lexus', modelName: 'ES'),
    (manufacturerName: 'Honda', modelName: 'Accord'),
    (manufacturerName: 'Jeep', modelName: 'Wrangler'),
    (manufacturerName: 'Peugeot', modelName: '3008'),
    (manufacturerName: 'Land Rover', modelName: 'Defender'),
    (manufacturerName: 'Cadillac', modelName: 'Escalade'),
    (manufacturerName: 'Ford', modelName: 'Explorer'),
    (manufacturerName: 'Lincoln', modelName: 'Nautilus'),
  ];

  Database? _db;

  Future<Database> get database async {
    final cached = _db;
    if (cached != null) return cached;

    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    final opened = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db, force: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db, force: true);
      },
      onOpen: (db) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db);
      },
    );

    _db = opened;
    return opened;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manufacturer_name TEXT NOT NULL,
  model_name TEXT NOT NULL,
  priority_1_slot_key TEXT,
  priority_2_slot_key TEXT,
  priority_3_slot_key TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(manufacturer_name, model_name)
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS $_metaTableName (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await _ensureColumn(db, tableName, 'priority_1_slot_key', 'TEXT');
    await _ensureColumn(db, tableName, 'priority_2_slot_key', 'TEXT');
    await _ensureColumn(db, tableName, 'priority_3_slot_key', 'TEXT');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_vehicle_parking_pref_unique_model ON $tableName (manufacturer_name, model_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicle_parking_pref_manufacturer ON $tableName (manufacturer_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicle_parking_pref_model ON $tableName (model_name)',
    );
  }

  static Future<void> _ensureColumn(
      Database db,
      String table,
      String column,
      String type,
      ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  static Future<int> _currentSeedVersion(Database db) async {
    final rows = await db.query(
      _metaTableName,
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['vehicle_seed_version'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse((rows.first['value'] ?? '').toString()) ?? 0;
  }

  static Future<void> _setSeedVersion(Database db, int version) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      _metaTableName,
      <String, Object?>{
        'key': 'vehicle_seed_version',
        'value': version.toString(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _applySeedDataIfNeeded(
      Database db, {
        bool force = false,
      }) async {
    final current = await _currentSeedVersion(db);
    if (!force && current >= _seedVersion) return;

    await _normalizeExistingRows(db);

    final batch = db.batch();
    for (final key in _obsoleteSeedKeys) {
      batch.delete(
        tableName,
        where: 'manufacturer_name = ? AND model_name = ?',
        whereArgs: <Object?>[key.manufacturerName, key.modelName],
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in _seedRows) {
      batch.insert(
        tableName,
        <String, Object?>{
          'manufacturer_name': _canonicalManufacturerName(row.manufacturerName),
          'model_name': _canonicalModelName(row.modelName),
          'priority_1_slot_key': ParkingSlotPreferenceKey.normalize(row.priority1SlotKey),
          'priority_2_slot_key': ParkingSlotPreferenceKey.normalize(row.priority2SlotKey),
          'priority_3_slot_key': ParkingSlotPreferenceKey.normalize(row.priority3SlotKey),
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _setSeedVersion(db, _seedVersion);
  }

  static Future<void> _normalizeExistingRows(Database db) async {
    final rows = await db.query(
      tableName,
      columns: const <String>[
        'id',
        'manufacturer_name',
        'model_name',
        'priority_1_slot_key',
        'priority_2_slot_key',
        'priority_3_slot_key',
        'created_at',
        'updated_at',
      ],
    );

    final batch = db.batch();
    var changed = false;

    for (final row in rows) {
      final id = row['id'];
      if (id == null) continue;

      final manufacturerName = ((row['manufacturer_name'] as String?) ?? '').trim();
      final modelName = ((row['model_name'] as String?) ?? '').trim();
      final canonicalManufacturerName = _canonicalManufacturerName(manufacturerName);
      final canonicalModelName = _canonicalModelName(modelName);

      if (canonicalManufacturerName.isEmpty || canonicalModelName.isEmpty) continue;
      if (manufacturerName == canonicalManufacturerName && modelName == canonicalModelName) {
        continue;
      }

      final existing = await db.query(
        tableName,
        columns: const <String>['id'],
        where: 'manufacturer_name = ? AND model_name = ? AND id != ?',
        whereArgs: <Object?>[canonicalManufacturerName, canonicalModelName, id],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        batch.delete(
          tableName,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      } else {
        final priorities = _completePriorityKeys(
          (row['priority_1_slot_key'] ?? '').toString(),
          (row['priority_2_slot_key'] ?? '').toString(),
          (row['priority_3_slot_key'] ?? '').toString(),
        );
        batch.update(
          tableName,
          <String, Object?>{
            'manufacturer_name': canonicalManufacturerName,
            'model_name': canonicalModelName,
            'priority_1_slot_key': priorities[0],
            'priority_2_slot_key': priorities[1],
            'priority_3_slot_key': priorities[2],
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      }
      changed = true;
    }

    if (changed) await batch.commit(noResult: true);
  }

  Future<List<String>> getManufacturers() async {
    final db = await database;
    final rows = await db.query(
      tableName,
      columns: const <String>['manufacturer_name'],
      distinct: true,
      orderBy: 'manufacturer_name ASC',
    );

    return rows
        .map((e) => _canonicalManufacturerName(((e['manufacturer_name'] as String?) ?? '').trim()))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  Future<List<String>> getModelsByManufacturer(String manufacturerName) async {
    final db = await database;
    final cleanManufacturerName = _canonicalManufacturerName(manufacturerName);
    if (cleanManufacturerName.isEmpty) return const <String>[];

    final rows = await db.query(
      tableName,
      columns: const <String>['model_name'],
      where: 'manufacturer_name = ?',
      whereArgs: <Object?>[cleanManufacturerName],
      orderBy: 'model_name ASC',
    );

    return rows
        .map((e) => _canonicalModelName(((e['model_name'] as String?) ?? '').trim()))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  Future<VehicleParkingPreference?> findPreference({
    required String manufacturerName,
    required String modelName,
  }) async {
    final db = await database;
    final cleanManufacturerName = _canonicalManufacturerName(manufacturerName);
    final cleanModelName = _canonicalModelName(modelName);
    if (cleanManufacturerName.isEmpty || cleanModelName.isEmpty) return null;

    final rows = await db.query(
      tableName,
      where: 'manufacturer_name = ? AND model_name = ?',
      whereArgs: <Object?>[cleanManufacturerName, cleanModelName],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return VehicleParkingPreference.fromMap(rows.first);
  }

  Future<void> upsertPreference({
    required String manufacturerName,
    required String modelName,
    required String priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  }) async {
    final db = await database;
    final cleanManufacturerName = _canonicalManufacturerName(manufacturerName);
    final cleanModelName = _canonicalModelName(modelName);
    final priorities = _completePriorityKeys(
      priority1SlotKey,
      priority2SlotKey,
      priority3SlotKey,
    );

    if (cleanManufacturerName.isEmpty || cleanModelName.isEmpty) return;
    if (!ParkingSlotPreferenceKey.isValid(priorities[0])) return;
    if (!ParkingSlotPreferenceKey.isValid(priorities[1])) return;
    if (!ParkingSlotPreferenceKey.isValid(priorities[2])) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await findPreference(
      manufacturerName: cleanManufacturerName,
      modelName: cleanModelName,
    );

    if (existing == null) {
      await db.insert(
        tableName,
        <String, Object?>{
          'manufacturer_name': cleanManufacturerName,
          'model_name': cleanModelName,
          'priority_1_slot_key': priorities[0],
          'priority_2_slot_key': priorities[1],
          'priority_3_slot_key': priorities[2],
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    await db.update(
      tableName,
      <String, Object?>{
        'priority_1_slot_key': priorities[0],
        'priority_2_slot_key': priorities[1],
        'priority_3_slot_key': priorities[2],
        'updated_at': now,
      },
      where: 'manufacturer_name = ? AND model_name = ?',
      whereArgs: <Object?>[cleanManufacturerName, cleanModelName],
    );
  }

  static List<String> _completePriorityKeys(
      String priority1SlotKey,
      String? priority2SlotKey,
      String? priority3SlotKey,
      ) {
    final result = <String>[];

    void addKey(String? value) {
      if (value == null) return;
      final normalized = ParkingSlotPreferenceKey.normalize(value);
      if (normalized.isEmpty) return;
      if (!ParkingSlotPreferenceKey.isValid(normalized)) return;
      if (result.contains(normalized)) return;
      result.add(normalized);
    }

    addKey(priority1SlotKey);
    addKey(priority2SlotKey);
    addKey(priority3SlotKey);

    for (final fallback in _fallbackPriorityKeys(result.isEmpty ? ParkingSlotPreferenceKey.standard : result.first)) {
      addKey(fallback);
      if (result.length >= 3) break;
    }

    while (result.length < 3) {
      addKey(ParkingSlotPreferenceKey.standard);
      addKey(ParkingSlotPreferenceKey.extended);
      addKey(ParkingSlotPreferenceKey.compact);
    }

    return result.take(3).toList(growable: false);
  }

  static List<String> _fallbackPriorityKeys(String primaryKey) {
    switch (ParkingSlotPreferenceKey.normalize(primaryKey)) {
      case ParkingSlotPreferenceKey.compact:
        return const <String>[
          ParkingSlotPreferenceKey.standard,
          ParkingSlotPreferenceKey.extended,
        ];
      case ParkingSlotPreferenceKey.standard:
        return const <String>[
          ParkingSlotPreferenceKey.extended,
          ParkingSlotPreferenceKey.compact,
        ];
      case ParkingSlotPreferenceKey.extended:
        return const <String>[
          ParkingSlotPreferenceKey.standard,
          ParkingSlotPreferenceKey.compact,
        ];
      case ParkingSlotPreferenceKey.evCompact:
        return const <String>[
          ParkingSlotPreferenceKey.evStandard,
          ParkingSlotPreferenceKey.standard,
          ParkingSlotPreferenceKey.compact,
        ];
      case ParkingSlotPreferenceKey.evStandard:
        return const <String>[
          ParkingSlotPreferenceKey.standard,
          ParkingSlotPreferenceKey.evExtended,
          ParkingSlotPreferenceKey.extended,
        ];
      case ParkingSlotPreferenceKey.evExtended:
        return const <String>[
          ParkingSlotPreferenceKey.extended,
          ParkingSlotPreferenceKey.evStandard,
          ParkingSlotPreferenceKey.standard,
        ];
      default:
        return const <String>[
          ParkingSlotPreferenceKey.standard,
          ParkingSlotPreferenceKey.extended,
          ParkingSlotPreferenceKey.compact,
        ];
    }
  }

  static String _canonicalManufacturerName(String manufacturerName) {
    final clean = _cleanName(manufacturerName);
    final key = _compactKey(clean);
    if (key.isEmpty) return '';

    switch (key) {
      case 'hyundai':
      case 'hyundaimotor':
      case '현대':
      case '현대차':
      case '현대자동차':
        return '현대';
      case 'kia':
      case '기아':
      case '기아자동차':
        return '기아';
      case 'genesis':
      case '제네시스':
        return '제네시스';
      case 'kgm':
      case 'kgmobility':
      case 'kg모빌리티':
      case '쌍용':
      case '쌍용자동차':
      case 'ssangyong':
        return 'KGM';
      case 'renaultkorea':
      case 'renaultkoreamotors':
      case 'renault':
      case '르노':
      case '르노코리아':
      case '르노삼성':
        return '르노코리아';
      case 'chevrolet':
      case '쉐보레':
      case '한국gm':
      case 'gmkorea':
        return '쉐보레';
      case 'mercedesbenz':
      case 'mercedes-benz':
      case 'mercedes':
      case 'benz':
      case '메르세데스벤츠':
      case '메르세데스-벤츠':
      case '메르세데스':
      case '벤츠':
        return '메르세데스-벤츠';
      case 'bmw':
      case '비엠더블유':
        return 'BMW';
      case 'mini':
      case '미니':
        return 'MINI';
      case 'audi':
      case '아우디':
        return '아우디';
      case 'volkswagen':
      case 'vw':
      case '폭스바겐':
        return '폭스바겐';
      case 'volvo':
      case '볼보':
        return '볼보';
      case 'polestar':
      case '폴스타':
        return '폴스타';
      case 'tesla':
      case '테슬라':
        return '테슬라';
      case 'toyota':
      case '토요타':
      case '도요타':
        return '토요타';
      case 'lexus':
      case '렉서스':
        return '렉서스';
      case 'honda':
      case '혼다':
        return '혼다';
      case 'jeep':
      case '지프':
        return '지프';
      case 'peugeot':
      case '푸조':
        return '푸조';
      case 'landrover':
      case '랜드로버':
      case 'rangerover':
      case '레인지로버':
        return '랜드로버';
      case 'cadillac':
      case '캐딜락':
        return '캐딜락';
      case 'ford':
      case '포드':
        return '포드';
      case 'lincoln':
      case '링컨':
        return '링컨';
      case 'byd':
      case '비야디':
        return 'BYD';
      default:
        return clean;
    }
  }

  static String _canonicalModelName(String modelName) {
    final clean = _cleanName(modelName);
    final key = _compactKey(clean);
    if (key.isEmpty) return '';

    if (key.contains('grandeur') || key.contains('그랜저')) return '그랜저';
    if (key.contains('sonata') || key.contains('쏘나타') || key.contains('소나타')) return '쏘나타';
    if (key.contains('avante') || key.contains('elantra') || key.contains('아반떼') || key.contains('아반테')) return '아반떼';
    if (key.contains('santafe') || key.contains('싼타페') || key.contains('산타페')) return '싼타페';
    if (key.contains('palisade') || key.contains('팰리세이드') || key.contains('펠리세이드')) return '팰리세이드';
    if (key.contains('tucson') || key.contains('투싼')) return '투싼';
    if (key.contains('venue') || key.contains('베뉴')) return '베뉴';
    if (key.contains('casper') || key.contains('캐스퍼')) return '캐스퍼';
    if (key.contains('kona') || key.contains('코나')) return '코나';
    if (key.contains('nexo') || key.contains('넥쏘') || key.contains('넥소')) return '넥쏘';
    if (key.contains('staria') || key.contains('스타리아') || key.contains('starex') || key.contains('스타렉스')) return '스타리아';
    if (key == 'st1') return 'ST1';
    if (key.contains('porter') || key.contains('포터')) return '포터 II';
    if (key.contains('ioniq9') || key.contains('아이오닉9')) return '아이오닉 9';
    if (key.contains('ioniq6') || key.contains('아이오닉6')) return '아이오닉 6';
    if (key.contains('ioniq5') || key.contains('아이오닉5')) return '아이오닉 5';

    if (key.contains('morning') || key.contains('모닝')) return '모닝';
    if (key == 'ray' || key.contains('레이')) return '레이';
    if (key.contains('seltos') || key.contains('셀토스')) return '셀토스';
    if (key.contains('niro') || key.contains('니로')) return '니로';
    if (key.contains('sportage') || key.contains('스포티지')) return '스포티지';
    if (key.contains('sorento') || key.contains('쏘렌토') || key.contains('소렌토')) return '쏘렌토';
    if (key.contains('carnival') || key.contains('카니발')) return '카니발';
    if (key.contains('bongo') || key.contains('봉고')) return '봉고Ⅲ';
    if (key == 'pv5') return 'PV5';
    if (key == 'k5') return 'K5';
    if (key == 'k8') return 'K8';
    if (key == 'k9') return 'K9';
    if (key == 'ev3') return 'EV3';
    if (key == 'ev4') return 'EV4';
    if (key == 'ev5') return 'EV5';
    if (key == 'ev6') return 'EV6';
    if (key == 'ev9') return 'EV9';

    if (key.startsWith('gv60')) return 'GV60';
    if (key.startsWith('gv70')) return 'GV70';
    if (key.startsWith('gv80')) return 'GV80';
    if (key.startsWith('g70')) return 'G70';
    if (key.startsWith('g80')) return 'G80';
    if (key.startsWith('g90')) return 'G90';

    if (key.contains('tivoli') || key.contains('티볼리')) return '티볼리';
    if (key.contains('korando') || key.contains('코란도')) return '코란도';
    if (key.contains('torres') || key.contains('토레스')) return '토레스';
    if (key.contains('actyon') || key.contains('액티언')) return '액티언';
    if (key.contains('rexton') || key.contains('렉스턴')) return '렉스턴';

    if (key.contains('grandkoleos') || key.contains('그랑콜레오스')) return '그랑 콜레오스';
    if (key.contains('arkana') || key.contains('아르카나')) return '아르카나';
    if (key.contains('scenic') || key.contains('세닉')) return '세닉';

    if (key.contains('traxcrossover') || key.contains('트랙스크로스오버')) return '트랙스 크로스오버';
    if (key.contains('trailblazer') || key.contains('트레일블레이저')) return '트레일블레이저';

    if (key == 'aclass' || key == 'a클래스') return 'A-Class';
    if (key == 'cclass' || key == 'c클래스') return 'C-Class';
    if (key == 'eclass' || key == 'e클래스') return 'E-Class';
    if (key == 'sclass' || key == 's클래스') return 'S-Class';
    if (key == 'eqb') return 'EQB';
    if (key == 'eqe') return 'EQE';
    if (key == 'gla') return 'GLA';
    if (key == 'glb') return 'GLB';
    if (key == 'glc') return 'GLC';
    if (key == 'gle') return 'GLE';
    if (key == 'gls') return 'GLS';
    if (key == 'gclass' || key == 'g클래스') return 'G-Class';

    if (key == '1series' || key == '1시리즈') return '1시리즈';
    if (key == '2series' || key == '2시리즈') return '2시리즈';
    if (key == '3series' || key == '3시리즈') return '3시리즈';
    if (key == '4series' || key == '4시리즈') return '4시리즈';
    if (key == '5series' || key == '5시리즈') return '5시리즈';
    if (key == '7series' || key == '7시리즈') return '7시리즈';
    if (key == 'x1') return 'X1';
    if (key == 'x2') return 'X2';
    if (key == 'x3') return 'X3';
    if (key == 'x4') return 'X4';
    if (key == 'x5') return 'X5';
    if (key == 'x6') return 'X6';
    if (key == 'x7') return 'X7';
    if (key == 'i3') return 'i3';
    if (key == 'i4') return 'i4';
    if (key == 'i5') return 'i5';
    if (key == 'i7') return 'i7';
    if (key == 'ix1') return 'iX1';
    if (key == 'ix2') return 'iX2';
    if (key == 'ix3') return 'iX3';
    if (key == 'ix') return 'iX';

    if (key == 'cooper' || key == 'minicooper') return 'MINI Cooper';
    if (key == 'cooper5door' || key == 'minicooper5door') return 'MINI Cooper 5-Door';
    if (key == 'countryman' || key == 'minicountryman') return 'MINI Countryman';
    if (key == 'aceman' || key == 'miniaceman') return 'MINI Aceman';
    if (key == 'allelectricminicooper' || key == 'electricminicooper') return 'All-Electric MINI Cooper';
    if (key == 'allelectricminicountryman' || key == 'electricminicountryman') return 'All-Electric MINI Countryman';

    if (key == 'a3') return 'A3';
    if (key == 'a5') return 'A5';
    if (key == 'a6') return 'A6';
    if (key == 'a7') return 'A7';
    if (key == 'a8') return 'A8';
    if (key == 'q3') return 'Q3';
    if (key == 'q5') return 'Q5';
    if (key == 'q7') return 'Q7';
    if (key == 'q8') return 'Q8';
    if (key == 'q6etron') return 'Q6 e-tron';
    if (key == 'q8etron') return 'Q8 e-tron';
    if (key == 'a6etron') return 'A6 e-tron';

    if (key == 'golf' || key == '골프') return 'Golf';
    if (key == 'atlas' || key == '아틀라스') return 'Atlas';
    if (key == 'touareg' || key == '투아렉') return 'Touareg';
    if (key == 'id4') return 'ID.4';
    if (key == 'id5') return 'ID.5';

    if (key == 's60') return 'S60';
    if (key == 's90') return 'S90';
    if (key == 'v60crosscountry' || key == 'v60cc') return 'V60 Cross Country';
    if (key == 'v90crosscountry' || key == 'v90cc') return 'V90 Cross Country';
    if (key == 'xc40') return 'XC40';
    if (key == 'xc60') return 'XC60';
    if (key == 'xc90') return 'XC90';
    if (key == 'ex30') return 'EX30';
    if (key == 'ex40') return 'EX40';
    if (key == 'ec40') return 'EC40';
    if (key == 'ex90') return 'EX90';

    if (key == 'polestar2' || key == '폴스타2') return 'Polestar 2';
    if (key == 'polestar3' || key == '폴스타3') return 'Polestar 3';
    if (key == 'polestar4' || key == '폴스타4') return 'Polestar 4';

    if (key == 'model3' || key == '모델3') return 'Model 3';
    if (key == 'modely' || key == '모델y') return 'Model Y';
    if (key == 'models' || key == '모델s') return 'Model S';
    if (key == 'modelx' || key == '모델x') return 'Model X';

    if (key == 'camry' || key == '캠리') return 'Camry';
    if (key == 'prius' || key == '프리우스') return 'Prius';
    if (key == 'crown' || key == '크라운') return 'Crown';
    if (key == 'rav4' || key == '라브4') return 'RAV4';
    if (key == 'highlander' || key == '하이랜더') return 'Highlander';
    if (key == 'alphard' || key == '알파드') return 'Alphard';
    if (key == 'sienna' || key == '시에나') return 'Sienna';

    if (key == 'ux') return 'UX';
    if (key == 'nx') return 'NX';
    if (key == 'rx') return 'RX';
    if (key == 'rz') return 'RZ';
    if (key == 'es') return 'ES';
    if (key == 'ls') return 'LS';
    if (key == 'lm') return 'LM';

    if (key == 'accord' || key == '어코드') return 'Accord';
    if (key == 'crv') return 'CR-V';
    if (key == 'pilot' || key == '파일럿') return 'Pilot';
    if (key == 'odyssey' || key == '오딧세이' || key == '오디세이') return 'Odyssey';

    if (key == 'wrangler' || key == '랭글러') return 'Wrangler';
    if (key == 'grandcherokeel' || key == '그랜드체로키l') return 'Grand Cherokee L';

    if (key == '308') return '308';
    if (key == '408') return '408';
    if (key == '3008') return '3008';
    if (key == '5008') return '5008';

    if (key == 'defender' || key == '디펜더') return 'Defender';
    if (key == 'discovery' || key == '디스커버리') return 'Discovery';
    if (key == 'discoverysport' || key == '디스커버리스포츠') return 'Discovery Sport';
    if (key == 'rangeroverevoque' || key == '레인지로버이보크') return 'Range Rover Evoque';
    if (key == 'rangerovervelar' || key == '레인지로버벨라') return 'Range Rover Velar';
    if (key == 'rangerover sport' || key == 'rangerover스포츠') return 'Range Rover Sport';
    if (key == 'rangeroversport' || key == '레인지로버스포츠') return 'Range Rover Sport';

    if (key == 'xt4') return 'XT4';
    if (key == 'xt5') return 'XT5';
    if (key == 'xt6') return 'XT6';
    if (key == 'lyriq' || key == '리릭') return 'Lyriq';
    if (key == 'escalade' || key == '에스컬레이드') return 'Escalade';

    if (key == 'explorer' || key == '익스플로러') return 'Explorer';
    if (key == 'bronco' || key == '브롱코') return 'Bronco';
    if (key == 'expedition' || key == '익스페디션') return 'Expedition';

    if (key == 'corsair' || key == '코세어') return 'Corsair';
    if (key == 'nautilus' || key == '노틸러스') return 'Nautilus';
    if (key == 'aviator' || key == '에비에이터' || key == '애비에이터') return 'Aviator';
    if (key == 'navigator' || key == '네비게이터' || key == '내비게이터') return 'Navigator';

    if (key == 'dolphin' || key == '돌핀') return 'Dolphin';
    if (key == 'atto3' || key == '아토3') return 'Atto 3';
    if (key == 'seal' || key == '씰') return 'Seal';
    if (key == 'sealion7' || key == '씨라이언7' || key == '실리온7') return 'Sealion 7';

    return clean;
  }

  static String _cleanName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _compactKey(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('×', 'x')
        .replaceAll('Ⅱ', 'ii')
        .replaceAll('Ⅲ', 'iii')
        .replaceAll('ⅱ', 'ii')
        .replaceAll('ⅲ', 'iii')
        .replaceAll(RegExp(r'[\s\-_/().\[\]]+'), '');
  }
}

class _VehicleParkingPreferenceSeed {
  final String manufacturerName;
  final String modelName;
  final String priority1SlotKey;
  final String priority2SlotKey;
  final String priority3SlotKey;

  const _VehicleParkingPreferenceSeed({
    required this.manufacturerName,
    required this.modelName,
    required this.priority1SlotKey,
    required this.priority2SlotKey,
    required this.priority3SlotKey,
  });
}
