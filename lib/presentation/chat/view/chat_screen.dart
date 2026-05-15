import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/chat_controller.dart';
import '../model/chat_message_model.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'group_chat'.tr,
        showBackButton: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: GetBuilder<ChatController>(
              builder: (controller) {
                if (controller.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'no_messages_yet'.tr,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'start_conversation'.tr,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: controller.scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: controller.messages.length,
                  itemBuilder: (context, index) {
                    final message = controller.messages[index];
                    final isMe = message.senderPhone == controller.userPhone;
                    
                    bool isFirstInGroup = true;
                    bool isLastInGroup = true;
                    bool showDateHeader = false;

                    if (index < controller.messages.length - 1) {
                      final nextMessage = controller.messages[index + 1];
                      if (nextMessage.senderPhone == message.senderPhone) {
                        isFirstInGroup = false;
                      }
                      
                      final messageDate = DateFormat('yyyy-MM-dd').format(message.createdAt);
                      final nextMessageDate = DateFormat('yyyy-MM-dd').format(nextMessage.createdAt);
                      if (messageDate != nextMessageDate) {
                        showDateHeader = true;
                      }
                    } else {
                      showDateHeader = true;
                    }

                    if (index > 0) {
                      final nextMessage = controller.messages[index - 1];
                      if (nextMessage.senderPhone == message.senderPhone) {
                        isLastInGroup = false;
                      }
                    }

                    return _MessageBubble(
                      key: controller.getKeyForMessage(message.id),
                      message: message,
                      isMe: isMe,
                      isFirstInGroup: isFirstInGroup,
                      isLastInGroup: isLastInGroup,
                      showDateHeader: showDateHeader,
                      controller: controller,
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(context),
        ],
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GetBuilder<ChatController>(
              builder: (controller) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.isMentioning) _buildMentionSuggestionBox(context),
                    if (controller.replyingToMessage != null) _buildReplyPreview(context),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller.messageController,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 1,
                              maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: 'type_message'.tr,
                                  hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6)),
                                  border: InputBorder.none,
                                  filled: false,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: controller.sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
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

  Widget _buildReplyPreview(BuildContext context) {
    final message = controller.replyingToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'replying_to'.trParams({'name': message.senderName}),
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.primary, 
                    fontSize: 13
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7), fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: controller.cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildMentionSuggestionBox(BuildContext context) {
    if (controller.filteredMentionUsers.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: controller.filteredMentionUsers.length,
        itemBuilder: (context, index) {
          final user = controller.filteredMentionUsers[index];
          final name = user['name'] ?? 'unknown'.tr;
          
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            onTap: () => controller.insertMention(name),
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showDateHeader;
  final ChatController controller;
  final LayerLink _layerLink = LayerLink();

  _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.showDateHeader,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final showTime = controller.forceShowTimeMessageId == message.id;
    final isHighlighted = controller.highlightedMessageId == message.id;

    return Column(
      children: [
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getFormattedDate(message.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ),
            ),
          ),
        Dismissible(
          key: Key(message.id.isEmpty ? message.hashCode.toString() : message.id),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (direction) async {
            controller.setReply(message);
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            child: Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: EdgeInsets.only(
              bottom: isLastInGroup ? 8 : 2,
              top: isFirstInGroup ? 16 : 0,
            ),
            decoration: BoxDecoration(
              color: isHighlighted ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe && isLastInGroup)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.amber.shade100,
                      backgroundImage: message.senderImage != null
                          ? NetworkImage(message.senderImage!)
                          : null,
                      child: message.senderImage == null
                          ? Text(
                              message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    ),
                  )
                else if (!isMe)
                  const SizedBox(width: 32),

                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isMe ? 50 : 0,
                      right: !isMe ? 50 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CompositedTransformTarget(
                              link: _layerLink,
                              child: GestureDetector(
                                onLongPress: () {
                                  HapticFeedback.mediumImpact();
                                  _showReactionPicker(context, controller, message, _layerLink, isMe);
                                },
                                onTap: () => controller.toggleTimeDisplay(message.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isMe 
                                        ? Theme.of(context).colorScheme.primary 
                                        : (Theme.of(context).brightness == Brightness.dark 
                                            ? Theme.of(context).cardColor 
                                            : Colors.black.withOpacity(0.05)),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(!isMe ? (isFirstInGroup ? 20 : 4) : 20),
                                      topRight: Radius.circular(isMe ? (isFirstInGroup ? 20 : 4) : 20),
                                      bottomLeft: Radius.circular(!isMe ? (isLastInGroup ? 20 : 4) : 20),
                                      bottomRight: Radius.circular(isMe ? (isLastInGroup ? 20 : 4) : 20),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (message.replyToText != null)
                                        _buildReplyContent(context),
                                      RichText(
                                        text: TextSpan(
                                          children: _parseMentionText(message.text, context, isMe),
                                          style: TextStyle(
                                            fontSize: 15,
                                            height: 1.3,
                                            color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            if (message.reactions != null && message.reactions!.isNotEmpty)
                              Positioned(
                                bottom: -10,
                                right: 0,
                                child: _buildReactions(context, message, isMe),
                              ),
                          ],
                        ),
                        
                        if (message.reactions != null && message.reactions!.isNotEmpty)
                          const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showTime)
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isMe ? 0 : 48,
              right: isMe ? 8 : 0,
            ),
            child: Text(
              DateFormat('hh:mm a').format(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReplyContent(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (message.replyToMessageId != null) {
          controller.scrollToMessage(message.replyToMessageId!);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.2) : Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white : Theme.of(context).colorScheme.primary, 
              width: 3
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.replyToSenderName ?? 'unknown'.tr,
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 11, 
                color: isMe ? Colors.white : Theme.of(context).colorScheme.primary
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.replyToText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12, 
                color: isMe ? Colors.white.withOpacity(0.9) : Theme.of(context).textTheme.bodyMedium?.color
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext context, ChatController controller, ChatMessageModel message, LayerLink link, bool isMe) {
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => overlayEntry.remove(),
            child: Container(color: Colors.transparent),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            offset: Offset(isMe ? -150 : 0, -60), // Positioned above the bubble
            child: Material(
              color: Colors.transparent,
              child: _ReactionPickerWidget(
                onEmojiSelected: (emoji) {
                  controller.reactToMessage(message, emoji);
                  overlayEntry.remove();
                },
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  Widget _buildReactions(BuildContext context, ChatMessageModel message, bool isMe) {
    final Map<String, int> counts = {};
    message.reactions!.forEach((user, emoji) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: counts.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 12)),
                if (entry.value > 1) ...[
                  const SizedBox(width: 2),
                  Text(
                    entry.value.toString(), 
                    style: TextStyle(
                      fontSize: 10, 
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getFormattedDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return 'today'.tr;
    if (messageDate == yesterday) return 'yesterday'.tr;
    return DateFormat('MMM dd, yyyy').format(date);
  }

  List<TextSpan> _parseMentionText(String text, BuildContext context, bool isMe) {
    final RegExp mentionRegExp = RegExp(r'@\w+');
    final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
    
    if (matches.isEmpty) {
      return [TextSpan(text: text)];
    }

    List<TextSpan> spans = [];
    int currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
      }
      
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isMe ? Colors.white : Theme.of(context).colorScheme.primary,
        ),
      ));
      
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return spans;
  }
}

class _ReactionPickerWidget extends StatefulWidget {
  final Function(String) onEmojiSelected;

  const _ReactionPickerWidget({required this.onEmojiSelected});

  @override
  State<_ReactionPickerWidget> createState() => _ReactionPickerWidgetState();
}

class _ReactionPickerWidgetState extends State<_ReactionPickerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _emojis = ['❤️', '👍', '👎', '😂', '😮', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _emojis.map((emoji) => _buildEmojiItem(emoji)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiItem(String emoji) {
    return GestureDetector(
      onTap: () => widget.onEmojiSelected(emoji),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (_emojis.indexOf(emoji) * 50)),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
