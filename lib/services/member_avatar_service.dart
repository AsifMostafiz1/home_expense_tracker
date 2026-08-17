import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_constant.dart';

/// House-wide lookup of who has a profile picture.
///
/// Most screens only ever hold a member's name or phone — the meal totals, the
/// month ledger, the announcement history all work off denormalised rows that
/// were never going to carry an image URL. Rather than thread one through
/// every model, this keeps a single small map in memory and lets
/// [ProfileAvatar] resolve against it.
///
/// One Firestore read of `users` fills it. That collection is a handful of
/// documents — the same read `fetchUsersForFilter` and the member screen
/// already do.
class MemberAvatarService extends GetxController implements GetxService {
  final Map<String, String> _byPhone = {};
  final Map<String, String> _byName = {};

  String _myPhone = '';
  String? _myImage;

  bool _loaded = false;

  /// The signed-in user's own picture. Kept separate because the screens that
  /// show it label the row "My Meals" or "You" rather than by name, so there
  /// is nothing to look up.
  String? get myImage => _myImage;

  String get myPhone => _myPhone;

  /// Resolves a picture from whichever identifier the caller happens to have.
  ///
  /// Phone wins over name — two members can share a name, and the name map is
  /// only there for the rows that carry no phone at all.
  String? imageFor({String? phone, String? name}) {
    if (phone != null && phone.isNotEmpty) {
      final String? byPhone = _byPhone[phone];
      if (byPhone != null) return byPhone;
    }
    if (name != null && name.trim().isNotEmpty) {
      return _byName[name.trim().toLowerCase()];
    }
    return null;
  }

  /// Fills the directory. Cheap to call repeatedly — it no-ops once loaded
  /// unless [force] is set, which is what a profile save does.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _myPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';

      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .get();

      _byPhone.clear();
      _byName.clear();

      for (final QueryDocumentSnapshot doc in snapshot.docs) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        final String image = (data['profileImage'] ?? '').toString();
        if (image.isEmpty) continue;

        // The document id is the phone number, so it stands in when the field
        // itself is missing on an older record.
        final String phone = (data['phone'] ?? doc.id).toString();
        final String name = (data['name'] ?? '').toString().trim().toLowerCase();

        if (phone.isNotEmpty) _byPhone[phone] = image;
        if (name.isNotEmpty) _byName[name] = image;
      }

      _myImage = _myPhone.isEmpty ? null : _byPhone[_myPhone];
      _loaded = true;
      update();
    } catch (e) {
      debugPrint('MemberAvatarService: failed to load avatars — $e');
    }
  }

  /// Applies a just-saved avatar without waiting for the Firestore round trip,
  /// so the picture changes on screen the moment the save returns.
  void setMyImage(String phone, String? image) {
    _myPhone = phone;
    _myImage = image;

    if (phone.isEmpty) return;
    if (image == null || image.isEmpty) {
      _byPhone.remove(phone);
    } else {
      _byPhone[phone] = image;
    }
    update();
  }
}
