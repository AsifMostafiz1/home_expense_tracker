import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../services/supabase_storage_service.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../../../utils/supabase_config.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_list_controller.dart';
import '../model/chat_thread_model.dart';
import 'group_avatar.dart';

/// What the group chat is called and what it looks like.
///
/// Admins only, the way every other house-wide setting is — a rename lands on
/// everybody's phone. Members can still open it to see who set what.
void showGroupSettingsSheet(BuildContext context) {
  Get.bottomSheet(
    const _GroupSettingsSheet(),
    isScrollControlled: true,
    // Transparent because the sheet paints its own rounded surface. Left
    // unset, GetX hands null to Flutter's BottomSheet, which falls back to a
    // theme colour and paints a square-cornered rectangle behind it — visible
    // as two notched shoulders at the top wherever that colour is not the
    // card's.
    backgroundColor: Colors.transparent,
  );
}

class _GroupSettingsSheet extends StatefulWidget {
  const _GroupSettingsSheet();

  @override
  State<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<_GroupSettingsSheet> {
  final ChatController _chat = Get.find<ChatController>();
  final SupabaseStorageService _storage = SupabaseStorageService();

  late final TextEditingController _name =
      TextEditingController(text: _chat.groupInfo.name);

  /// Chosen on this device, not uploaded yet.
  File? _picked;

  /// Set when the current picture is to go, putting the members' icon back.
  bool _clearing = false;

  bool _saving = false;

  bool get _canEdit => _chat.isAdminUser;

  /// What the preview shows right now, which is not necessarily what is
  /// stored — a picture can be picked or dropped before anything is saved.
  String? get _shownUrl =>
      _clearing || _picked != null ? null : _chat.groupInfo.imageUrl;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        // Downscaled on the device: nothing here is ever drawn larger than a
        // circle, and a camera shot is several megabytes.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() {
        _picked = File(picked.path);
        _clearing = false;
      });
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_pick_image'.tr);
    }
  }

  void _remove() => setState(() {
        _picked = null;
        _clearing = true;
      });

  Future<void> _save() async {
    if (!_canEdit || _saving) return;

    setState(() => _saving = true);
    try {
      String? imageUrl = _chat.groupInfo.imageUrl;
      if (_clearing) {
        imageUrl = null;
      } else if (_picked != null) {
        imageUrl = await _storage.uploadFile(
          _picked!,
          folder: SupabaseConfig.folderProfile,
        );
      }

      final bool saved = await _chat.saveGroupInfo(
        name: _name.text,
        imageUrl: imageUrl,
      );
      if (!saved) return;

      closeOverlayRoute();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'group_updated'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_group'.tr);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    // No keyboard inset here. Get.bottomSheet already pads its own route by
    // `viewInsets.bottom`, so adding it again lifts the sheet a second
    // keyboard-height off the bottom and leaves a gap between the two — the
    // same trap the ledger sheets document.
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
              'group_settings'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Center(child: _buildAvatar(context, primary)),
            const SizedBox(height: 22),
            _buildNameField(context),
            const SizedBox(height: 20),
            if (_canEdit)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'save_changes'.tr,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              )
            else
              // Not a refusal so much as an explanation: the group's name is
              // the house's, and one member renaming it for everybody is not
              // something that should happen by accident.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppUi.neutralSurface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppUi.hairline(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 18, color: AppUi.muted(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'group_settings_admin_only'.tr,
                        style: TextStyle(
                            fontSize: 12.5, color: AppUi.muted(context)),
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

  /// The picture as it will be — including, when there is none, the icon the
  /// members make between them. Someone clearing the photo should see what
  /// they are going back to before they save.
  Widget _buildAvatar(BuildContext context, Color primary) {
    final List<ChatUser> members = Get.isRegistered<ChatListController>()
        ? Get.find<ChatListController>().houseMembers
        : const <ChatUser>[];

    final Widget preview = _picked != null
        ? ClipOval(
            child: Image.file(_picked!,
                width: 96, height: 96, fit: BoxFit.cover),
          )
        : GroupAvatar(
            imageUrl: _shownUrl,
            members: members,
            size: 96,
            gapColor: Theme.of(context).cardColor,
          );

    if (!_canEdit) return preview;

    return GestureDetector(
      onTap: () => showPhotoSourceSheet(
        context,
        onPick: _pick,
        // Nothing to take away when the icon is already the members'.
        onRemove: _shownUrl == null && _picked == null ? null : _remove,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          preview,
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                border:
                    Border.all(color: Theme.of(context).cardColor, width: 2.5),
              ),
              child:
                  const Icon(Icons.camera_alt, size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField(BuildContext context) {
    return CustomTextField(
      controller: _name,
      labelText: 'group_name'.tr,
      // The hint is the default an empty field falls back to, so it shows
      // what leaving it blank would give.
      hintText: 'group_chat'.tr,
      prefixIcon: Icons.groups_rounded,
      maxLength: 40,
      textCapitalization: TextCapitalization.words,
      // Greyed rather than absent for a member: they can read what the group
      // is called, they just cannot rename it for everybody.
      readOnly: !_canEdit,
    );
  }
}
