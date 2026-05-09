import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/theme/app_theme.dart';
import '../../core/config/supabase_config.dart';
import '../../domains/auth/presentation/auth_controller.dart';
import '../../services/api_service.dart';
import '../../services/device_capability_service.dart';
import '../../services/notification_service.dart';
import '../../services/theme_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const double _heroImageAspectRatio = 1059 / 1486;

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
    if (!SupabaseConfig.isInitialized) {
      setState(() {
        _hasError = true;
        _errorMessage =
            'Conexao com o servidor indisponivel. Reinicie o app ou verifique a configuracao do ambiente.';
      });
      return;
    }

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
      _hasError = false;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: email, password: _passwordController.text);

      await _api.syncUserProfile('', name: null);
      if (!mounted) return;

      // Garante role atualizado antes do redirecionamento
      try {
        await _api.getMyProfile();
        // ✅ Verifica se role foi atualizado corretamente
        debugPrint('🔍 [LoginScreen] Role após getMyProfile: ${_api.role}');
      } catch (e) {
        debugPrint('⚠️ [LoginScreen] Erro ao carregar profile: $e');
      }

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
    }
  }

  Future<void> _handleGoogleLogin() async {
    if (!SupabaseConfig.isInitialized) {
      setState(() {
        _hasError = true;
        _errorMessage =
            'Login indisponivel no momento. Supabase nao foi inicializado.';
      });
      return;
    }

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
      final webClientId = SupabaseConfig.googleWebClientId.trim();
      if (webClientId.isEmpty) {
        debugPrint(
          '⚠️ [Login] GOOGLE_WEB_CLIENT_ID ausente; usando configuração nativa do Android/iOS quando disponível.',
        );
        await GoogleSignIn.instance.initialize();
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

      // O Supabase requer accessToken junto com idToken para Google native sign-in.
      String? googleAccessToken;
      try {
        final authz = await googleUser.authorizationClient.authorizeScopes([
          'email',
          'profile',
          'openid',
        ]);
        googleAccessToken = authz.accessToken;
        debugPrint(
          '🔵 [Login] accessToken recebido (length: ${googleAccessToken.length})',
        );
      } catch (e) {
        debugPrint('⚠️ [Login] Erro ao obter accessToken: $e');
      }

      if (googleAccessToken == null || googleAccessToken.isEmpty) {
        throw 'Nenhum Access Token retornado pelo Google.';
      }

      debugPrint('🚀 [Login] Chamando Supabase.signInWithIdToken...');
      final authResponse = await Supabase.instance.client.auth
          .signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: googleAccessToken,
          );

      debugPrint(
        '✅ [Login] Supabase Auth Sucesso: ${authResponse.user?.email}',
      );

      final session = authResponse.session;
      final sessionAccessToken = session?.accessToken;
      if (sessionAccessToken == null) {
        throw AuthException('Sessao invalida: accessToken ausente');
      }

      await _api.syncUserProfile(
        sessionAccessToken,
        name: authResponse.user?.userMetadata?['full_name'],
      );
      if (!mounted) return;

      await NotificationService().syncToken();
      if (!mounted) return;

      // Verifica CPF antes de redirecionar (Google não coleta CPF no cadastro)
      await _checkCpfAndRedirect();
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

  /// Verifica se o usuário tem CPF cadastrado.
  /// Se não tiver → /cpf-completion
  /// Se tiver → rota normal baseada no role
  Future<void> _checkCpfAndRedirect() async {
    if (!mounted) return;
    try {
      final row = await _api.getUserData();
      if (row == null) {
        _redirectUserBasedOnRole();
        return;
      }

      final cpf = row['document_value'] as String?;
      final birthDate = row['birth_date'] as String?;

      final hasCpf = cpf != null && cpf.isNotEmpty;
      final hasBirthDate = birthDate != null && birthDate.isNotEmpty;

      if (!hasCpf || !hasBirthDate) {
        debugPrint(
          '⚠️ [Login] Usuário Google sem CPF/nascimento → /cpf-completion',
        );
        if (mounted) context.go('/cpf-completion');
        return;
      }

      debugPrint('✅ [Login] CPF verificado → redirecionando normalmente');
      _redirectUserBasedOnRole();
    } catch (e) {
      debugPrint('⚠️ [Login] Erro ao verificar CPF (fallback normal): $e');
      _redirectUserBasedOnRole();
    }
  }

  Future<void> _redirectUserBasedOnRole() async {
    if (!mounted) return;

    final role = _api.role;
    debugPrint('🚀 [Login] Redirecionando usuário com role: $role');

    // O papel de driver foi removido. Caso algum usuário legado ainda tenha esse role,
    // tratamos como provider por segurança ou redirecionamos para home.
    if (role == 'driver' || role == 'provider') {
      ThemeService().setProviderMode(true);
      if (_api.isMedical) {
        context.go('/medical-home');
      } else {
        final activeServiceRoute = await _findProviderActiveServiceRoute();
        if (!mounted) return;
        if (activeServiceRoute != null && activeServiceRoute.isNotEmpty) {
          context.go(activeServiceRoute);
        } else {
          context.go('/provider-home');
        }
      }
    } else {
      ThemeService().setProviderMode(false);
      debugPrint('🚀 [Login] Redirecionando como cliente (Standard flow)');

      if (mounted) context.go('/home');
    }
  }

  Future<String?> _findProviderActiveServiceRoute() async {
    try {
      final service = await _api.findActiveService();
      if (service == null) return null;

      final serviceId = service['id']?.toString().trim() ?? '';
      if (serviceId.isEmpty) return null;

      final serviceScope = _api.getServiceScopeTag(service);
      if (serviceScope == 'fixed') {
        return '/provider-home';
      }
      return '/provider-active/$serviceId';
    } catch (e) {
      debugPrint(
        '⚠️ [Login] Falha ao verificar serviço ativo do prestador: $e',
      );
    }
    return null;
  }

  ImageProvider _buildHeroImageProvider(BuildContext context) {
    const asset = AssetImage('assets/images/fundo.png');
    final capability = DeviceCapabilityService.instance;
    if (!capability.prefersLowResolutionImages) {
      return asset;
    }

    final mediaQuery = MediaQuery.of(context);
    final targetWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio)
        .round()
        .clamp(360, 720);
    final targetHeight = (targetWidth / _heroImageAspectRatio).round().clamp(
      420,
      960,
    );

    return ResizeImage(
      asset,
      width: targetWidth,
      height: targetHeight,
      allowUpscaling: false,
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    DeviceCapabilityService capability,
    ImageProvider heroImageProvider,
    double heroHeight,
  ) {
    return SizedBox(
      width: double.infinity,
      height: heroHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: heroImageProvider,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: capability.prefersLowResolutionImages
                      ? FilterQuality.low
                      : FilterQuality.medium,
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00FFFFFF),
                    Color(0x33FFFFFF),
                    Color(0xB3FFFFFF),
                    Color(0xFFFFFFFF),
                  ],
                  stops: [0.0, 0.45, 0.82, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final capability = DeviceCapabilityService.instance;
    final heroImageProvider = _buildHeroImageProvider(context);
    return PopScope(
      canPop: _isLoginForm,
      onPopInvokedWithResult: (didPop, result) {
        if (!mounted) return;
        if (didPop) return;
        if (!_isLoginForm) setState(() => _isLoginForm = true);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(),
        child: Scaffold(
          backgroundColor: AppTheme.primaryYellow,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final mediaQuery = MediaQuery.of(context);
              final screenHeight = mediaQuery.size.height;
              final safeBottom = mediaQuery.padding.bottom;
              final preferredHeroMinHeight = capability.isLowEndDevice
                  ? 420.0
                  : 440.0;
              final preferredHeroMaxHeight =
                  screenHeight * (capability.isLowEndDevice ? 0.64 : 0.68);
              final preferredHeroLowerBound =
                  preferredHeroMinHeight <= preferredHeroMaxHeight
                  ? preferredHeroMinHeight
                  : preferredHeroMaxHeight;
              final preferredHeroUpperBound =
                  preferredHeroMaxHeight >= preferredHeroLowerBound
                  ? preferredHeroMaxHeight
                  : preferredHeroLowerBound;
              final preferredHeroHeight =
                  (mediaQuery.size.width / _heroImageAspectRatio)
                      .clamp(preferredHeroLowerBound, preferredHeroUpperBound)
                      .toDouble();
              final formEstimatedHeight = _isLoginForm ? 370.0 : 420.0;
              const overlapHeight = 26.0;
              const desiredBottomGap = 40.0;
              final availableHeroHeight =
                  constraints.maxHeight -
                  formEstimatedHeight +
                  overlapHeight -
                  safeBottom -
                  desiredBottomGap;
              final minHeroHeight = capability.isLowEndDevice ? 300.0 : 320.0;
              final maxHeroHeight = availableHeroHeight > minHeroHeight
                  ? availableHeroHeight.toDouble()
                  : minHeroHeight;
              final heroHeight = preferredHeroHeight
                  .clamp(minHeroHeight, maxHeroHeight)
                  .toDouble();

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      _buildHeroSection(
                        context,
                        capability,
                        heroImageProvider,
                        heroHeight,
                      ),
                      Transform.translate(
                        offset: const Offset(0, -26),
                        child: Container(
                          width: double.infinity,
                          margin: EdgeInsets.zero,
                          padding: EdgeInsets.fromLTRB(
                            24,
                            22,
                            24,
                            34 + safeBottom + desiredBottomGap,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(32),
                              topRight: Radius.circular(32),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 20,
                                offset: Offset(0, -2),
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
                      ),
                    ],
                  ),
                ),
              );
            },
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
            onPressed: () => context.push('/admin'),
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
    final authState = ref.watch(authControllerProvider);
    final isLoading = _isLoading || authState.isLoading;

    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 1),
        TextField(
          key: const ValueKey('login-email-field'),
          controller: _emailController,
          focusNode: _emailFocus,
          style: GoogleFonts.manrope(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          decoration: AppTheme.authInputDecoration(
            'Email',
            LucideIcons.mail,
            hasError: _hasError,
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('login-password-field'),
          controller: _passwordController,
          focusNode: _passwordFocus,
          style: GoogleFonts.manrope(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          obscureText: !_isPasswordVisible,
          decoration: AppTheme.authInputDecoration(
            'Senha',
            LucideIcons.lock,
            hasError: _hasError,
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 20,
                color: AppTheme.accentBlue,
              ),
              onPressed: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),
          ),
          onSubmitted: (_) => _handleLogin(),
        ),
        if (_hasError && _errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: GoogleFonts.manrope(
              color: Colors.red.shade800,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            key: const ValueKey('login-submit-button'),
            onPressed: isLoading ? null : _handleLogin,
            style: AppTheme.primaryActionButtonStyle(),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ENTRAR'),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            key: const ValueKey('login-google-button'),
            onPressed: isLoading ? null : _handleGoogleLogin,
            style: AppTheme.secondaryActionButtonStyle(),
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
        const SizedBox(height: 18),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ainda não tem conta?',
                style: GoogleFonts.manrope(
                  color: AppTheme.textDark.withOpacity(0.82),
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isLoginForm = false),
                child: Text(
                  'CADASTRAR',
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFB48A00),
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
          borderRadius: BorderRadius.circular(18),
          border: AppTheme.cardBorder,
          boxShadow: AppTheme.cardShadow,
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
