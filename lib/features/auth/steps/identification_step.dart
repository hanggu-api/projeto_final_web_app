import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/input_formatters.dart';

class IdentificationStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController businessNameController;
  final TextEditingController nameController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController passwordController;

  const IdentificationStep({
    super.key,
    required this.formKey,
    required this.businessNameController,
    required this.nameController,
    required this.docController,
    required this.phoneController,
    required this.emailController,
    required this.passwordController,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: formKey,
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
              controller: businessNameController,
              decoration: const InputDecoration(
                labelText: 'Nome do Estabelecimento',
                prefixIcon: Icon(Icons.store),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v?.isEmpty == true ? 'Informe o nome do estabelecimento' : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: docController,
                    decoration: const InputDecoration(
                      labelText: 'CPF ou CNPJ',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CpfCnpjInputFormatter(),
                    ],
                    validator: (v) {
                      if (v?.isEmpty == true) return 'Obrigatório';
                      final digits = v!.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 11 && digits.length != 14) {
                        return 'Inválido';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Telefone / WhatsApp',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
              validator: (v) {
                if (v?.isEmpty == true) return 'Obrigatório';
                final digits = v!.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return 'Inválido';
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
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nome do Responsável',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Senha',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
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
