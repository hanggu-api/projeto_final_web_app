import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/remote_ui/remote_screen_body.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/app_runtime_diagnostic_banner.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
          'Ajuda',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: const AppRuntimeDiagnosticBanner(),
      body: RemoteScreenBody(
        screenKey: 'help',
        padding: const EdgeInsets.all(20),
        fallbackBuilder: (context) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _helpTile(
                context,
                icon: LucideIcons.messageCircle,
                title: 'Conversar no chat',
                subtitle: 'Fale com o suporte via mensagens.',
                onTap: () => context.push('/chats'),
              ),
              const SizedBox(height: 12),
              _helpTile(
                context,
                icon: LucideIcons.phone,
                title: 'Ligar para suporte',
                subtitle: 'Telefone: 0800-000-1010',
                onTap: () {},
              ),
              const SizedBox(height: 12),
              _helpTile(
                context,
                icon: LucideIcons.shieldCheck,
                title: 'Segurança e privacidade',
                subtitle: 'Dicas para viagens e serviços seguros.',
                onTap: () => context.push('/client-settings'),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(LucideIcons.home),
                  label: const Text('Voltar para Início'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textDark,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Colors.grey.shade100,
      leading: Icon(icon, color: AppTheme.textDark),
      title: Text(
        title,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: onTap,
    );
  }
}
