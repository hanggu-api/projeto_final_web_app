import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class TrackingProviderJourneyCard extends StatelessWidget {
  final String providerName;
  final String categoryName;
  final String? providerEtaLabel;
  final bool isCompletedStatus;
  final Widget chatAction;

  const TrackingProviderJourneyCard({
    super.key,
    required this.providerName,
    required this.categoryName,
    required this.providerEtaLabel,
    required this.isCompletedStatus,
    required this.chatAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.user),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  providerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  categoryName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if ((providerEtaLabel ?? '').trim().isNotEmpty)
                  Text(
                    providerEtaLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (!isCompletedStatus) ...[const SizedBox(width: 10), chatAction],
        ],
      ),
    );
  }
}
