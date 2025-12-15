import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isLogin = true;
  bool _isLoading = false;
  String? _selectedRole;

  final _api = ApiService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Preencha email e senha');
      return;
    }

    if (!_isLogin && (_nameController.text.isEmpty || _selectedRole == null)) {
      _showError('Preencha todos os campos');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        final result = await _api.login(_emailController.text, _passwordController.text);
        final role = result['user']['role'];
        
        if (!mounted) return;
        
        if (role == 'provider') {
          context.go('/provider-home');
        } else {
          context.go('/home');
        }
      } else {
        await _api.register(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text,
          role: _selectedRole!,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        );
        if (!mounted) return;
        
        if (_selectedRole == 'provider') {
          context.go('/provider-home');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Logo
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(LucideIcons.wrench, size: 48, color: AppTheme.primaryPurple),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Conserta+',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'Serviços técnicos na palma da mão',
                  style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.8)),
                ),
                const SizedBox(height: 48),

                // Form Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      // Toggle Login/Register
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => setState(() => _isLogin = true),
                              style: TextButton.styleFrom(
                                backgroundColor: _isLogin ? AppTheme.primaryPurple : Colors.transparent,
                                foregroundColor: _isLogin ? Colors.white : Colors.black54,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Entrar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextButton(
                              onPressed: () => setState(() => _isLogin = false),
                              style: TextButton.styleFrom(
                                backgroundColor: !_isLogin ? AppTheme.primaryPurple : Colors.transparent,
                                foregroundColor: !_isLogin ? Colors.white : Colors.black54,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Cadastrar'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Email
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: const Icon(LucideIcons.mail),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(LucideIcons.lock),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: true,
                      ),

                      // Register fields
                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Nome Completo',
                            prefixIcon: const Icon(LucideIcons.user),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Telefone (opcional)',
                            prefixIcon: const Icon(LucideIcons.phone),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          decoration: InputDecoration(
                            labelText: 'Tipo de Conta',
                            prefixIcon: const Icon(LucideIcons.users),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'client', child: Text('Cliente')),
                            DropdownMenuItem(value: 'provider', child: Text('Prestador')),
                          ],
                          onChanged: (value) => setState(() => _selectedRole = value),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(_isLogin ? 'Entrar' : 'Cadastrar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
