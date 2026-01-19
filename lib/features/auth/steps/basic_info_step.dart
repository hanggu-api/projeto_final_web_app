import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/input_formatters.dart';

class BasicInfoStep extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  final String role;
  final VoidCallback onRoleToggle;
  final GlobalKey<FormState> formKey;

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
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              role == 'client' ? 'Cadastro de Cliente' : 'Seus Dados Básicos',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (role == 'client')
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
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome Completo',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
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
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe seu email';
                }
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                  return 'Email inválido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Senha',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
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
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Celular',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
                hintText: '(XX) XXXXX-XXXX',
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe seu celular';
                }
                if (value.replaceAll(RegExp(r'\D'), '').length < 11) {
                  return 'Celular inválido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: docController,
              decoration: const InputDecoration(
                labelText: 'CPF/CNPJ',
                prefixIcon: Icon(Icons.assignment_ind),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CpfCnpjInputFormatter(),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe seu CPF ou CNPJ';
                }
                final digits = value.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 11 && digits.length != 14) {
                  return 'CPF (11) ou CNPJ (14) inválido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
