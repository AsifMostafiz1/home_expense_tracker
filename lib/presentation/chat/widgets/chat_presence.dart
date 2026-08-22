import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/profile_avatar.dart';
import '../model/chat_thread_model.dart';

/// Green means a heartbeat inside the window — see `PresenceService`.
const Color kOnlineDot = Color(0xFF22C55E);
const Color kOnlineText = Color(0xFF16A34A);

/// "Active now", "Active 20m ago", "Offline" — the line under a name.
///
/// Nobody writes "went offline": the last heartbeat simply ages out, so this
/// reads the gap rather than a flag.
String presenceLabel(ChatUser? user) {
  if (user == null) return 'offline'.tr;
  if (user.isOnline) return 'active_now'.tr;

  final DateTime? seen = user.lastActiveAt;
  if (seen == null) return 'offline'.tr;

  final Duration gap = DateTime.now().difference(seen);
  if (gap.inMinutes < 60) {
    return 'active_min_ago'.trParams({'count': '${gap.inMinutes.clamp(1, 59)}'});
  }
  if (gap.inHours < 24) {
    return 'active_hour_ago'.trParams({'count': '${gap.inHours}'});
  }
  if (gap.inDays < 7) {
    return 'active_day_ago'.trParams({'count': '${gap.inDays}'});
  }
  return 'offline'.tr;
}

/// When the last message landed, at the width a list row can spare: the clock
/// for today, the day name this week, the date beyond that.
String chatTimeLabel(DateTime? at) {
  if (at == null) return '';

  final DateTime now = DateTime.now();
  final DateTime day = DateTime(at.year, at.month, at.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diff = today.difference(day).inDays;

  if (diff == 0) return DateFormat('hh:mm a').format(at);
  if (diff == 1) return 'yesterday'.tr;
  if (diff < 7) return DateFormat('EEE').format(at);
  return DateFormat('dd MMM').format(at);
}

/// A member's picture with the presence dot on it — the one place both the
/// list and the chat header get their "is this person around" from.
class PresenceAvatar extends StatelessWidget {
  final ChatUser user;
  final double size;

  /// Painted behind the dot so it reads as a hole punched in the avatar
  /// rather than a sticker on top of it. Matches whatever the row sits on.
  final Color ringColor;

  const PresenceAvatar({
    super.key,
    required this.user,
    this.size = 52,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProfileAvatar(
            name: user.name,
            phone: user.phone,
            imageUrl: user.image,
            size: size,
            background: primary.withOpacity(0.14),
            foreground: primary,
            fontSize: size * 0.33,
          ),
          if (user.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: kOnlineDot,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: size * 0.05),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The count of what has not been read. Nothing at all at zero — an empty
/// pill next to every quiet conversation is noise.
class UnreadBadge extends StatelessWidget {
  final int count;

  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final Color primary = Theme.of(context).colorScheme.primary;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
