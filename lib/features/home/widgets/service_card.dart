import 'package:flutter/material.dart';

import '../../../core/utils/fixed_schedule_gate.dart';
import 'mobile_service_card.dart';
import 'fixed_service_card.dart';

/// SMART WRAPPER PARA O SERVICE CARD
/// Decidirá qual componente renderizar (Fixed vs Mobile) baseado no `location_type`.
class ServiceCard extends StatelessWidget {
  final String status;
  final String providerName;
  final String distance;
  final String category;
  final Map<String, dynamic>? details;
  final ValueChanged<bool>? onExpandChange;
  final bool? expanded;
  final bool showExpandIcon;
  final VoidCallback? onCancel;
  final VoidCallback? onTrack;
  final VoidCallback? onArrived;
  final VoidCallback? onPay;
  final VoidCallback? onRate;
  final VoidCallback? onRefreshNeeded;
  final bool isProviderView;
  final String? serviceId;

  const ServiceCard({
    super.key,
    required this.status,
    required this.providerName,
    required this.distance,
    required this.category,
    this.details,
    this.onExpandChange,
    this.expanded,
    this.onCancel,
    this.onTrack,
    this.onArrived,
    this.onPay,
    this.onRate,
    this.onRefreshNeeded,
    this.showExpandIcon = true,
    this.isProviderView = false,
    this.serviceId,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFixed =
        details != null && isCanonicalFixedServiceRecord(details!);

    if (isFixed) {
      return FixedServiceCard(
        status: status,
        providerName: providerName,
        category: category,
        details: details,
        onExpandChange: onExpandChange,
        expanded: expanded,
        showExpandIcon: showExpandIcon,
        onCancel: onCancel,
        onArrived: onArrived,
        onPay: onPay,
        onRate: onRate,
        onRefreshNeeded: onRefreshNeeded,
        isProviderView: isProviderView,
        serviceId: serviceId,
      );
    } else {
      return MobileServiceCard(
        status: status,
        providerName: providerName,
        distance: distance,
        category: category,
        details: details,
        onExpandChange: onExpandChange,
        expanded: expanded,
        showExpandIcon: showExpandIcon,
        onCancel: onCancel,
        onTrack: onTrack,
        onArrived: onArrived,
        onPay: onPay,
        onRate: onRate,
        onRefreshNeeded: onRefreshNeeded,
        isProviderView: isProviderView,
        serviceId: serviceId,
      );
    }
  }
}
