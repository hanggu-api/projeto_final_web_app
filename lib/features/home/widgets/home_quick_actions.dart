import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import 'home_suggestion_card.dart';

class HomeQuickActions extends StatelessWidget {
  final VoidCallback onTripTap;
  final VoidCallback onServiceTap;
  final VoidCallback onDeliveryTap;

  const HomeQuickActions({
    super.key,
    required this.onTripTap,
    required this.onServiceTap,
    required this.onDeliveryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          HomeSuggestionCard(
            label: 'Viagem',
            color: AppTheme.primaryYellow,
            onTap: onTripTap,
            isBig: true,
            customIcons: const ['assets/icons/036-car.png', 'assets/icons/034-motorbike.png'],
          ),
          HomeSuggestionCard(
            label: 'Serviço',
            icon: LucideIcons.wrench,
            color: const Color(0xFFF3F4F6),
            onTap: onServiceTap,
          ),
          HomeSuggestionCard(
            label: 'Entrega',
            icon: LucideIcons.package,
            color: const Color(0xFFF3F4F6),
            onTap: onDeliveryTap,
          ),
        ],
      ),
    );
  }
}
