
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import 'package:service_101/services/notification_service.dart' as ns;

class ClientSettingsScreen extends StatefulWidget {
  const ClientSettingsScreen({super.key});

  @override
  State<ClientSettingsScreen> createState() => _ClientSettingsScreenState();
}

class _ClientSettingsScreenState extends State<ClientSettingsScreen> {
  final ApiService _api = ApiService();
  final MediaService _mediaService = MediaService();
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _api.getMyProfile();
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
        if (result != null && result.files.isNotEmpty && result.files.first.bytes != null) {
           setState(() => _isUploadingAvatar = true);
           final file = result.files.first;
           final mime = file.extension != null ? 'image/${file.extension}' : 'image/jpeg';
           
           await _mediaService.uploadAvatarBytes(
             file.bytes!,
             file.name,
             mime,
           );
           
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

      final file = await _mediaService.pickImageMobile(ImageSource.gallery);
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
          await _loadProfile(); // Await reload
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EditProfileSheet(
        user: _user,
        onSave: _updateProfile,
        onPickAvatar: _pickAndUploadAvatar,
        isUploadingAvatar: _isUploadingAvatar,
      ),
    );
  }

  void _showActivityLog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Histórico de Atividades',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _api.getMyServices(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Erro: ${snapshot.error}'));
                  }
                  final services = snapshot.data ?? [];
                  if (services.isEmpty) {
                    return const Center(
                      child: Text('Nenhuma atividade encontrada.'),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: services.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, index) {
                      final service = services[index];
                      final date = DateTime.tryParse(
                        service['created_at'] ?? '',
                      );
                      final formattedDate = date != null
                          ? DateFormat('dd/MM/yyyy HH:mm').format(date)
                          : '';
                      return ListTile(
                        leading: const Icon(
                          LucideIcons.history,
                          color: Colors.grey,
                        ),
                        title: Text(
                          service['description'] ?? 'Serviço sem descrição',
                        ),
                        subtitle: Text('$formattedDate • ${service['status']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Could navigate to details if needed
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                   // Custom Yellow Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(
                      top: 60,
                      bottom: 40,
                      left: 24,
                      right: 24,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryYellow,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
                              onPressed: () => context.pop(),
                            ),
                            Text(
                              'Configurações',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.darkBlueText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_user != null) ...[
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.white,
                              backgroundImage: _user!['avatar_url'] != null && !_isUploadingAvatar
                                  ? CachedNetworkImageProvider(_user!['avatar_url'])
                                  : null,
                              child: _isUploadingAvatar
                                  ? const CircularProgressIndicator()
                                  : (_user!['avatar_url'] == null
                                      ? Text(
                                          (_user!['name'] ?? 'U')[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 36,
                                            color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _user!['name'] ?? 'Usuário',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          Text(
                            _user!['email'] ?? '',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _editProfile,
                            icon: const Icon(LucideIcons.edit2, size: 18),
                            label: const Text('Editar Perfil'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              minimumSize: const Size(200, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Settings List
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildSettingTile(
                          icon: LucideIcons.history,
                          color: Colors.blue,
                          title: 'Histórico de Atividades',
                          onTap: _showActivityLog,
                        ),
                        if (_api.role == 'provider') ...[
                           if (_user?['is_fixed_location'] == true) ...[
                            const SizedBox(height: 16),
                            _buildSettingTile(
                              icon: LucideIcons.calendarClock,
                              color: Colors.deepPurple,
                              title: 'Horário de Funcionamento',
                              onTap: () => context.push('/provider-schedule-settings'),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _buildSettingTile(
                            icon: LucideIcons.layers,
                            color: Colors.orange,
                            title: 'Permissões Avançadas',
                            subtitle: 'Habilitar sobreposição de tela',
                            onTap: () => ns.NotificationService().showOverlayExplanationAndRequest(context),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildSettingTile(
                          icon: LucideIcons.logOut,
                          color: Colors.red,
                          title: 'Sair',
                          onTap: _logout,
                          textColor: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor ?? Colors.black87,
          ),
        ),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    _phoneController = TextEditingController(text: widget.user?['phone']);
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
      if (!_emailController.text.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email inválido')),
        );
        return;
      }
      
      setState(() => _isSaving = true);
      await widget.onSave(
        _nameController.text,
        _emailController.text,
        _phoneController.text,
      );
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Editar Perfil',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Avatar Header inside Modal
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).primaryColor,
                    backgroundImage: widget.user?['avatar_url'] != null && !widget.isUploadingAvatar
                        ? CachedNetworkImageProvider(widget.user!['avatar_url'])
                        : null,
                    child: widget.isUploadingAvatar
                        ? const CircularProgressIndicator()
                        : (widget.user?['avatar_url'] == null
                            ? Text(
                                (widget.user?['name'] ?? 'U')[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 32,
                                  color: Colors.black87,
                                ),
                              )
                            : null),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        widget.onPickAvatar();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          size: 20,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
              validator: (v) => v?.isNotEmpty == true ? null : 'Nome obrigatório',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => v?.isNotEmpty == true ? null : 'Email obrigatório',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Telefone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.black87,
              ),
              child: _isSaving 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
