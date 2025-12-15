import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/realtime_service.dart';

class AppTheme {
  static const Color primaryPurple = Color(0xFF6A35FF);
  static const Color secondaryOrange = Color(0xFFFF6B35);
  static const Color successGreen = Color(0xFF10B981);
  static const Color darkBackground = Color(0xFF111827); // Gray 900
  static const Color lightBackground = Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryPurple,
        primary: primaryPurple,
        secondary: secondaryOrange,
        surface: lightBackground,
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F4F6), // Gray 100
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryPurple,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  String? _role;
  int _unread = 0;
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      _role = prefs.getString('user_role');
      _unread = prefs.getInt('unread_chat_count') ?? 0;
      _myUserId = prefs.getInt('user_id');
      if (mounted) setState(() {});
      final rt = RealtimeService();
      rt.connect();
      rt.on('chat.message', (data) async {
        final senderId = data is Map<String, dynamic> ? data['sender_id'] : null;
        if (_myUserId != null && senderId != _myUserId) {
          _unread += 1;
          final p = await SharedPreferences.getInstance();
          await p.setInt('unread_chat_count', _unread);
          if (mounted) setState(() {});
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _role == 'provider';
    return BottomNavigationBar(
      selectedItemColor: AppTheme.primaryPurple,
      unselectedItemColor: Colors.grey,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      currentIndex: widget.currentIndex,
      onTap: (idx) async {
        if (idx == 0) {
          context.go(isProvider ? '/provider-home' : '/home');
        } else if (idx == 1) {
          final prefs = await SharedPreferences.getInstance();
          _unread = 0;
          await prefs.setInt('unread_chat_count', 0);
          if (!context.mounted) return;
          setState(() {});
          context.go('/chats');
        } else if (isProvider && idx == 2) {
          context.go('/provider-profile');
        } else if ((isProvider && idx == 3) || (!isProvider && idx == 2)) {
          context.go(isProvider ? '/provider-settings' : '/client-settings');
        }
      },
      items: isProvider
          ? [
              BottomNavigationBarItem(icon: const Icon(LucideIcons.home), label: 'Home'),
              BottomNavigationBarItem(icon: _chatIcon(), label: 'Chat'),
              BottomNavigationBarItem(icon: const Icon(LucideIcons.user), label: 'Perfil'),
              BottomNavigationBarItem(icon: const Icon(LucideIcons.settings), label: 'Configurações'),
            ]
          : [
              BottomNavigationBarItem(icon: const Icon(LucideIcons.home), label: 'Home'),
              BottomNavigationBarItem(icon: _chatIcon(), label: 'Chat'),
              BottomNavigationBarItem(icon: const Icon(LucideIcons.settings), label: 'Configurações'),
            ],
    );
  }

  Widget _chatIcon() {
    final count = _unread;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(LucideIcons.messageCircle),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppTheme.secondaryOrange, borderRadius: BorderRadius.circular(10)),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
