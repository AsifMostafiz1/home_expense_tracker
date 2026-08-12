import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// ---------------------------------------------------------------------------
/// Loading placeholders for the monthly statistics section.
///
/// Each one traces the screen it stands in for — same block sizes, same
/// rhythm — so the page does not jump when the real content lands. A centred
/// spinner would tell the user to wait; these tell them what they are waiting
/// for.
/// ---------------------------------------------------------------------------

/// The months list: header, this-month card, then saved-month rows.
class MonthlyStatsSkeleton extends StatelessWidget {
  const MonthlyStatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 42, height: 42, radius: 14),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 120, height: 15),
                    SizedBox(height: 9),
                    ShimmerBox(height: 10),
                    SizedBox(height: 6),
                    ShimmerBox(width: 190, height: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const ShimmerBox(height: 196, radius: 24),
          const SizedBox(height: 28),
          const ShimmerBox(width: 110, height: 11),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            const ShimmerBox(height: 70, radius: 20),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// The month breakdown: totals card, rates card, then a card per member.
class MonthDetailsSkeleton extends StatelessWidget {
  const MonthDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          const ShimmerBox(height: 152, radius: 24),
          const SizedBox(height: 14),
          const ShimmerBox(height: 148, radius: 20),
          const SizedBox(height: 24),
          const ShimmerBox(width: 130, height: 11),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            const ShimmerBox(height: 156, radius: 20),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          const ShimmerBox(height: 76, radius: 18),
        ],
      ),
    );
  }
}

/// The rent split inside the bill form, while the members are still loading.
class MemberSplitSkeleton extends StatelessWidget {
  const MemberSplitSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == 2 ? 0 : 10),
              child: const Row(
                children: [
                  ShimmerBox(height: 38, circle: true),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 120, height: 13),
                        SizedBox(height: 7),
                        ShimmerBox(width: 84, height: 10),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  ShimmerBox(width: 112, height: 42, radius: 12),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
