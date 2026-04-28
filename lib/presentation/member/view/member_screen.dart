import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/member_controller.dart';

class MemberScreen extends StatelessWidget {
  const MemberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Inject the controller here since we are not using GetX routing (GetPage) yet.
    final controller = Get.put(MemberController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Members'),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage.value.isNotEmpty) {
          return Center(child: Text('Error: ${controller.errorMessage.value}'));
        }

        if (controller.members.isEmpty) {
          return const Center(child: Text('No members found.'));
        }

        return ListView.builder(
          itemCount: controller.members.length,
          itemBuilder: (context, index) {
            final member = controller.members[index];
            
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(member.name),
                subtitle: Text(member.phone),
              ),
            );
          },
        );
      }),
    );
  }
}
