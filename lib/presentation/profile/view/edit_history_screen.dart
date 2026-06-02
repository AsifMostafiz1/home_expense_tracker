import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/profile_controller.dart';
import '../../auth/model/user_model.dart';

class EditHistoryScreen extends GetView<ProfileController> {
  const EditHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'edit_history'.tr),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GetBuilder<ProfileController>(
        builder: (controller) {
          return Column(
            children: [
              _buildModernFilterSection(context, controller),
              Expanded(
                child: controller.editLogs.isEmpty
                    ? _buildEmptyState(context)
                    : _buildTimelineList(context, controller),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          Text(
            'no_edit_history'.tr,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.6),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters to see more results.',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(BuildContext context, ProfileController controller) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 16, right: 16),
      itemCount: controller.editLogs.length,
      itemBuilder: (context, index) {
        final log = controller.editLogs[index];
        final isMeal = log.type == 'meal';
        final isLast = index == controller.editLogs.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline line and dot
              Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isMeal ? Colors.teal.shade50 : Colors.blue.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isMeal ? Colors.teal.shade200 : Colors.blue.shade200,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isMeal ? Colors.teal : Colors.blue).withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Icon(
                      isMeal ? Icons.restaurant : Icons.attach_money,
                      color: isMeal ? Colors.teal : Colors.blue.shade700,
                      size: 20,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Content Card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log.targetUserName,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('dd MMM yyyy, hh:mm a').format(log.createdAt),
                                    style: TextStyle(
                                      color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isMeal ? Colors.teal : Colors.blue).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Text(
                                log.type.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: isMeal ? Colors.teal.shade700 : Colors.blue.shade700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          log.description,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                height: 1.4,
                              ),
                        ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(
                                  '${'admin'.tr}: ${log.adminName}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernFilterSection(BuildContext context, ProfileController controller) {
    String dateRangeText = 'date_range'.tr;
    bool hasDateFilter = controller.filterStartDate != null || controller.filterEndDate != null;
    
    if (controller.filterStartDate != null && controller.filterEndDate != null) {
      dateRangeText = '${DateFormat('MMM dd').format(controller.filterStartDate!)} - ${DateFormat('MMM dd').format(controller.filterEndDate!)}';
    } else if (controller.filterStartDate != null) {
      dateRangeText = 'from_date'.trParams({'date': DateFormat('MMM dd').format(controller.filterStartDate!)});
    } else if (controller.filterEndDate != null) {
      dateRangeText = 'until_date'.trParams({'date': DateFormat('MMM dd').format(controller.filterEndDate!)});
    }

    String userFilterText = controller.filterTargetUser != null 
        ? controller.filterTargetUser!.name 
        : 'filter_by_user'.tr;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildFilterChip(
                  context,
                  label: dateRangeText,
                  icon: Icons.calendar_today_rounded,
                  isActive: hasDateFilter,
                  onTap: () async {
                    DateTimeRange? picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: hasDateFilter
                          ? DateTimeRange(start: controller.filterStartDate ?? DateTime.now(), end: controller.filterEndDate ?? DateTime.now())
                          : null,
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.light(
                              primary: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          child: child!,
                        );
                      }
                    );
                    if (picked != null) {
                      controller.setDateFilter(picked.start, picked.end);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildFilterChip(
                  context,
                  label: userFilterText,
                  icon: Icons.people_alt_rounded,
                  isActive: controller.filterTargetUser != null,
                  onTap: () => _showUserFilterBottomSheet(context, controller),
                ),
              ),
            ],
          ),
          if (hasDateFilter || controller.filterTargetUser != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: controller.clearFilters,
                child: Text(
                  'clear_filters'.tr,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, {required String label, required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey.shade600),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).textTheme.bodyMedium?.color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserFilterBottomSheet(BuildContext context, ProfileController controller) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'filter_by_user'.tr,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text('all_users'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: controller.filterTargetUser == null
                          ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        controller.setUserFilter(null);
                        Get.back();
                      },
                    ),
                    ...controller.availableUsers.map((user) {
                      bool isSelected = controller.filterTargetUser?.phone == user.phone;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        title: Text(user.name),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                            : null,
                        onTap: () {
                          controller.setUserFilter(user);
                          Get.back();
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
      ignoreSafeArea: false,
    );
  }
}

