import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class FixedBookingProviderSelectionCard extends StatelessWidget {
  final bool isSelected;
  final String providerName;
  final String providerAddress;
  final String distanceLabel;
  final String nextSlotLabel;
  final String serviceLabel;
  final double selectedPrice;
  final String? avatarUrl;
  final VoidCallback onTap;

  const FixedBookingProviderSelectionCard({
    super.key,
    required this.isSelected,
    required this.providerName,
    required this.providerAddress,
    required this.distanceLabel,
    required this.nextSlotLabel,
    required this.serviceLabel,
    required this.selectedPrice,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
      elevation: 6,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? AppTheme.primaryYellow : Colors.grey.shade100,
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _ProviderAvatar(avatarUrl: avatarUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      providerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            providerAddress,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ProviderInfoChip(
                          icon: Icons.near_me_outlined,
                          label: distanceLabel,
                        ),
                        _ProviderInfoChip(
                          icon: Icons.schedule,
                          label: nextSlotLabel,
                        ),
                        _ProviderInfoChip(
                          icon: Icons.payments_outlined,
                          label:
                              '$serviceLabel • R\$ ${selectedPrice.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? Icons.check_circle : Icons.chevron_right,
                    color: isSelected
                        ? AppTheme.primaryYellow
                        : Colors.grey.shade400,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Agendar',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderAvatar extends StatelessWidget {
  final String? avatarUrl;

  const _ProviderAvatar({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 65,
      height: 65,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.grey[100],
        image: avatarUrl != null && avatarUrl!.trim().isNotEmpty
            ? DecorationImage(
                image: NetworkImage(avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: avatarUrl == null || avatarUrl!.trim().isEmpty
          ? const Icon(Icons.person, color: Colors.grey, size: 30)
          : null,
    );
  }
}

class _ProviderInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProviderInfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
