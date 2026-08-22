import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_constant.dart';
import '../model/chat_thread_model.dart';
import '../repository/chat_repository.dart';
import '../view/chat_screen.dart';
import 'chat_controller.dart';

/// One row of the chat list: a member of the house, and the conversation with
/// them when there is one.
///
/// Every member gets a row whether or not anything has been said yet — the
/// list is a list of people first and a list of conversations second, so
/// starting a new chat is a tap rather than a hunt through a separate picker.
class ChatListEntry {
  final ChatUser user;
  final DirectThread? thread;

  const ChatListEntry({required this.user, this.thread});

  bool get hasHistory => thread?.hasMessage ?? false;

  DateTime? get lastAt => thread?.lastAt;

  int unreadFor(String phone) => thread?.unreadFor(phone) ?? 0;
}

/// The screen that sits on the chat tab: the house group, then everyone in it.
class ChatListController extends GetxController implements GetxService {
  final ChatRepository repository;

  ChatListController({required this.repository});

  String myPhone = '';
  String myName = '';

  bool isLoading = true;

  List<ChatUser> _members = [];
  Map<String, DirectThread> _threads = {};

  /// What the search field holds. Matched against name and phone.
  String query = '';
  final TextEditingController searchController = TextEditingController();
  bool isSearching = false;

  StreamSubscription? _membersSubscription;
  StreamSubscription? _threadsSubscription;

  /// Presence is a timestamp that ages: nobody writes "went offline", the
  /// last heartbeat simply falls out of the window. Without a tick the dots
  /// would stay green until something else happened to redraw the list.
  Timer? _presenceTicker;

  @override
  void onInit() {
    super.onInit();
    _start();
    searchController.addListener(() {
      if (searchController.text == query) return;
      query = searchController.text;
      update();
    });
    _presenceTicker =
        Timer.periodic(const Duration(minutes: 1), (_) => update());
  }

  @override
  void onClose() {
    _membersSubscription?.cancel();
    _threadsSubscription?.cancel();
    _presenceTicker?.cancel();
    searchController.dispose();
    super.onClose();
  }

  Future<void> _start() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    myPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    myName = prefs.getString(AppConstant.keyUserName) ?? '';

    _membersSubscription = repository.getChatUsersStream().listen(
      (users) {
        _members = users;
        isLoading = false;
        update();
      },
      onError: (Object e) {
        debugPrint('ChatList: members stream failed — $e');
        isLoading = false;
        update();
      },
    );

    _threadsSubscription = repository.getDirectThreadsStream(myPhone).listen(
      (threads) {
        _threads = {for (final DirectThread t in threads) t.id: t};
        update();
      },
      onError: (Object e) => debugPrint('ChatList: threads stream failed — $e'),
    );
  }

  /// Every member but the one holding the phone, each carrying whatever
  /// conversation already exists with them.
  List<ChatListEntry> get _allEntries {
    return _members
        .where((user) => user.phone.isNotEmpty && user.phone != myPhone)
        .map((user) => ChatListEntry(
              user: user,
              thread: _threads[
                  ChatThread.conversationIdFor(myPhone, user.phone)],
            ))
        .toList();
  }

  List<ChatListEntry> _matching(List<ChatListEntry> entries) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return entries;
    return entries
        .where((e) =>
            e.user.name.toLowerCase().contains(needle) ||
            e.user.phone.contains(needle))
        .toList();
  }

  /// Conversations that have been had, newest first.
  List<ChatListEntry> get recentChats {
    final List<ChatListEntry> list =
        _matching(_allEntries.where((e) => e.hasHistory).toList());
    list.sort((a, b) {
      // A message queued offline has no server timestamp yet; it belongs at
      // the top, where the person who just sent it is looking.
      final DateTime aAt = a.lastAt ?? DateTime.now();
      final DateTime bAt = b.lastAt ?? DateTime.now();
      return bAt.compareTo(aAt);
    });
    return list;
  }

  /// Everyone there is nothing to show yet — the "start a chat" half of the
  /// list. Online members first, so whoever is around is easiest to reach.
  List<ChatListEntry> get otherMembers {
    final List<ChatListEntry> list =
        _matching(_allEntries.where((e) => !e.hasHistory).toList());
    list.sort((a, b) {
      if (a.user.isOnline != b.user.isOnline) return a.user.isOnline ? -1 : 1;
      return a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase());
    });
    return list;
  }

  /// Who is around right now — the strip along the top of the list.
  List<ChatUser> get onlineMembers => _members
      .where((u) => u.phone != myPhone && u.isOnline)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  int get memberCount => _members.length;

  /// Everyone in the house, the viewer included — what the group icon is made
  /// of when no picture has been set. Unsorted: `GroupAvatar` decides the
  /// order it draws them in.
  List<ChatUser> get houseMembers => List<ChatUser>.unmodifiable(_members);

  /// One member, by phone — how a chat header looks up the presence of the
  /// person it is showing.
  ChatUser? userByPhone(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    return _members.firstWhereOrNull((u) => u.phone == phone);
  }

  /// Unread across every direct thread.
  int get directUnread => _threads.values
      .fold<int>(0, (sum, thread) => sum + thread.unreadFor(myPhone));

  /// What the group chat has waiting. Held in memory by the group controller
  /// rather than in Firestore — see `ChatController.unseenCount`.
  int get groupUnread => Get.isRegistered<ChatController>()
      ? Get.find<ChatController>().unseenCount
      : 0;

  /// The number on the chat tab: both halves of the section together.
  int get totalUnread => groupUnread + directUnread;

  bool get hasAnything => recentChats.isNotEmpty || otherMembers.isNotEmpty;

  void toggleSearch() {
    isSearching = !isSearching;
    if (!isSearching) {
      searchController.clear();
      query = '';
    }
    update();
  }

  /// Opens the house group — the one thread the dashboard already holds a
  /// controller for, so nothing is created here.
  void openGroup() => Get.to(() => const ChatScreen());

  /// Opens the direct thread with [user], building its controller first.
  ///
  /// One controller per conversation, tagged with the thread id: two of them
  /// on the same Firestore path would both write read receipts and both
  /// listen. The screen takes it down again when it closes.
  void openDirect(ChatUser user) {
    if (myPhone.isEmpty || user.phone == myPhone) return;

    final ChatThread thread = ChatThread.direct(
      peerPhone: user.phone,
      peerName: user.name,
      peerImage: user.image,
      myPhone: myPhone,
    );
    final String tag = thread.controllerTag!;

    if (!Get.isRegistered<ChatController>(tag: tag)) {
      Get.put(
        ChatController(repository: repository, thread: thread),
        tag: tag,
      );
    }

    Get.to(() => ChatScreen(tag: tag));
  }
}
