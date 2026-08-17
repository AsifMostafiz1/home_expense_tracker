import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/member_avatar_service.dart';

/// `Mostafizur Rahman` → `MR`. Unicode-aware, so a Bengali name gives back its
/// own letters rather than a `?`.
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && RegExp(r'[\wঀ-৿]').hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

/// One member's avatar: their picture when there is one, their initials when
/// there is not.
///
/// Every colour is passed in rather than derived here, so each screen keeps
/// the palette it already had — dropping this in changes what is inside the
/// circle, never the circle itself.
class ProfileAvatar extends StatelessWidget {
  final String name;

  /// Preferred identifier for the lookup when [imageUrl] is not to hand.
  final String? phone;

  /// A URL the caller already holds — used only when the directory has
  /// nothing, since a URL denormalised onto a chat message or a bill row was
  /// stamped when that row was written and may since have been replaced.
  final String? imageUrl;

  /// Resolve against the signed-in user instead of [name]/[phone]. The rows
  /// for "My Meals" and "You" are labelled, not named, so there is nothing to
  /// match on.
  final bool isMe;

  final double size;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final double borderWidth;

  /// Drawn instead of initials when no picture resolves — the meal screen uses
  /// a person icon for the viewer's own row.
  final Widget? placeholder;

  final double? fontSize;
  final FontWeight fontWeight;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.phone,
    this.imageUrl,
    this.isMe = false,
    this.size = 42,
    required this.background,
    required this.foreground,
    this.borderColor,
    this.borderWidth = 1.5,
    this.placeholder,
    this.fontSize,
    this.fontWeight = FontWeight.bold,
  });

  @override
  Widget build(BuildContext context) {
    // A screen reached before the bindings run has no directory to consult —
    // render straight through rather than blowing up on a missing service.
    if (!Get.isRegistered<MemberAvatarService>()) {
      return _circle(context, imageUrl);
    }

    // Rebuilds every avatar in the tree once the directory finishes loading,
    // which is what makes pictures appear without pull-to-refresh.
    return GetBuilder<MemberAvatarService>(
      builder: (directory) {
        final String? resolved = isMe
            ? directory.myImage
            : directory.imageFor(phone: phone, name: name);

        // Directory first — see [imageUrl].
        return _circle(
          context,
          resolved != null && resolved.isNotEmpty ? resolved : imageUrl,
        );
      },
    );
  }

  Widget _circle(BuildContext context, String? url) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      // The ring goes in front, so a photo cannot paint over it the way it
      // would with a plain `border` on the backing decoration.
      foregroundDecoration: borderColor == null
          ? null
          : BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: borderColor!, width: borderWidth),
            ),
      child: url == null || url.isEmpty
          ? _fallback(context)
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // A broken or still-decoding picture falls back to initials
              // rather than to a grey box or a half-drawn frame.
              errorBuilder: (_, __, ___) => _fallback(context),
              frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded || frame != null
                      ? child
                      : _fallback(context),
            ),
    );
  }

  Widget _fallback(BuildContext context) {
    if (placeholder != null) return placeholder!;

    return Text(
      initialsOf(name),
      style: TextStyle(
        color: foreground,
        fontSize: fontSize ?? size * 0.34,
        fontWeight: fontWeight,
      ),
    );
  }
}
