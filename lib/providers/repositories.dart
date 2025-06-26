import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'dart:developer' as dev;

import '../enums/plate_type.dart';
import '../repositories/bill_repo/firestore_bill_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/firestore_plate_repository.dart';
import '../repositories/status/firestore_status_repository.dart';
import '../repositories/user/firestore_user_repository.dart';

import '../repositories/plate/plate_repository.dart';
import '../repositories/location/location_repository.dart';
import '../repositories/user/user_repository.dart';
import '../repositories/bill_repo/bill_repository.dart';
import '../repositories/status/status_repository.dart';
import '../models/plate_model.dart';
import '../models/location_model.dart';
import '../models/user_model.dart';
import '../models/bill_model.dart';
import '../models/status_model.dart';

/// ⚠️ fallback dummy 구현체들 (필수 메서드 구현 포함)
class DummyPlateRepository implements PlateRepository {
  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) => throw UnimplementedError();

  @override
  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields) => throw UnimplementedError();

  @override
  Future<void> addRequestOrCompleted({
    required String plateNumber,
    required String area,
    required String region,
    required String location,
    required PlateType plateType,
    required String userName,
    String? billingType,
    List<String>? statusList,
    int basicStandard = 0,
    int basicAmount = 0,
    int addStandard = 0,
    int addAmount = 0,
    List<String>? imageUrls,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deletePlate(String documentId) => throw UnimplementedError();

  Stream<List<PlateModel>> getPlatesStream() => throw UnimplementedError();

  @override
  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  }) =>
      throw UnimplementedError();

  Future<PlateModel?> getPlateById(String docId) => throw UnimplementedError();

  Future<void> logPlateAction(PlateModel plate, String action) => throw UnimplementedError();

  Future<void> updatePlateStatus(String plateId, String status) => throw UnimplementedError();

  @override
  Stream<List<PlateModel>> getPlatesByTypeAndArea(
    PlateType type,
    String area, {
    bool descending = true,
    int? limit,
  }) =>
      throw UnimplementedError();

  @override
  Future<int> getPlateCountByTypeAndArea(PlateType type, String area) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlateModel>> getPlatesByFourDigit({
    required String plateFourDigit,
    required String area,
  }) =>
      throw UnimplementedError();

  @override
  Future<PlateModel?> getPlate(String documentId) => throw UnimplementedError();

  @override
  Future<void> updatePlateSelection(String id, bool isSelected, {String? selectedBy}) => throw UnimplementedError();

  @override
  Future<int> getPlateCountByType(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  }) =>
      throw UnimplementedError();
}

class DummyLocationRepository implements LocationRepository {
  @override
  Future<void> addLocation(LocationModel location) => throw UnimplementedError();

  @override
  Future<void> deleteLocations(List<String> ids) => throw UnimplementedError();

  @override
  Stream<List<LocationModel>> getLocationsStream(String area) => throw UnimplementedError();

  @override
  Future<List<LocationModel>> getLocationsOnce(String area) => throw UnimplementedError();

  @override
  Future<void> toggleLocationSelection(String id, bool selected) => throw UnimplementedError();

  @override
  Future<void> addCompositeLocation(
    String parent,
    List<Map<String, dynamic>> subs, // ✅ 수정된 부분
    String area,
  ) =>
      throw UnimplementedError();
}

class DummyUserRepository implements UserRepository {
  @override
  Future<void> addUser(UserModel user) => throw UnimplementedError();

  @override
  Future<void> deleteUsers(List<String> ids) => throw UnimplementedError();

  @override
  Future<UserModel?> getUserById(String id) => throw UnimplementedError();

  @override
  Future<UserModel?> getUserByPhone(String phone) => throw UnimplementedError();

  @override
  Future<void> toggleUserSelection(String userId, bool selected) => throw UnimplementedError();

  @override
  Future<void> updateUserStatus(
    String phone,
    String area, {
    bool? isSaved,
    bool? isWorking,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> updateCurrentArea(
    String phone,
    String area,
    String currentArea,
  ) =>
      throw UnimplementedError();

  @override
  Stream<List<UserModel>> getUsersBySelectedAreaStream(String selectedArea) => throw UnimplementedError();

  @override
  Future<String?> getEnglishNameByArea(String area, String division) => throw UnimplementedError();

  @override
  Future<List<UserModel>> getUsersBySelectedAreaOnceWithCache(String selectedArea) => throw UnimplementedError();

  @override
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) => throw UnimplementedError();
}

class DummyBillRepository implements BillRepository {
  @override
  Future<void> addBill(BillModel bill) => throw UnimplementedError();

  @override
  Future<void> deleteBill(List<String> ids) => throw UnimplementedError();

  @override
  Stream<List<BillModel>> getBillStream(String locationId) => throw UnimplementedError();

  @override
  Future<List<BillModel>> getBillOnce(String area) => throw UnimplementedError();
}

class DummyStatusRepository implements StatusRepository {
  @override
  Future<void> addToggleItem(StatusModel item) => throw UnimplementedError();

  @override
  Future<void> deleteToggleItem(String id) => throw UnimplementedError();

  @override
  Stream<List<StatusModel>> getStatusStream(String type) => throw UnimplementedError();

  @override
  Future<void> updateToggleStatus(String id, bool status) => throw UnimplementedError();

  @override
  Future<List<StatusModel>> getStatusesOnce(String area) => throw UnimplementedError();
}

final List<SingleChildWidget> repositoryProviders = [
  Provider<PlateRepository>(
    create: (_) {
      try {
        return FirestorePlateRepository();
      } catch (e, s) {
        dev.log("⚠️ PlateRepository 초기화 실패", error: e, stackTrace: s);
        return DummyPlateRepository();
      }
    },
  ),
  Provider<LocationRepository>(
    create: (_) {
      try {
        return FirestoreLocationRepository();
      } catch (e, s) {
        dev.log("⚠️ LocationRepository 초기화 실패", error: e, stackTrace: s);
        return DummyLocationRepository();
      }
    },
  ),
  Provider<UserRepository>(
    create: (_) {
      try {
        return FirestoreUserRepository();
      } catch (e, s) {
        dev.log("⚠️ UserRepository 초기화 실패", error: e, stackTrace: s);
        return DummyUserRepository();
      }
    },
  ),
  Provider<BillRepository>(
    create: (_) {
      try {
        return FirestoreBillRepository();
      } catch (e, s) {
        dev.log("⚠️ AdjustmentRepository 초기화 실패", error: e, stackTrace: s);
        return DummyBillRepository();
      }
    },
  ),
  Provider<StatusRepository>(
    create: (_) {
      try {
        return FirestoreStatusRepository();
      } catch (e, s) {
        dev.log("⚠️ StatusRepository 초기화 실패", error: e, stackTrace: s);
        return DummyStatusRepository();
      }
    },
  ),
];
