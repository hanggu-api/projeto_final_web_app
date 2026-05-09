import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import 'dart:async';
import '../../../services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';

class BasicInfoStep extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController? confirmPasswordController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  // Honeypot anti-bot (must remain empty)
  final TextEditingController? botBirthDateController;
  final TextEditingController? botMotherNameController;
  final TextEditingController? birthDateController;
  final String role;
  final String? subRole;
  final Function(String) onSubRoleChanged;
  final GlobalKey<FormState> formKey;
  final Function(bool isValidating, Map<String, String?> errors)
  onValidationChanged;

  const BasicInfoStep({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    this.confirmPasswordController,
    required this.docController,
    required this.phoneController,
    required this.role,
    this.subRole,
    required this.onSubRoleChanged,
    this.botBirthDateController,
    this.botMotherNameController,
    this.birthDateController,
    required this.formKey,
    required this.onValidationChanged,
  });

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  Timer? _debounce;
  final Map<String, String?> _fieldErrors = {};
  final Map<String, bool> _isValidating = {};

  @override
  void initState() {
    super.initState();
    widget.passwordController.addListener(_validatePasswords);
    widget.confirmPasswordController?.addListener(_validatePasswords);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = (widget.subRole ?? '').toString().trim();
      if (current.isNotEmpty) return;
      // Define sub-role padrão: 'seeker' para clientes e 'mobile' para prestadores
      final defaultSubRole = widget.role == 'provider' ? 'mobile' : 'seeker';
      widget.onSubRoleChanged(defaultSubRole);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.passwordController.removeListener(_validatePasswords);
    widget.confirmPasswordController?.removeListener(_validatePasswords);
    super.dispose();
  }

  void _validatePasswords() {
    final password = widget.passwordController.text;
    final confirm = widget.confirmPasswordController?.text ?? '';

    String? passErr;
    if (password.isNotEmpty && password.length < 6) {
      passErr = 'A senha deve ter pelo menos 6 caracteres';
    }

    String? confirmErr;
    if (widget.confirmPasswordController != null &&
        confirm.isNotEmpty &&
        password != confirm) {
      confirmErr = 'As senhas não conferem';
    }

    if (!mounted) return;
    setState(() {
      _fieldErrors['password'] = passErr;
      _fieldErrors['confirm_password'] = confirmErr;
    });
    _notifyParent();
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim());
  }

  bool _isValidCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;
    final nums = digits.split('').map(int.parse).toList();
    int calcDigit(int length) {
      int sum = 0;
      for (int i = 0; i < length; i++) {
        sum += nums[i] * ((length + 1) - i);
      }
      final mod = (sum * 10) % 11;
      return mod == 10 ? 0 : mod;
    }
    final d1 = calcDigit(9);
    final d2 = calcDigit(10);
    return nums[9] == d1 && nums[10] == d2;
  }

  bool _isValidCnpj(String cnpj) {
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 14) return false;
    if (RegExp(r'^(\d)\1{13}$').hasMatch(digits)) return false;
    final nums = digits.split('').map(int.parse).toList();
    const w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    int calc(List<int> weights) {
      int sum = 0;
      for (int i = 0; i < weights.length; i++) {
        sum += nums[i] * weights[i];
      }
      final mod = sum % 11;
      return mod < 2 ? 0 : (11 - mod);
    }
    final d1 = calc(w1);
    final d2 = calc(w2);
    return nums[12] == d1 && nums[13] == d2;
  }

  bool _isValidCpfCnpj(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) return _isValidCpf(digits);
    if (digits.length == 14) return _isValidCnpj(digits);
    return false;
  }

  bool _computeStepValid() {
    final nameOk = widget.nameController.text.trim().split(' ').length >= 2;
    final email = widget.emailController.text.trim();
    final emailOk =
        email.isNotEmpty && _isValidEmail(email) && _fieldErrors['email'] == null;
    final phoneOk =
        widget.phoneController.text.trim().isNotEmpty &&
        PhoneInputFormatter.isValid(widget.phoneController.text) &&
        _fieldErrors['phone'] == null;
    final docOk =
        widget.docController.text.trim().isNotEmpty &&
        _isValidCpfCnpj(widget.docController.text) &&
        _fieldErrors['doc'] == null;
    final pass = widget.passwordController.text;
    final passOk =
        pass.isNotEmpty && pass.length >= 6 && _fieldErrors['password'] == null;
    final confirmCtrl = widget.confirmPasswordController;
    final confirmOk = confirmCtrl == null
        ? true
        : (confirmCtrl.text.isNotEmpty &&
            confirmCtrl.text == pass &&
            _fieldErrors['confirm_password'] == null);
    final anyValidating = _isValidating.values.any((v) => v == true);

    final honeypotOk =
        (widget.botBirthDateController?.text.trim().isEmpty ?? true) &&
        (widget.botMotherNameController?.text.trim().isEmpty ?? true);

    return nameOk &&
        emailOk &&
        phoneOk &&
        docOk &&
        passOk &&
        confirmOk &&
        !anyValidating &&
        honeypotOk;
  }

  Widget? _statusIcon(String field, String currentValue) {
    final validating = _isValidating[field] == true;
    if (validating) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (currentValue.trim().isEmpty) return null;
    String? err = _fieldErrors[field];
    if (field == 'name') {
      final parts = currentValue.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      err = parts.length >= 2 ? null : 'Informe nome e sobrenome';
    }
    if (field == 'phone' && err == null) {
      err = PhoneInputFormatter.isValid(currentValue) ? null : 'Celular inválido';
    }
    if (field == 'doc' && err == null) {
      err = _isValidCpfCnpj(currentValue) ? null : 'CPF/CNPJ inválido';
    }
    if (field == 'email' && err == null) {
      err = _isValidEmail(currentValue) ? null : 'Email inválido';
    }
    if (err != null) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
    return const Icon(Icons.check_circle, color: Colors.blue);
  }

  void _onFieldChanged(String field, String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (value.isEmpty) {
      setState(() {
        _fieldErrors[field] = null;
        _isValidating[field] = false;
      });
      _notifyParent();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final cleanValue = field == 'email'
          ? value.trim()
          : value.replaceAll(RegExp(r'\D'), '');

      if (field == 'email' && !_isValidEmail(cleanValue)) {
        return;
      }
      if (field == 'phone' && cleanValue.length < 11) return;
      if (field == 'doc') {
        if (cleanValue.length != 11 && cleanValue.length != 14) return;
        final isValid = _isValidCpfCnpj(cleanValue);
        if (mounted) {
          setState(() {
            _fieldErrors[field] = isValid ? null : 'CPF/CNPJ inválido';
          });
          _notifyParent();
        }
        if (!isValid) return;
      }

      setState(() => _isValidating[field] = true);
      _notifyParent();

      try {
        final result = await ApiService().checkUnique(
          email: field == 'email' ? cleanValue : null,
          phone: field == 'phone' ? cleanValue : null,
          document: field == 'doc' ? cleanValue : null,
        );

        if (mounted) {
          setState(() {
            _isValidating[field] = false;
            if (field == 'doc') {
            } else if (result['exists'] == true) {
              _fieldErrors[field] =
                  'Este ${field == 'doc' ? 'CPF/CNPJ' : field} já está cadastrado';
            } else if (result['invalid'] == true) {
              _fieldErrors[field] = result['message'] ?? 'Número inválido';
            } else {
              _fieldErrors[field] = null;
            }
          });
          _notifyParent();
        }
      } catch (e) {
        if (mounted) setState(() => _isValidating[field] = false);
        _notifyParent();
      }
    });
  }

  void _notifyParent() {
    final currentlyValidating = _isValidating.values.any((v) => v == true);
    final stepValid = _computeStepValid();
    widget.onValidationChanged(currentlyValidating, {
      ..._fieldErrors,
      '__basic_info_step_valid': stepValid ? 'true' : 'false',
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.role == 'client'
                  ? 'Cadastro de Cliente'
                  : 'Cadastro de Prestador',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Preencha as informações básicas para prosseguir',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                color: Colors.grey.shade600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),

            TextFormField(
              controller: widget.nameController,
              decoration: AppTheme.inputDecoration(
                'Nome Completo',
                Icons.person,
              ).copyWith(
                suffixIcon: _statusIcon('name', widget.nameController.text),
              ),
              onChanged: (_) => _notifyParent(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe seu nome completo';
                }
                if (value.trim().split(' ').length < 2) {
                  return 'Informe nome e sobrenome';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            if (widget.botBirthDateController != null &&
                widget.botMotherNameController != null) ...[
              Opacity(
                opacity: 0.0,
                child: SizedBox(
                  height: 0,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: widget.botBirthDateController,
                        decoration: const InputDecoration(labelText: 'B-Day'),
                      ),
                      TextFormField(
                        controller: widget.botMotherNameController,
                        decoration: const InputDecoration(labelText: 'M-Name'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            TextFormField(
              controller: widget.emailController,
              decoration: AppTheme.inputDecoration('Email', Icons.email)
                  .copyWith(
                    suffixIcon: _statusIcon('email', widget.emailController.text),
                    errorText: _fieldErrors['email'],
                  ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => _onFieldChanged('email', v),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe seu email';
                }
                if (!_isValidEmail(value)) {
                  return 'Email inválido';
                }
                return _fieldErrors['email'];
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.passwordController,
              decoration: AppTheme.inputDecoration('Senha', Icons.lock).copyWith(
                suffixIcon: _statusIcon('password', widget.passwordController.text),
                errorText: _fieldErrors['password'],
              ),
              obscureText: true,
              onChanged: (_) => _notifyParent(),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'A senha deve ter pelo menos 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            if (widget.confirmPasswordController != null) ...[
              TextFormField(
                controller: widget.confirmPasswordController,
                decoration: AppTheme.inputDecoration(
                  'Confirmar Senha',
                  Icons.lock_outline,
                ).copyWith(
                  suffixIcon: _statusIcon(
                    'confirm_password',
                    widget.confirmPasswordController!.text,
                  ),
                  errorText: _fieldErrors['confirm_password'],
                ),
                obscureText: true,
                onChanged: (_) => _notifyParent(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirme sua senha';
                  }
                  if (value != widget.passwordController.text) {
                    return 'As senhas não conferem';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: widget.phoneController,
              decoration: AppTheme.inputDecoration('Celular', Icons.phone)
                  .copyWith(
                    hintText: '(XX) XXXXX-XXXX',
                    suffixIcon: _statusIcon('phone', widget.phoneController.text),
                    errorText: _fieldErrors['phone'],
                  ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
              onChanged: (v) => _onFieldChanged('phone', v),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe seu celular';
                }
                if (!PhoneInputFormatter.isValid(value)) {
                  return 'Celular inválido';
                }
                return _fieldErrors['phone'];
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.docController,
              decoration: AppTheme.inputDecoration('CPF ou CNPJ', Icons.assignment_ind)
                  .copyWith(
                    suffixIcon: _statusIcon('doc', widget.docController.text),
                    errorText: _fieldErrors['doc'],
                  ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CpfCnpjInputFormatter(),
              ],
              onChanged: (v) => _onFieldChanged('doc', v),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe seu CPF ou CNPJ';
                }
                if (!_isValidCpfCnpj(value)) {
                  return 'CPF/CNPJ inválido';
                }
                return _fieldErrors['doc'];
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
