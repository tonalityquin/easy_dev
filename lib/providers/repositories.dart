import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'dart:developer' as dev;

import '../enums/plate_type.dart';
import '../repositories/adjustment/firestore_adjustment_repository.dart';
import '../repositories/location/firestore_location_repository.dart';
import '../repositories/plate/firestore_plate_repository.dart';
import '../repositories/status/firestore_status_repository.dart';
import '../repositories/user/firestore_user_repository.dart';

import '../repositories/plate/plate_repository.dart';
import '../repositories/location/location_repository.dart';
import '../repositories/user/user_repository.dart';
import '../repositories/adjustment/adjustment_repository.dart';
import '../repositories/status/status_repository.dart';
import '../models/plate_model.dart';
import '../models/location_model.dart';
import '../models/user_model.dart';
import '../models/adjustment_model.dart';
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
    String? adjustmentType,
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
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteAllData() => throw UnimplementedError();

  @override
  Future<void> deletePlate(String documentId) => throw UnimplementedError();

  Stream<List<PlateModel>> getPlatesStream() => throw UnimplementedError();

  Future<PlateModel?> getPlateById(String docId) => throw UnimplementedError();

  Future<void> logPlateAction(PlateModel plate, String action) => throw UnimplementedError();

  Future<void> updatePlateStatus(String plateId, String status) => throw UnimplementedError();

  @override
  Future<List<String>> getAvailableLocations(String area) => throw UnimplementedError();

  @override
  Stream<List<PlateModel>> getPlatesByType(PlateType type) => throw UnimplementedError();

  @override
  Future<PlateModel?> getPlate(String documentId) => throw UnimplementedError();

  @override
  Future<List<PlateModel>> getPlatesByArea(PlateType type, String area) => throw UnimplementedError();

  @override
  Future<void> updatePlateSelection(String id, bool isSelected, {String? selectedBy}) => throw UnimplementedError();

  @override
  Future<int> getPlateCountByType(PlateType type, {DateTime? selectedDate}) {
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
  Stream<List<LocationModel>> getLocationsStream() => throw UnimplementedError();

  @override
  Future<void> toggleLocationSelection(String id, bool selected) => throw UnimplementedError();
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
  Stream<List<UserModel>> getUsersStream() => throw UnimplementedError();

  Future<void> updateUser(UserModel user) => throw UnimplementedError();

  Future<void> resetPassword(String userId) => throw UnimplementedError();

  Future<void> changeUserRole(String userId, String role) => throw UnimplementedError();

  @override
  Stream<UserModel?> listenToUserStatus(String userId) => throw UnimplementedError();

  @override
  Future<void> toggleUserSelection(String userId, bool selected) => throw UnimplementedError();

  @override
  Future<void> updateUserStatus(String userId, String status, {bool? isSaved, bool? isWorking}) =>
      throw UnimplementedError();

  /// ✅ 추가된 추상 메서드 구현 (비워만 놓기)
  @override
  Future<void> updateCurrentArea(String phone, String area, String currentArea) => throw UnimplementedError();
}

class DummyAdjustmentRepository implements AdjustmentRepository {
  @override
  Future<void> addAdjustment(AdjustmentModel adjustment) => throw UnimplementedError();

  @override
  Future<void> deleteAdjustment(List<String> ids) => throw UnimplementedError();

  @override
  Stream<List<AdjustmentModel>> getAdjustmentStream(String locationId) => throw UnimplementedError();
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
  Provider<AdjustmentRepository>(
    create: (_) {
      try {
        return FirestoreAdjustmentRepository();
      } catch (e, s) {
        dev.log("⚠️ AdjustmentRepository 초기화 실패", error: e, stackTrace: s);
        return DummyAdjustmentRepository();
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
