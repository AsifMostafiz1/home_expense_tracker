import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The profile page's shape while the account is being read.
///
/// Traced from the real layout — avatar, name, phone, the three stat cards,
/// then the two sections of rows — so nothing jumps when the data lands.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const Center(child: ShimmerBox(height: 100, circle: true)),
          const SizedBox(height: 18),
          const Center(child: ShimmerBox(width: 150, height: 18)),
          const SizedBox(height: 10),
          const Center(child: ShimmerBox(width: 110, height: 12)),
          const SizedBox(height: 32),
          const Row(
            children: [
              Expanded(child: ShimmerBox(height: 82, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 82, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 82, radius: 16)),
            ],
          ),
          const SizedBox(height: 32),
          const ShimmerBox(width: 60, height: 11),
          const SizedBox(height: 12),
          const ShimmerBox(height: 78, radius: 20),
          const SizedBox(height: 24),
          const ShimmerBox(width: 80, height: 11),
          const SizedBox(height: 12),
          const ShimmerBox(height: 300, radius: 20),
        ],
      ),
    );
  }
}
