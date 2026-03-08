import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_bottom_nav.dart';
import '../services/theme_service.dart';

class ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;

  const ScaffoldWithNavBar({required this.child, super.key});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  final GlobalKey _navBarKey = GlobalKey();
  double _navBarHeight = 100.0;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  void _updateHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? renderBox =
          _navBarKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final newHeight = renderBox.size.height + 32;
        if ((_navBarHeight - newHeight).abs() > 1.0) {
          setState(() {
            _navBarHeight = newHeight;
          });
        }
      }
    });
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _role = prefs.getString('user_role');
      });
    }
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    final isProvider = _role == 'provider' || _role == 'driver';

    if (isProvider) {
      if (location.startsWith('/provider-home') ||
          location.startsWith('/medical-home')) {
        return 0;
      }
      if (location.startsWith('/uber-driver-earnings')) {
        return 1;
      }
      if (location.startsWith('/activity')) {
        return 2;
      }
      if (location.startsWith('/client-settings') ||
          location.startsWith('/my-provider-profile')) {
        return 3;
      }
    } else {
      if (location.startsWith('/home') ||
          location.startsWith('/tracking') ||
          location.startsWith('/uber-request')) {
        return 0;
      }
      if (location.startsWith('/chats') || location.startsWith('/chat/')) {
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
    final String location = GoRouterState.of(context).uri.toString();
    final bool isTripRoute =
        location.startsWith('/uber-tracking') ||
        location.startsWith('/uber-driver-trip');

    return Scaffold(
      extendBody: true, // Garante que o conteúdo vá até o fundo real da tela
      body: Stack(
        children: [
          // Conteúdo Principal
          widget.child,

          // Barra de Navegação Flutuante (Estilo Stitch)
          Positioned(
            key: _navBarKey,
            left: 16,
            right: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: ListenableBuilder(
              listenable: ThemeService(),
              builder: (context, child) {
                _updateHeight();

                // Oculta se o ThemeService mandar ou se estiver em uma rota de viagem
                final isVisible =
                    ThemeService().isNavBarVisible && !isTripRoute;

                return AnimatedSlide(
                  duration: const Duration(milliseconds: 400),
                  offset: isVisible ? Offset.zero : const Offset(0, 1.5),
                  curve: Curves.easeInOut,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isVisible ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !isVisible,
                      child: AppBottomNav(
                        currentIndex: _calculateSelectedIndex(context),
                        isProvider: _role == 'provider' || _role == 'driver',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
