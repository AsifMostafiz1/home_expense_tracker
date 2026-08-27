import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_media_controller.dart';
import '../model/chat_message_model.dart';
import '../widgets/chat_media_skeleton.dart';
import 'chat_media_viewer.dart';

/// Opens a conversation's gallery. [tag] is the chat's controller tag — null
/// for the house group, the conversation id for a direct thread.
void openChatMedia({String? tag}) =>
    Get.to(() => ChatMediaScreen(tag: tag), preventDuplicates: false);

/// Every picture a conversation has carried, in one place.
///
/// The thread is where photos are talked about; this is where they are
/// looked at. Newest first, cut into months, three to a row — and a tap opens
/// the same picture full screen with every other one a swipe away.
class ChatMediaScreen extends StatefulWidget {
  /// Which conversation's pictures. See [openChatMedia].
  final String? tag;

  const ChatMediaScreen({super.key, this.tag});

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  late final ChatController _chat = Get.find<ChatController>(tag: widget.tag);
  late final ChatMediaController _media;

  final ScrollController _scroll = ScrollController();

  /// Ask for the next page before the last row is reached, so the grid is
  /// still filling itself while there is something to look at.
  static const double _loadAhead = 700;

  @override
  void initState() {
    super.initState();
    _media = Get.put(
      ChatMediaController(
        // The thread's own repository rather than a fresh lookup: this
        // screen is only ever reached from a conversation that already has
        // one, and there is nothing to be gained by finding it twice.
        repository: _chat.repository,
        chat: _chat,
      ),
      tag: widget.tag,
    );
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    // The gallery's controller belongs to the gallery. `force` because a
    // controller with a listener on the thread is otherwise kept alive by it.
    Get.delete<ChatMediaController>(tag: widget.tag, force: true);
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - _loadAhead) {
      _media.loadMore();
    }
  }

  /// Keeps reading while what has been found does not fill the screen.
  ///
  /// A page of history is a stretch of messages, not a number of pictures, so
  /// the first one can come back with three photos in it — and a grid that
  /// does not scroll never asks for a second page. Filtering to one person
  /// puts a gallery in the same position.
  void _fillViewport() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent <= 0) _media.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChatMediaController>(
      tag: widget.tag,
      builder: (c) {
        if (c.hasMore && !c.isLoadingMore) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _fillViewport());
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: _buildAppBar(context, c),
          body: _buildBody(context, c),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ChatMediaController c) {
    return CustomAppBar(
      centerTitle: false,
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'media'.tr,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
              color: AppUi.body(context),
            ),
          ),
          const SizedBox(height: 2),
          // The conversation this belongs to, and how much of it is here.
          // Both matter: a gallery with no header could be anybody's.
          Text(
            c.isLoading && c.items.isEmpty
                ? c.title
                : '${c.title} · ${'photos_count'.trParams({'count': '${c.items.length}'})}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ChatMediaController c) {
    if (c.isLoading && c.items.isEmpty) return const ChatMediaSkeleton();

    if (c.items.isEmpty) return _buildEmpty(context, c);

    return RefreshIndicator(
      onRefresh: c.reload,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (c.senders.isNotEmpty)
            SliverToBoxAdapter(child: _buildSenderFilter(context, c)),
          for (final ChatMediaSection section in c.sections) ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _MonthHeaderDelegate(
                label: section.label,
                count: section.items.length,
              ),
            ),
            _buildGrid(context, c, section),
          ],
          SliverToBoxAdapter(child: _buildFooter(context, c)),
        ],
      ),
    );
  }

  /// Three to a row, with room to breathe between them. Wide enough on a
  /// phone that a face is recognisable without opening anything.
  Widget _buildGrid(
    BuildContext context,
    ChatMediaController c,
    ChatMediaSection section,
  ) {
    final int cacheWidth = _thumbCacheWidth(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final ChatMessageModel message = section.items[i];
            return _MediaTile(
              // Keyed by the message so a photo arriving at the top of the
              // grid slides the rest along rather than shuffling which tile
              // is which.
              key: ValueKey<String>(message.id),
              message: message,
              cacheWidth: cacheWidth,
              onTap: () => _open(context, c, section.startIndex + i),
              onLongPress: () => _showTileSheet(context, c, message),
            );
          },
          childCount: section.items.length,
        ),
      ),
    );
  }

  /// The strip of chips above the grid: whose pictures to show. Group chats
  /// only, and only once more than one person has posted one.
  Widget _buildSenderFilter(BuildContext context, ChatMediaController c) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        itemCount: c.senders.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _FilterChip(
              label: 'all'.tr,
              count: c.totalCount,
              selected: c.senderFilter == null,
              onTap: () => c.filterBySender(null),
            );
          }

          final ChatMediaSender sender = c.senders[i - 1];
          return _FilterChip(
            label: _firstName(sender.name),
            count: sender.count,
            selected: c.senderFilter == sender.phone,
            onTap: () => c.filterBySender(sender.phone),
            avatar: ProfileAvatar(
              name: sender.name,
              phone: sender.phone,
              imageUrl: sender.image,
              size: 22,
              background: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              foreground: Theme.of(context).colorScheme.primary,
              fontSize: 9,
            ),
          );
        },
      ),
    );
  }

  /// What sits under the last row: the next page arriving, a read that
  /// failed, or nothing at all once the whole conversation has been walked.
  Widget _buildFooter(BuildContext context, ChatMediaController c) {
    if (c.loadFailed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        child: Column(
          children: [
            Text(
              'failed_load_media'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppUi.muted(context)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: c.loadMore,
              child: Text('retry'.tr),
            ),
          ],
        ),
      );
    }

    if (c.isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: 40);
  }

  Widget _buildEmpty(BuildContext context, ChatMediaController c) {
    // Two different nothings: a conversation with no pictures in it, and a
    // filter that has hidden the ones there are.
    final bool filtered = c.isFilteredEmpty;
    final String name = filtered
        ? c.senders
            .firstWhere(
              (s) => s.phone == c.senderFilter,
              orElse: () => const ChatMediaSender(
                  phone: '', name: '', count: 0),
            )
            .name
        : '';

    return ListView(
      // A list rather than a column so the grid's pull-to-refresh gesture
      // still exists on an empty gallery.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (c.senders.isNotEmpty) _buildSenderFilter(context, c),
        SizedBox(height: MediaQuery.of(context).size.height * 0.16),
        Icon(
          filtered ? Icons.filter_alt_off_rounded : Icons.photo_library_outlined,
          size: 58,
          color: AppUi.muted(context).withOpacity(0.5),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            children: [
              Text(
                filtered
                    ? 'no_media_from_person'
                        .trParams({'name': _firstName(name)})
                    : 'no_media_yet'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                filtered ? 'no_media_from_person_hint'.tr : 'no_media_yet_hint'.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppUi.muted(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, ChatMediaController c, int index) {
    if (c.items.isEmpty) return;

    Get.to(
      () => ChatMediaViewer(
        items: c.items,
        initialIndex: index < 0 ? 0 : index,
        thumbCacheWidth: _thumbCacheWidth(context),
        onJumpToMessage: (ChatMessageModel message) =>
            _jumpToMessage(message, popViewer: true),
      ),
      // Black on black: the picture is already on screen and flying into
      // place, so a slide underneath it only reads as a stutter.
      opaque: false,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 220),
      preventDuplicates: false,
    );
  }

  /// What a long press offers: who sent this and when, and a way back to the
  /// moment it was sent.
  void _showTileSheet(
    BuildContext context,
    ChatMediaController c,
    ChatMessageModel message,
  ) {
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.muted(context).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        message.imageUrl!,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        cacheWidth: _thumbCacheWidth(context),
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            message.senderName.trim().isEmpty
                                ? 'unknown'.tr
                                : message.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppUi.body(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a')
                                .format(message.createdAt),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppUi.muted(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppUi.hairline(context)),
              _sheetAction(
                context,
                icon: Icons.photo_size_select_actual_outlined,
                label: 'view_photo'.tr,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _open(context, c, c.indexOf(message));
                },
              ),
              _sheetAction(
                context,
                icon: Icons.forum_outlined,
                label: 'jump_to_message'.tr,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _jumpToMessage(message, popViewer: false);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 21, color: AppUi.body(context)),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: AppUi.body(context),
        ),
      ),
    );
  }

  /// Back to the conversation, landing on the message the picture came in.
  ///
  /// The gallery reaches further back than the thread keeps loaded, so a
  /// photo from months ago may have no bubble to scroll to — that says so
  /// rather than swallowing the tap, the same way a pinned message does.
  void _jumpToMessage(ChatMessageModel message, {required bool popViewer}) {
    if (popViewer) Get.back();
    Get.back();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chat.scrollToMessage(message.id)) {
        CustomSnackbar.show(
          type: SnackbarType.info,
          message: 'message_not_loaded'.tr,
        );
      }
    });
  }

  /// How wide a thumbnail is decoded at — the tile's own width in real
  /// pixels, so a 3MB photo is not held in memory nine times over at full
  /// size. The same number is handed to the viewer, which lets one decode
  /// serve the grid, the filmstrip and the moment before a full picture
  /// arrives.
  static int _thumbCacheWidth(BuildContext context) {
    final MediaQueryData query = MediaQuery.of(context);
    final double tile = (query.size.width - 24 - 12) / 3;
    return (tile * query.devicePixelRatio).round();
  }

  static String _firstName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return 'unknown'.tr;
    return trimmed.split(' ').first;
  }
}

/// A month's name, held at the top of the grid while its own pictures scroll
/// under it and pushed off by the next one — so wherever the scroll stops,
/// what is on screen is dated.
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final int count;

  const _MonthHeaderDelegate({required this.label, required this.count});

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      // Opaque: a pinned header has the grid running underneath it.
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      alignment: Alignment.bottomLeft,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
              color: AppUi.body(context),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_MonthHeaderDelegate old) =>
      old.label != label || old.count != count;
}

/// One picture in the grid.
///
/// Presses in slightly under a finger before it opens, which is the whole
/// difference between a grid of images and something that feels like it was
/// built to be touched.
class _MediaTile extends StatefulWidget {
  final ChatMessageModel message;
  final int cacheWidth;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MediaTile({
    super.key,
    required this.message,
    required this.cacheWidth,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.955 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Something to look at while the bytes come down, in the same
              // shape as the picture that replaces it.
              Container(color: AppUi.neutralSurface(context)),
              Hero(
                tag: chatMediaHeroTag(widget.message.id),
                child: Image.network(
                  widget.message.imageUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: widget.cacheWidth,
                  filterQuality: FilterQuality.medium,
                  frameBuilder: (context, child, frame, wasSynchronous) {
                    if (wasSynchronous) return child;
                    // Fades in as it decodes rather than snapping — nine of
                    // these arriving at once otherwise reads as a flicker.
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 22,
                      color: AppUi.muted(context),
                    ),
                  ),
                ),
              ),
              // A hairline over the picture, so a photo with pale edges still
              // reads as a tile on a pale background.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.06),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A chip in the filter strip.
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? avatar;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(avatar == null ? 14 : 5, 5, 12, 5),
        decoration: BoxDecoration(
          color: selected ? AppUi.tint(context, primary) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary.withOpacity(0.55) : AppUi.hairline(context),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              avatar!,
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? primary : AppUi.body(context),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? primary.withOpacity(0.8) : AppUi.muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
