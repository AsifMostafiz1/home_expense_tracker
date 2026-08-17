import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import 'package:intl/intl.dart';
import '../../meal/controller/meal_controller.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/push_outbox_service.dart';
import '../../../services/receipt_outbox_service.dart';
import '../../../services/supabase_storage_service.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/supabase_config.dart';
import '../model/expense_model.dart';
import '../repository/expense_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseController extends GetxController implements GetxService {
  final ExpenseRepository repository;

  ExpenseController({required this.repository});

  bool isLoading = false;
  List<ExpenseModel> expenses = [];
  Map<String, List<ExpenseModel>> groupedExpenses = {};
  int selectedMonthIndex = 0; // 0 for current, 1 for next
  String selectedType = 'expense'; // 'expense' or 'others'

  DateTime get targetMonth {
    DateTime now = DateTime.now();
    if (selectedMonthIndex == 0) return now;
    return DateTime(now.year, now.month + 1, 1);
  }

  String get selectedMonthName => DateFormat('MMMM, yyyy').format(targetMonth);

  double get displayTotal =>
      filteredExpenses.fold(0.0, (sum, item) => sum + item.amount);

  double get mealTotal =>
      filteredExpenses.where((exp) => exp.type == 'expense').fold(0.0, (sum, item) => sum + item.amount);

  double get othersTotal =>
      filteredExpenses.where((exp) => exp.type == 'others').fold(0.0, (sum, item) => sum + item.amount);

  List<ExpenseModel> get filteredExpenses {
    DateTime target = targetMonth;
    return expenses.where((exp) => exp.date.year == target.year && exp.date.month == target.month).toList();
  }

  void setMonthIndex(int index) {
    selectedMonthIndex = index;
    groupExpenses();
    update();
  }

  void setExpenseType(String type) {
    selectedType = type;
    update();
  }

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  String? amountError;

  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  final SupabaseStorageService _storage = SupabaseStorageService();
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();
  final ReceiptOutboxService _outbox = Get.find<ReceiptOutboxService>();
  final PushOutboxService _pushOutbox = Get.find<PushOutboxService>();

  StreamSubscription<bool>? _onlineSubscription;
  StreamSubscription<void>? _receiptSyncSubscription;

  /// Whether the device has a connection right now — what the screen's status
  /// strip and the save path read.
  bool get isOnline => _connectivity.isOnline;

  /// Entries in the months on screen that are not fully on the server yet —
  /// the entry itself still queued, or its receipt still waiting to upload.
  int get pendingCount => expenses
      .where((exp) => exp.isPending || exp.hasPendingReceipt)
      .length;

  /// Receipt chosen in the form but not uploaded yet. The upload waits for
  /// "save": backing out of the sheet should leave nothing behind in storage.
  File? pickedReceipt;

  /// The receipt already on the entry being edited, if any.
  String? existingReceiptUrl;

  /// Set when the existing receipt is to be dropped on the next save.
  bool removeReceipt = false;

  /// True when [pickedReceipt] is the outbox's copy of a receipt that was
  /// picked offline earlier — the sheet labels it as waiting to upload rather
  /// than as unsaved.
  bool receiptWaitingUpload = false;

  /// Whether the form currently has a receipt to show — a fresh pick, or the
  /// stored one as long as it has not been marked for removal.
  bool get hasReceipt => pickedReceipt != null || (!removeReceipt && (existingReceiptUrl?.isNotEmpty ?? false));

  @override
  void onInit() {
    super.onInit();
    fetchExpenses();

    // Back online: Firestore is already delivering its queue on its own, so a
    // fresh read is what turns the pending badges off. The outbox flushes
    // itself and says when it is done.
    _onlineSubscription =
        _connectivity.onOnline.listen((_) => fetchExpenses(background: true));
    _receiptSyncSubscription =
        _outbox.onSynced.listen((_) => fetchExpenses(background: true));
    // Only the connection flag is read off it — the strip re-renders on that.
    _connectivity.addListener(_onConnectivityChanged);
  }

  @override
  void onClose() {
    _onlineSubscription?.cancel();
    _receiptSyncSubscription?.cancel();
    _connectivity.removeListener(_onConnectivityChanged);
    super.onClose();
  }

  void _onConnectivityChanged() => update();

  void clearForm() {
    amountController.clear();
    descriptionController.clear();
    amountError = null;
    selectedDate = DateTime.now();
    selectedTime = TimeOfDay.now();
    selectedType = 'expense';
    clearReceiptSelection();
    update();
  }

  /// Fills the form from an existing entry, ready for the edit sheet.
  void loadForEdit(ExpenseModel item) {
    amountController.text = item.amount.toString();
    descriptionController.text = item.description;
    amountError = null;
    selectedDate = item.date;
    selectedTime = item.time;
    selectedType = item.type;
    // A receipt still waiting in the outbox comes back into the form as the
    // picked file: saving online uploads it, saving offline re-queues it.
    pickedReceipt = item.pendingReceiptFile;
    receiptWaitingUpload = pickedReceipt != null;
    removeReceipt = false;
    existingReceiptUrl = item.imageUrl;
    update();
  }

  /// Drops any unsaved receipt choice — called when the sheet is left and when
  /// a fresh form is opened.
  void clearReceiptSelection() {
    pickedReceipt = null;
    existingReceiptUrl = null;
    removeReceipt = false;
    receiptWaitingUpload = false;
  }

  /// Photographs or picks a receipt. Downscaled on the device: a receipt has
  /// to stay readable, so it keeps more resolution than an avatar, but not the
  /// several megabytes a phone camera would hand over.
  Future<void> pickReceipt(ImageSource source) async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;

      pickedReceipt = File(picked.path);
      receiptWaitingUpload = false;
      removeReceipt = false;
      update();
    } catch (e) {
      debugPrint('Error picking receipt: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_pick_image'.tr);
    }
  }

  /// Marks the receipt for removal on the next save.
  void removeReceiptImage() {
    pickedReceipt = null;
    receiptWaitingUpload = false;
    removeReceipt = true;
    update();
  }

  void updateSelectedDate(DateTime date) {
    selectedDate = date;
    update();
  }

  void updateSelectedTime(TimeOfDay time) {
    selectedTime = time;
    update();
  }

  /// Cache first, then the server.
  ///
  /// The device's copy answers instantly and holds every entry saved while
  /// offline, so the list is on screen before the network is even asked. The
  /// server read then replaces it — or fails, when there is no connection,
  /// and the cached list simply stays.
  ///
  /// [background] keeps the list on screen and swaps it once the response
  /// lands, instead of collapsing to a skeleton — pull-to-refresh, and the
  /// re-read after a save, which offline is the only read that will land.
  Future<void> fetchExpenses({bool background = false}) async {
    try {
      isLoading = !background;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userPhone == null) {
        isLoading = false;
        update();
        return;
      }

      try {
        final List<ExpenseModel> cached =
            await repository.fetchExpenses(userPhone, fromCache: true);
        if (cached.isNotEmpty) {
          _applyFetched(cached);
          isLoading = false;
          update();
        }
      } catch (e) {
        debugPrint('Expense cache read failed: $e');
      }

      _applyFetched(await repository.fetchExpenses(userPhone));

      // The server just answered — proof of a working connection, and as
      // good a moment as any for the receipts that were waiting on one.
      _connectivity.reportReachable();
      if (_outbox.isNotEmpty) _outbox.flush();
    } catch (e) {
      // Offline, or the server did not answer in time: whatever the cache
      // gave us stays up. Not an error worth a toast — the app bar says the
      // device is offline. Worth a fresh probe, though: a data plan that has
      // just run out looks connected to the OS until something fails.
      debugPrint('Error fetching expenses: $e');
      _connectivity.probe();
    } finally {
      isLoading = false;
      update();
    }
  }

  /// Narrows a fetched list to the two months on screen, orders it newest
  /// first, marks the receipts still waiting in the outbox, and shows it.
  void _applyFetched(List<ExpenseModel> fetchedList) {
    // Filter for current and next month
    DateTime now = DateTime.now();
    DateTime nextMonth = DateTime(now.year, now.month + 1, 1);
    fetchedList = fetchedList.where((exp) {
      bool isCurrent = exp.date.year == now.year && exp.date.month == now.month;
      bool isNext = exp.date.year == nextMonth.year && exp.date.month == nextMonth.month;
      return isCurrent || isNext;
    }).toList();

    // Sort by date then time descending locally
    fetchedList.sort((a, b) {
      DateTime dateA = DateTime(a.date.year, a.date.month, a.date.day);
      DateTime dateB = DateTime(b.date.year, b.date.month, b.date.day);

      int dateCmp = dateB.compareTo(dateA);
      if (dateCmp != 0) return dateCmp;

      int timeA = a.time.hour * 60 + a.time.minute;
      int timeB = b.time.hour * 60 + b.time.minute;
      return timeB.compareTo(timeA);
    });

    for (final ExpenseModel exp in fetchedList) {
      exp.pendingReceiptPath = _outbox.pathFor(exp.id);
    }

    expenses = fetchedList;
    groupExpenses();

    if (expenses.any((exp) => exp.isPending)) {
      _refreshWhenQueueDrains();
      // Covers a queue left over from a launch that was closed before the
      // OS job could be armed — cheap, since an armed job is not re-armed.
      BackgroundSyncService.schedule();
    } else if (_outbox.isEmpty) {
      BackgroundSyncService.disarm();
    }
  }

  bool _watchingQueue = false;

  /// Re-reads the list once Firestore reports every queued write delivered,
  /// so the pending badges clear on their own — a server read that lands
  /// right after reconnecting can still carry them, since the query answer
  /// and the write acknowledgements travel separately.
  ///
  /// Offline this simply waits, however long that takes: the future resolves
  /// when the connection is back and the queue has gone out.
  void _refreshWhenQueueDrains() {
    if (_watchingQueue) return;
    _watchingQueue = true;

    FirebaseFirestore.instance.waitForPendingWrites().then((_) {
      _watchingQueue = false;
      if (!isClosed) fetchExpenses(background: true);
    }).catchError((Object e) {
      // Rejected on a user change, which this app never does mid-session;
      // the next fetch simply arms it again.
      _watchingQueue = false;
      debugPrint('Expense: waitForPendingWrites failed — $e');
    });
  }

  void groupExpenses() {
    Map<String, List<ExpenseModel>> map = {};
    for (var exp in filteredExpenses) {
      DateTime cleanDate = DateTime(exp.date.year, exp.date.month, exp.date.day);
      String dateStr = DateFormat('dd MMMM, yyyy').format(cleanDate);

      if (!map.containsKey(dateStr)) {
        map[dateStr] = [];
      }
      map[dateStr]!.add(exp);
    }
    groupedExpenses = map;
  }

  Future<void> submitExpense({ExpenseModel? existingExpense}) async {
    String amountStr = amountController.text.trim();
    String desc = descriptionController.text.trim();

    amountError = null;
    update();

    if (amountStr.isEmpty) {
      amountError = 'please_enter_amount'.tr;
      update();
      return;
    }

    double? parsedAmount = double.tryParse(amountStr);
    if (parsedAmount == null || parsedAmount <= 0) {
      amountError = 'please_enter_valid_amount'.tr;
      update();
      return;
    }

    double amount = parsedAmount;

    try {
      // The sheet stays up while this runs — a receipt upload takes seconds,
      // and closing first would throw the form away if it failed.
      isLoading = true;
      update();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? currentUserName = prefs.getString(AppConstant.keyUserName);
      String? currentUserPhone = prefs.getString(AppConstant.keyUserPhone);

      if (currentUserName == null || currentUserPhone == null) return;

      String finalUserName = existingExpense != null ? existingExpense.userName : currentUserName;
      String finalUserPhone = existingExpense != null ? existingExpense.userPhone : currentUserPhone;

      final bool online = isOnline;

      // Receipts live in Supabase Storage; Firestore only ever holds the URL.
      //
      // Offline there is no uploading, and the entry must not wait for it: the
      // photo goes into the outbox, filed under the entry's id, and the entry
      // is saved without a URL for now. Same when the upload fails while the
      // device believes it is online — the picture is safe either way.
      final String? previousReceipt = existingExpense?.imageUrl;
      String? receiptUrl = previousReceipt;
      File? deferredReceipt;
      if (removeReceipt) {
        receiptUrl = null;
      } else if (pickedReceipt != null) {
        final String? uploaded =
            online ? await _tryUploadReceipt(pickedReceipt!) : null;
        if (uploaded != null) {
          receiptUrl = uploaded;
        } else {
          deferredReceipt = pickedReceipt;
        }
      }

      Map<String, dynamic> data = {
        'description': desc.isEmpty ? 'expense'.tr : desc,
        'amount': amount,
        'date': selectedDate.toIso8601String(),
        'time_hour': selectedTime.hour,
        'time_minute': selectedTime.minute,
        'user_name': finalUserName,
        'user_phone': finalUserPhone,
        'type': selectedType,
        'image_url': receiptUrl,
        'updatedAt': DateTime.now().toIso8601String(), // Or use FieldValue.serverTimestamp() in repository
      };

      // Both writes return as soon as they are on the device — offline they
      // sit in Firestore's queue and go out with the next connection.
      final String expenseId;
      if (existingExpense == null) {
        data['createdAt'] = DateTime.now().toIso8601String();
        expenseId = await repository.addExpense(data);
      } else {
        expenseId = existingExpense.id;
        await repository.updateExpense(expenseId, data);
      }

      if (deferredReceipt != null) {
        await _outbox.enqueue(
          expenseId: expenseId,
          file: deferredReceipt,
          replacesUrl: previousReceipt,
        );
      } else {
        // Uploaded now, or removed: nothing left waiting for this entry.
        await _outbox.remove(expenseId);

        // Only once Firestore points at the new object. Deleting first would
        // lose the receipt for good if the write then failed. Offline the old
        // object is left behind — best effort, as everywhere else.
        if (existingExpense != null && receiptUrl != previousReceipt && online) {
          await _storage.deleteByPublicUrl(previousReceipt);
        }
      }

      if (existingExpense != null && finalUserPhone != currentUserPhone) {
        await _logAdminEdit(
          adminName: currentUserName,
          adminPhone: currentUserPhone,
          targetName: finalUserName,
          targetPhone: finalUserPhone,
          description: 'Expense "${existingExpense.description}" edited: amount ${existingExpense.amount} -> $amount',
        );

        // Not worth holding the sheet for: sent now if there is a connection,
        // filed for the next one if not. The log above is queued like any
        // other write.
        unawaited(_pushOutbox.send(
          title: 'Admin Updated Your Expense',
          body: '$currentUserName has updated your expense "${existingExpense.description}".',
          targetPhones: [finalUserPhone],
        ));
      }

      // Saved — now the sheet can go.
      clearReceiptSelection();
      closeOverlayRoute();

      final String message;
      if (!online) {
        message = 'expense_saved_offline'.tr;
      } else if (deferredReceipt != null) {
        message = 'receipt_upload_deferred'.tr;
      } else {
        message = existingExpense == null ? 'expense_added'.tr : 'expense_updated'.tr;
      }
      CustomSnackbar.show(
          type: online && deferredReceipt == null
              ? SnackbarType.success
              : SnackbarType.info,
          message: message);

      // Not awaited, and in the background: the entry is already in the
      // local store, so the cache step shows it at once. The server read that
      // follows can take a while to give up offline, and neither the toast
      // nor the button should wait on it.
      unawaited(fetchExpenses(background: true));
      if (Get.isRegistered<MealController>()) {
        Get.find<MealController>().fetchMonthlyStats();
      }
    } catch (e) {
      debugPrint('Error saving expense: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_expense'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  /// The receipt's public URL, or null when the upload did not go through —
  /// the caller queues the file for later rather than failing the save.
  Future<String?> _tryUploadReceipt(File file) async {
    try {
      // Bounded: a link the OS calls "up" can still go nowhere, and the entry
      // must not wait on it — the outbox will get the picture there later.
      return await _storage
          .uploadFile(file, folder: SupabaseConfig.folderExpense)
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      debugPrint('Receipt upload failed, queued for later: $e');
      return null;
    }
  }

  /// Records an admin's change to someone else's entry. Queued offline like
  /// every other write; the future is not awaited for the server, since it
  /// would never resolve there.
  Future<void> _logAdminEdit({
    required String adminName,
    required String adminPhone,
    required String targetName,
    required String targetPhone,
    required String description,
  }) async {
    final Future<DocumentReference<Map<String, dynamic>>> write =
        FirebaseFirestore.instance.collection(AppConstant.collectionEditLogs).add({
      'adminName': adminName,
      'adminPhone': adminPhone,
      'targetUserName': targetName,
      'targetUserPhone': targetPhone,
      'type': 'expense',
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
    unawaited(write.then<void>(
      (_) {},
      onError: (Object e) => debugPrint('Edit log write failed: $e'),
    ));
  }

  Future<void> deleteExpense(ExpenseModel expense) async {
    try {
      isLoading = true;
      update();
      await repository.deleteExpense(expense.id);

      // The receipt goes with the entry — nothing points at it any more.
      // Whether it was uploaded or still waiting to be.
      await _outbox.remove(expense.id);
      if (expense.hasImage && isOnline) {
        await _storage.deleteByPublicUrl(expense.imageUrl);
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? currentUserPhone = prefs.getString(AppConstant.keyUserPhone);
      String? currentUserName = prefs.getString(AppConstant.keyUserName);

      if (currentUserPhone != null && currentUserName != null && expense.userPhone != currentUserPhone) {
        await _logAdminEdit(
          adminName: currentUserName,
          adminPhone: currentUserPhone,
          targetName: expense.userName,
          targetPhone: expense.userPhone,
          description: 'Expense "${expense.description}" of ৳${expense.amount} deleted',
        );

        unawaited(_pushOutbox.send(
          title: 'Admin Deleted Your Expense',
          body: '$currentUserName has deleted your expense "${expense.description}".',
          targetPhones: [expense.userPhone],
        ));
      }
      CustomSnackbar.show(
          type: isOnline ? SnackbarType.success : SnackbarType.info,
          message: isOnline ? 'expense_deleted'.tr : 'expense_deleted_offline'.tr);

      // See submitExpense — the local store already reflects the delete.
      unawaited(fetchExpenses(background: true));
      if (Get.isRegistered<MealController>()) {
        Get.find<MealController>().fetchMonthlyStats();
      }
    } catch (e) {
      debugPrint('Error deleting expense: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_expense'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }
}
