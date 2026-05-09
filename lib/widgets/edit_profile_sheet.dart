import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/input_formatters.dart';

typedef EditProfileSave = Future<void> Function(
  String name,
  String email,
  String phone,
);

class EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic>? user;
  final EditProfileSave onSave;
  final VoidCallback onPickAvatar;
  final bool isUploadingAvatar;

  const EditProfileSheet({
    super.key,
    required this.user,
    required this.onSave,
    required this.onPickAvatar,
    required this.isUploadingAvatar,
  });

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.user?['name'] ?? widget.user?['full_name'],
    );
    _emailController = TextEditingController(text: widget.user?['email']);
    _phoneController = TextEditingController(
      text: formatPhoneDisplay(widget.user?['phone']?.toString()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _isSaving = true);
      await widget.onSave(
        _nameController.text,
        _emailController.text,
        phoneDigitsOnly(_phoneController.text),
      );
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Campo obrigatório';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        left: 24,
        right: 24,
        top: 32,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Editar Perfil',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildField(
              controller: _nameController,
              label: 'NOME COMPLETO',
              icon: LucideIcons.user,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _emailController,
              label: 'EMAIL',
              icon: LucideIcons.mail,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _phoneController,
              label: 'TELEFONE',
              icon: LucideIcons.phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submit,
                child: Text(_isSaving ? 'Salvando...' : 'Salvar alterações'),
              ),
            ),
            if (widget.isUploadingAvatar) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: widget.onPickAvatar,
              icon: const Icon(Icons.photo_camera),
              label: const Text('Alterar foto de perfil'),
            ),
          ],
        ),
      ),
    );
  }
}
