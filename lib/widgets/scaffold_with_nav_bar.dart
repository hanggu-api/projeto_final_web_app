import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_bottom_nav.dart';

class ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;

  const ScaffoldWithNavBar({required this.child, super.key});

  @override
  State<ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<ScaffoldWithNavBar> {
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
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
    final isProvider = _role == 'provider';

    if (isProvider) {
      if (location.startsWith('/provider-home') ||
          location.startsWith('/medical-home')) {
        return 0;
      }
      if (location.startsWith('/chats')) {
        return 1;
      }
      if (location.startsWith('/provider-profile') || location.startsWith('/my-provider-profile')) {
        return 2;
      }
      if (location.startsWith('/client-settings')) {
        return 3;
      } // Provider usa client-settings ou tem settings proprias?
      // O AppBottomNav provider tem: Home, Chat, Perfil, Configurações.
      // Configurações pode ser client-settings ou outra rota?
      // No AppBottomNav original:
      // case 3: context.push('/client-settings'); (Sim, usa client-settings)
    } else {
      if (location.startsWith('/home')) {
        return 0;
      }
      if (location.startsWith('/tracking')) {
        return 0;
      } // Tracking mantém Home ativa
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
    return Scaffold(
      extendBody: true, // Garante que o conteúdo vá até o fundo real da tela
      body: Stack(
        children: [
          // Conteúdo Principal
          widget.child,
          
          // Barra de Navegação Flutuante
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: AppBottomNav(
              currentIndex: _calculateSelectedIndex(context),
              isProvider: _role == 'provider',
            ),
          ),
        ],
      ),
    );
  }
}
