import 'package:flutter/material.dart';

import 'fixed_booking_provider_selection_card.dart';

class FixedBookingProviderSelectionItem {
  final String providerName;
  final String providerAddress;
  final String distanceLabel;
  final String nextSlotLabel;
  final String serviceLabel;
  final double selectedPrice;
  final String? avatarUrl;
  final bool isSelected;
  final VoidCallback onTap;

  const FixedBookingProviderSelectionItem({
    required this.providerName,
    required this.providerAddress,
    required this.distanceLabel,
    required this.nextSlotLabel,
    required this.serviceLabel,
    required this.selectedPrice,
    required this.avatarUrl,
    required this.isSelected,
    required this.onTap,
  });
}

class FixedBookingProviderSelectionStep extends StatelessWidget {
  final String serviceQuery;
  final bool loadingProviders;
  final List<FixedBookingProviderSelectionItem> items;

  const FixedBookingProviderSelectionStep({
    super.key,
    required this.serviceQuery,
    required this.loadingProviders,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estética e Beleza',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Salões próximos para $serviceQuery, ordenados por distância e próximo horário disponível.',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        if (loadingProviders)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          const Expanded(
            child: Center(
              child: Text('Nenhum prestador encontrado para esta categoria.'),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return FixedBookingProviderSelectionCard(
                  isSelected: item.isSelected,
                  providerName: item.providerName,
                  providerAddress: item.providerAddress,
                  distanceLabel: item.distanceLabel,
                  nextSlotLabel: item.nextSlotLabel,
                  serviceLabel: item.serviceLabel,
                  selectedPrice: item.selectedPrice,
                  avatarUrl: item.avatarUrl,
                  onTap: item.onTap,
                );
              },
            ),
          ),
      ],
    );
  }
}
