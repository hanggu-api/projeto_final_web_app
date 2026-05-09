import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/profile/backend_profile_api.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/media_service.dart';
import '../widgets/user_avatar.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key, this.asPage = false});

  final bool asPage;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String? _userName;
  String? _role;
  String? _userId;
  String? _avatarUrl;
  int _currentIndex = 0;
  bool _isUploadingAvatar = false;
  final MediaService _media = MediaService();
  final ApiService _api = ApiService();
  final BackendProfileApi _backendProfileApi = const BackendProfileApi();

  String? _normalizeUserId(Object? userId) => userId?.toString();

  String? _normalizedText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    if (text.toLowerCase() == 'null') return null;
    return text;
  }

  String? _resolveDisplayName(Map<String, dynamic>? user) {
    if (user == null) return null;
    return _normalizedText(user['full_name']) ??
        _normalizedText(user['name']) ??
        _normalizedText(user['profile']?['full_name']) ??
        _normalizedText(user['display_name']);
  }

  String? _resolveAvatar(Map<String, dynamic>? user) {
    if (user == null) return null;
    return _normalizedText(user['avatar_url']) ??
        _normalizedText(user['photo']) ??
        _normalizedText(user['avatar']) ??
        _normalizedText(user['profile']?['avatar_url']);
  }

  void _applyResolvedProfile({
    required String? name,
    String? role,
    String? userId,
    String? avatarUrl,
  }) {
    setState(() {
      _userName = _normalizedText(name) ?? _userName ?? 'Usuário';
      _role = _normalizedText(role) ?? _role;
      _userId = _normalizedText(userId) ?? _userId;
      _avatarUrl = _normalizedText(avatarUrl) ?? _avatarUrl;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedApiUser = _api.userData;
    if (!mounted) return;
    _applyResolvedProfile(
      name:
          _resolveDisplayName(cachedApiUser) ??
          prefs.getString('user_name') ??
          prefs.getString('full_name'),
      role:
          _normalizedText(cachedApiUser?['role']) ??
          prefs.getString('user_role'),
      userId:
          _normalizedText(cachedApiUser?['id']) ??
          _normalizeUserId(prefs.get('user_id')),
      avatarUrl: _resolveAvatar(cachedApiUser) ?? prefs.getString('avatar_url'),
    );

    try {
      final canonicalProfile = await _backendProfileApi.fetchMyProfile();
      final canonicalMap = canonicalProfile?.toApiUserMap();
      if (mounted && canonicalMap != null) {
        _applyResolvedProfile(
          name: _resolveDisplayName(canonicalMap),
          role: _normalizedText(canonicalMap['role']),
          userId: _normalizedText(canonicalMap['id']),
        );
      }
    } catch (_) {
      // Keep cached data when canonical profile fetch fails
    }

    try {
      final profile = await _api.getMyProfile();
      if (!mounted) return;
      _applyResolvedProfile(
        name: _resolveDisplayName(profile),
        role: _normalizedText(profile['role']),
        userId: _normalizedText(profile['id']),
        avatarUrl: _resolveAvatar(profile),
      );
    } catch (_) {
      // Keep cached data when profile fetch fails
    }
  }

  Future<void> _editAvatar() async {
    if (_isUploadingAvatar) return;

    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
        return;
      }
      final file = res.files.first;
      final ext = file.extension?.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';

      setState(() => _isUploadingAvatar = true);
      try {
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _loadUserData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil atualizada com sucesso!'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
      } finally {
        if (mounted) setState(() => _isUploadingAvatar = false);
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
    if (xfile == null) return;

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
      await _loadUserData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  void _openProfilePage() {
    final role = (_role ?? '').trim().toLowerCase();
    final route = (role == 'provider' || role == 'driver')
        ? '/my-provider-profile'
        : '/client-settings';
    context.pop();
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = _role == 'provider' || _role == 'driver';
    final content = Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildMenuList(isProvider),
              ],
            ),
          ),
        ),
        _buildLogoutButton(),
        _buildFooter(),
      ],
    );

    if (widget.asPage) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(top: false, child: content),
      );
    }

    return Drawer(
      backgroundColor: Colors.white,
      width: MediaQuery.of(context).size.width * 0.85,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: content,
    );
  }

  Widget _buildHeader() {
    final canEditAvatar = _role == 'provider' || _role == 'driver';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 40,
        left: 32,
        right: 32,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
        borderRadius: const BorderRadius.only(topRight: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  InkWell(
                    onTap: _openProfilePage,
                    borderRadius: BorderRadius.circular(40),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 180,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Center(
                        child: UserAvatar(
                          avatar: _avatarUrl,
                          name: _userName ?? 'U',
                          userId: _userId,
                          radius: 32,
                          showOnlineStatus: true,
                        ),
                      ),
                    ),
                  ),
                  if (canEditAvatar)
                    GestureDetector(
                      onTap: _isUploadingAvatar ? null : _editAvatar,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black87,
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
              if (canEditAvatar)
                Text(
                  'Toque na câmera para alterar',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark.withOpacity(0.65),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: _openProfilePage,
            borderRadius: BorderRadius.circular(8),
            child: Text(
              _userName ?? 'Usuário',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildMenuList(bool isProvider) {
    final passengerItems = [
      _DrawerNavItem(label: 'Início', icon: LucideIcons.home, route: '/home'),
      _DrawerNavItem(
        label: 'Atividade',
        icon: LucideIcons.activity,
        route: '/activity',
      ),
      _DrawerNavItem(
        label: 'Pagamento',
        icon: LucideIcons.creditCard,
        route: '/payment-methods',
      ),
      _DrawerNavItem(
        label: 'Segurança',
        icon: LucideIcons.shield,
        route: '/security',
      ),
      _DrawerNavItem(
        label: 'Configurações',
        icon: LucideIcons.settings,
        route: '/general-settings',
      ),
      _DrawerNavItem(
        label: 'Ajuda',
        icon: LucideIcons.helpCircle,
        route: '/help',
      ),
    ];

    final providerItems = [
      _DrawerNavItem(
        label: 'Início',
        icon: LucideIcons.home,
        route: '/provider-home',
      ),
      _DrawerNavItem(
        label: 'Atividade',
        icon: LucideIcons.activity,
        route: '/activity',
      ),
      _DrawerNavItem(
        label: 'Pagamento',
        icon: LucideIcons.banknote,
        route: '/payment-onboarding',
      ),
      _DrawerNavItem(
        label: 'Segurança',
        icon: LucideIcons.shield,
        route: '/security',
      ),
      _DrawerNavItem(
        label: 'Configurações',
        icon: LucideIcons.settings,
        route: '/my-provider-profile',
      ),
      _DrawerNavItem(
        label: 'Ajuda',
        icon: LucideIcons.helpCircle,
        route: '/chats',
      ),
    ];

    final items = isProvider ? providerItems : passengerItems;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final isSelected = _currentIndex == idx;

          return _DrawerMenuTile(
            item: item,
            isSelected: isSelected,
            onTap: () {
              setState(() => _currentIndex = idx);
              context.pop();
              context.go(item.route);
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: InkWell(
        onTap: () async {
          if (!context.mounted) return;
          context.pop();
          await ApiService().clearToken();
          if (!context.mounted) return;
          context.go('/login');
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.errorRed.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.logOut, color: AppTheme.errorRed, size: 20),
              const SizedBox(width: 12),
              Text(
                'SAIR DA CONTA',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppTheme.errorRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          Text(
            '101 SERVICE V2.4.0',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppTheme.textMuted.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerNavItem {
  final String label;
  final IconData icon;
  final String route;

  _DrawerNavItem({
    required this.label,
    required this.icon,
    required this.route,
  });
}

class _DrawerMenuTile extends StatelessWidget {
  final _DrawerNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerMenuTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryYellow : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 22, color: Colors.black),
              const SizedBox(width: 16),
              Text(
                item.label,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
