import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ServiceCard extends StatelessWidget {
  final String status;
  final String providerName;
  final String distance;
  final String category;

  const ServiceCard({
    super.key,
    required this.status,
    required this.providerName,
    required this.distance,
    required this.category,
  });

  Color _getStatusColor() {
    switch (status) {
      case 'accepted': return Colors.blue;
      case 'inProgress': return Colors.orange;
      case 'completed': return AppTheme.successGreen;
      default: return Colors.grey;
    }
  }

  String _getStatusText() {
    switch (status) {
      case 'accepted': return 'Aceito';
      case 'inProgress': return 'Em andamento';
      case 'completed': return 'Concluído';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(),
                  ),
                ),
              ),
              Icon(LucideIcons.moreHorizontal, size: 20, color: Colors.grey[400]),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            category,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  providerName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                distance,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
