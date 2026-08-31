import 'package:shared_preferences/shared_preferences.dart';

import 'app_constant.dart';

/// Which side of the app the signed-in account gets.
///
/// A meal user has everything the app does today. A general user manages only
/// their own money: their home tabs become the personal wallet — money, dues,
/// direct messages, the report — and nothing house-shared (meals, shared
/// expenses, bills, the group thread) is offered or counted for them.
enum UserType { meal, general }

/// The signed-in account's type, readable synchronously.
///
/// The dashboard decides its tabs in `build`, before any `await` could answer,
/// so the type is loaded into this static ahead of the home screen: by the
/// splash on every launch, and by sign-in and sign-up the moment their prefs
/// are written. It follows the same bargain the admin flag does — an admin's
/// change reaches the member's device at their next launch.
class UserSession {
  const UserSession._();

  static UserType userType = UserType.meal;

  static bool get isGeneral => userType == UserType.general;

  /// The type a stored string means. Anything but 'general' — including a
  /// missing field on an account older than the field — is a meal user.
  static UserType typeOf(String? raw) =>
      raw == AppConstant.userTypeGeneral ? UserType.general : UserType.meal;

  /// Re-reads the type from local preferences into the static.
  static Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    userType = typeOf(prefs.getString(AppConstant.keyUserType));
  }

  /// Forgets the account's type — sign-out and a removed account both land
  /// here, so the next account on this device starts from the default.
  static void reset() => userType = UserType.meal;
}
