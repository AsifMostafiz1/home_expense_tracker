import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../utils/app_ui.dart';
import '../../../utils/user_session.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_list_controller.dart';
import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../widgets/chat_presence.dart';
import '../widgets/group_avatar.dart';

/// Everything the house can talk in, on one screen.
///
/// The group sits at the top because it is the thread everybody shares and the
/// one most messages land in. Under it, one row per member — with a
/// conversation when there is one, and an invitation to start one when there
/// is not. There is no separate "new chat" picker: the person is the row.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChatListController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: 'messages'.tr,
            centerTitle: false,
            showBackButton: false,
            actions: [
              IconButton(
                tooltip: c.isSearching ? 'cancel'.tr : 'search'.tr,
                icon: Icon(
                  c.isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: AppUi.body(context),
                ),
                onPressed: c.toggleSearch,
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Column(
            children: [
              if (c.isSearching) _buildSearchField(context, c),
              Expanded(child: _buildBody(context, c)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchField(BuildContext context, ChatListController c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: Theme.of(context).cardColor,
      child: TextField(
        controller: c.searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'search_people'.tr,
          hintStyle: TextStyle(color: AppUi.muted(context), fontSize: 14),
          prefixIcon:
              Icon(Icons.search_rounded, size: 20, color: AppUi.muted(context)),
          filled: true,
          fillColor: AppUi.neutralSurface(context),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ChatListController c) {
    if (c.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final List<ChatListEntry> recent = c.recentChats;
    final List<ChatListEntry> others = c.otherMembers;
    final bool searching = c.query.trim().isNotEmpty;

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: c.refreshList,
      child: ListView(
        // Short lists — a house of three — still have to be draggable, or
        // there is nothing to pull.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // The group is the house's own thread — always there, never filtered
          // away by a search for a person's name. Except for a general user,
          // whose chat is direct messages alone: no card, and no group
          // controller ever built behind it.
          if (!searching) ...[
            if (!UserSession.isGeneral) ...[
              _GroupCard(members: c.houseMembers, onTap: c.openGroup),
              const SizedBox(height: 20),
            ],
            if (c.onlineMembers.isNotEmpty) ...[
              _SectionLabel(text: 'active_now'.tr),
              const SizedBox(height: 10),
              _OnlineStrip(
                members: c.onlineMembers,
                onTap: c.openDirect,
              ),
              const SizedBox(height: 20),
            ],
          ],
          if (recent.isNotEmpty) ...[
            _SectionLabel(
              text: 'direct_messages'.tr,
              trailing: c.directUnread > 0
                  ? 'unread_count'.trParams({'count': '${c.directUnread}'})
                  : null,
            ),
            const SizedBox(height: 8),
            _PeopleCard(
              children: recent
                  .map((entry) => _ChatRow(
                        entry: entry,
                        myPhone: c.myPhone,
                        onTap: () => c.openDirect(entry.user),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
          if (others.isNotEmpty) ...[
            _SectionLabel(
              text: recent.isEmpty && !searching
                  ? 'start_a_chat'.tr
                  : 'other_members'.tr,
            ),
            const SizedBox(height: 8),
            _PeopleCard(
              children: others
                  .map((entry) => _ChatRow(
                        entry: entry,
                        myPhone: c.myPhone,
                        onTap: () => c.openDirect(entry.user),
                      ))
                  .toList(),
            ),
          ],
          if (recent.isEmpty && others.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: _EmptyState(searching: searching),
            ),
        ],
      ),
    );
  }
}

/// The house group, pinned above everything else.
///
/// Drawn as one filled card rather than another row: it is not a person, it is
/// the place the whole house talks, and it should not have to be found among
/// the members.
class _GroupCard extends StatelessWidget {
  /// Everyone in the house — what the icon is made of until an admin uploads
  /// a picture for the group.
  final List<ChatUser> members;

  final VoidCallback onTap;

  const _GroupCard({required this.members, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return GetBuilder<ChatController>(
      // The untagged instance: the group thread the dashboard keeps alive for
      // its badge, which already holds the last message.
      builder: (chat) {
        final bool hasMessages = chat.messages.isNotEmpty;
        final String preview = hasMessages
            ? _previewOf(chat, chat.messages.first)
            : 'no_messages_yet'.tr;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primary, primary.withOpacity(0.72)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GroupAvatar(
                    imageUrl: chat.groupInfo.imageUrl,
                    members: members,
                    size: 52,
                    // The card is the accent colour, so the gaps between the
                    // faces are cut out of that rather than out of white, and
                    // a member with no picture shows white initials rather
                    // than accent-on-accent.
                    gapColor: primary,
                    tileBackground: Colors.white.withOpacity(0.26),
                    tileForeground: Colors.white,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.groupInfo.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (hasMessages)
                              Text(
                                chatTimeLabel(chat.messages.first.createdAt),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            if (chat.unseenCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(minWidth: 20),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  chat.unseenCount > 99
                                      ? '99+'
                                      : '${chat.unseenCount}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// `Rahim: got the rice` — who said it, then what, the way the row for a
  /// direct chat reads.
  String _previewOf(ChatController chat, ChatMessageModel message) {
    final String who = message.senderPhone == chat.userPhone
        ? 'you'.tr
        : message.senderName.split(' ').first;
    return '$who: ${message.preview}';
  }
}

/// Whoever is around right now, as a strip of faces. A shortcut, not a
/// separate list — every one of them also has a row further down.
class _OnlineStrip extends StatelessWidget {
  final List<ChatUser> members;
  final void Function(ChatUser) onTap;

  const _OnlineStrip({required this.members, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: members.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final ChatUser user = members[index];
          return GestureDetector(
            onTap: () => onTap(user),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PresenceAvatar(
                    user: user,
                    size: 54,
                    ringColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user.name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppUi.body(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One person, and whatever was last said to them.
class _ChatRow extends StatelessWidget {
  final ChatListEntry entry;
  final String myPhone;
  final VoidCallback onTap;

  const _ChatRow({
    required this.entry,
    required this.myPhone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final DirectThread? thread = entry.thread;
    final int unread = entry.unreadFor(myPhone);
    final bool hasUnread = unread > 0;
    final Color primary = Theme.of(context).colorScheme.primary;

    final String? lastActive = lastActiveLabel(entry.user);

    // Nothing said yet — or nothing left after this member deleted the
    // thread for themselves — reads as an invitation rather than an empty
    // line.
    final bool hasHistory = entry.hasHistory;
    final String preview = hasHistory && thread!.preview.isNotEmpty
        ? (thread.lastSenderPhone == myPhone
            ? '${'you'.tr}: ${thread.preview}'
            : thread.preview)
        : 'tap_to_start_chat'.tr;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            PresenceAvatar(
              user: entry.user,
              size: 50,
              ringColor: Theme.of(context).cardColor,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                      color: AppUi.body(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                      fontStyle:
                          hasHistory ? FontStyle.normal : FontStyle.italic,
                      color: hasUnread
                          ? AppUi.body(context)
                          : AppUi.muted(context),
                    ),
                  ),
                  // Only when there is a figure to give — see
                  // [lastActiveLabel]. That somebody is around is already on
                  // the row twice over, in the dot on their picture and their
                  // face in the strip at the top of this screen; and a flat
                  // "Offline" under a member nobody has heard from is a line
                  // spent saying nothing. What is worth a line is how long it
                  // has been.
                  if (lastActive != null) ...[
                    const SizedBox(height: 3),
                    PresenceLine(
                      label: lastActive,
                      online: false,
                      fontSize: 11,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // A deleted thread has no last message to date.
                  hasHistory ? chatTimeLabel(entry.lastAt) : '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                    color: hasUnread ? primary : AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 6),
                UnreadBadge(count: unread),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The surface the rows sit on — one card per section, hairlines between.
class _PeopleCard extends StatelessWidget {
  final List<Widget> children;

  const _PeopleCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 77),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: AppUi.hairline(context).withOpacity(0.5),
                ),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? trailing;

  const _SectionLabel({required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: AppUi.muted(context),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;

  const _EmptyState({required this.searching});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          searching ? Icons.search_off_rounded : Icons.people_outline_rounded,
          size: 56,
          color: AppUi.muted(context).withOpacity(0.5),
        ),
        const SizedBox(height: 14),
        Text(
          searching ? 'no_one_matches'.tr : 'no_other_members'.tr,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppUi.muted(context),
          ),
        ),
      ],
    );
  }
}
