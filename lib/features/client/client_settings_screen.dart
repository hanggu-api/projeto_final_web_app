import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/profile/backend_profile_api.dart';
import '../../core/utils/input_formatters.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../widgets/edit_profile_sheet.dart';

class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({super.key});

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  final ApiService _api = ApiService();
  final BackendProfileApi _backendProfileApi = const BackendProfileApi();
  final MediaService _mediaService = MediaService();
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isUploadingAvatar = false;

  void _notAvailable(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profileState = await _backendProfileApi.fetchMyProfile();
      if (profileState == null) {
        throw Exception('Perfil canônico indisponível.');
      }
      final profile = profileState.toApiUserMap();
      if (mounted) {
        setState(() {
          _user = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateProfile(String name, String email, String phone) async {
    try {
      await _api.updateProfile(name: name, email: email, phone: phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil atualizado com sucesso!')),
        );
        Navigator.pop(context);
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar perfil: $e')));
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      if (kIsWeb) {
        final result = await _mediaService.pickImageWeb();
        if (result != null &&
            result.files.isNotEmpty &&
            result.files.first.bytes != null) {
          setState(() => _isUploadingAvatar = true);
          final file = result.files.first;
          final mime = file.extension != null
              ? 'image/${file.extension}'
              : 'image/jpeg';

          await _mediaService.uploadAvatarBytes(file.bytes!, file.name, mime);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Foto de perfil atualizada!')),
            );
            await _loadProfile();
            setState(() => _isUploadingAvatar = false);
          }
        }
        return;
      }

      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Usar câmera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      final file = await _mediaService.pickImageMobile(source);
      if (file != null) {
        setState(() => _isUploadingAvatar = true);
        final bytes = await file.readAsBytes();

        await _mediaService.uploadAvatarBytes(
          bytes,
          file.name,
          file.mimeType ?? 'image/jpeg',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto de perfil atualizada!')),
          );
          await _loadProfile();
          setState(() => _isUploadingAvatar = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
      }
    }
  }

  void _editProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditProfileSheet(
        user: _user,
        onSave: _updateProfile,
        onPickAvatar: _pickAndUploadAvatar,
        isUploadingAvatar: _isUploadingAvatar,
      ),
    );
  }

  Future<void> _logout() async {
    await _api.clearToken();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  // NEW HARMONIZED HEADER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 32),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () => context.go('/home'),
                              child: const Icon(
                                LucideIcons.chevronLeft,
                                color: AppTheme.textDark,
                              ),
                            ),
                            Text(
                              'Perfil',
                              style: GoogleFonts.manrope(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textDark,
                              ),
                            ),
                            const Icon(
                              LucideIcons.settings,
                              color: AppTheme.textDark,
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Avatar Section
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryYellow.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 56,
                                backgroundColor: AppTheme.backgroundLight,
                                backgroundImage:
                                    _user!['avatar_url'] != null &&
                                        !_isUploadingAvatar
                                    ? CachedNetworkImageProvider(
                                        _user!['avatar_url'],
                                      )
                                    : null,
                                child: _isUploadingAvatar
                                    ? const CircularProgressIndicator(
                                        strokeWidth: 2,
                                      )
                                    : (_user!['avatar_url'] == null
                                          ? Text(
                                              (_user!['name'] ?? 'U')[0]
                                                  .toUpperCase(),
                                              style: GoogleFonts.manrope(
                                                fontSize: 40,
                                                color: AppTheme.textDark,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          : null),
                              ),
                            ),
                            GestureDetector(
                              onTap: _pickAndUploadAvatar,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryYellow,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  LucideIcons.edit2,
                                  color: AppTheme.textDark,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        Text(
                          _user!['name'] ?? 'Usuário',
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          'Membro desde ${DateFormat('MMMM yyyy').format(DateTime.now())}', // Mock date for now
                          style: GoogleFonts.manrope(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // BALANCE CARD
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: AppTheme.surfacedCardDecoration(
                        color: Colors.white,
                        radius: 24,
                        shadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SALDO DISPONÍVEL',
                                style: GoogleFonts.manrope(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.textMuted,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'R\$ 250,00',
                                style: GoogleFonts.manrope(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.primaryYellow,
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _notAvailable(
                              'Adicionar saldo estará disponível em breve.',
                            ),
                            icon: const Icon(LucideIcons.plusCircle, size: 18),
                            label: Text(
                              'ADICIONAR',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryYellow,
                              foregroundColor: AppTheme.textDark,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // SETTINGS LIST
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: AppTheme.surfacedCardDecoration(
                        color: Colors.white,
                        radius: 24,
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                            child: Text(
                              'ACCOUNT SETTINGS',
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textMuted,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          _buildSettingItem(
                            icon: LucideIcons.user,
                            label: 'Personal Information',
                            onTap: _editProfile,
                          ),
                          _buildSettingItem(
                            icon: LucideIcons.creditCard,
                            label: 'Formas de Pagamento',
                            onTap: () => context.push('/payment-methods'),
                          ),
                          _buildSettingItem(
                            icon: LucideIcons.mapPin,
                            label: 'My Addresses',
                            onTap: () => _notAvailable(
                              'Cadastro de endereços estará disponível em breve.',
                            ),
                          ),
                          _buildSettingItem(
                            icon: LucideIcons.shieldCheck,
                            label: 'Security & Privacy',
                            onTap: () => _notAvailable(
                              'Segurança e privacidade estarão disponíveis em breve.',
                            ),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: _buildSettingItem(
                        icon: LucideIcons.helpCircle,
                        label: 'Help & Support',
                        onTap: () => _notAvailable(
                          'Central de ajuda estará disponível em breve.',
                        ),
                        isLast: true,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // LOGOUT
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: TextButton.icon(
                        onPressed: _logout,
                        icon: const Icon(LucideIcons.logOut, color: Colors.red),
                        label: Text(
                          'LOGOUT',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                            color: Colors.red,
                            letterSpacing: 1,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text(
                    'Version 1.0.42 (Production)',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isLast = false,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(color: Colors.grey.shade100, width: 1),
                ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (color ?? AppTheme.textDark).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color ?? AppTheme.textDark),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppTheme.textDark,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic>? user;
  final Future<void> Function(String name, String email, String phone) onSave;
  final VoidCallback onPickAvatar;
  final bool isUploadingAvatar;

  const _EditProfileSheet({
    required this.user,
    required this.onSave,
    required this.onPickAvatar,
    required this.isUploadingAvatar,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?['name']);
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.textDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'SALVAR ALTERAÇÕES',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: AppTheme.textMuted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppTheme.textDark,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: AppTheme.textDark),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppTheme.primaryYellow, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          validator: (v) => v?.isNotEmpty == true ? null : 'Campo obrigatório',
        ),
      ],
    );
  }
}
