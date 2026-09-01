import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/chat_media_page.dart';
import '../model/chat_message_model.dart';
import '../repository/chat_repository.dart';
import 'chat_controller.dart';

/// Every picture one conversation has ever carried, newest first.
///
/// Built on top of the thread's own controller rather than beside it: the
/// live window it already holds is where a photo sent a second ago comes
/// from, and the pages read below are only for everything older. Anything
/// arriving — or being deleted — while the gallery is open lands in the grid
/// without a reload.
///
/// One of these per conversation, put up with the gallery screen and taken
/// down with it. Nothing here outlives the screen: the thread's controller
/// is the long-lived one.
class ChatMediaController extends GetxController {
  final ChatRepository repository;

  /// The conversation this gallery belongs to.
  final ChatController chat;

  ChatMediaController({required this.repository, required this.chat});

  /// How many pictures one "load more" aims to add. Roughly three screens of
  /// a three-column grid, so scrolling rarely catches up with loading.
  static const int _pageSize = 30;

  /// How many barren pages one load will walk through before handing the
  /// scroll back. A thread can hold a long stretch of pure conversation
  /// between two photos, and stopping at the first empty page would make the
  /// grid look finished when it is not.
  static const int _emptyPagesPerLoad = 3;

  String? get conversationId => chat.conversationId;

  bool get isGroupChat => chat.isGroupChat;

  /// What the gallery is titled after — the group's name, or the person.
  String get title => chat.title;

  final Map<String, ChatMessageModel> _byId = <String, ChatMessageModel>{};

  /// Everything found so far, newest first, whoever sent it.
  List<ChatMessageModel> all = const <ChatMessageModel>[];

  /// What the grid is drawing — [all], less anyone filtered out.
  List<ChatMessageModel> items = const <ChatMessageModel>[];

  /// [items] cut into months, in the order they are shown.
  List<ChatMediaSection> sections = const <ChatMediaSection>[];

  /// Who has posted pictures here, most prolific first. Empty in a direct
  /// chat, where filtering by one of two people is not worth a row of chips.
  List<ChatMediaSender> senders = const <ChatMediaSender>[];

  /// Whose pictures the grid is limited to. Null is everybody.
  String? senderFilter;

  /// The first page is still coming — the grid shows its skeleton.
  bool isLoading = true;

  bool isLoadingMore = false;

  /// Whether there is history left behind [_cursor]. Not the same as having
  /// found pictures in it.
  bool hasMore = true;

  /// The last read failed. The grid keeps whatever it already had and offers
  /// to try again.
  bool loadFailed = false;

  /// Where the next page starts: when the oldest message read so far was
  /// sent.
  DateTime? _cursor;

  int get totalCount => all.length;

  bool get isEmpty => items.isEmpty;

  /// True when the filter — not the conversation — is what emptied the grid.
  bool get isFilteredEmpty => items.isEmpty && all.isNotEmpty;

  @override
  void onInit() {
    super.onInit();
    // The thread's live window first: whatever is on screen behind this is
    // in the grid before the first read even goes out.
    _absorb(chat.messages);
    _rebuild();
    chat.addListener(_onThreadChanged);
    loadMore();
  }

  @override
  void onClose() {
    chat.removeListener(_onThreadChanged);
    super.onClose();
  }

  /// A picture sent, or deleted, while the gallery is open.
  void _onThreadChanged() {
    if (_absorb(chat.messages)) {
      _rebuild();
      update();
    }
  }

  /// Files whatever in [incoming] carries a picture, and drops anything that
  /// no longer does — a deleted message keeps its id and loses its image.
  ///
  /// Returns whether any of it changed what the grid should show.
  bool _absorb(Iterable<ChatMessageModel> incoming) {
    bool changed = false;

    for (final ChatMessageModel message in incoming) {
      // The reader's own line under the thread counts here as much as a
      // deletion does — see `ChatController.isVisibleToMe`. Checked on the
      // way in as well as in [_rebuild], so a page walked back through a
      // cleared conversation does not report finding pictures it will then
      // hide.
      if (message.hasImage && !message.deleted && chat.isVisibleToMe(message)) {
        final ChatMessageModel? held = _byId[message.id];
        // The caption and the picture are the only parts of a message this
        // screen draws, so nothing else is worth a rebuild for.
        if (held == null ||
            held.imageUrl != message.imageUrl ||
            held.text != message.text) {
          _byId[message.id] = message;
          changed = true;
        }
      } else if (_byId.remove(message.id) != null) {
        changed = true;
      }
    }

    return changed;
  }

  /// Sorts what has been found, applies the filter, and cuts the result into
  /// months. Called once per change rather than per frame — the grid asks for
  /// [sections] on every build.
  void _rebuild() {
    // The reader's own line under the thread applies here too: a picture from
    // a conversation they have deleted for themselves is not theirs to look
    // at, however deep in the history it was read back from.
    final List<ChatMessageModel> sorted =
        _byId.values.where(chat.isVisibleToMe).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    all = sorted;

    _rebuildSenders();

    final String? filter = senderFilter;
    items = filter == null
        ? sorted
        : sorted.where((m) => m.senderPhone == filter).toList();

    sections = _cutIntoMonths(items);
  }

  void _rebuildSenders() {
    if (!isGroupChat) {
      senders = const <ChatMediaSender>[];
      return;
    }

    final Map<String, ChatMediaSender> byPhone = <String, ChatMediaSender>{};
    for (final ChatMessageModel message in all) {
      final ChatMediaSender? held = byPhone[message.senderPhone];
      byPhone[message.senderPhone] = ChatMediaSender(
        phone: message.senderPhone,
        name: message.senderName,
        // The newest picture carries the newest profile photo, and [all] is
        // walked newest first — so the first one seen is the one to keep.
        image: held?.image ?? message.senderImage,
        count: (held?.count ?? 0) + 1,
      );
    }

    final List<ChatMediaSender> list = byPhone.values.toList()
      ..sort((a, b) {
        final int byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });

    // One person's pictures in a group of one contributor: a chip that
    // filters to everything is not a filter.
    senders = list.length > 1 ? list : const <ChatMediaSender>[];

    // Whoever was being filtered on has stopped being a sender here — their
    // last picture was deleted. Fall back to everybody rather than showing an
    // empty grid with no chip to explain it.
    if (senderFilter != null && !byPhone.containsKey(senderFilter)) {
      senderFilter = null;
    }
  }

  static List<ChatMediaSection> _cutIntoMonths(List<ChatMessageModel> items) {
    final List<ChatMediaSection> sections = <ChatMediaSection>[];

    for (int i = 0; i < items.length; i++) {
      final DateTime sentAt = items[i].createdAt;
      final DateTime month = DateTime(sentAt.year, sentAt.month);

      if (sections.isEmpty || sections.last.month != month) {
        sections.add(ChatMediaSection(
          month: month,
          startIndex: i,
          items: <ChatMessageModel>[items[i]],
        ));
      } else {
        sections.last.items.add(items[i]);
      }
    }

    return sections;
  }

  void filterBySender(String? phone) {
    if (senderFilter == phone) return;
    senderFilter = phone;
    _rebuild();
    update();
  }

  /// Reads the next stretch of history. Safe to call from a scroll listener:
  /// a call while one is already running, or once the thread has been read to
  /// its beginning, does nothing.
  Future<void> loadMore() async {
    if (isLoadingMore || (!hasMore && !isLoading)) return;

    isLoadingMore = true;
    loadFailed = false;
    update();

    try {
      // Keep walking while the pages come back empty — a run of text-only
      // messages is not the end of the pictures.
      for (int page = 0; page < _emptyPagesPerLoad; page++) {
        final ChatMediaPage read = await repository.fetchMediaPage(
          conversationId: conversationId,
          before: _cursor,
          want: _pageSize,
        );

        _cursor = read.cursor ?? _cursor;
        hasMore = !read.reachedEnd;

        final bool found = _absorb(read.items);
        if (found) _rebuild();
        if (found || !hasMore) break;
      }
    } catch (e) {
      debugPrint('Chat media: could not read the gallery — $e');
      loadFailed = true;
    } finally {
      isLoading = false;
      isLoadingMore = false;
      update();
    }
  }

  /// Throws away everything read so far and starts again — what a pull down
  /// the grid does. Not called `refresh`: GetX puts one of those on every
  /// controller, and quietly taking it over would break anything of its own
  /// that leans on it.
  Future<void> reload() async {
    _byId.clear();
    _cursor = null;
    hasMore = true;
    loadFailed = false;
    isLoading = true;
    _absorb(chat.messages);
    _rebuild();
    update();
    await loadMore();
  }

  /// Where a picture sits in the grid's flat order — the page the viewer
  /// opens on.
  int indexOf(ChatMessageModel message) =>
      items.indexWhere((m) => m.id == message.id);
}

/// One month's worth of pictures, as the grid lays them out.
class ChatMediaSection {
  final DateTime month;

  /// Where this month's first picture sits in the flat list the viewer pages
  /// through, so a tap on any tile knows its own index.
  final int startIndex;

  final List<ChatMessageModel> items;

  ChatMediaSection({
    required this.month,
    required this.startIndex,
    required this.items,
  });

  /// `This month`, `Last month`, or the month by name — the way somebody
  /// would say it out loud.
  String get label {
    final DateTime now = DateTime.now();
    final DateTime thisMonth = DateTime(now.year, now.month);
    if (month == thisMonth) return 'this_month'.tr;
    final DateTime lastMonth = DateTime(now.year, now.month - 1);
    if (month == lastMonth) return 'last_month'.tr;
    return AppUi.monthLabel(month);
  }
}

/// Somebody who has posted pictures in a conversation, and how many.
class ChatMediaSender {
  final String phone;
  final String name;
  final String? image;
  final int count;

  const ChatMediaSender({
    required this.phone,
    required this.name,
    this.image,
    required this.count,
  });
}
