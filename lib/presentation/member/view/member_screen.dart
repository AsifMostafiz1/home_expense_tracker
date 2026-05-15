import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/member_controller.dart';

class MemberScreen extends GetView<MemberController> {
  const MemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via MemberBinding

    return Scaffold(
      appBar: CustomAppBar(
        title: 'registered_members'.tr,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GetBuilder<MemberController>(
        builder: (controller) {
          if (controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.errorMessage.isNotEmpty) {
            return Center(
              child: Text(
                '${'error'.tr}: ${controller.errorMessage}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }

          if (controller.members.isEmpty) {
            return Center(child: Text('no_members_found'.tr));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: controller.members.length,
            itemBuilder: (context, index) {
              final member = controller.members[index];

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    member.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  subtitle: Text(
                    member.phone,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.call,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => controller.makeCall(member.phone),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

