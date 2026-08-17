import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The edit history's shape while the log is being read: a day header, then
/// a rail of dots beside cards — traced from the real timeline so nothing
/// jumps when the entries land.
class EditHistorySkeleton extends StatelessWidget {
  const EditHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const ShimmerBox(width: 96, height: 26, radius: 20),
          const SizedBox(height: 14),
          for (int i = 0; i < 2; i++) ...[
            _entry(),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          const ShimmerBox(width: 130, height: 26, radius: 20),
          const SizedBox(height: 14),
          for (int i = 0; i < 3; i++) ...[
            _entry(),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _entry() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShimmerBox(height: 40, circle: true),
        SizedBox(width: 14),
        Expanded(
          child: ShimmerBox(height: 128, radius: 18),
        ),
      ],
    );
  }
}
