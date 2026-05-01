import '../model/user_model.dart';

abstract class AuthRepository {
  Future<bool> checkUserExists(String phone);
  Future<void> signUp(UserModel user);
  Future<UserModel?> signIn(String phone);
}
