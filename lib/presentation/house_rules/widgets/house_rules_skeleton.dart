import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The rules page's shape while the first snapshot is on its way.
class HouseRulesSkeleton extends StatelessWidget {
  const HouseRulesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: const [
          ShimmerBox(height: 86, radius: 20),
          SizedBox(height: 18),
          ShimmerBox(height: 78, radius: 18),
          SizedBox(height: 12),
          ShimmerBox(height: 78, radius: 18),
          SizedBox(height: 12),
          ShimmerBox(height: 78, radius: 18),
          SizedBox(height: 12),
          ShimmerBox(height: 78, radius: 18),
        ],
      ),
    );
  }
}
