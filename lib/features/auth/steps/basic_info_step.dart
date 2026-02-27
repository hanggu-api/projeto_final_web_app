import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import 'dart:async';
import '../../../services/api_service.dart';

class BasicInfoStep extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  final String role;
  final VoidCallback onRoleToggle;
  final GlobalKey<FormState> formKey;
  final Function(bool isValidating, Map<String, String?> errors) onValidationChanged;

  const BasicInfoStep({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.docController,
    required this.phoneController,
    required this.role,
    required this.onRoleToggle,
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

  void _onFieldChanged(String field, String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // Clear error while typing or if empty
    if (value.isEmpty) {
      setState(() {
        _fieldErrors[field] = null;
        _isValidating[field] = false;
      });
      _notifyParent();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final cleanValue = field == 'email' ? value.trim() : value.replaceAll(RegExp(r'\D'), '');
      
      // Basic format check before API call
      if (field == 'email' && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(cleanValue)) return;
      if (field == 'phone' && cleanValue.length < 11) return;
      if (field == 'doc' && (cleanValue.length != 11 && cleanValue.length != 14)) return;

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
            if (result['exists'] == true) {
              _fieldErrors[field] = 'Este ${field == 'doc' ? 'CPF/CNPJ' : field} já está cadastrado';
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
    widget.onValidationChanged(currentlyValidating, _fieldErrors);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.role == 'client' ? 'Cadastro de Cliente' : 'Seus Dados Básicos',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (widget.role == 'client')
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Preencha seus dados para solicitar serviços',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: widget.nameController,
              decoration: AppTheme.inputDecoration('Nome Completo', Icons.person),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.emailController,
              decoration: AppTheme.inputDecoration('Email', Icons.email).copyWith(
                suffixIcon: _isValidating['email'] == true 
                  ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) 
                  : null,
                errorText: _fieldErrors['email'],
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => _onFieldChanged('email', v),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe seu email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                  return 'Email inválido';
                }
                if (_fieldErrors['email'] != null) return _fieldErrors['email'];
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.passwordController,
              decoration: AppTheme.inputDecoration('Senha', Icons.lock),
              obscureText: true,
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'A senha deve ter pelo menos 6 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.phoneController,
              decoration: AppTheme.inputDecoration('Celular', Icons.phone).copyWith(
                hintText: '(XX) XXXXX-XXXX',
                suffixIcon: _isValidating['phone'] == true 
                  ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) 
                  : null,
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
                if (value.replaceAll(RegExp(r'\D'), '').length < 11) {
                  return 'Celular inválido';
                }
                if (_fieldErrors['phone'] != null) return _fieldErrors['phone'];
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: widget.docController,
              decoration: AppTheme.inputDecoration('CPF/CNPJ', Icons.assignment_ind).copyWith(
                suffixIcon: _isValidating['doc'] == true 
                  ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))) 
                  : null,
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
                final digits = value.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 11 && digits.length != 14) {
                  return 'CPF (11) ou CNPJ (14) inválido';
                }
                if (_fieldErrors['doc'] != null) return _fieldErrors['doc'];
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
