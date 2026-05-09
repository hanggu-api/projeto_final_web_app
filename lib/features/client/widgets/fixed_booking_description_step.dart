import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class FixedBookingDescriptionStep extends StatelessWidget {
  final ScrollController? scrollController;
  final Widget searchBar;
  final bool hasQuery;
  final bool compactResultsLayout;
  final bool showInitialLoadingState;
  final bool showEmptyState;
  final String providerSearchMessage;
  final String providerSearchDetail;
  final List<Widget> providerCards;
  final bool loadingMoreProviders;
  final Widget? paymentInfoCard;

  const FixedBookingDescriptionStep({
    super.key,
    required this.scrollController,
    required this.searchBar,
    required this.hasQuery,
    required this.compactResultsLayout,
    required this.showInitialLoadingState,
    required this.showEmptyState,
    required this.providerSearchMessage,
    required this.providerSearchDetail,
    required this.providerCards,
    required this.loadingMoreProviders,
    required this.paymentInfoCard,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'O que você precisa hoje?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          searchBar,
          SizedBox(height: compactResultsLayout ? 12 : 16),
          if (!compactResultsLayout) ...[
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            const Text(
              'Salões próximos com horário livre',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Toque em um salão para escolher o horário do serviço.'
                  : 'Digite o serviço desejado para buscar salões parceiros próximos.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],
          if (showInitialLoadingState)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    providerSearchMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.darkBlueText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    providerSearchDetail,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (!hasQuery)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Exemplos: barba completa, corte feminino, manicure, limpeza de pele.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            )
          else if (showEmptyState)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    providerSearchMessage.isNotEmpty
                        ? providerSearchMessage
                        : 'Nenhum salão parceiro foi encontrado para este serviço.',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (providerSearchDetail.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      providerSearchDetail,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else ...[
            ...providerCards,
            if (loadingMoreProviders)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        providerSearchMessage.isNotEmpty
                            ? providerSearchMessage
                            : 'Consultando agenda dos próximos prestadores...',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (paymentInfoCard != null) ...[
            const SizedBox(height: 20),
            paymentInfoCard!,
          ],
        ],
      ),
    );
  }
}
