import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The settings page's shape while the config document is read.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: const [
          ShimmerBox(height: 96, radius: 20),
          SizedBox(height: 18),
          ShimmerBox(width: 110, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 220, radius: 20),
          SizedBox(height: 18),
          ShimmerBox(width: 160, height: 11),
        ],
      ),
    );
  }
}
