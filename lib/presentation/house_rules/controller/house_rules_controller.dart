import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/default_house_rules.dart';
import '../model/house_rule_model.dart';
import '../repository/house_rules_repository.dart';

/// The house rules, live for everyone and editable by an admin.
///
/// The list is a stream rather than a fetch for the reason the announcements
/// are: a rule an admin adds, rewords or drops is house-wide the moment it
/// lands, and every phone already on the screen should show it without a
/// pull. Each rule carries both languages, so nothing here picks one — the
/// screen asks the model for whichever the app is running in.
class HouseRulesController extends GetxController implements GetxService {
  final HouseRulesRepository repository;

  HouseRulesController({required this.repository});

  bool isLoading = true;
  bool isSaving = false;
  bool isSeeding = false;
  String errorMessage = '';

  bool isAdminUser = false;
  String userName = '';

  List<HouseRuleModel> rules = [];

  StreamSubscription<List<HouseRuleModel>>? _subscription;

  /// The language the rules are read in — the same one the rest of the app is
  /// showing, so nothing has to be chosen twice.
  String get languageCode => Get.locale?.languageCode ?? 'en';

  bool get hasRules => rules.isNotEmpty;

  /// Who last touched any rule, and when — the footer of the screen.
  HouseRuleModel? get lastTouched {
    HouseRuleModel? latest;
    for (final HouseRuleModel rule in rules) {
      if (rule.updatedAt == null || rule.updatedBy.isEmpty) continue;
      if (latest == null || rule.updatedAt!.isAfter(latest.updatedAt!)) {
        latest = rule;
      }
    }
    return latest;
  }

  bool get _isOffline =>
      Get.isRegistered<ConnectivityService>() &&
      Get.find<ConnectivityService>().isOffline;

  @override
  void onInit() {
    super.onInit();
    _loadSession();
    _watchRules();
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }

  Future<void> _loadSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    userName = prefs.getString(AppConstant.keyUserName) ?? '';
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  void _watchRules() {
    _subscription?.cancel();
    _subscription = repository.watchRules().listen(
      (list) {
        rules = list;
        isLoading = false;
        errorMessage = '';
        update();
      },
      onError: (Object error) {
        debugPrint('Error listening to house rules: $error');
        isLoading = false;
        errorMessage = error.toString();
        update();
      },
    );
  }

  /// Pull-to-refresh. The stream already keeps the list current, so this
  /// re-attaches it — which is what recovers a listener that fell over while
  /// the connection was gone — and re-reads the role at the same time, for a
  /// screen left open across the moment someone was made an admin.
  Future<void> refreshRules() async {
    await _loadSession();
    _watchRules();
    if (Get.isRegistered<ConnectivityService>()) {
      unawaited(Get.find<ConnectivityService>().probe());
    }
  }

  /// Adds a rule, or rewrites [existing] when one is passed.
  ///
  /// Both languages are required: a rule saved in one of them would be
  /// invisible to whoever reads the app in the other.
  Future<bool> saveRule({
    HouseRuleModel? existing,
    required String textEn,
    required String textBn,
  }) async {
    if (!_requireAdmin()) return false;

    final String en = textEn.trim();
    final String bn = textBn.trim();
    if (en.isEmpty || bn.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'rule_needs_both_languages'.tr);
      return false;
    }

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      if (existing == null) {
        await repository.addRule(
          textEn: en,
          textBn: bn,
          // Appended, not inserted: a new rule goes to the bottom of the list
          // until an admin drags it somewhere else.
          order: rules.isEmpty ? 0 : rules.last.order + 1,
          by: userName,
        );
      } else {
        await repository.updateRule(
          existing.id,
          textEn: en,
          textBn: bn,
          by: userName,
        );
      }

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'rules_saved_offline'.tr : 'rule_saved'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error saving house rule: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_rule'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Removes a rule for the whole house. The list redraws from the stream —
  /// Firestore reports its own local delete straight away, so the row leaves
  /// at once whether or not there is a connection.
  Future<void> deleteRule(HouseRuleModel rule) async {
    if (!_requireAdmin()) return;

    final bool offline = _isOffline;

    try {
      await repository.deleteRule(rule.id);
      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'rules_saved_offline'.tr : 'rule_deleted'.tr,
      );
    } catch (e) {
      debugPrint('Error deleting house rule: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_rule'.tr);
    }
  }

  /// Moves a rule up or down the list.
  ///
  /// [newIndex] is where the rule ends up once it has been lifted out —
  /// `onReorderItem` has already accounted for the gap it left behind.
  ///
  /// The local list is rearranged first so the drag lands where it was
  /// dropped instead of snapping back while the batch is in flight; the
  /// stream then confirms the same order a moment later.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (!_requireAdmin()) return;
    if (oldIndex < 0 || oldIndex >= rules.length) return;
    if (oldIndex == newIndex) return;

    final List<HouseRuleModel> reordered = List<HouseRuleModel>.from(rules);
    final HouseRuleModel moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex.clamp(0, reordered.length), moved);

    rules = [
      for (int i = 0; i < reordered.length; i++)
        reordered[i].copyWith(order: i),
    ];
    update();

    try {
      await repository.saveOrder(rules, by: userName);
    } catch (e) {
      debugPrint('Error reordering house rules: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_rule'.tr);
      // Put the server's order back on screen rather than leaving a local
      // arrangement nobody else can see.
      _watchRules();
    }
  }

  /// Writes the starter set, offered when the house has no rules yet.
  ///
  /// The seeded documents have fixed ids, so a second tap — or two admins
  /// tapping at once — rewrites the same rules instead of doubling them.
  Future<void> addStarterRules() async {
    if (!_requireAdmin()) return;

    try {
      isSeeding = true;
      update();

      await repository.seedRules(kDefaultHouseRules, by: userName);

      CustomSnackbar.show(
        type: _isOffline ? SnackbarType.info : SnackbarType.success,
        message: _isOffline ? 'rules_saved_offline'.tr : 'starter_rules_added'.tr,
      );
    } catch (e) {
      debugPrint('Error seeding house rules: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_rule'.tr);
    } finally {
      isSeeding = false;
      update();
    }
  }

  bool _requireAdmin() {
    if (isAdminUser) return true;
    CustomSnackbar.show(
        type: SnackbarType.error, message: 'admin_only_action'.tr);
    return false;
  }
}
