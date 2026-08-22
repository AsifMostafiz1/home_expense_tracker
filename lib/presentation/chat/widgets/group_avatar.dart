import 'package:flutter/material.dart';

import '../../../common/widgets/profile_avatar.dart';
import '../model/chat_thread_model.dart';

/// The group chat's icon.
///
/// An admin can upload a picture, and then that is simply what it is. Until
/// somebody does, the icon is built from the members themselves — their faces
/// laid over each other the way a group thread looks in any messaging app.
/// A house that never opens the settings sheet still gets an icon that says
/// whose house it is, rather than a generic silhouette.
///
/// Up to four members are drawn. Past that the last tile counts the rest,
/// because five circles inside forty pixels is a smudge.
class GroupAvatar extends StatelessWidget {
  /// The uploaded picture, when there is one. Everything else is ignored then.
  final String? imageUrl;

  /// Everyone in the house. Order does not matter — this sorts.
  final List<ChatUser> members;

  final double size;

  /// Painted in the gaps between the tiles, so they read as separate circles
  /// rather than one shape. Match whatever the icon sits on.
  final Color gapColor;

  /// Behind a member with no picture of their own, and behind the count.
  /// Defaults to a tint of the theme's accent — the group card passes its own,
  /// because an accent-tinted circle on an accent-coloured card is a smudge.
  final Color? tileBackground;

  /// The initials, the count, and the fallback icon.
  final Color? tileForeground;

  const GroupAvatar({
    super.key,
    this.imageUrl,
    this.members = const [],
    this.size = 44,
    required this.gapColor,
    this.tileBackground,
    this.tileForeground,
  });

  /// How many faces fit before the count takes over.
  static const int maxTiles = 4;

  Color _background(BuildContext context) =>
      tileBackground ??
      Theme.of(context).colorScheme.primary.withOpacity(0.16);

  Color _foreground(BuildContext context) =>
      tileForeground ?? Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ProfileAvatar(
        name: '',
        imageUrl: imageUrl,
        size: size,
        background: _background(context),
        foreground: _foreground(context),
        placeholder: Icon(Icons.groups_rounded,
            size: size * 0.52, color: _foreground(context)),
      );
    }

    final List<ChatUser> ordered = orderForIcon(members);

    // Nobody to draw — a house of one, or a directory that has not loaded.
    if (ordered.isEmpty) return _fallback(context);

    if (ordered.length == 1) {
      return _tile(context, ordered.first, size, ring: false);
    }

    final List<_Slot> slots = _layout(ordered.length);
    final double tile = slots.first.size * size;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < slots.length; i++)
            Positioned(
              left: slots[i].x * (size - tile),
              top: slots[i].y * (size - tile),
              child: i == slots.length - 1 && ordered.length > maxTiles
                  ? _overflow(context, ordered.length - (maxTiles - 1), tile)
                  : _tile(context, ordered[i], tile),
            ),
        ],
      ),
    );
  }

  /// Members with a picture first, then by name.
  ///
  /// Faces make a better icon than initials, so the ones who have uploaded a
  /// picture get the four slots first. Both halves are sorted, so the icon is
  /// stable — it changes when the house does, not when a stream re-emits.
  static List<ChatUser> orderForIcon(List<ChatUser> members) {
    final List<ChatUser> list = List<ChatUser>.from(members)
      ..sort((a, b) {
        final bool aHas = a.image != null && a.image!.isNotEmpty;
        final bool bHas = b.image != null && b.image!.isNotEmpty;
        if (aHas != bHas) return aHas ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  /// Where each circle sits, as a fraction of the free space, and how big it
  /// is as a fraction of the whole. Two overlap on the diagonal, three make a
  /// triangle, four make a square.
  List<_Slot> _layout(int count) {
    if (count == 2) {
      return const [
        _Slot(0, 0, 0.62),
        _Slot(1, 1, 0.62),
      ];
    }
    if (count == 3) {
      return const [
        _Slot(0.5, 0, 0.58),
        _Slot(0, 1, 0.58),
        _Slot(1, 1, 0.58),
      ];
    }
    return const [
      _Slot(0, 0, 0.54),
      _Slot(1, 0, 0.54),
      _Slot(0, 1, 0.54),
      _Slot(1, 1, 0.54),
    ];
  }

  Widget _tile(BuildContext context, ChatUser user, double tile,
      {bool ring = true}) {
    return ProfileAvatar(
      name: user.name,
      phone: user.phone,
      imageUrl: user.image,
      size: tile,
      background: _background(context),
      foreground: _foreground(context),
      fontSize: tile * 0.36,
      borderColor: ring ? gapColor : null,
      borderWidth: size * 0.045,
    );
  }

  /// `+3` — the members that did not fit.
  Widget _overflow(BuildContext context, int count, double tile) {
    return Container(
      width: tile,
      height: tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _background(context),
        shape: BoxShape.circle,
        border: Border.all(color: gapColor, width: size * 0.045),
      ),
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.all(tile * 0.18),
          child: Text(
            '+$count',
            style: TextStyle(
              color: _foreground(context),
              fontWeight: FontWeight.bold,
              fontSize: tile * 0.42,
            ),
          ),
        ),
      ),
    );
  }

  /// Before the member directory has answered, and for a house of one.
  Widget _fallback(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _background(context),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.groups_rounded,
          color: _foreground(context), size: size * 0.52),
    );
  }
}

/// One circle's place in the icon: position as a fraction of the free space,
/// size as a fraction of the whole.
class _Slot {
  final double x;
  final double y;
  final double size;

  const _Slot(this.x, this.y, this.size);
}
