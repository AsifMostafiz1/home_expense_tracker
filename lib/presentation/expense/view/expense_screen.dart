import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/hiding_fab.dart';
import '../../../common/widgets/image_viewer_screen.dart';
import '../../../utils/app_ui.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../controller/expense_controller.dart';
import '../model/expense_model.dart';
import '../widgets/expense_bottom_sheet.dart';

/// Type `expense` means a meal expense; `others` is everything else. The two
/// keep the same icon and color they already have on the meal screen, so a
/// row means the same thing wherever it is shown.
const MaterialColor _mealColor = Colors.blue;
const MaterialColor _othersColor = Colors.orange;

bool _isMeal(ExpenseModel item) => item.type == 'expense';

MaterialColor _colorOf(ExpenseModel item) =>
    _isMeal(item) ? _mealColor : _othersColor;

IconData _iconOf(ExpenseModel item) => _isMeal(item)
    ? Icons.shopping_cart_outlined
    : Icons.miscellaneous_services_outlined;

String _labelOf(ExpenseModel item) => _isMeal(item) ? 'meal'.tr : 'others'.tr;

class ExpenseScreen extends GetView<ExpenseController> {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via ExpenseBinding

    return HidingFab(
      icon: Icons.add_rounded,
      tooltip: 'add_expense'.tr,
      onPressed: () => _showExpenseBottomSheet(context),
      builder: (context, fab) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: CustomAppBar(
          title: 'expense'.tr,
          bottom: const _MonthSwitcher(),
        ),
        floatingActionButton: fab,
        body: GetBuilder<ExpenseController>(
          builder: (controller) {
            final bool isFirstLoad =
                controller.isLoading && controller.expenses.isEmpty;
            final List<String> dateKeys =
                controller.groupedExpenses.keys.toList();

            return RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                await controller.fetchExpenses(background: true);
                // The strip above this screen reads a month nothing here owns.
                await MonthlyStatsController.refreshDuesIfLoaded();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildSummaryCard(context, isLoading: isFirstLoad),
                  ),
                  SliverToBoxAdapter(
                    child: _SyncStrip(
                      online: controller.isOnline,
                      pending: controller.pendingCount,
                    ),
                  ),
                  if (isFirstLoad)
                    const SliverToBoxAdapter(child: _ListSkeleton())
                  else if (dateKeys.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState(context))
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final String dateKey = dateKeys[index];
                          return _buildDayGroup(
                            context,
                            dateKey,
                            controller.groupedExpenses[dateKey]!,
                          );
                        },
                        childCount: dateKeys.length,
                      ),
                    ),
                  // Breathing room so the FAB never covers the last card.
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// --------------------------------------------------------------- summary

  Widget _buildSummaryCard(BuildContext context, {required bool isLoading}) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final double total = controller.displayTotal;
    final double meal = controller.mealTotal;
    final double others = controller.othersTotal;
    final int count = controller.filteredExpenses.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  controller.selectedMonthName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              if (!isLoading)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'entries_count'.trParams({'count': '$count'}),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          isLoading
              ? const _Pulse(width: 150, height: 34, radius: 10, onDark: true)
              : Text(
                  AppUi.money(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            'total_paid'.tr,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          // Where the money actually went — value contrast reads cleanly on a
          // saturated ground, where two hues would fight the gradient.
          _SplitBar(meal: meal, others: others),
          const SizedBox(height: 12),
          Row(
            children: [
              _splitLegend(
                label: 'meal'.tr,
                amount: meal,
                total: total,
                opacity: 0.95,
              ),
              const SizedBox(width: 20),
              _splitLegend(
                label: 'others'.tr,
                amount: others,
                total: total,
                opacity: 0.45,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _splitLegend({
    required String label,
    required double amount,
    required double total,
    required double opacity,
  }) {
    final int percent = total <= 0 ? 0 : ((amount / total) * 100).round();

    return Expanded(
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · $percent%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  AppUi.money(amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------- day group

  Widget _buildDayGroup(
    BuildContext context,
    String dateKey,
    List<ExpenseModel> items,
  ) {
    final double dayTotal =
        items.fold<double>(0, (sum, item) => sum + item.amount);
    // The key is a pre-formatted string; the items carry the real date.
    final String label =
        items.isEmpty ? dateKey : AppUi.dayLabel(items.first.date);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppUi.neutralSurface(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppUi.hairline(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12, color: AppUi.muted(context)),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context).withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Divider(color: AppUi.hairline(context), height: 1),
              ),
              const SizedBox(width: 12),
              Text(
                AppUi.money(dayTotal),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppUi.body(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppUi.hairline(context)),
              boxShadow: AppUi.softShadow(context),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _buildExpenseRow(context, items[i]),
                  if (i != items.length - 1)
                    Divider(
                      height: 1,
                      indent: 68,
                      endIndent: 16,
                      color: AppUi.hairline(context),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tap edits, the overflow menu keeps delete one step away — the row itself
  /// is the primary target, so the chrome can stay quiet.
  Widget _buildExpenseRow(BuildContext context, ExpenseModel item) {
    final MaterialColor color = _colorOf(item);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showExpenseBottomSheet(context, item: item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
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
                child: Icon(_iconOf(item),
                    size: 19, color: AppUi.accent(context, color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppUi.tint(context, color),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _labelOf(item),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: AppUi.accent(context, color),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.time.format(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppUi.muted(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // A receipt is worth advertising on the row: it is the
                        // difference between "trust me" and "here it is". One
                        // still waiting to upload opens from the device.
                        if (item.hasAnyReceipt) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => Get.to(() => ImageViewerScreen(
                                  imageFile: item.pendingReceiptFile,
                                  imageUrl: item.hasPendingReceipt
                                      ? null
                                      : item.imageUrl,
                                  title: item.description,
                                  subtitle: AppUi.money(item.amount),
                                )),
                            child: Icon(Icons.attachment_rounded,
                                size: 14, color: AppUi.accent(context, color)),
                          ),
                        ],
                        // Saved here, not yet on the server — a labelled
                        // chip, not just an icon, so it reads at a glance. It
                        // clears by itself once the connection delivers the
                        // entry (and its receipt, if one is waiting too).
                        if (item.isPending || item.hasPendingReceipt) ...[
                          const SizedBox(width: 8),
                          const _PendingChip(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppUi.money(item.amount),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppUi.body(context),
                ),
              ),
              SizedBox(
                width: 32,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  splashRadius: 18,
                  tooltip: '',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  icon: Icon(Icons.more_vert_rounded,
                      color: AppUi.muted(context)),
                  onSelected: (value) {
                    if (value == 'update') {
                      _showExpenseBottomSheet(context, item: item);
                    } else if (value == 'delete') {
                      _confirmDelete(item);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'update',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: AppUi.body(context)),
                          const SizedBox(width: 12),
                          Text('update'.tr),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.red),
                          const SizedBox(width: 12),
                          Text('delete'.tr,
                              style: const TextStyle(color: Colors.red)),
                        ],
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

  /// ----------------------------------------------------------- empty state

  Widget _buildEmptyState(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: AppUi.tint(context, primary),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_outlined, size: 48, color: primary),
          ),
          const SizedBox(height: 22),
          Text(
            'no_expenses_found'
                .trParams({'month': controller.selectedMonthName}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context).withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'expense_empty_hint'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------------- sheets

  void _confirmDelete(ExpenseModel item) {
    showConfirmDialog(
      title: 'delete_expense'.tr,
      message: 'confirm_delete'.tr,
      detail: '${item.description} · ${AppUi.money(item.amount)}',
      confirmText: 'delete'.tr,
      onConfirm: () => controller.deleteExpense(item),
    );
  }

  void _showExpenseBottomSheet(BuildContext context, {ExpenseModel? item}) {
    if (item != null) {
      controller.loadForEdit(item);
    } else {
      controller.clearForm();
    }

    Get.bottomSheet(
      ExpenseBottomSheet(item: item),
      isScrollControlled: true,
    ).whenComplete(
      // Backing out of the sheet abandons an unsaved receipt: nothing was
      // uploaded, the picked file only ever lived in the controller.
      controller.clearReceiptSelection,
    );
  }
}

/// ---------------------------------------------------------------------------
/// "Waiting to sync" — the mark on a row that exists on this device only.
/// Orange to match the app bar's offline badge, so the two read as one story.
/// ---------------------------------------------------------------------------

class _PendingChip extends StatelessWidget {
  const _PendingChip();

  @override
  Widget build(BuildContext context) {
    final Color fg = AppUi.accent(context, Colors.orange);

    return Tooltip(
      message: 'waiting_to_sync'.tr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppUi.tint(context, Colors.orange),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(
              'not_synced'.tr,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Sync status — a slim strip under the summary that only appears while
/// entries saved on this device are still on their way to the server: how many
/// are waiting (offline) or going out (online). "Offline" itself is said by
/// the strip across the top of the app (`ConnectionBanner`), so this one stays
/// quiet with nothing pending.
/// ---------------------------------------------------------------------------

class _SyncStrip extends StatelessWidget {
  final bool online;

  /// Entries saved on this device that the server does not have yet.
  final int pending;

  const _SyncStrip({required this.online, required this.pending});

  @override
  Widget build(BuildContext context) {
    final int waiting = pending;
    if (waiting == 0) return const SizedBox.shrink();

    final MaterialColor color = online ? Colors.blue : Colors.orange;
    final IconData icon = online ? Icons.sync_rounded : Icons.cloud_off_rounded;
    final String title = online
        ? 'syncing_count'.trParams({'count': '$waiting'})
        : 'pending_sync_count'.trParams({'count': '$waiting'});
    final String? detail = online ? null : 'offline_sync_hint'.tr;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppUi.tint(context, color),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppUi.accent(context, color)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppUi.accent(context, color),
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppUi.body(context).withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Month selector — a segmented pill instead of a stock tab strip, so it reads
/// as a filter over the card below rather than as page navigation.
/// ---------------------------------------------------------------------------

class _MonthSwitcher extends StatelessWidget implements PreferredSizeWidget {
  const _MonthSwitcher();

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ExpenseController>(
      builder: (controller) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppUi.neutralSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppUi.hairline(context)),
          ),
          child: Row(
            children: [
              _segment(context, controller, 0, 'current_month'.tr),
              _segment(context, controller, 1, 'next_month'.tr),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    ExpenseController controller,
    int index,
    String label,
  ) {
    final bool selected = controller.selectedMonthIndex == index;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.setMonthIndex(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withOpacity(0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : AppUi.muted(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// The meal / others split, drawn as one bar so the proportion is readable at
/// a glance instead of having to compare two numbers.
/// ---------------------------------------------------------------------------

class _SplitBar extends StatelessWidget {
  final double meal;
  final double others;

  const _SplitBar({required this.meal, required this.others});

  @override
  Widget build(BuildContext context) {
    final double total = meal + others;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 8,
        child: total <= 0
            ? Container(color: Colors.white.withOpacity(0.22))
            : Row(
                children: [
                  Expanded(
                    flex: (meal * 1000).round().clamp(0, 1000000),
                    child: Container(color: Colors.white.withOpacity(0.95)),
                  ),
                  if (meal > 0 && others > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: (others * 1000).round().clamp(0, 1000000),
                    child: Container(color: Colors.white.withOpacity(0.45)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Loading placeholders — the shape of the content beats a centered spinner.
/// ---------------------------------------------------------------------------

class _Pulse extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final bool onDark;

  const _Pulse({
    this.width,
    this.height = 14,
    this.radius = 8,
    this.onDark = false,
  });

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
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
    final Color base =
        widget.onDark || AppUi.isDark(context) ? Colors.white : Colors.black;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 0.75).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withOpacity(widget.onDark ? 0.28 : 0.10),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          for (int group = 0; group < 2; group++) ...[
            Row(
              children: [
                const _Pulse(width: 96, height: 26, radius: 20),
                const SizedBox(width: 12),
                Expanded(child: Divider(color: AppUi.hairline(context))),
                const SizedBox(width: 12),
                const _Pulse(width: 54, height: 14),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppUi.hairline(context)),
              ),
              child: const Column(
                children: [
                  _SkeletonRow(),
                  SizedBox(height: 22),
                  _SkeletonRow(),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Pulse(width: 40, height: 40, radius: 13),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Pulse(height: 14),
              SizedBox(height: 8),
              _Pulse(width: 110, height: 10),
            ],
          ),
        ),
        SizedBox(width: 12),
        _Pulse(width: 58, height: 14),
      ],
    );
  }
}
