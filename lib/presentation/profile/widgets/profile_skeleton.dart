import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The profile page's shape while the account is being read.
///
/// Traced from the real layout — avatar, name, phone, the three stat cards,
/// then the two sections of rows — so nothing jumps when the data lands.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // The real page's bar is a sliver inside its own scroll view, so there is
    // no app bar above this one — the toolbar and the status bar have to be
    // accounted for here, or the page jumps when the account lands.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top),
        Container(
          height: kToolbarHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'profile'.tr,
            style: TextStyle(
              color: Theme.of(context).textTheme.titleLarge?.color ??
                  Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  /// The figures come from [ProfileHeader]: same gaps, same line heights, so
  /// the avatar and the cards are already where the real header will put them
  /// when the account lands.
  Widget _body() {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: const [
          Center(child: ShimmerBox(height: 100, circle: true)),
          SizedBox(height: 16),
          SizedBox(
            height: 29.7,
            child: Center(child: ShimmerBox(width: 150, height: 20)),
          ),
          SizedBox(height: 4),
          SizedBox(
            height: 18.9,
            child: Center(child: ShimmerBox(width: 110, height: 13)),
          ),
          SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: ShimmerBox(height: 87.2, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 87.2, radius: 16)),
              SizedBox(width: 12),
              Expanded(child: ShimmerBox(height: 87.2, radius: 16)),
            ],
          ),
          SizedBox(height: 32),
          ShimmerBox(width: 60, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 78, radius: 20),
          SizedBox(height: 24),
          ShimmerBox(width: 80, height: 11),
          SizedBox(height: 12),
          ShimmerBox(height: 300, radius: 20),
        ],
      ),
    );
  }
}
