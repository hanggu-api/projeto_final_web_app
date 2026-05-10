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
  final ScrollController _scrollController = ScrollController();
  final _fieldKeys = List.generate(6, (_) => GlobalKey());
  late final List<FocusNode> _focusNodes;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(6, (_) => FocusNode());
    for (final node in _focusNodes) {
      node.addListener(() {
        if (node.hasFocus) {
          _scrollFocusedInputIntoView(node);
        }
      });
    }
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
    _scrollController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    widget.passwordController.removeListener(_validatePasswords);
    widget.confirmPasswordController?.removeListener(_validatePasswords);
    super.dispose();
  }

  Future<void> _scrollFocusedInputIntoView(FocusNode node) async {
    final index = _focusNodes.indexOf(node);
    if (index < 0 || index >= _fieldKeys.length) return;
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    final context = _fieldKeys[index].currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
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
        email.isNotEmpty &&
        _isValidEmail(email) &&
        _fieldErrors['email'] == null;
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

  bool _isNameValid() {
    return widget.nameController.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .length >=
        2;
  }

  bool _isEmailValid() {
    final email = widget.emailController.text.trim();
    return email.isNotEmpty &&
        _isValidEmail(email) &&
        _fieldErrors['email'] == null &&
        _isValidating['email'] != true;
  }

  bool _isPasswordValid() {
    final password = widget.passwordController.text;
    return password.isNotEmpty &&
        password.length >= 6 &&
        _fieldErrors['password'] == null;
  }

  bool _isConfirmPasswordValid() {
    final confirmCtrl = widget.confirmPasswordController;
    if (confirmCtrl == null) return true;
    return confirmCtrl.text.isNotEmpty &&
        confirmCtrl.text == widget.passwordController.text &&
        _fieldErrors['confirm_password'] == null;
  }

  bool _isPhoneValid() {
    return widget.phoneController.text.trim().isNotEmpty &&
        PhoneInputFormatter.isValid(widget.phoneController.text) &&
        _fieldErrors['phone'] == null &&
        _isValidating['phone'] != true;
  }

  bool _isDocValid() {
    return widget.docController.text.trim().isNotEmpty &&
        _isValidCpfCnpj(widget.docController.text) &&
        _fieldErrors['doc'] == null &&
        _isValidating['doc'] != true;
  }

  int _activeInputIndex() {
    if (!_isNameValid()) return 0;
    if (!_isEmailValid()) return 1;
    if (!_isPasswordValid()) return 2;
    if (widget.confirmPasswordController != null &&
        !_isConfirmPasswordValid()) {
      return 3;
    }
    if (!_isPhoneValid()) return 4;
    if (!_isDocValid()) return 5;
    return 5;
  }

  bool _isInputEnabled(int index) => _activeInputIndex() == index;

  bool _isPasswordFieldInteractable(int index) =>
      _isInputEnabled(index) ||
      (index == 2 && widget.passwordController.text.isNotEmpty) ||
      (index == 3 &&
          (widget.confirmPasswordController?.text.isNotEmpty ?? false));

  void _focusNextEnabledInput() {
    final index = _activeInputIndex();
    if (index >= 0 && index < _focusNodes.length) {
      _focusNodes[index].requestFocus();
    }
  }

  Color _fieldFillColor(int index) {
    return _isInputEnabled(index)
        ? AppTheme.surfaceWhite
        : const Color(0xFFF8FAFC);
  }

  InputDecoration _sequentialDecoration(
    int index,
    String label,
    IconData icon, {
    Widget? suffixIcon,
    String? errorText,
    String? hintText,
  }) {
    return AppTheme.inputDecoration(label, icon).copyWith(
      hintText: hintText ?? label,
      suffixIcon: suffixIcon,
      errorText: errorText,
      fillColor: _fieldFillColor(index),
      prefixIcon: Icon(
        icon,
        color: _isInputEnabled(index)
            ? AppTheme.accentBlue
            : AppTheme.textMuted.withOpacity(0.72),
        size: 21,
      ),
    );
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
      final parts = currentValue
          .trim()
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      err = parts.length >= 2 ? null : 'Informe nome e sobrenome';
    }
    if (field == 'phone' && err == null) {
      err = PhoneInputFormatter.isValid(currentValue)
          ? null
          : 'Celular inválido';
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

  Widget _passwordSuffixIcon({
    required bool visible,
    required VoidCallback onToggle,
    required Widget? statusIcon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: visible ? 'Ocultar senha' : 'Mostrar senha',
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.only(right: 4),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppTheme.textMuted,
            size: 21,
          ),
          onPressed: onToggle,
        ),
        if (statusIcon != null) ...[
          Padding(padding: const EdgeInsets.only(right: 12), child: statusIcon),
        ] else
          const SizedBox(width: 8),
      ],
    );
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
          _focusNextEnabledInput();
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
      controller: _scrollController,
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
              key: _fieldKeys[0],
              focusNode: _focusNodes[0],
              enabled: _isInputEnabled(0),
              controller: widget.nameController,
              decoration: _sequentialDecoration(
                0,
                'Nome Completo',
                Icons.person,
                suffixIcon: _statusIcon('name', widget.nameController.text),
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {});
                _notifyParent();
                if (_isNameValid()) _focusNextEnabledInput();
              },
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
              key: _fieldKeys[1],
              focusNode: _focusNodes[1],
              enabled: _isInputEnabled(1),
              controller: widget.emailController,
              decoration: _sequentialDecoration(
                1,
                'Email',
                Icons.email,
                suffixIcon: _statusIcon('email', widget.emailController.text),
                errorText: _fieldErrors['email'],
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
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
              key: _fieldKeys[2],
              focusNode: _focusNodes[2],
              enabled: _isPasswordFieldInteractable(2),
              readOnly: !_isInputEnabled(2),
              controller: widget.passwordController,
              decoration: _sequentialDecoration(
                2,
                'Senha',
                Icons.lock,
                suffixIcon: _passwordSuffixIcon(
                  visible: _showPassword,
                  onToggle: () =>
                      setState(() => _showPassword = !_showPassword),
                  statusIcon: _statusIcon(
                    'password',
                    widget.passwordController.text,
                  ),
                ),
                errorText: _fieldErrors['password'],
              ),
              obscureText: !_showPassword,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                setState(() {});
                _notifyParent();
                if (!_isInputEnabled(2)) return;
                if (_isPasswordValid()) _focusNextEnabledInput();
              },
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
                key: _fieldKeys[3],
                focusNode: _focusNodes[3],
                enabled: _isPasswordFieldInteractable(3),
                readOnly: !_isInputEnabled(3),
                controller: widget.confirmPasswordController,
                decoration: _sequentialDecoration(
                  3,
                  'Confirmar Senha',
                  Icons.lock_outline,
                  suffixIcon: _passwordSuffixIcon(
                    visible: _showConfirmPassword,
                    onToggle: () => setState(
                      () => _showConfirmPassword = !_showConfirmPassword,
                    ),
                    statusIcon: _statusIcon(
                      'confirm_password',
                      widget.confirmPasswordController!.text,
                    ),
                  ),
                  errorText: _fieldErrors['confirm_password'],
                ),
                obscureText: !_showConfirmPassword,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  setState(() {});
                  _notifyParent();
                  if (!_isInputEnabled(3)) return;
                  if (_isConfirmPasswordValid()) _focusNextEnabledInput();
                },
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
              key: _fieldKeys[4],
              focusNode: _focusNodes[4],
              enabled: _isInputEnabled(4),
              controller: widget.phoneController,
              decoration: _sequentialDecoration(
                4,
                'Celular',
                Icons.phone,
                hintText: '(XX) XXXXX-XXXX',
                suffixIcon: _statusIcon('phone', widget.phoneController.text),
                errorText: _fieldErrors['phone'],
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
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
              key: _fieldKeys[5],
              focusNode: _focusNodes[5],
              enabled: _isInputEnabled(5),
              controller: widget.docController,
              decoration: _sequentialDecoration(
                5,
                'CPF ou CNPJ',
                Icons.assignment_ind,
                suffixIcon: _statusIcon('doc', widget.docController.text),
                errorText: _fieldErrors['doc'],
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
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
