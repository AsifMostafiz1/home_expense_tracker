import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The task list's shape while the first snapshot is on its way.
class TaskSkeleton extends StatelessWidget {
  const TaskSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: const [
          ShimmerBox(height: 140, radius: 24),
          SizedBox(height: 16),
          ShimmerBox(height: 46, radius: 14),
          SizedBox(height: 20),
          ShimmerBox(width: 110, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 74, radius: 18),
          SizedBox(height: 10),
          ShimmerBox(height: 74, radius: 18),
          SizedBox(height: 10),
          ShimmerBox(height: 74, radius: 18),
          SizedBox(height: 22),
          ShimmerBox(width: 90, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 74, radius: 18),
        ],
      ),
    );
  }
}
