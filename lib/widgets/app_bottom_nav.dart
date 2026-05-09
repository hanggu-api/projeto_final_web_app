import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/realtime_service.dart';
import '../services/api_service.dart';

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
  String? _myUserId;
  void Function(dynamic)? _chatMessageHandler;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final api = ApiService();
      // Prioriza papel do ApiService (fonte da verdade em tempo real)
      if (mounted) {
        setState(() {
          _role = api.role ?? prefs.getString('user_role');
          _isMedical = api.isMedical || (prefs.getBool('is_medical') ?? false);
          _unread = prefs.getInt('unread_chat_count') ?? 0;
          _myUserId = _normalizeUserId(api.userId ?? prefs.get('user_id'));
        });
      }

      final rt = RealtimeService();
      rt.connect();

      if (_myUserId != null) {
        rt.authenticate(_myUserId!);
      }

      void handleNewMessage(dynamic data) async {
        final senderId = data is Map ? data['sender_id'] : null;
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

      _chatMessageHandler = handleNewMessage;
      rt.on('chat.message', handleNewMessage);
      rt.on('chat_message', handleNewMessage);

    });
  }

  String? _normalizeUserId(Object? userId) => userId?.toString();

  @override
  void dispose() {
    final handler = _chatMessageHandler;
    if (handler != null) {
      final rt = RealtimeService();
      rt.off('chat.message', handler);
      rt.off('chat_message', handler);
    }
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final isProvider =
        widget.isProvider ?? (_role == 'provider' || _role == 'driver');

    // Stitch inspired items - Consolidating to 5 tabs for Client as per harmonized designs
    final items = isProvider
        ? [
            _NavData(label: 'Início', icon: LucideIcons.home),
            _NavData(
              label: 'Chat',
              icon: LucideIcons.messageSquare,
              isBadge: true,
            ),
            _NavData(
              label: 'Perfil',
              icon: _role == 'driver' ? LucideIcons.user : Icons.person_rounded,
            ),
          ]
        : [
            _NavData(label: 'Início', icon: LucideIcons.home),
            _NavData(
              label: 'Chat',
              icon: LucideIcons.messageSquare,
              isBadge: true,
            ),
            _NavData(label: 'Perfil', icon: LucideIcons.user),
          ];

    final safeIndex = (widget.currentIndex < 0)
        ? 0
        : (widget.currentIndex >= items.length
              ? items.length - 1
              : widget.currentIndex);

    final List<Widget> navWidgets = items.asMap().entries.map((entry) {
      final idx = entry.key;
      final data = entry.value;
      final isSelected = idx == safeIndex;

      final color = isSelected
          ? const Color(0xFF09111F)
          : const Color(0xFF09111F).withOpacity(0.42);

      final bgColor = isSelected
          ? const Color(0xFFE8F0FF)
          : Colors.transparent;

      return Expanded(
        child: GestureDetector(
          onTap: () => _onTap(idx, isProvider),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: _buildIcon(data, color, isSelected),
          ),
        ),
      );
    }).toList();

    final media = MediaQuery.of(context);
    final bottomInset = media.viewPadding.bottom;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      minimum: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF).withOpacity(0.94),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white.withOpacity(0.9)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF09111F).withOpacity(0.18),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: navWidgets,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(_NavData data, Color color, bool isSelected) {
    Widget icon = Icon(data.icon, color: color, size: 24);

    if (data.isBadge && _unread > 0) {
      return Badge(
        label: Text(
          '$_unread',
          style: const TextStyle(fontSize: 10, color: Colors.white),
        ),
        backgroundColor: Colors.red,
        child: icon,
      );
    }
    return icon;
  }

  void _onTap(int idx, bool isProvider) {
    if (isProvider) {
      switch (idx) {
        case 0:
          final api = ApiService();
          if (api.isMedical || _isMedical) {
            context.go('/medical-home');
          } else {
            context.go('/provider-home');
          }
          break;
        case 1:
          context.go('/chats');
          break;
        case 2:
          // Abrir o menu drawer (menu hamburger) em vez de navegar para perfil
          Scaffold.of(context).openDrawer();
          break;
      }
    } else {
      switch (idx) {
        case 0:
          context.go('/home');
          break;
        case 1:
          context.go('/chats');
          break;
        case 2:
          // Abrir o menu drawer (menu hamburger) em vez de navegar para perfil
          Scaffold.of(context).openDrawer();
          break;
      }
    }
  }
}

class _NavData {
  final String label;
  final IconData icon;
  final bool isBadge;

  _NavData({required this.label, required this.icon, this.isBadge = false});
}
