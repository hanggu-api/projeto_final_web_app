import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/profile/backend_profile_api.dart';
import '../../core/config/supabase_config.dart';
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
  final BackendProfileApi _backendProfileApi = const BackendProfileApi();
  List<String> _specialties = [];
  List<String> _availableProfessions = [];
  List<Map<String, dynamic>> _scheduleConfigs = [];
  bool _isLoadingSpecialties = false;
  String _userName = 'Carregando...';
  String _userEmail = 'Carregando...';
  String _userPhone = '';
  String _commercialName = '';
  String _providerAddress = '';
  bool _isFixedProfile = false;
  bool _isVerified = false;
  double _walletBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadAvatar();
    _loadSpecialties();
    _loadAvailableProfessions();
    _loadScheduleConfig();
  }

  Future<void> _loadAvailableProfessions() async {
    if (!SupabaseConfig.isInitialized) {
      if (mounted) setState(() => _availableProfessions = []);
      return;
    }
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
    if (!SupabaseConfig.isInitialized) {
      if (mounted) {
        setState(() {
          _userName = 'Usuário';
          _userEmail = 'email@exemplo.com';
          _isVerified = false;
          _walletBalance = 0.0;
        });
      }
      return;
    }
    try {
      final backendProfile = await _backendProfileApi.fetchMyProfile();
      if (backendProfile == null) {
        throw Exception('Perfil canônico indisponível.');
      }
      final user = backendProfile.toApiUserMap();
      final providersRel = user['providers'];
      final providerData = providersRel is List
          ? (providersRel.isNotEmpty && providersRel.first is Map
                ? Map<String, dynamic>.from(providersRel.first as Map)
                : <String, dynamic>{})
          : (providersRel is Map
                ? Map<String, dynamic>.from(providersRel)
                : <String, dynamic>{});
      if (mounted) {
        setState(() {
          _userName = user['name'] ?? user['full_name'] ?? 'Usuário';
          _userEmail = user['email'] ?? 'email@exemplo.com';
          _userPhone = (user['phone'] ?? '').toString();
          _commercialName = (providerData['commercial_name'] ?? _userName)
              .toString();
          _providerAddress = (providerData['address'] ?? '').toString();
          _isFixedProfile = user['is_fixed_location'] == true;
          _isVerified = user['is_verified'] == true;
          final walletRaw =
              user['wallet_balance_effective'] ??
              user['wallet_balance'] ??
              user['balance'] ??
              0;
          _walletBalance = walletRaw is num
              ? walletRaw.toDouble()
              : double.tryParse('$walletRaw') ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil: $e');
      if (mounted) {
        setState(() {
          _userName = 'Usuário';
          _userEmail = 'email@exemplo.com';
        });
      }
    }
  }

  Future<void> _loadScheduleConfig() async {
    try {
      final configs = await _api.getScheduleConfig();
      if (!mounted) return;
      setState(() {
        _scheduleConfigs = configs
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      debugPrint('Erro ao carregar horários do prestador: $e');
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
    if (_isFixedProfile) return;
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

  Future<void> _showEditPersonalDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => EditProfileDialog(
        api: _api,
        currentName: _userName,
        currentPhone: _userPhone,
      ),
    );
    if (updated == true) {
      await _loadProfile();
    }
  }

  Future<void> _showEditBusinessDialog() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => EditBusinessDialog(
        api: _api,
        currentCommercialName: _commercialName,
        currentAddress: _providerAddress,
      ),
    );
    if (updated == true) {
      await _loadProfile();
    }
  }

  Future<void> _editSchedule() async {
    final result = await context.push('/provider-schedule');
    if (result != null) {
      await _loadScheduleConfig();
    } else {
      await _loadScheduleConfig();
    }
  }

  double _contentBottomInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.viewPadding.bottom + 140;
  }

  String _formatScheduleSummary() {
    final enabled =
        _scheduleConfigs.where((item) {
          final raw = item['is_enabled'];
          return raw == true || raw == 1 || raw == 'true';
        }).toList()..sort(
          (a, b) => ((a['day_of_week'] as num?)?.toInt() ?? 0).compareTo(
            ((b['day_of_week'] as num?)?.toInt() ?? 0),
          ),
        );

    if (enabled.isEmpty) {
      return 'Nenhum horário configurado.';
    }

    final first = enabled.first;
    final start = (first['start_time'] ?? '').toString();
    final end = (first['end_time'] ?? '').toString();
    final totalDays = enabled.length;
    final startLabel = start.length >= 5 ? start.substring(0, 5) : start;
    final endLabel = end.length >= 5 ? end.substring(0, 5) : end;
    return '$totalDays dias ativos • $startLabel às $endLabel';
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    VoidCallback? onEdit,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.surfacedCardDecoration(
        color: Colors.white,
        radius: 24,
        border: Border.all(
          color: AppTheme.primaryYellow.withOpacity(0.18),
          width: 1.2,
        ),
        shadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppTheme.textMuted),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(
                    LucideIcons.edit3,
                    size: 16,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value.isEmpty ? 'Não informado' : value,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  bool _isUploadingAvatar = false;

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
        setState(() => _isUploadingAvatar = true);
        try {
          await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
          await _loadAvatar();
          await _loadProfile();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Foto de perfil atualizada com sucesso!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao enviar foto: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _isUploadingAvatar = false);
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
    final xfile = await _media.pickImageMobile(source);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      final ext = xfile.name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      setState(() => _isUploadingAvatar = true);
      try {
        await _media.uploadAvatarBytes(bytes, xfile.name, mime);
        await _loadAvatar();
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto de perfil atualizada com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao enviar foto: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploadingAvatar = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = _contentBottomInset(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        bottom: true,
        child: CustomScrollView(
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
                                  onTap: _isUploadingAvatar
                                      ? null
                                      : _editAvatar,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.textDark,
                                      shape: BoxShape.circle,
                                    ),
                                    child: _isUploadingAvatar
                                        ? const SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
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
                                    color: AppTheme.textDark.withOpacity(0.6),
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
                            color: Colors.white.withOpacity(0.3),
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

                    if (!_isFixedProfile)
                      GestureDetector(
                        onTap: _showWithdrawalDialog,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppTheme.textDark,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
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
              padding: EdgeInsets.fromLTRB(24, 20, 24, bottomInset),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildSectionCard(
                    title: 'Dados pessoais',
                    icon: LucideIcons.user,
                    onEdit: _showEditPersonalDialog,
                    children: [
                      _buildInfoItem('Nome', _userName),
                      _buildInfoItem('Email', _userEmail),
                      _buildInfoItem('Telefone', _userPhone),
                    ],
                  ),

                  const SizedBox(height: 24),

                  if (_isFixedProfile) ...[
                    _buildSectionCard(
                      title: 'Estabelecimento',
                      icon: LucideIcons.store,
                      onEdit: _showEditBusinessDialog,
                      children: [
                        _buildInfoItem(
                          'Nome do estabelecimento',
                          _commercialName,
                        ),
                        _buildInfoItem('Endereço', _providerAddress),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],

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

                  _buildSectionCard(
                    title: _isFixedProfile
                        ? 'Serviços oferecidos'
                        : 'Minhas Profissões',
                    icon: LucideIcons.briefcase,
                    onEdit: _showEditSpecialtiesDialog,
                    children: [
                      if (_isLoadingSpecialties)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        Text(
                          _isFixedProfile
                              ? 'Edite os serviços e áreas atendidas pelo seu estabelecimento.'
                              : 'Edite as categorias em que você atende.',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                    color: AppTheme.primaryYellow.withOpacity(
                                      0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.primaryYellow.withOpacity(
                                        0.3,
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
                    ],
                  ),

                  if (_isFixedProfile) ...[
                    const SizedBox(height: 20),

                    _buildSectionCard(
                      title: 'Horário de funcionamento',
                      icon: LucideIcons.clock3,
                      onEdit: _editSchedule,
                      children: [
                        _buildInfoItem('Resumo', _formatScheduleSummary()),
                        Text(
                          'Toque no lápis para editar expediente, intervalo e dias ativos.',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                  ] else ...[
                    const SizedBox(height: 32),
                  ],
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
                  SizedBox(
                    height: MediaQuery.of(context).viewPadding.bottom + 36,
                  ),
                ]),
              ),
            ),
          ],
        ),
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
