import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

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
  bool _isVerified = false;
  double _walletBalance = 0.0;

  @override
  void initState() {
    super.initState();
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
      builder: (context) =>
          WithdrawalDialog(api: _api, currentBalance: _walletBalance),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // STITCH PREMIUM HEADER
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
              decoration: BoxDecoration(
                color: AppTheme.primaryYellow,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: AppTheme.backgroundLight,
                                  backgroundImage: _avatarBytes != null
                                      ? MemoryImage(_avatarBytes!)
                                      : null,
                                  child: _avatarBytes == null
                                      ? Text(
                                          _userName.isNotEmpty
                                              ? _userName[0].toUpperCase()
                                              : 'P',
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.textDark,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              GestureDetector(
                                onTap: _editAvatar,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.textDark,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    LucideIcons.camera,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Olá,',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textDark.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _userName,
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                  if (_isVerified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      LucideIcons.checkCircle,
                                      color: Colors.blue,
                                      size: 14,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          LucideIcons.bell,
                          color: AppTheme.textDark,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // SALDO CARD PREMIUM
                  GestureDetector(
                    onTap: _showWithdrawalDialog,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.textDark,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
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
                                  color: Colors.white60,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'R\$ ${_walletBalance.toStringAsFixed(2).replaceAll('.', ',')}',
                                style: GoogleFonts.manrope(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryYellow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              LucideIcons.plus,
                              color: AppTheme.textDark,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'ATUAÇÃO',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),

                // Profissões Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Minhas Profissões',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textDark,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showEditSpecialtiesDialog,
                            child: const Icon(
                              LucideIcons.edit3,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_isLoadingSpecialties)
                        const Center(child: CircularProgressIndicator())
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _specialties
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryYellow.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.primaryYellow.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    s,
                                    style: GoogleFonts.manrope(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                Text(
                  'DESEMPENHO',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        LucideIcons.star,
                        Colors.orange,
                        '4.9',
                        'Avaliação',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        LucideIcons.checkCircle,
                        Colors.green,
                        '92%',
                        'Conclusão',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                // Botão de Sair
                TextButton.icon(
                  onPressed: () async {
                    await _api.clearToken();
                    if (!context.mounted) return;
                    context.go('/login');
                  },
                  icon: const Icon(
                    LucideIcons.logOut,
                    color: Colors.red,
                    size: 18,
                  ),
                  label: Text(
                    'SAIR DA CONTA',
                    style: GoogleFonts.manrope(
                      color: Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 50),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
