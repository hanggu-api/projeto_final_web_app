import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  bool _notifications = true;
  bool _promo = true;
  bool _location = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: Text(
          'Configurações',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _switchTile(
            icon: LucideIcons.bellRing,
            title: 'Notificações gerais',
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
          _switchTile(
            icon: LucideIcons.percent,
            title: 'Receber promoções',
            value: _promo,
            onChanged: (v) => setState(() => _promo = v),
          ),
          _switchTile(
            icon: LucideIcons.mapPin,
            title: 'Compartilhar localização',
            value: _location,
            onChanged: (v) => setState(() => _location = v),
          ),
          _navTile(
            icon: LucideIcons.shieldCheck,
            title: 'Segurança',
            subtitle: 'Revise autenticação e privacidade.',
            onTap: () => context.push('/security'),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => context.go('/home'),
            icon: const Icon(LucideIcons.home),
            label: const Text('Voltar para Início'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      secondary: CircleAvatar(
        backgroundColor: AppTheme.backgroundLight,
        child: Icon(icon, color: AppTheme.textDark),
      ),
    );
  }

  Widget _navTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppTheme.backgroundLight,
        child: Icon(icon, color: AppTheme.textDark),
      ),
      title: Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: onTap,
    );
  }
}
