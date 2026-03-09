import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'provider_home_fixed.dart';
import 'provider_home_mobile.dart';

class ProviderHomeScreen extends StatefulWidget {
  final bool loadOnInit;
  final bool connectRealtime;
  final List<dynamic>? initialAvailableServices;
  final List<dynamic>? initialMyServices;

  const ProviderHomeScreen({
    super.key,
    this.loadOnInit = true,
    this.connectRealtime = true,
    this.initialAvailableServices,
    this.initialMyServices,
  });

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> {
  bool _isFixedLocation = false;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    // Use cached value immediately for perceived performance
    _isFixedLocation = _api.isFixedLocation;
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final user = await _api.getMyProfile();
      if (mounted) {
        setState(() {
          _isFixedLocation = user['is_fixed_location'] == true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isFixedLocation) {
      return const ProviderHomeFixed();
    }

    return ProviderHomeMobile(
      loadOnInit: widget.loadOnInit,
      connectRealtime: widget.connectRealtime,
      initialAvailableServices: widget.initialAvailableServices,
      initialMyServices: widget.initialMyServices,
    );
  }
}
