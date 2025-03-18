import '../../models/user_model.dart';

abstract class UserRepository {
  Stream<List<UserModel>> getUsersStream();
  Stream<UserModel?> listenToUserStatus(String phone);
  Future<UserModel?> getUserByPhone(String phone);
  Future<void> addUser(UserModel user);
  Future<void> updateUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});
  Future<void> toggleUserSelection(String id, bool isSelected);
  Future<void> deleteUsers(List<String> ids);
  Future<UserModel?> getUserById(String userId);

}
