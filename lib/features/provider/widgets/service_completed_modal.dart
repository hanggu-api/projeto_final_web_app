import 'package:flutter/material.dart';

import '../../../services/api_service.dart';

class ServiceCompletedModal extends StatefulWidget {
  final String serviceId;
  final Map<String, dynamic>? initialData;

  const ServiceCompletedModal({
    super.key,
    required this.serviceId,
    this.initialData,
  });

  @override
  State<ServiceCompletedModal> createState() => _ServiceCompletedModalState();
}

class _ServiceCompletedModalState extends State<ServiceCompletedModal> {
  final _api = ApiService();
  Map<String, dynamic>? _serviceData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _serviceData = widget.initialData;
    if (_serviceData != null) {
      _isLoading = false;
    } else {
      _loadDetails();
    }
  }

  Future<void> _loadDetails() async {
    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _serviceData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Carregando informações...'),
            ],
          ),
        ),
      );
    }

    final s = _serviceData ?? {};
    final address = s['address'] ?? 'Endereço não disponível';
    final description = s['description'] ?? 'Serviço concluído';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Serviço Concluído',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(description, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              address,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
