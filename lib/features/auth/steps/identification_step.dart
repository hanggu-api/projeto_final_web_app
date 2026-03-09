import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import 'dart:async';
import '../../../services/api_service.dart';

class IdentificationStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController businessNameController;
  final TextEditingController nameController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final Function(bool isValidating, Map<String, String?> errors)
  onValidationChanged;

  const IdentificationStep({
    super.key,
    required this.formKey,
    required this.businessNameController,
    required this.nameController,
    required this.docController,
    required this.phoneController,
    required this.emailController,
    required this.passwordController,
    required this.onValidationChanged,
  });

  @override
  State<IdentificationStep> createState() => _IdentificationStepState();
}

class _IdentificationStepState extends State<IdentificationStep> {
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
      final cleanValue = field == 'email'
          ? value.trim()
          : value.replaceAll(RegExp(r'\D'), '');

      // Basic format check before API call
      if (field == 'email' &&
          !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(cleanValue)) {
        return;
      }
      if (field == 'phone' && cleanValue.length < 10) return;
      if (field == 'doc' &&
          (cleanValue.length != 11 && cleanValue.length != 14)) {
        return;
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
            if (result['exists'] == true) {
              _fieldErrors[field] =
                  'Este ${field == 'doc' ? 'CPF/CNPJ' : field} já está cadastrado';
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
            const Text(
              'Identificação',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Dados do estabelecimento e do responsável',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // BUSINESS INFO
            TextFormField(
              controller: widget.businessNameController,
              decoration: AppTheme.inputDecoration(
                'Nome do Estabelecimento',
                Icons.store,
              ),
              validator: (v) => v?.isEmpty == true
                  ? 'Informe o nome do estabelecimento'
                  : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: widget.docController,
                    decoration:
                        AppTheme.inputDecoration(
                          'CPF ou CNPJ',
                          Icons.badge,
                        ).copyWith(
                          suffixIcon: _isValidating['doc'] == true
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                          errorText: _fieldErrors['doc'],
                        ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CpfCnpjInputFormatter(),
                    ],
                    onChanged: (v) => _onFieldChanged('doc', v),
                    validator: (v) {
                      if (v?.isEmpty == true) return 'Obrigatório';
                      final digits = v!.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 11 && digits.length != 14) {
                        return 'Inválido';
                      }
                      if (_fieldErrors['doc'] != null) {
                        return _fieldErrors['doc'];
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.phoneController,
              decoration:
                  AppTheme.inputDecoration(
                    'Telefone / WhatsApp',
                    Icons.phone,
                  ).copyWith(
                    suffixIcon: _isValidating['phone'] == true
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    errorText: _fieldErrors['phone'],
                  ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
              onChanged: (v) => _onFieldChanged('phone', v),
              validator: (v) {
                if (v?.isEmpty == true) return 'Obrigatório';
                final digits = v!.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return 'Inválido';
                if (_fieldErrors['phone'] != null) return _fieldErrors['phone'];
                return null;
              },
            ),
            const SizedBox(height: 24),

            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Dados de Acesso',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.nameController,
              decoration: AppTheme.inputDecoration(
                'Nome do Responsável',
                Icons.person,
              ),
              validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.emailController,
              decoration: AppTheme.inputDecoration('E-mail', Icons.email)
                  .copyWith(
                    suffixIcon: _isValidating['email'] == true
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    errorText: _fieldErrors['email'],
                  ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => _onFieldChanged('email', v),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obrigatório';
                if (!RegExp(
                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                ).hasMatch(v.trim())) {
                  return 'Inválido';
                }
                if (_fieldErrors['email'] != null) return _fieldErrors['email'];
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.passwordController,
              decoration: AppTheme.inputDecoration('Senha', Icons.lock),
              obscureText: true,
              validator: (v) =>
                  (v?.length ?? 0) < 6 ? 'Mínimo 6 caracteres' : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
