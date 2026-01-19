import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class BaseSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const BaseSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class CardSkeleton extends StatelessWidget {
  final double? height;
  final double? width;
  final BorderRadius? borderRadius;

  const CardSkeleton({
    super.key,
    this.height,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BaseSkeleton(width: 40, height: 40, borderRadius: BorderRadius.all(Radius.circular(20))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BaseSkeleton(width: 120, height: 16),
                    const SizedBox(height: 8),
                    const BaseSkeleton(width: 80, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const BaseSkeleton(width: double.infinity, height: 14),
          const SizedBox(height: 8),
          const BaseSkeleton(width: 200, height: 14),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BaseSkeleton(width: 100, height: 36),
            ],
          ),
        ],
      ),
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BaseSkeleton(width: 48, height: 48, borderRadius: BorderRadius.all(Radius.circular(24))),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BaseSkeleton(width: 150, height: 20),
            const SizedBox(height: 8),
            const BaseSkeleton(width: 100, height: 14),
          ],
        ),
      ],
    );
  }
}
