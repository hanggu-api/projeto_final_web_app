import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/realtime_service.dart';
import '../core/theme/app_theme.dart';

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

      rt.on('chat.message', handleNewMessage);
      rt.on('chat_message', handleNewMessage);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = widget.isProvider ?? (_role == 'provider' || _role == 'driver');
    
    // Stitch inspired items - Consolidating to 5 tabs for Client as per harmonized designs
    final items = isProvider
        ? [
            _NavData(label: 'Início', icon: LucideIcons.home),
            _NavData(label: 'Ganhos', icon: LucideIcons.banknote),
            _NavData(label: 'Atividade', icon: LucideIcons.history),
            _NavData(label: 'Perfil', icon: LucideIcons.user),
          ]
        : [
            _NavData(label: 'Início', icon: LucideIcons.home),
            _NavData(label: 'Chat', icon: LucideIcons.messageSquare, isBadge: true),
            _NavData(label: 'Perfil', icon: LucideIcons.user),
          ];

    final safeIndex = (widget.currentIndex < 0)
        ? 0
        : (widget.currentIndex >= items.length
              ? items.length - 1
              : widget.currentIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95), 
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, -10),
          )
        ],
      ),
      padding: EdgeInsets.only(
        left: 20, 
        right: 20, 
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 10,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          final data = entry.value;
          final isSelected = idx == safeIndex;
          
          final color = isSelected 
              ? Colors.black // Preto para o selecionado
              : Colors.black.withValues(alpha: 0.4); // Preto suave para o não selecionado

          return Expanded(
            child: GestureDetector(
              onTap: () => _onTap(idx, isProvider),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(data, color, isSelected),
                  const SizedBox(height: 6),
                  Text(
                    data.label,
                    style: GoogleFonts.manrope(
                      color: color,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIcon(_NavData data, Color color, bool isSelected) {
    Widget icon = Icon(
      data.icon,
      color: color,
      size: 24,
    );

    if (data.isBadge && _unread > 0) {
      return Badge(
        label: Text('$_unread', style: const TextStyle(fontSize: 10, color: Colors.white)),
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
          context.go(_isMedical ? '/medical-home' : '/provider-home');
          break;
        case 1:
          context.go('/uber-driver-earnings');
          break;
        case 2:
          context.go('/activity'); 
          break;
        case 3:
          context.go('/client-settings'); // Ou perfil do motorista
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
          context.go('/client-settings');
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
