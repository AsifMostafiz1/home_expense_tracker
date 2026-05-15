import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/chat_controller.dart';
import '../model/chat_message_model.dart';

class ChatScreen extends GetView<ChatController> {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const CustomAppBar(
        title: 'Group Chat',
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
                          'No messages yet',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start the conversation!',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: controller.scrollController,
                  reverse: true, // Show newest messages at the bottom
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: controller.messages.length,
                  itemBuilder: (context, index) {
                    final message = controller.messages[index];
                    final isMe = message.senderPhone == controller.userPhone;
                    
                    // Check if previous message (which is physically below since it's reversed) 
                    // is from the same user to group them
                    bool isFirstInGroup = true;
                    if (index < controller.messages.length - 1) {
                      final prevMessage = controller.messages[index + 1];
                      isFirstInGroup = prevMessage.senderPhone != message.senderPhone;
                    }

                    bool isLastInGroup = true;
                    if (index > 0) {
                      final nextMessage = controller.messages[index - 1];
                      isLastInGroup = nextMessage.senderPhone != message.senderPhone;
                    }

                    // Check if we should show time (only show if time difference is > 5 minutes from the physically lower/newer message)
                    bool showTime = true;
                    if (index > 0) {
                      final newerMessage = controller.messages[index - 1];
                      final diff = message.createdAt.difference(newerMessage.createdAt).inMinutes.abs();
                      if (newerMessage.senderPhone == message.senderPhone && diff < 5) {
                        showTime = false;
                      }
                    }
                    
                    if (controller.forceShowTimeMessageId == message.id) {
                      showTime = true;
                    }

                    return AnimatedContainer(
                      key: controller.getKeyForMessage(message.id),
                      duration: const Duration(milliseconds: 800),
                      color: controller.highlightedMessageId == message.id 
                          ? Theme.of(context).colorScheme.primary.withOpacity(0.3) 
                          : Colors.transparent,
                      child: _buildMessageBubble(context, message, isMe, isFirstInGroup, isLastInGroup, showTime),
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

  Widget _buildMessageBubble(BuildContext context, ChatMessageModel message, bool isMe, bool isFirstInGroup, bool isLastInGroup, bool showTime) {
    return Dismissible(
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
      child: Padding(
        padding: EdgeInsets.only(
          bottom: isLastInGroup ? 8 : 2,
          top: isFirstInGroup ? 16 : 0,
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isFirstInGroup && !isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe && isLastInGroup)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.amber.shade100,
                      child: Text(
                        message.senderName.isNotEmpty ? message.senderName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else if (!isMe)
                  const SizedBox(width: 36),
  
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => controller.toggleTimeDisplay(message.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe ? Theme.of(context).colorScheme.primary : Colors.black.withOpacity(0.05),
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
                          GestureDetector(
                            onTap: () {
                              if (message.replyToMessageId != null) {
                                controller.scrollToMessage(message.replyToMessageId!);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isMe ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.05),
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
                                  message.replyToSenderName ?? 'Unknown',
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
                                    color: isMe ? Colors.white.withOpacity(0.9) : Colors.black87
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        RichText(
                          text: TextSpan(
                            children: _parseMentionText(message.text, context, isMe),
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              color: isMe ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (showTime)
              Padding(
                padding: EdgeInsets.only(
                top: 4,
                left: isMe ? 0 : 52,
                right: isMe ? 8 : 0,
              ),
              child: Text(
                DateFormat('hh:mm a').format(message.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
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
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller.messageController,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 1,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
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
                  'Replying to ${message.senderName}',
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
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
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
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: controller.filteredMentionUsers.length,
        itemBuilder: (context, index) {
          final user = controller.filteredMentionUsers[index];
          final name = user['name'] ?? 'Unknown';
          
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
