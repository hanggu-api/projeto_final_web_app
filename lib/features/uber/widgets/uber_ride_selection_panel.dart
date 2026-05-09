import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/uber_service.dart';

class UberRideSelectionPanel extends StatefulWidget {
  final Map<int, Map<String, dynamic>> vehicleFares;
  final int selectedVehicleId;
  final String selectedPaymentMethod;
  final bool isPaymentExpanded;
  final bool isLoading;
  final List<dynamic> predefinedVehicles;
  final List<dynamic> savedCards;
  final ValueChanged<int> onRequestRide;
  final ValueChanged<int> onVehicleSelected;
  final VoidCallback onTogglePaymentExpanded;
  final ValueChanged<String> onPaymentMethodSelected;
  final UberService uberService;
  final bool hasDriversWithCardMachine;

  const UberRideSelectionPanel({
    super.key,
    required this.vehicleFares,
    required this.selectedVehicleId,
    required this.selectedPaymentMethod,
    required this.isPaymentExpanded,
    required this.isLoading,
    required this.predefinedVehicles,
    required this.savedCards,
    required this.onRequestRide,
    required this.onVehicleSelected,
    required this.onTogglePaymentExpanded,
    required this.onPaymentMethodSelected,
    required this.uberService,
    required this.hasDriversWithCardMachine,
  });

  @override
  State<UberRideSelectionPanel> createState() => _UberRideSelectionPanelState();
}

class _UberRideSelectionPanelState extends State<UberRideSelectionPanel> {
  Future<void> _openPaymentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Forma de pagamento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('PIX'),
                  onTap: () {
                    widget.onPaymentMethodSelected('PIX');
                    Navigator.of(ctx).pop();
                  },
                ),
                ListTile(
                  title: const Text('Cartão (No app)'),
                  onTap: () {
                    widget.onPaymentMethodSelected('CARD_IN_APP');
                    Navigator.of(ctx).pop();
                    if (widget.savedCards.isEmpty && mounted) {
                      context.push('/payment-methods');
                    }
                  },
                ),
                ListTile(
                  title: const Text('Cartão (Direto com Motorista)'),
                  subtitle: widget.hasDriversWithCardMachine
                      ? null
                      : const Text('Indisponível no momento'),
                  enabled: widget.hasDriversWithCardMachine,
                  onTap: widget.hasDriversWithCardMachine
                      ? () {
                          widget.onPaymentMethodSelected('CARD_WITH_DRIVER');
                          Navigator.of(ctx).pop();
                        }
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Pagamento')),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _openPaymentSheet,
            ),
          ],
        ),
      ],
    );
  }
}
