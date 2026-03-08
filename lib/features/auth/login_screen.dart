import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../services/theme_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoginForm = true;
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isPasswordVisible = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email.trim());
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Preencha email e senha';
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Formato de e-mail inválido';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });
    try {
      final authResponse = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: _passwordController.text);

      final session = authResponse.session;

      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Falha ao obter token do Supabase');
      }

      await _api.loginWithFirebase(
        session.accessToken,
        name: authResponse.user?.userMetadata?['full_name'],
      );
      if (!mounted) return;

      await NotificationService().syncToken();
      if (!mounted) return;

      _redirectUserBasedOnRole();
    } on AuthException catch (e) {
      if (!mounted) return;
      String mensagemErro = "Ocorreu um erro inesperado.";

      if (e.message.contains('Invalid login credentials')) {
        mensagemErro = "E-mail ou senha incorretos.";
      } else if (e.message.contains('Email not confirmed')) {
        mensagemErro = "Por favor, confirme seu e-mail.";
      }

      setState(() {
        _hasError = true;
        _errorMessage = mensagemErro;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao entrar: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      if (kIsWeb) {
        // No Web, usamos o fluxo nativo de redirecionamento do Supabase
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          // Em desenvolvimento, o Supabase redireciona para o localhost automaticamente.
          // Em produção, deve estar configurado no dashboard do Supabase em Auth > URL Configuration.
        );
        return; // O navegador irá redirecionar, o código abaixo não será executado.
      }

      // 📱 FLUXO MOBILE (Nativo usando google_sign_in)
      const webClientId =
          '478559853980-bd63tr459gslb0ish8t53c4e7gehjmi9.apps.googleusercontent.com';

      // No Android/iOS, o serverClientId é necessário para obter o idToken para o Supabase
      if (kIsWeb) {
        await GoogleSignIn.instance.initialize(clientId: webClientId);
      } else {
        await GoogleSignIn.instance.initialize(serverClientId: webClientId);
      }

      // Inicia o processo de login
      debugPrint('🔵 [Login] Iniciando GoogleSignIn.authenticate()...');
      final googleUser = await GoogleSignIn.instance.authenticate();

      // Obtém o idToken da autenticação
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      debugPrint(
        '🔵 [Login] idToken recebido (length: ${idToken?.length ?? 0})',
      );

      if (idToken == null) throw 'Nenhum Id Token retornado pelo Google.';

      // Tenta obter o accessToken (opcional no Supabase mas útil para logs)
      String? accessToken;
      try {
        final authz = await googleUser.authorizationClient.authorizeScopes([
          'email',
          'profile',
          'openid',
        ]);
        accessToken = authz.accessToken;
        debugPrint(
          '🔵 [Login] accessToken recebido (length: ${accessToken.length})',
        );
      } catch (e) {
        debugPrint('⚠️ [Login] Erro ao obter accessToken (não crítico): $e');
      }

      debugPrint('🚀 [Login] Chamando Supabase.signInWithIdToken...');
      final authResponse = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        // accessToken: accessToken, // Comentado para testar se resolve erro 401 (Audience mismatch)
      );

      debugPrint(
        '✅ [Login] Supabase Auth Sucesso: ${authResponse.user?.email}',
      );

      final session = authResponse.session;
      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Falha ao obter sessão do Supabase.');
      }

      await _api.loginWithFirebase(
        session.accessToken,
        name: authResponse.user?.userMetadata?['full_name'],
      );
      if (!mounted) return;

      await NotificationService().syncToken();
      if (!mounted) return;

      _redirectUserBasedOnRole();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Erro Google Login: $e';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _redirectUserBasedOnRole() {
    if (!mounted) return;

    final role = _api.role;
    debugPrint('🚀 [Login] Redirecionando usuário com role: $role');

    if (role == 'driver') {
      ThemeService().setProviderMode(true);
      context.go('/uber-driver');
    } else if (role == 'provider') {
      ThemeService().setProviderMode(true);
      if (_api.isMedical) {
        context.go('/medical-home');
      } else {
        context.go('/provider-home');
      }
    } else {
      ThemeService().setProviderMode(false);
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isLoginForm,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_isLoginForm) setState(() => _isLoginForm = true);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: AppTheme.primaryYellow,
          body: Column(
            children: [
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(
                        'assets/images/workers_illustration.png',
                      ),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '101',
                            style: GoogleFonts.manrope(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                              letterSpacing: -2,
                            ),
                          ),
                          Text(
                            'SERVICE',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 20,
                      offset: Offset(0, -5),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isLoginForm
                      ? _buildLoginForm()
                      : _buildSelectionForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionForm() {
    return Column(
      key: const ValueKey('selection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bem-vindo!',
          style: GoogleFonts.manrope(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Como você deseja usar o app hoje?',
          style: GoogleFonts.manrope(
            fontSize: 16,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: _buildTypeButton(
                label: 'Cliente',
                icon: LucideIcons.user,
                onTap: () => context.push('/register', extra: 'client'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTypeButton(
                label: 'Prestador',
                icon: LucideIcons.wrench,
                onTap: () => context.push('/register', extra: 'provider'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTypeButton(
          label: 'Motorista (Carro ou Moto)',
          icon: LucideIcons.car,
          isFullWidth: true,
          onTap: () => context.push('/register', extra: 'driver'),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: () => setState(() => _isLoginForm = true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryYellow,
              foregroundColor: AppTheme.textDark,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'JÁ TENHO CONTA',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => context.push('/agency'),
            child: Text(
              'Agência & Investidores',
              style: GoogleFonts.manrope(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Fazer Login',
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          focusNode: _emailFocus,
          style: GoogleFonts.manrope(color: AppTheme.textDark),
          decoration: AppTheme.inputDecoration('Email', LucideIcons.mail)
              .copyWith(
                enabledBorder: _hasError
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 1,
                        ),
                      )
                    : null,
              ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          style: GoogleFonts.manrope(color: AppTheme.textDark),
          obscureText: !_isPasswordVisible,
          decoration: AppTheme.inputDecoration('Senha', LucideIcons.lock)
              .copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _isPasswordVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
                enabledBorder: _hasError
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.red,
                          width: 1,
                        ),
                      )
                    : null,
              ),
          onSubmitted: (_) => _handleLogin(),
        ),
        if (_hasError && _errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: GoogleFonts.manrope(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ENTRAR'),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _handleGoogleLogin,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/google_logo.png',
                  height: 20,
                  errorBuilder: (c, e, s) => const Icon(Icons.login),
                ),
                const SizedBox(width: 12),
                Text(
                  'Continuar com Google',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ainda não tem conta?',
                style: GoogleFonts.manrope(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isLoginForm = false),
                child: Text(
                  'CADASTRAR',
                  style: GoogleFonts.manrope(
                    color: AppTheme.primaryYellow,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isFullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isFullWidth ? 64 : 110,
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: isFullWidth
            ? Row(
                children: [
                  Icon(icon, size: 24, color: AppTheme.textDark),
                  const SizedBox(width: 16),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 32, color: AppTheme.textDark),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
