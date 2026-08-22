import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../model/chat_message_model.dart';

/// What the conversation shows while somebody is searching it.
///
/// The thread itself is put away rather than filtered in place: a hit from
/// three months ago means nothing next to the bubbles around it, and a list of
/// hits reads as an index — who said it, when, and the words themselves.
/// Tapping a row puts the thread back with that message flashing.
class ChatSearchResults extends StatelessWidget {
  final ChatController controller;

  const ChatSearchResults({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final String query = controller.searchQuery.trim();

    if (query.isEmpty) {
      return _Placeholder(
        icon: Icons.search_rounded,
        text: 'search_messages_hint'.tr,
      );
    }

    final List<ChatMessageModel> results = controller.searchResults;

    // The history arrives a moment after the field opens. Saying so beats an
    // empty list that turns out to have been wrong.
    if (results.isEmpty && controller.isSearchLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    if (results.isEmpty) {
      return _Placeholder(
        icon: Icons.search_off_rounded,
        text: 'no_messages_found'.tr,
      );
    }

    return Column(
      children: [
        // The count is in the search bar, where it is read while typing.
        // This strip only exists while there is still history on its way in,
        // so a thin list does not look like the whole answer.
        if (controller.isSearchLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'searching_older_messages'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: results.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              thickness: 1,
              indent: 64,
              color: AppUi.hairline(context).withOpacity(0.5),
            ),
            itemBuilder: (context, index) => _ResultRow(
              message: results[index],
              query: query,
              isMe: results[index].senderPhone == controller.userPhone,
              onTap: () => controller.openSearchResult(results[index].id),
            ),
          ),
        ),
      ],
    );
  }
}

/// One hit: who wrote it, when, and the line it was found in.
class _ResultRow extends StatelessWidget {
  final ChatMessageModel message;
  final String query;
  final bool isMe;
  final VoidCallback onTap;

  const _ResultRow({
    required this.message,
    required this.query,
    required this.isMe,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(
              name: message.senderName,
              phone: message.senderPhone,
              imageUrl: message.senderImage,
              size: 40,
              background: primary.withOpacity(0.15),
              foreground: primary,
              fontSize: 15,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isMe ? 'you'.tr : message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppUi.body(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _stamp(message.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppUi.muted(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppUi.muted(context),
                      ),
                      children: _highlighted(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The matched run of characters, picked out of the line it sits in, so the
  /// eye lands on the word that was typed rather than reading the whole row.
  ///
  /// A hit on the sender's name has nothing to mark in the text; that row
  /// simply reads plainly.
  List<TextSpan> _highlighted(BuildContext context) {
    final String text = message.preview;
    final String needle = query.toLowerCase();
    final String haystack = text.toLowerCase();

    final List<TextSpan> spans = [];
    final TextStyle hit = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.bold,
    );

    int start = 0;
    while (true) {
      final int at = haystack.indexOf(needle, start);
      if (at < 0 || needle.isEmpty) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (at > start) spans.add(TextSpan(text: text.substring(start, at)));
      spans.add(TextSpan(
        text: text.substring(at, at + needle.length),
        style: hit,
      ));
      start = at + needle.length;
    }
    return spans;
  }

  /// The clock for today, the date for anything older — a result list spans
  /// months, so the day matters more than the minute.
  String _stamp(DateTime at) {
    final DateTime now = DateTime.now();
    final bool today =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (today) return DateFormat('hh:mm a').format(at);
    if (at.year == now.year) return DateFormat('dd MMM').format(at);
    return DateFormat('dd MMM yyyy').format(at);
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Placeholder({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.08),
              ),
              child: Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppUi.muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
