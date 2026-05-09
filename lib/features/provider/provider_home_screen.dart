import 'package:flutter/material.dart';

import '../../core/home/backend_home_api.dart';
import '../../services/api_service.dart';
import 'driver_home_remote_screen.dart';
import 'provider_home_fixed.dart';
// import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isBootstrappingProfile = false;
  final _api = ApiService();
  final _backendHomeApi = const BackendHomeApi();

  @override
  void initState() {
    super.initState();
    _isFixedLocation = _api.isFixedLocation;
    if (widget.loadOnInit) {
      _isBootstrappingProfile = true;
      _checkProfile();
    }
  }

  Future<void> _checkProfile() async {
    try {
      await _api.loadToken();
      final backendHome = await _backendHomeApi.fetchProviderHome();
      if (backendHome != null) {
        final profileSnapshot = <String, dynamic>{
          'id': backendHome.userId,
          'role': backendHome.role,
          'is_medical': backendHome.isMedical,
          'is_fixed_location': backendHome.isFixedLocation,
          'sub_role': backendHome.subRole,
        };
        await _api.applyBackendProfileSnapshot(profileSnapshot);
      } else {
        throw Exception('Snapshot canônico da home do prestador indisponível.');
      }
      debugPrint(
        '🪪 [ProviderHomeScreen] profile bootstrap resolved '
        'userId=${_api.userId ?? "-"} role=${_api.role ?? "-"} '
        'isFixedLocation=${_api.isFixedLocation}',
      );
      if (mounted) {
        setState(() {
          _isFixedLocation = _api.isFixedLocation;
          _isBootstrappingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [ProviderHomeScreen] profile bootstrap failed: $e');
      if (mounted) {
        setState(() {
          _isFixedLocation = _api.isFixedLocation;
          _isBootstrappingProfile = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrappingProfile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isFixedLocation) {
      return const ProviderHomeFixed();
    }

    return DriverHomeRemoteScreen(
      loadOnInit: widget.loadOnInit,
      connectRealtime: widget.connectRealtime,
      initialAvailableServices: widget.initialAvailableServices,
      initialMyServices: widget.initialMyServices,
    );
  }
}
