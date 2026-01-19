import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controle de estado: Mostrando login ou seleção
  bool _isLoginForm = false;
  bool _isLoading = false;

  // Campos de Login
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  DateTime _openedAt = DateTime.now();
  int _pointerMoves = 0;
  int _focusChanges = 0;
  int _emailLastTs = 0;
  int _passwordLastTs = 0;
  final List<int> _emailIntervals = [];
  final List<int> _passwordIntervals = [];
  bool _emailPasteSuspect = false;
  bool _passwordPasteSuspect = false;
  bool _isPasswordVisible = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    _emailFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_emailFocus.hasFocus || _passwordFocus.hasFocus) {
      if (mounted) {
        setState(() {
          _focusChanges++;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
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
      final now = DateTime.now();
      final dwellMs = now.difference(_openedAt).inMilliseconds;
      final allIntervals = [..._emailIntervals, ..._passwordIntervals];
      double avgKeypress = allIntervals.isEmpty
          ? 0
          : allIntervals.reduce((a, b) => a + b) / allIntervals.length;

      final humanMetrics = {
        'dwell_time_ms': dwellMs,
        'pointer_moves': _pointerMoves,
        'focus_changes': _focusChanges,
        'avg_keypress_interval_ms': avgKeypress.round(),
        'was_pasted': _emailPasteSuspect || _passwordPasteSuspect,
      };
      // 1. Login no Supabase Auth
      final authResponse = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _passwordController.text,
      );

      final session = authResponse.session;

      if (session == null || session.accessToken.isEmpty) {
        throw Exception('Falha ao obter token do Supabase');
      }

      // 2. Login no Backend (Aproveitando a mesma rota para sincronizar human_metrics etc)
      await _api.loginWithFirebase(
        session.accessToken,
        name: authResponse.user?.userMetadata?['full_name'],
        humanMetrics: humanMetrics,
      );
      if (!mounted) return;

      // Sync notification token
      await NotificationService().syncToken();
      if (!mounted) return;

      if (_api.role == 'provider') {
        if (_api.isMedical) {
          context.go('/medical-home');
        } else {
          context.go('/provider-home');
        }
      } else {
        context.go('/home');
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      String mensagemErro = "Ocorreu um erro inesperado.";

      if (e.message.contains('Invalid login credentials')) {
        mensagemErro =
            "E-mail ou senha incorretos. Por favor, tente novamente.";
      } else if (e.message.contains('Email not confirmed')) {
        mensagemErro = "Por favor, confirme seu e-mail antes de entrar.";
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

  // ignore: unused_element
  void _showConfigDialog(BuildContext context) {
    final controller = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configurar API'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'URL da API',
            hintText: 'https://backend-pi-ivory-11.vercel.app/api',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await _api.setBaseUrl(newUrl);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL atualizada!')),
                  );
                }
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoginForm,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isLoginForm) {
          setState(() => _isLoginForm = false);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: AppTheme.primaryYellow,
          body: Column(
            children: [
              // --- PARTE SUPERIOR (Amarela com Imagem) ---
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/images/workers_illustration.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              // --- PARTE INFERIOR (Card Branco) ---
              GestureDetector(
                onPanUpdate: (_) => _pointerMoves++,
                onTapDown: (_) => _pointerMoves++,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(30, 40, 30, 40),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(40),
                      topRight: Radius.circular(40),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
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
        const Text(
          'Quero ser:',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 20),

        // Botões de Seleção (Cliente / Prestador)
        Row(
          children: [
            Expanded(
              child: _buildTypeButton(
                label: 'Cliente',
                color: Colors.black,
                icon: Icons.person,
                onTap: () {
                  // Navega para cadastro de cliente
                  context.push('/register', extra: 'client');
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildTypeButton(
                label: 'Prestador',
                color: Colors.black,
                icon: Icons.handyman,
                onTap: () {
                  // Navega para cadastro de prestador
                  context.push('/register', extra: 'provider');
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        // Botão Entrar
        SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            onPressed: () => setState(() => _isLoginForm = true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryYellow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
            ),
            child: Text(
              'JÁ TENHO CONTA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkBlueText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => context.push('/agency'),
            child: const Text(
              'Agência & Investidores',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => context.push('/ios-login'),
            child: const Text(
              'Demo iOS (Teste)',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 20), // Spacing for bottom inset
      ],
    );
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      // Initiate Supabase Google Sign in
      // This will open a web browser to complete the flow.
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'app.service101.com://login-callback/', 
      );

      // The rest of the login flow (fetching api profile, etc) 
      // is handled via Supabase auth state changes listener
      // Typically set up in main.dart or a dedicated Auth Gateway.
      
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

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bem-vindo ao 101 Service!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.darkBlueText,
              ),
            ),
            IconButton(
              onPressed: () => setState(() => _isLoginForm = false),
              icon: const Icon(Icons.close),
              color: Colors.black54,
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Email
        TextField(
          controller: _emailController,
          focusNode: _emailFocus,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            labelText: 'Email',
            labelStyle: const TextStyle(color: Colors.black54),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.email_outlined, color: Colors.black54),
            enabledBorder: _hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  )
                : OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12), // Subtle border
                  ),
            focusedBorder: _hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  )
                : OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.primaryYellow, // Yellow when focused
                      width: 2,
                    ),
                  ),
          ),
          onChanged: (v) {
            if (_hasError) {
              setState(() {
                _hasError = false;
                _errorMessage = null;
              });
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            if (_emailLastTs > 0) {
              final diff = now - _emailLastTs;
              _emailIntervals.add(diff);
            }
            _emailLastTs = now;
            final jump =
                v.length >= 4 &&
                _emailIntervals.isNotEmpty &&
                _emailIntervals.last < 60;
            if (jump) _emailPasteSuspect = true;
          },
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),

        const SizedBox(height: 15),

        // Senha
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            labelText: 'Senha',
            labelStyle: const TextStyle(color: Colors.black54),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.black54),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                color: Colors.black54,
              ),
              onPressed: () {
                setState(() {
                  _isPasswordVisible = !_isPasswordVisible;
                });
              },
            ),
            enabledBorder: _hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  )
                : OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
            focusedBorder: _hasError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  )
                : OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppTheme.primaryYellow,
                      width: 2,
                    ),
                  ),
          ),
          onChanged: (v) {
            if (_hasError) {
              setState(() {
                _hasError = false;
                _errorMessage = null;
              });
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            if (_passwordLastTs > 0) {
              final diff = now - _passwordLastTs;
              _passwordIntervals.add(diff);
            }
            _passwordLastTs = now;
            final jump =
                v.length >= 4 &&
                _passwordIntervals.isNotEmpty &&
                _passwordIntervals.last < 60;
            if (jump) _passwordPasteSuspect = true;
          },
          obscureText: !_isPasswordVisible,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
        ),

        if (_hasError && _errorMessage != null) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 25),

        // Botão Entrar (Amarelo Sólido + Texto Preto)
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryYellow, // Yellow bg
              foregroundColor: Colors.black, // Black ripple
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.black)
                : const Text(
                    'Entrar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black, // Black Text
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Botão Google (Outline Amarelo + Texto Preto)
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _isLoading ? null : _handleGoogleLogin,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primaryYellow, width: 2), // Yellow Border
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/google_logo.png',
                  height: 24,
                  errorBuilder: (ctx, error, stack) => const Icon(
                    Icons.login, // Fallback icon
                    color: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Entrar com Google', // Updated styling
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black, // Black Text
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20), // Spacing for bottom inset
      ],
    );
  }

  // Widget auxiliar para os botões de opção
  Widget _buildTypeButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100, // Mais alto para destaque
        decoration: BoxDecoration(
          color: AppTheme.primaryYellow, // Fundo Amarelo
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.black), // Ícone Preto
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black, // Texto Preto
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
