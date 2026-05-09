import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

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
          'Segurança',
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
          _tile(
            icon: LucideIcons.shieldCheck,
            title: 'Verificação em duas etapas',
            subtitle: 'Adicione uma camada extra de proteção.',
            trailing: Switch(value: false, onChanged: (_) {}),
          ),
          _tile(
            icon: LucideIcons.bell,
            title: 'Alertas de login',
            subtitle: 'Receba aviso ao entrar em um novo aparelho.',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
          _tile(
            icon: LucideIcons.lock,
            title: 'Trocar senha',
            subtitle: 'Atualize sua senha com segurança.',
            onTap: () => context.push('/change-password'),
          ),
          _tile(
            icon: LucideIcons.shield,
            title: 'Privacidade de dados',
            subtitle: 'Revise permissões e compartilhamento.',
            onTap: () {},
          ),
          _tile(
            icon: LucideIcons.trash2,
            title: 'Excluir conta',
            subtitle: 'Remover permanentemente seus dados.',
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Excluir Conta', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                  content: Text(
                    'Tem certeza que deseja solicitar a exclusão da sua conta permanentemente? Você será redirecionado para a página de exclusão.',
                    style: GoogleFonts.manrope(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text('Cancelar', style: GoogleFonts.manrope(color: Colors.black)),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        
                        final user = Supabase.instance.client.auth.currentUser;
                        final email = user?.email ?? '';
                        final id = user?.id ?? '';
                        
                        final url = Uri.parse('https://101service.com.br/excluir_conta?email=$email&id=$id');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Não foi possível abrir a página de exclusão.', style: GoogleFonts.manrope()),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      child: Text('Continuar', style: GoogleFonts.manrope(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
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

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: AppTheme.backgroundLight,
        child: Icon(icon, color: AppTheme.textDark),
      ),
      title: Text(title, style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(LucideIcons.chevronRight),
      onTap: onTap,
    );
  }
}
