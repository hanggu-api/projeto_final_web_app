import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_drawer.dart';
import 'app_bottom_nav.dart';
import '../services/api_service.dart';
import '../services/client_tracking_service.dart';

class ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;

  const ScaffoldWithNavBar({required this.child, super.key});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  String? _role;
  bool _isMedical = false;
  bool _restoreChecked = false;
  int _restoreAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _restoreActiveTrackingIfNeeded() async {
    if (_restoreChecked || !mounted) return;

    final location = GoRouterState.of(context).uri.toString();
    final isClient = !(_role == 'provider' || _role == 'driver');
    if (!isClient) return;
    if (!location.startsWith('/home') && !location.startsWith('/login')) return;

    final activeServiceId =
        await ClientTrackingService.activeServiceIdForCurrentSession();
    if (!mounted) return;
    if (activeServiceId == null || activeServiceId.trim().isEmpty) {
      // No reload web, auth/session pode hidratar alguns instantes depois.
      // Repetimos algumas tentativas antes de desistir.
      _restoreAttempts++;
      if (_restoreAttempts < 18) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted || _restoreChecked) return;
          _restoreActiveTrackingIfNeeded();
        });
      } else {
        _restoreChecked = true;
      }
      return;
    }
    _restoreChecked = true;

    Future.microtask(() {
      if (!mounted) return;
      context.go('/service-tracking/$activeServiceId');
    });
  }

  /// Carrega role e is_medical do SharedPreferences
  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final api = ApiService();
    if (mounted) {
      setState(() {
        _role = api.role ?? prefs.getString('user_role');
        _isMedical = api.isMedical || (prefs.getBool('is_medical') ?? false);
      });
      debugPrint(
        '🔄 [ScaffoldWithNavBar] Role carregado: $_role, Medical: $_isMedical',
      );
      unawaited(_restoreActiveTrackingIfNeeded());
    }
  }

  /// Calcula qual aba deve estar selecionada baseado na rota atual
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    final isProvider = _role == 'provider' || _role == 'driver';

    if (isProvider) {
      if (location.startsWith('/provider-home') ||
          location.startsWith('/medical-home')) {
        return 0;
      }
      if (location.startsWith('/chats')) {
        return 1;
      }
      if (location.startsWith('/my-provider-profile') ||
          location.startsWith('/driver-settings') ||
          location.startsWith('/provider-settings') ||
          location.startsWith('/client-settings')) {
        return 2;
      }
    } else {
      if (location.startsWith('/home')) {
        return 0;
      }
      if (location.startsWith('/tracking')) {
        return 0;
      }
      if (location.startsWith('/service-tracking')) {
        return 0;
      }
      if (location.startsWith('/service-busca-prestador-movel')) {
        return 0;
      }
      if (location.startsWith('/chats')) {
        return 1;
      }
      if (location.startsWith('/client-settings')) {
        return 2;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _role == 'provider' || _role == 'driver';
    final String location = GoRouterState.of(context).uri.toString();
    final bool hideBottomNav =
        location.startsWith('/servicos') ||
        location.startsWith('/provider-profile') ||
        location.startsWith('/service-tracking') ||
        location.startsWith('/service-busca-prestador-movel') ||
        location.startsWith('/provider-active') ||
        location.startsWith('/provider-service-finish');

    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: !hideBottomNav,
      drawer: const AppDrawer(),
      body: widget.child,
      bottomNavigationBar: hideBottomNav
          ? null
          : AppBottomNav(
              currentIndex: _calculateSelectedIndex(context),
              isProvider: isProvider,
            ),
    );
  }
}
