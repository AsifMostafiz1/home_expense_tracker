import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../services/call_service.dart';
import '../../chat/repository/chat_repository.dart';

/// Writes the line a finished call leaves in the thread.
///
/// Straight to the repository rather than through the chat outbox, for two
/// reasons. A call log is not something anybody sent, so it must not carry a
/// push notification — the ringing already did that. And it is only worth
/// anything at the moment it happens: a call log delivered tomorrow, when the
/// connection comes back, would land in the wrong place in the conversation.
/// Firestore's own queue still carries it if the write cannot go now.
class ChatCallLog implements ChatCallLogger {
  final ChatRepository? _override;

  const ChatCallLog({ChatRepository? repository}) : _override = repository;

  /// Resolved when a call ends rather than when this is built: the chat
  /// repository is registered lazily, and the calling service is put together
  /// before anybody has opened a thread.
  ChatRepository get _repository => _override ?? Get.find<ChatRepository>();

  @override
  Future<void> log({
    required String conversationId,
    required String peerPhone,
    required String callerPhone,
    required String callerName,
    String? callerImage,
    required String outcome,
    required int seconds,
  }) async {
    if (conversationId.isEmpty) return;

    try {
      await _repository.sendMessage(
        '',
        callerName,
        callerPhone,
        senderImage: callerImage,
        conversationId: conversationId,
        peerPhone: peerPhone,
        callOutcome: outcome,
        callSeconds: seconds,
      );
    } catch (e) {
      debugPrint('Call: the thread kept no record — $e');
    }
  }
}
