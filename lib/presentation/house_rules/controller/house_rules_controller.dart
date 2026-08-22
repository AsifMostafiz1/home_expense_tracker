import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/push_outbox_service.dart';
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
  String userPhone = '';

  List<HouseRuleModel> rules = [];

  /// Rule id → the wording version this member has agreed to. Loaded from the
  /// device first and from Firestore right after, so the launch gate can
  /// decide without a connection.
  Map<String, int> acks = {};

  /// Ticked in the acknowledgement screen, before anything is written.
  Set<String> checkedRuleIds = {};

  bool isAcknowledging = false;

  StreamSubscription<List<HouseRuleModel>>? _subscription;

  Completer<void>? _firstSnapshot;

  /// Completes once the rules have arrived at least once — what the launch
  /// gate waits on instead of polling [isLoading].
  Future<void> get rulesReady => (_firstSnapshot ??= Completer<void>()).future;

  Future<void>? _acksLoad;

  /// Completes once the acknowledgements have been read at least once.
  Future<void> get acksReady => _acksLoad ?? loadAcks();

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
    _loadSession().then((_) => loadAcks());
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
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
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
        _completeFirstSnapshot();
        update();
      },
      onError: (Object error) {
        debugPrint('Error listening to house rules: $error');
        isLoading = false;
        errorMessage = error.toString();
        // The gate is waiting on this; a listener that cannot start must not
        // hold the launch open.
        _completeFirstSnapshot();
        update();
      },
    );
  }

  void _completeFirstSnapshot() {
    final Completer<void> completer = _firstSnapshot ??= Completer<void>();
    if (!completer.isCompleted) completer.complete();
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

    // Saving a rule back exactly as it was is not an edit. Writing it anyway
    // would move its stamp forward, which is what the house acknowledges
    // against — so everyone would be asked to agree again to wording nobody
    // touched, and the notification would go out for nothing.
    if (existing != null &&
        en == existing.textEn.trim() &&
        bn == existing.textBn.trim()) {
      CustomSnackbar.show(type: SnackbarType.info, message: 'rule_saved'.tr);
      return true;
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

      _notifyHouse(isNew: existing == null, textEn: en, textBn: bn);

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
      await repository.saveOrder(rules);
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

  /// Tells everyone else a rule has changed.
  ///
  /// Rides the push outbox rather than the network directly: the rule itself
  /// is already written, and a notification that cannot go out now goes out on
  /// the next connection instead of being lost. The sender's own phone drops
  /// it on arrival — see `_showNotificationIfAppropriate`.
  void _notifyHouse({
    required bool isNew,
    required String textEn,
    required String textBn,
  }) {
    if (!Get.isRegistered<PushOutboxService>()) return;

    unawaited(Get.find<PushOutboxService>().send(
      title: (isNew ? 'new_rule_notification_title' : 'rule_updated_notification_title')
          .trParams({'name': userName}),
      // Both wordings, because the recipients do not all read the same one
      // and the notification is composed here, on the admin's phone.
      body: languageCode == 'bn' ? '$textBn\n$textEn' : '$textEn\n$textBn',
      data: {
        'senderName': userName,
        'senderPhone': userPhone,
        'type': 'house_rules',
      },
    ));
  }

  /// ------------------------------------------------------- acknowledgements

  /// Reads what this member has already agreed to: the device's copy first,
  /// so a launch decides immediately, then Firestore's, which is the one that
  /// survives a reinstall. The two are merged by keeping the newer version of
  /// each rule — an acknowledgement is never taken away by a stale read.
  Future<void> loadAcks() {
    return _acksLoad = _loadAcks();
  }

  Future<void> _loadAcks() async {
    if (userPhone.isEmpty) await _loadSession();
    if (userPhone.isEmpty) return;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    acks = _merged(acks, _decodeAcks(
        prefs.getString(AppConstant.keyHouseRuleAcks(userPhone))));
    update();

    try {
      acks = _merged(acks, await repository.fetchAcks(userPhone));
      await _cacheAcks(prefs);
    } catch (e) {
      // The device's copy stands. Erring towards "already agreed" here is
      // deliberate: a failed read must not put the gate in front of somebody
      // who has answered it.
      debugPrint('House rules: could not read acknowledgements — $e');
    }
    update();
  }

  static Map<String, int> _decodeAcks(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toInt(),
      };
    } catch (e) {
      debugPrint('House rules: cached acknowledgements unreadable — $e');
      return {};
    }
  }

  static Map<String, int> _merged(Map<String, int> a, Map<String, int> b) {
    final Map<String, int> out = Map<String, int>.from(a);
    b.forEach((id, version) {
      final int? mine = out[id];
      if (mine == null || version > mine) out[id] = version;
    });
    return out;
  }

  Future<void> _cacheAcks(SharedPreferences prefs) => prefs.setString(
        AppConstant.keyHouseRuleAcks(userPhone),
        jsonEncode(acks),
      );

  /// Whether this member still owes [rule] an agreement — never seen, or seen
  /// at an older wording than the one on screen now.
  bool needsAck(HouseRuleModel rule) {
    final int? acked = acks[rule.id];
    if (acked == null) return true;
    // A rule whose server stamp has not landed yet reads as version 0, so it
    // never counts as newer than what was agreed to.
    return rule.version > acked;
  }

  List<HouseRuleModel> get pendingRules =>
      rules.where(needsAck).toList(growable: false);

  bool get hasPendingRules => pendingRules.isNotEmpty;

  /// Opens the acknowledgement screen's state: everything already agreed to
  /// starts ticked, so a member who owes one new rule ticks one box rather
  /// than all seven again.
  void beginAcknowledgement() {
    checkedRuleIds = rules
        .where((rule) => !needsAck(rule))
        .map((rule) => rule.id)
        .toSet();
    update();
  }

  void toggleChecked(HouseRuleModel rule) {
    if (!checkedRuleIds.add(rule.id)) checkedRuleIds.remove(rule.id);
    update();
  }

  bool isChecked(HouseRuleModel rule) => checkedRuleIds.contains(rule.id);

  bool get allChecked =>
      rules.isNotEmpty && rules.every((rule) => checkedRuleIds.contains(rule.id));

  /// Records agreement to every rule as it reads right now.
  ///
  /// The device's copy is written first and the screen closes on it: the
  /// answer is the member's, and a connection that is not there must not make
  /// them sit through the same list again. Firestore catches up behind.
  Future<bool> acceptRules() async {
    if (!allChecked) return false;
    if (userPhone.isEmpty) await _loadSession();

    try {
      isAcknowledging = true;
      update();

      final Map<String, int> next = {
        for (final HouseRuleModel rule in rules)
          rule.id: rule.version == 0
              ? DateTime.now().millisecondsSinceEpoch
              : rule.version,
      };
      acks = next;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await _cacheAcks(prefs);

      unawaited(repository
          .saveAcks(userPhone, next, name: userName)
          .catchError((Object e) =>
              debugPrint('House rules: acknowledgement not stored — $e')));

      return true;
    } catch (e) {
      debugPrint('Error acknowledging house rules: $e');
      return false;
    } finally {
      isAcknowledging = false;
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
