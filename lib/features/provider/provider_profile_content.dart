
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import 'widgets/provider_profile_widgets.dart';

class ProviderProfileContent extends StatefulWidget {
  const ProviderProfileContent({super.key});

  @override
  State<ProviderProfileContent> createState() => _ProviderProfileContentState();
}

class _ProviderProfileContentState extends State<ProviderProfileContent> {
  Uint8List? _avatarBytes;
  final _media = MediaService();
  final _api = ApiService();
  List<String> _specialties = [];
  List<String> _availableProfessions = [];
  bool _isLoadingSpecialties = false;
  String _userName = 'Carregando...';
  String _userPhone = '';
  bool _isVerified = false;
  double _walletBalance = 0.0;

  bool _isMedical = false;

  @override
  void initState() {
    super.initState();
    _isMedical = _api.isMedical;
    _loadProfile();
    _loadAvatar();
    _loadSpecialties();
    _loadAvailableProfessions();
  }

  Future<void> _loadAvailableProfessions() async {
    try {
      final list = await _api.getProfessions();
      if (mounted) {
        setState(() {
          _availableProfessions = list
              .map((e) => e['name'].toString())
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _api.getMyProfile();
      if (mounted) {
        setState(() {
          _userName = user['name'] ?? user['full_name'] ?? 'Usuário';
          _userPhone = user['phone'] ?? '';
          _isVerified = user['is_verified'] == true;
          _walletBalance = (user['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
    }
  }

  Future<void> _loadSpecialties() async {
    setState(() => _isLoadingSpecialties = true);
    try {
      final list = await _api.getProviderSpecialties();
      if (mounted) {
        setState(() {
          _specialties = list;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar especialidades: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSpecialties = false);
    }
  }

  void _showWithdrawalDialog() async {
    final success = await showDialog<bool>(
      context: context,
      builder: (context) => WithdrawalDialog(api: _api, currentBalance: _walletBalance),
    );
    if (success == true) {
      _loadProfile();
    }
  }

  void _showEditSpecialtiesDialog() {
    showDialog(
      context: context,
      builder: (context) => SpecialtiesDialog(
        api: _api,
        availableProfessions: _availableProfessions,
        currentSpecialties: _specialties,
        onAdded: (name) {
          setState(() {
            if (!_specialties.contains(name)) _specialties.add(name);
          });
        },
        onRemoved: (name) {
          setState(() {
            _specialties.remove(name);
          });
        },
      ),
    );
  }

  void _showEditProfileDialog() async {
    final success = await showDialog<bool>(
      context: context,
      builder: (context) => EditProfileDialog(
        api: _api,
        currentName: _userName,
        currentPhone: _userPhone,
      ),
    );
    if (success == true) {
      _loadProfile();
    }
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (bytes != null) {
        setState(() => _avatarBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _editAvatar() async {
    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res != null &&
          res.files.isNotEmpty &&
          res.files.first.bytes != null) {
        final file = res.files.first;
        final mime = file.extension != null
            ? 'image/${file.extension}'
            : 'image/jpeg';
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _loadAvatar();
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
    final xfile = await _media.pickImageMobile(source);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      await _media.uploadAvatarBytes(bytes, xfile.name, 'image/jpeg');
      await _loadAvatar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.only(
              top: 50,
              left: 24,
              right: 24,
              bottom: 14,
            ),
            decoration: BoxDecoration(color: AppTheme.primaryYellow),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            image: _avatarBytes != null
                                ? DecorationImage(
                                    image: MemoryImage(_avatarBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _avatarBytes == null
                              ? const Center(
                                  child: Text(
                                    'CS',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: InkWell(
                            onTap: _editAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit,
                                size: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Olá,',
                          style: TextStyle(color: Colors.black54),
                        ),
                        Row(
                            children: [
                              Text(
                                _userName,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (_isVerified)
                                Icon(
                                  LucideIcons.checkCircle,
                                  color: AppTheme.successGreen,
                                  size: 14,
                                )
                              else
                                const Icon(
                                  LucideIcons.edit3,
                                  color: Colors.black54,
                                  size: 14,
                                ),
                            ],
                        ),
                      ],
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _showWithdrawalDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.bell, color: Colors.black87),
                          const SizedBox(width: 12),
                          const Text(
                            'Saldo disponível',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.wallet,
                            color: Colors.black87,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'R\$ ${_walletBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // Specialties
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Profissões',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (!_isMedical)
                            InkWell(
                              onTap: _showEditSpecialtiesDialog,
                              child: const Padding(
                                padding: EdgeInsets.all(4.0),
                                child: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingSpecialties)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _specialties
                              .map(
                                (e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryYellow,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    e,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Metrics
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        LucideIcons.trendingUp,
                        Colors.orange,
                        '4.9',
                        '128 avaliações',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        LucideIcons.zap,
                        Colors.green,
                        '92%',
                        'Taxa de aceitação',
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// CurrencyInputFormatter and _buildMetricCard remain the same but cleaner widget structure helps.
