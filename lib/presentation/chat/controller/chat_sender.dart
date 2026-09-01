import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/chat_outbox_service.dart';
import '../../../utils/app_constant.dart';
import '../model/chat_thread_model.dart';

/// Puts a message into a thread from somewhere that is not a chat screen.
///
/// The month ledger shares its figures this way: it has the numbers, the chat
/// has the delivery. Everything still goes through the outbox the composer
/// uses, so a share made with no connection waits on disk and goes out with
/// everything else — from the app or from the background job.
class ChatSender {
  const ChatSender._();

  /// Sends [text] to the house group, or — with [peerPhone] — to that
  /// person's inbox. Returns false when there is nobody to send as.
  static Future<bool> send({
    required String text,
    String? peerPhone,
    String peerName = '',

    /// What tapping the delivered message opens — see
    /// `ChatMessageModel.action`.
    String? action,
  }) async {
    if (text.trim().isEmpty) return false;
    if (!Get.isRegistered<ChatOutboxService>()) return false;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String myPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    final String myName = prefs.getString(AppConstant.keyUserName) ?? '';
    final String? myImage = prefs.getString(AppConstant.keyUserProfileImage);

    // Nothing to stamp the message with, and the thread id needs it.
    if (myPhone.isEmpty) return false;
    // A conversation with yourself is not a thread.
    if (peerPhone != null && peerPhone == myPhone) return false;

    final ChatThread thread = peerPhone == null
        ? const ChatThread.group()
        : ChatThread.direct(
            peerPhone: peerPhone,
            peerName: peerName,
            myPhone: myPhone,
          );

    try {
      await Get.find<ChatOutboxService>().enqueue(
        localId: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        conversationId: thread.conversationId,
        peerPhone: thread.peerPhone,
        action: action,
        senderName: myName,
        senderPhone: myPhone,
        senderImage: myImage,
        pushTitle: myName,
        // Chat notifications carry the whole message; a summary is long
        // enough that the shade would swallow it, so this says what arrived.
        pushBody: text,
        pushTargets: peerPhone == null ? null : [peerPhone],
        pushData: peerPhone == null
            ? {
                'senderName': myName,
                'senderPhone': myPhone,
                // The face the notification is drawn with on the other end —
                // see `_showNotificationIfAppropriate`. No group name here:
                // this sends from screens that never load it, and the
                // notification falls back to the sender's own line.
                'senderImage': myImage ?? '',
                'replyToSenderName': '',
                'mentions': '',
                'isEveryone': 'false',
                'type': 'chat_message',
              }
            : {
                'senderName': myName,
                'senderPhone': myPhone,
                'senderImage': myImage ?? '',
                'conversationId': thread.conversationId ?? '',
                'replyToSenderName': '',
                'mentions': '',
                'isEveryone': 'false',
                'type': 'direct_message',
              },
      );
      return true;
    } catch (e) {
      debugPrint('ChatSender: could not queue the message — $e');
      return false;
    }
  }
}
