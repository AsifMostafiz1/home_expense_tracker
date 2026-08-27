import 'package:flutter/material.dart';

import '../../../common/widgets/shimmer_loading.dart';

/// The gallery's shape while its first page is on the way.
///
/// Laid out to the same grid the pictures land in, so nothing shifts when
/// they arrive — the tiles simply stop shimmering and start being photos.
class ChatMediaSkeleton extends StatelessWidget {
  const ChatMediaSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: ShimmerBox(width: 108, height: 13, radius: 7),
          ),
          _grid(6),
          const Padding(
            padding: EdgeInsets.only(left: 4, top: 24, bottom: 12),
            child: ShimmerBox(width: 76, height: 13, radius: 7),
          ),
          _grid(3),
        ],
      ),
    );
  }

  Widget _grid(int count) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: count,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (_, __) => const ShimmerBox(height: 120, radius: 14),
    );
  }
}
