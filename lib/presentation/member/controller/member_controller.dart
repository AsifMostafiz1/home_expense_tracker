import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/push_notification_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/member_model.dart';
import '../repository/member_repository.dart';

class MemberController extends GetxController implements GetxService {
  final MemberRepository repository;

  MemberController({required this.repository});

  List<MemberModel> members = [];
  bool isLoading = true;
  bool isRemoving = false;
  bool isUpdatingRole = false;
  String errorMessage = '';

  /// Who is looking at the screen — drives the "You" badge and decides
  /// whether the remove action is offered at all.
  String currentUserPhone = '';
  bool isAdminUser = false;

  StreamSubscription<List<MemberModel>>? _membersSub;

  @override
  void onInit() {
    super.onInit();
    _loadSession();
    fetchMembers();
  }

  @override
  void onClose() {
    _membersSub?.cancel();
    super.onClose();
  }

  Future<void> _loadSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentUserPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  bool isMe(MemberModel member) => member.phone == currentUserPhone;

  /// An admin may remove anyone but themselves.
  bool canRemove(MemberModel member) => isAdminUser && !isMe(member);

  /// Same rule for the admin switch: you cannot change your own role here, so
  /// the house can never be left without an admin by accident.
  bool canManageRole(MemberModel member) => isAdminUser && !isMe(member);

  /// Anything an admin can act on opens the manage sheet.
  bool canManage(MemberModel member) => isAdminUser && !isMe(member);

  void fetchMembers() {
    _membersSub?.cancel();
    _membersSub = repository.getMembersStream().listen(
      (membersList) {
        isLoading = false;
        errorMessage = '';
        // Admins first, then alphabetical — a stable order the list can keep.
        membersList.sort((a, b) {
          if (a.isAdminUser != b.isAdminUser) return a.isAdminUser ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        members = membersList;
        update();
      },
      onError: (error) {
        isLoading = false;
        errorMessage = error.toString();
        update();
      },
    );
  }

  /// Grants or revokes admin rights for another member.
  ///
  /// The member's own device reads its role from local preferences, so the
  /// change lands there on their next app launch, when the splash screen
  /// re-syncs the account.
  Future<void> setAdminRole(MemberModel member, bool makeAdmin) async {
    if (!canManageRole(member)) return;

    isUpdatingRole = true;
    update();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final String adminName =
          prefs.getString(AppConstant.keyUserName) ?? 'unknown'.tr;
      final String adminPhone =
          prefs.getString(AppConstant.keyUserPhone) ?? '';

      await repository.setAdminRole(member.phone, makeAdmin, adminName);

      await FirebaseFirestore.instance
          .collection(AppConstant.collectionEditLogs)
          .add({
        'adminName': adminName,
        'adminPhone': adminPhone,
        'targetUserName': member.name,
        'targetUserPhone': member.phone,
        'type': 'role',
        'description': makeAdmin
            ? '"${member.name}" (${member.phone}) was granted admin access'
            : 'Admin access was revoked for "${member.name}" (${member.phone})',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await PushNotificationService().sendPushNotification(
        title: makeAdmin ? 'admin_granted_title'.tr : 'admin_revoked_title'.tr,
        body: (makeAdmin ? 'admin_granted_body' : 'admin_revoked_body')
            .trParams({'name': adminName}),
        targetPhones: [member.phone],
      );

      CustomSnackbar.show(
        type: SnackbarType.success,
        message: (makeAdmin ? 'admin_granted' : 'admin_revoked')
            .trParams({'name': member.name}),
      );
    } catch (e) {
      CustomSnackbar.show(
        type: SnackbarType.error,
        message: 'failed_update_role'.tr,
      );
    } finally {
      isUpdatingRole = false;
      update();
    }
  }

  /// Revokes a member's access. Sign-in refuses a removed account, sign-up
  /// cannot reclaim the phone number, and the splash screen re-checks on every
  /// launch so a session that is already open gets signed out too.
  ///
  /// Their meals and expenses are deliberately left in place — removing them
  /// would silently rewrite the household's shared totals for the month.
  Future<void> removeMember(MemberModel member) async {
    if (!canRemove(member)) return;

    isRemoving = true;
    update();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final String adminName =
          prefs.getString(AppConstant.keyUserName) ?? 'unknown'.tr;
      final String adminPhone =
          prefs.getString(AppConstant.keyUserPhone) ?? '';

      await repository.removeMember(member.phone, adminName);

      await FirebaseFirestore.instance
          .collection(AppConstant.collectionEditLogs)
          .add({
        'adminName': adminName,
        'adminPhone': adminPhone,
        'targetUserName': member.name,
        'targetUserPhone': member.phone,
        'type': 'member',
        'description':
            'Member "${member.name}" (${member.phone}) was removed from the app',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Best effort: tell the device it has lost access.
      await PushNotificationService().sendPushNotification(
        title: 'account_removed_title'.tr,
        body: 'account_removed_body'.trParams({'name': adminName}),
        targetPhones: [member.phone],
      );

      CustomSnackbar.show(
        type: SnackbarType.success,
        message: 'member_removed'.trParams({'name': member.name}),
      );
    } catch (e) {
      CustomSnackbar.show(
        type: SnackbarType.error,
        message: 'failed_remove_member'.tr,
      );
    } finally {
      isRemoving = false;
      update();
    }
  }

  Future<void> makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      }
    } catch (e) {
      CustomSnackbar.show(
        type: SnackbarType.error,
        message: 'failed_place_call'.tr,
      );
    }
  }
}
