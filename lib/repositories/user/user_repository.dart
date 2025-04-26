import '../../models/user_model.dart';

abstract class UserRepository {
  Future<UserModel?> getUserByPhone(String phone);

  Future<UserModel?> getUserById(String userId);

  Future<void> updateCurrentArea(String phone, String area, String currentArea);

  Future<void> updateUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});

  Stream<List<UserModel>> getUsersStream(String area);

  Future<void> addUser(UserModel user);

  Future<void> deleteUsers(List<String> ids);

  Future<void> toggleUserSelection(String id, bool isSelected);
}
