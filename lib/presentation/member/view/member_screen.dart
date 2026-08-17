import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_ui.dart';
import '../controller/member_controller.dart';
import '../model/member_model.dart';

/// Stable per-member accent, so the same person keeps the same color between
/// this screen and the meal summary.
const List<MaterialColor> _memberColors = [
  Colors.orange,
  Colors.purple,
  Colors.pink,
  Colors.blue,
  Colors.teal,
];

MaterialColor _colorFor(String name) =>
    _memberColors[name.hashCode.abs() % _memberColors.length];

class MemberScreen extends GetView<MemberController> {
  const MemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via MemberBinding

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(title: 'registered_members'.tr),
      body: GetBuilder<MemberController>(
        builder: (controller) {
          if (controller.isLoading) {
            return const _MemberSkeleton();
          }

          if (controller.errorMessage.isNotEmpty) {
            return _buildErrorState(context);
          }

          if (controller.members.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: controller.members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader(context);

              final MemberModel member = controller.members[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildMemberCard(context, member),
              );
            },
          );
        },
      ),
    );
  }

  /// ----------------------------------------------------------------- header

  Widget _buildHeader(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final int count = controller.members.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppUi.tint(context, primary),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.groups_rounded, color: primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'members_count'.trParams({'count': '$count'}),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  controller.isAdminUser
                      ? 'members_admin_hint'.tr
                      : 'members_hint'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------ member card

  Widget _buildMemberCard(BuildContext context, MemberModel member) {
    final MaterialColor color = _colorFor(member.name);
    final bool isMe = controller.isMe(member);
    final bool canRemove = controller.canRemove(member);
    final bool canManage = controller.canManage(member);

    return Material(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppUi.hairline(context)),
      ),
      child: InkWell(
        // Admins get the full manage sheet; for everyone else the row is not
        // pretending to be interactive.
        onTap: canManage ? () => _showManageSheet(context, member) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
          children: [
            ProfileAvatar(
              name: member.name,
              phone: member.phone,
              imageUrl: member.profileImage,
              size: 46,
              background: AppUi.tint(context, color),
              foreground: AppUi.accent(context, color),
              borderColor: color.withOpacity(0.35),
              fontSize: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppUi.body(context),
                          ),
                        ),
                      ),
                      if (member.isAdminUser) ...[
                        const SizedBox(width: 6),
                        _badge(context, 'admin'.tr, Colors.indigo),
                      ],
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        _badge(context, 'you'.tr, Colors.teal),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.phone_rounded,
                          size: 12, color: AppUi.muted(context)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          member.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            letterSpacing: 0.2,
                            color: AppUi.muted(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isMe)
              _rowAction(
                context,
                icon: Icons.call_outlined,
                color: Colors.green,
                tooltip: 'call'.tr,
                onTap: () => controller.makeCall(member.phone),
              ),
            if (canRemove) ...[
              const SizedBox(width: 8),
              _rowAction(
                context,
                icon: Icons.person_remove_outlined,
                color: Colors.red,
                tooltip: 'remove_member'.tr,
                // Blocked while one removal is still in flight.
                onTap: controller.isRemoving
                    ? null
                    : () => _confirmRemove(member),
              ),
            ],
            if (isMe) const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: AppUi.accent(context, color),
        ),
      ),
    );
  }

  /// Row actions read as buttons, not as status badges: a quiet squircle that
  /// carries its color in the outline and the glyph rather than in a filled
  /// blob, so the avatar stays the only saturated thing on the row. Squared
  /// off so they are never mistaken for another avatar, and sized to a 44px
  /// touch target.
  Widget _rowAction(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppUi.neutralSurface(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: enabled
                ? color.withOpacity(AppUi.isDark(context) ? 0.45 : 0.30)
                : AppUi.hairline(context),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          splashColor: color.withOpacity(0.14),
          highlightColor: color.withOpacity(0.08),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Icon(
                icon,
                size: 19,
                color: enabled
                    ? AppUi.accent(context, color)
                    : AppUi.muted(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ----------------------------------------------------------------- states

  Widget _buildEmptyState(BuildContext context) {
    return _centeredState(
      context,
      icon: Icons.groups_outlined,
      color: Theme.of(context).colorScheme.primary,
      title: 'no_members_found'.tr,
      hint: 'members_hint'.tr,
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return _centeredState(
      context,
      icon: Icons.cloud_off_rounded,
      color: Colors.red,
      title: 'failed_load_members'.tr,
      hint: 'check_connection'.tr,
      action: TextButton.icon(
        onPressed: controller.fetchMembers,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text('retry'.tr),
      ),
    );
  }

  Widget _centeredState(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String hint,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: AppUi.tint(context, color),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context).withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------- actions

  void _confirmRemove(MemberModel member, {bool fromSheet = false}) {
    showConfirmDialog(
      title: 'remove_member'.tr,
      message: 'confirm_remove_member'.trParams({'name': member.name}),
      detail: 'remove_member_note'.tr,
      confirmText: 'remove'.tr,
      onConfirm: () {
        if (fromSheet) closeOverlayRoute();
        controller.removeMember(member);
      },
    );
  }

  /// ------------------------------------------------------------ manage sheet

  /// Everything an admin can do to one member, in one place: their role, a
  /// call, and removal — with room to say what each one actually means.
  void _showManageSheet(BuildContext context, MemberModel member) {
    Get.bottomSheet(
      GetBuilder<MemberController>(
        builder: (c) {
          // Read from the live list so the switch follows the server rather
          // than the snapshot the row was built with.
          final MemberModel current = c.members.firstWhere(
            (m) => m.phone == member.phone,
            orElse: () => member,
          );
          final MaterialColor color = _colorFor(current.name);

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppUi.muted(context).withOpacity(0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                    child: Row(
                      children: [
                        ProfileAvatar(
                          name: current.name,
                          phone: current.phone,
                          imageUrl: current.profileImage,
                          size: 52,
                          background: AppUi.tint(context, color),
                          foreground: AppUi.accent(context, color),
                          borderColor: color.withOpacity(0.35),
                          fontSize: 18,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      current.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: AppUi.body(context),
                                      ),
                                    ),
                                  ),
                                  if (current.isAdminUser) ...[
                                    const SizedBox(width: 6),
                                    _badge(context, 'admin'.tr, Colors.indigo),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                current.phone,
                                style: TextStyle(
                                  fontSize: 13,
                                  letterSpacing: 0.2,
                                  color: AppUi.muted(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppUi.hairline(context)),
                  _buildRoleRow(context, c, current),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 13, color: AppUi.muted(context)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'role_takes_effect_hint'.tr,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: AppUi.muted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: AppUi.hairline(context)),
                  _sheetAction(
                    context,
                    icon: Icons.call_outlined,
                    color: Colors.green,
                    label: 'call'.tr,
                    subtitle: current.phone,
                    onTap: () {
                      closeOverlayRoute();
                      c.makeCall(current.phone);
                    },
                  ),
                  _sheetAction(
                    context,
                    icon: Icons.person_remove_outlined,
                    color: Colors.red,
                    label: 'remove_member'.tr,
                    subtitle: 'remove_member_subtitle'.tr,
                    destructive: true,
                    onTap: c.isRemoving
                        ? null
                        : () => _confirmRemove(current, fromSheet: true),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
      isScrollControlled: true,
    );
  }

  /// The admin switch. Both directions are confirmed — this hands over or
  /// takes away the ability to edit everyone else's meals and expenses.
  Widget _buildRoleRow(
    BuildContext context,
    MemberController c,
    MemberModel member,
  ) {
    const MaterialColor color = Colors.indigo;
    final bool isAdmin = member.isAdminUser;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppUi.tint(context, color),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.shield_outlined,
                size: 19, color: AppUi.accent(context, color)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'admin_access'.tr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'admin_access_hint'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (c.isUpdatingRole)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: isAdmin,
              onChanged: (value) => _confirmRoleChange(member, value),
            ),
        ],
      ),
    );
  }

  void _confirmRoleChange(MemberModel member, bool makeAdmin) {
    showConfirmDialog(
      title: makeAdmin ? 'make_admin'.tr : 'revoke_admin'.tr,
      message: (makeAdmin ? 'confirm_make_admin' : 'confirm_revoke_admin')
          .trParams({'name': member.name}),
      detail: makeAdmin ? 'admin_rights_note'.tr : null,
      confirmText: makeAdmin ? 'make_admin'.tr : 'revoke_admin'.tr,
      confirmColor: makeAdmin ? Colors.indigo : Colors.red,
      onConfirm: () => controller.setAdminRole(member, makeAdmin),
    );
  }

  Widget _sheetAction(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String label,
    required String subtitle,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final bool enabled = onTap != null;
    final Color glyph =
        enabled ? AppUi.accent(context, color) : AppUi.muted(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, color),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 19, color: glyph),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: destructive
                            ? AppUi.accent(context, Colors.red)
                            : AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Loading placeholder — the shape of the list beats a centered spinner.
/// ---------------------------------------------------------------------------

class _MemberSkeleton extends StatefulWidget {
  const _MemberSkeleton();

  @override
  State<_MemberSkeleton> createState() => _MemberSkeletonState();
}

class _MemberSkeletonState extends State<_MemberSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = AppUi.isDark(context) ? Colors.white : Colors.black;

    Widget box({double? width, double height = 14, double radius = 8}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base.withOpacity(0.10),
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.8).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              box(width: 42, height: 42, radius: 14),
              const SizedBox(width: 12),
              Expanded(child: box(height: 16)),
            ],
          ),
          const SizedBox(height: 24),
          for (int i = 0; i < 5; i++) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppUi.hairline(context)),
              ),
              child: Row(
                children: [
                  box(width: 46, height: 46, radius: 23),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        box(width: 130, height: 14),
                        const SizedBox(height: 8),
                        box(width: 90, height: 11),
                      ],
                    ),
                  ),
                  box(width: 36, height: 36, radius: 18),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
