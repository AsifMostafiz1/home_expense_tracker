import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The money tab's shape while the first snapshot is on its way.
class PersonalMoneySkeleton extends StatelessWidget {
  const PersonalMoneySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: const [
          ShimmerBox(height: 108, radius: 22),
          SizedBox(height: 14),
          ShimmerBox(height: 190, radius: 20),
          SizedBox(height: 14),
          ShimmerBox(height: 160, radius: 20),
          SizedBox(height: 18),
          ShimmerBox(width: 120, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 72, radius: 18),
          SizedBox(height: 10),
          ShimmerBox(height: 72, radius: 18),
        ],
      ),
    );
  }
}

/// The dues tab's shape.
class PersonalDebtSkeleton extends StatelessWidget {
  const PersonalDebtSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: const [
          ShimmerBox(height: 96, radius: 22),
          SizedBox(height: 18),
          ShimmerBox(height: 76, radius: 18),
          SizedBox(height: 10),
          ShimmerBox(height: 76, radius: 18),
          SizedBox(height: 10),
          ShimmerBox(height: 76, radius: 18),
        ],
      ),
    );
  }
}
