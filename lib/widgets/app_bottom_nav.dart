import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/realtime_service.dart';

class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final bool? isProvider;
  const AppBottomNav({super.key, required this.currentIndex, this.isProvider});

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  String? _role;
  bool _isMedical = false;
  int _unread = 0;
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _role = prefs.getString('user_role');
      _isMedical = prefs.getBool('is_medical') ?? false;
      _unread = prefs.getInt('unread_chat_count') ?? 0;
      final userId = prefs.getInt('user_id');
      _myUserId = userId;
      if (mounted) setState(() {});

      final rt = RealtimeService();
      rt.connect();

      if (userId != null) {
        rt.authenticate(userId);
      }

      // Listen for new chat messages
      void handleNewMessage(dynamic data) async {
        final senderId = data is Map ? data['sender_id'] : null;
        // Don't count my own messages if they ever come back to me
        if (_myUserId != null &&
            senderId != null &&
            senderId.toString() == _myUserId.toString()) {
          return;
        }
        
        _unread += 1;
        final p = await SharedPreferences.getInstance();
        await p.setInt('unread_chat_count', _unread);
        if (mounted) setState(() {});
      }

      rt.on('chat.message', handleNewMessage);
      rt.on('chat_message', handleNewMessage);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.isProvider ?? (_role == 'provider');
    final items = isProvider
        ? [
            BottomNavigationBarItem(
              icon: const Icon(LucideIcons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(icon: _chatIcon(), label: 'Chat'),
            BottomNavigationBarItem(
              icon: const Icon(LucideIcons.user),
              label: 'Perfil',
            ),
            BottomNavigationBarItem(
              icon: const Icon(LucideIcons.settings),
              label: 'Configurações',
            ),
          ]
        : [
            BottomNavigationBarItem(
              icon: const Icon(LucideIcons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(icon: _chatIcon(), label: 'Chat'),
            BottomNavigationBarItem(
              icon: const Icon(LucideIcons.settings),
              label: 'Configurações',
            ),
          ];
    final safeIndex = (widget.currentIndex < 0)
        ? 0
        : (widget.currentIndex >= items.length
              ? items.length - 1
              : widget.currentIndex);
    return Container(
      height: 65,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final isSelected = idx == safeIndex;
          final color = isSelected 
              ? Theme.of(context).colorScheme.secondary 
              : Colors.grey.shade600;

          // Extrair o ícone real para pintá-lo corretamente
          Widget iconWidget = item.icon;
          if (iconWidget is Icon) {
             iconWidget = Icon(iconWidget.icon, color: color, size: isSelected ? 28 : 24);
          } else if (iconWidget is Badge) {
             // Caso seja o chatIcon com Badge
             final innerIcon = iconWidget.child as Icon;
             iconWidget = Badge(
               label: iconWidget.label,
               child: Icon(innerIcon.icon, color: color, size: isSelected ? 28 : 24),
             );
          }

          return GestureDetector(
            onTap: () {
              if (isProvider) {
                switch (idx) {
                  case 0:
                    context.go(_isMedical ? '/medical-home' : '/provider-home');
                    break;
                  case 1:
                    context.go('/chats');
                    break;
                  case 2:
                    context.go('/my-provider-profile');
                    break;
                  case 3:
                    context.go('/client-settings');
                    break;
                }
              } else {
                switch (idx) {
                  case 0:
                    // Se estiver no mapa, resetar. Mas via GoRouter, apenas garante a rota.
                    context.go('/home');
                    break;
                  case 1:
                    context.go('/chats');
                    break;
                  case 2:
                    context.go('/client-settings');
                    break;
                }
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
               padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
               child: AnimatedContainer(
                 duration: const Duration(milliseconds: 200),
                 curve: Curves.easeInOut,
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     iconWidget,
                     if (isSelected) ...[
                       const SizedBox(height: 4),
                       Text(
                         item.label ?? '',
                         style: TextStyle(
                           color: color,
                           fontSize: 10,
                           fontWeight: FontWeight.bold,
                         ),
                       )
                     ]
                   ],
                 ),
               ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _chatIcon() {
    if (_unread > 0) {
      return Badge(
        label: Text('$_unread'),
        child: const Icon(LucideIcons.messageSquare),
      );
    }
    return const Icon(LucideIcons.messageSquare);
  }
}
