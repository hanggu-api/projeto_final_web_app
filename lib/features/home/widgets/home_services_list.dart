import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'service_card.dart';
import '../../../widgets/skeleton_loader.dart';

class HomeServicesList extends StatelessWidget {
  final bool isLoading;
  final List<dynamic> services;
  final VoidCallback onRefreshNeeded;

  const HomeServicesList({
    Key? key,
    required this.isLoading,
    required this.services,
    required this.onRefreshNeeded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Column(
        children: List.generate(
          2,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CardSkeleton(),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: services.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final service = services[index];
        return ServiceCard(
          key: ValueKey(service['id']?.toString() ?? index.toString()),
          status: service['status'] ?? 'pending',
          providerName: service['provider_name'] ?? 
                        service['providers']?['users']?['full_name'] ?? 
                        'Aguardando...',
          distance: '---',
          category: service['profession'] ?? 
                    service['category_name'] ?? 
                    service['description'] ?? 
                    'Serviço',
          details: service,
          onRefreshNeeded: onRefreshNeeded,
          onTrack: () {
            final id = service['id']?.toString();
            if (id != null) context.push('/tracking/$id');
          },
        );
      },
    );
  }
}
