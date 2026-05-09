import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'home_suggestion_card.dart';

class HomeQuickActions extends StatelessWidget {
  final VoidCallback onServiceTap;
  final VoidCallback onDeliveryTap;

  const HomeQuickActions({
    super.key,
    required this.onServiceTap,
    required this.onDeliveryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          HomeSuggestionCard(
            label: 'Serviço',
            icon: LucideIcons.wrench,
            // Leve destaque para diferenciar ação de "Serviço" e confirmar build atualizado.
            color: const Color(0xFFF3F4F6),
            onTap: onServiceTap,
          ),
          HomeSuggestionCard(
            label: 'Beleza',
            icon: LucideIcons.sparkles,
            color: const Color(0xFFF3F4F6),
            onTap: onDeliveryTap,
          ),
        ],
      ),
    );
  }
}
