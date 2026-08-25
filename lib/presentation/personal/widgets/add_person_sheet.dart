import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_ui.dart';
import '../../member/controller/member_controller.dart';
import '../../member/model/member_model.dart';
import '../controller/personal_controller.dart';

/// Opens an account with somebody — the whole of what the dues screen's plus
/// button does.
///
/// Only a person: a name, a phone if there is one. No amount, no note, no
/// date, because at the moment somebody is added there is usually nothing to
/// record yet — and when there is, it is entered from inside their account,
/// where both directions are one tap away.
Future<void> showAddPersonSheet(BuildContext context) {
  return Get.bottomSheet(
    const _AddPersonSheet(),
    isScrollControlled: true,
  );
}

class _AddPersonSheet extends StatefulWidget {
  const _AddPersonSheet();

  @override
  State<_AddPersonSheet> createState() => _AddPersonSheetState();
}

class _AddPersonSheetState extends State<_AddPersonSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  String _query = '';
  String? _nameError;

  /// How many app users the sheet offers at once. Enough to pick from without
  /// the list becoming the sheet — the name field narrows it past this.
  static const int _suggestionLimit = 6;

  /// Who else uses the app. Held rather than looked up in `build`, and
  /// listened to by hand rather than through a `GetBuilder`: that widget
  /// takes ownership of a controller it instantiates and deletes it again on
  /// dispose, which from a bottom sheet would take the member list down with
  /// the sheet.
  MemberController? _members;

  /// What `addListener` hands back — calling it detaches again.
  VoidCallback? _membersListener;

  @override
  void initState() {
    super.initState();

    if (Get.isRegistered<MemberController>()) {
      final MemberController controller = Get.find<MemberController>();
      _members = controller;
      // The list is usually already in memory; this is for the launch where
      // the first snapshot is still out when the sheet opens.
      _membersListener = controller.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _membersListener?.call();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// App users who are not already on the dues list, and not the member
  /// themselves. Matched on name and on phone, so either half of a row can be
  /// typed to find it.
  List<MemberModel> _suggestions(PersonalController c) {
    final MemberController? members = _members;
    if (members == null) return const [];

    final Set<String> taken = c.personKeys;
    final String query = _query.trim().toLowerCase();

    final List<MemberModel> matches = members.members.where((member) {
      if (member.phone == c.userPhone) return false;
      if (taken.contains(member.phone.trim())) return false;
      if (taken.contains(member.name.trim().toLowerCase())) return false;
      if (query.isEmpty) return true;
      return member.name.toLowerCase().contains(query) ||
          member.phone.toLowerCase().contains(query);
    }).toList();

    matches.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return matches;
  }

  /// One tap on an app user is the whole add — their name and number are
  /// already known, so there is nothing left to type.
  Future<void> _addUser(PersonalController c, MemberModel member) async {
    final bool saved =
        await c.addPerson(name: member.name, phone: member.phone);
    if (saved) closeOverlayRoute();
  }

  Future<void> _addTyped(PersonalController c) async {
    final String name = _name.text.trim();
    setState(() => _nameError = name.isEmpty ? 'enter_a_name'.tr : null);
    if (_nameError != null) return;

    final bool saved =
        await c.addPerson(name: name, phone: _phone.text.trim());
    if (saved) closeOverlayRoute();
  }

  @override
  Widget build(BuildContext context) {
    // No keyboard inset here: Get.bottomSheet already pads its own route by
    // `viewInsets.bottom`, and adding it again lifts the sheet a second
    // keyboard-height off the bottom.
    return GetBuilder<PersonalController>(
      builder: (c) {
        final List<MemberModel> suggestions = _suggestions(c);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppUi.muted(context).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  'add_person'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'add_person_hint'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 18),
                CustomTextField(
                  controller: _name,
                  labelText: 'person_name'.tr,
                  hintText: 'person_name_hint'.tr,
                  prefixIcon: Icons.person_outline_rounded,
                  errorText: _nameError,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (value) => setState(() {
                    _query = value;
                    _nameError = null;
                  }),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _phone,
                  labelText: 'phone_optional'.tr,
                  hintText: '01XXXXXXXXX',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                  ],
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildSuggestions(context, c, suggestions),
                ],
                const SizedBox(height: 22),
                CustomButton(
                  text: 'add_person'.tr,
                  height: 52,
                  borderRadius: 14,
                  isLoading: c.isSaving,
                  onPressed: () => _addTyped(c),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The people already using the app, offered by name.
  ///
  /// A tap adds them outright rather than filling the fields in: their name
  /// and number are both already known, so a second confirming tap would only
  /// be asking whether they meant the row they just pressed.
  Widget _buildSuggestions(
    BuildContext context,
    PersonalController c,
    List<MemberModel> suggestions,
  ) {
    final List<MemberModel> shown =
        suggestions.take(_suggestionLimit).toList(growable: false);
    final int hidden = suggestions.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'from_the_app'.tr.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: AppUi.muted(context),
          ),
        ),
        const SizedBox(height: 10),
        for (final MemberModel member in shown) ...[
          _buildUserTile(context, c, member),
          const SizedBox(height: 8),
        ],
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'keep_typing_to_narrow'.trParams({'count': '$hidden'}),
              style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
            ),
          ),
      ],
    );
  }

  Widget _buildUserTile(
    BuildContext context,
    PersonalController c,
    MemberModel member,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: AppUi.neutralSurface(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Nothing to tap while a save is already in flight — two taps in a
        // row would otherwise open two accounts.
        onTap: c.isSaving ? null : () => _addUser(c, member),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppUi.hairline(context)),
          ),
          child: Row(
            children: [
              ProfileAvatar(
                name: member.name,
                phone: member.phone,
                imageUrl: member.profileImage,
                size: 36,
                background: AppUi.tint(context, Colors.blueGrey),
                foreground: AppUi.accent(context, Colors.blueGrey),
                fontSize: 13,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppUi.body(context),
                      ),
                    ),
                    if (member.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        member.phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: AppUi.muted(context)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.add_circle_outline_rounded, size: 20, color: primary),
            ],
          ),
        ),
      ),
    );
  }
}
