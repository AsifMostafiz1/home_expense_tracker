import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/meal_controller.dart';

class AnnouncementHistoryScreen extends GetView<MealController> {
  const AnnouncementHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'announcement_history'.tr,
        showBackButton: true,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GetBuilder<MealController>(
        builder: (controller) {
          if (controller.announcements.isEmpty) {
            return Center(
              child: Text('no_announcements_found'.tr),
            );
          }

          // Group announcements by date
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (var item in controller.announcements) {
            final updatedAt = item['updatedAt'];
            DateTime? date;
            if (updatedAt is Timestamp) {
              date = updatedAt.toDate();
            } else if (updatedAt is String) {
              date = DateTime.parse(updatedAt);
            }
            
            final dateKey = date != null 
                ? DateFormat('dd MMMM, yyyy').format(date) 
                : 'unknown_date'.tr;
            
            if (!grouped.containsKey(dateKey)) {
              grouped[dateKey] = [];
            }
            grouped[dateKey]!.add(item);
          }

          final dateKeys = grouped.keys.toList();
          final List<dynamic> flatList = [];
          for (var key in dateKeys) {
            flatList.add(key); // Header
            flatList.addAll(grouped[key]!); // Announcements
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: flatList.length,
            itemBuilder: (context, index) {
              final item = flatList[index];

              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 0, 12),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                );
              }

              final announcement = item as Map<String, dynamic>;
              final text = announcement['text'] ?? '';
              final userName = announcement['user_name'] ?? 'unknown'.tr;
              final updatedAt = announcement['updatedAt'];
              
              DateTime? date;
              if (updatedAt is Timestamp) {
                date = updatedAt.toDate();
              } else if (updatedAt is String) {
                date = DateTime.parse(updatedAt);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.campaign, color: Colors.amber, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (date != null)
                                Text(
                                  DateFormat('hh:mm a').format(date!),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
