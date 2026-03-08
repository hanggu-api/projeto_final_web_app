import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/api_service.dart';
import '../../services/uber_service.dart';

class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  final ApiService _api = ApiService();
  final UberService _uberService = UberService();
  Map<String, dynamic>? _user;
  bool _isLoading = true;

  // Preferências
  bool _acceptsRides = true;
  bool _acceptsServices = false;
  final bool _acceptsDeliveries = false; // Bloqueado conforme pedido

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await _api.getMyProfile();
      // Mocking/Reading preferences if they exist in DB
      setState(() {
        _user = profile;
        _acceptsRides = userAcceptsRides(profile);
        _acceptsServices = userAcceptsServices(profile);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool userAcceptsRides(Map<String, dynamic> profile) {
    // Implementar lógica real se o campo existir no banco
    return profile['accepts_rides'] ?? true;
  }

  bool userAcceptsServices(Map<String, dynamic> profile) {
    return profile['accepts_services'] ?? false;
  }

  Future<void> _togglePreference(String type, bool value) async {
    if (type == 'deliveries') return; // Bloqueado

    setState(() {
      if (type == 'rides') _acceptsRides = value;
      if (type == 'services') _acceptsServices = value;
    });

    try {
      // Salvar no banco via ApiService/UberService
      final field = type == 'rides' ? 'accepts_rides' : 'accepts_services';
      await _api.updateProfile(customFields: {field: value});
    } catch (e) {
      debugPrint('Erro ao salvar preferência: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          // Header (Ricardo Oliveira Style)
          _buildHeader(),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),

                  _buildSectionTitle("CONTA"),
                  _buildMenuCard([
                    _buildMenuItem(
                      label: "Dados Pessoais",
                      subtitle: "Nome, email e telefone",
                      icon: LucideIcons.user,
                      onTap: () {},
                    ),
                    _buildMenuItem(
                      label: "Veículo e Documentos",
                      subtitle: _getVehicleSummary(),
                      icon: LucideIcons.car,
                      onTap: () {},
                      isLast: true,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionTitle("PREFERÊNCIAS DE TRABALHO"),
                  _buildMenuCard([
                    _buildToggleItem(
                      label: "Corridas",
                      icon: LucideIcons.mapPin,
                      value: _acceptsRides,
                      onChanged: (v) => _togglePreference('rides', v),
                    ),
                    _buildToggleItem(
                      label: "Serviços",
                      icon: LucideIcons.briefcase,
                      value: _acceptsServices,
                      onChanged: (v) => _togglePreference('services', v),
                    ),
                    _buildToggleItem(
                      label: "Entregas",
                      icon: LucideIcons.package,
                      value: _acceptsDeliveries,
                      onChanged: (v) {},
                      disabled: true,
                      isLast: true,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionTitle("FINANCEIRO E SEGURANÇA"),
                  _buildMenuCard([
                    _buildMenuItem(
                      label: "Meios de Pagamento",
                      subtitle: "Quais métodos você aceita",
                      icon: LucideIcons.creditCard,
                      onTap: () => _showPaymentMethods(),
                    ),
                    _buildMenuItem(
                      label: "Conta Bancária e Repasses",
                      icon: LucideIcons.landmark,
                      onTap: () {},
                    ),
                    _buildMenuItem(
                      label: "Segurança",
                      subtitle: "Senha e Biometria ativa",
                      icon: LucideIcons.shield,
                      onTap: () {},
                      isLast: true,
                    ),
                  ]),

                  const SizedBox(height: 32),

                  _buildLogoutButton(),

                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      "101 SERVICE V2.4.0",
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade400,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
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
                onTap: () => context.pop(),
                child: const Icon(
                  LucideIcons.chevronLeft,
                  color: Color(0xFF1A1D1E),
                ),
              ),
              Text(
                'Configurações',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1D1E),
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),
          const SizedBox(height: 32),

          // Avatar with yellow border and check mark
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700), // AppTheme.primaryYellow
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: _user?['avatar_url'] != null
                      ? CachedNetworkImageProvider(_user!['avatar_url'])
                      : null,
                  child: _user?['avatar_url'] == null
                      ? const Icon(
                          LucideIcons.user,
                          size: 40,
                          color: Colors.grey,
                        )
                      : null,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.black),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Text(
            _user?['full_name'] ?? 'Motorista',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1A1D1E),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: Color(0xFFFFD700), size: 16),
                const SizedBox(width: 4),
                Text(
                  (_user?['rating_avg'] ?? 5.0).toString(),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1D1E),
                  ),
                ),
                Text(
                  " • ${_user?['rating_count'] ?? 0} corridas",
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade500,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required String label,
    String? subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFFE6B800), size: 20),
      ),
      title: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1D1E),
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            )
          : null,
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildToggleItem({
    required String label,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
    bool disabled = false,
    bool isLast = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFFE6B800), size: 20),
      ),
      title: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: disabled ? Colors.grey.shade400 : const Color(0xFF1A1D1E),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: disabled ? null : onChanged,
        activeThumbColor: const Color(0xFFFFD700),
        activeTrackColor: const Color(0xFFFFD700).withValues(alpha: 0.3),
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: Colors.grey.shade200,
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: TextButton.icon(
        onPressed: () => _logout(),
        icon: const Icon(LucideIcons.logOut, color: Colors.red, size: 20),
        label: Text(
          "Sair da Conta",
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.red,
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.1)),
          ),
        ),
      ),
    );
  }

  String _getVehicleSummary() {
    // Toyota Corolla • ABC-1234 • CNH Ativa
    final vehicle = _user?['vehicles'] != null
        ? (_user!['vehicles'] as List).firstOrNull
        : null;
    if (vehicle == null) return "Cadastrar veículo";
    return "${vehicle['brand']} ${vehicle['model']} • ${vehicle['plate']} • CNH Ativa";
  }

  void _showPaymentMethods() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PaymentMethodsSheet(
        userId: _api.userId!,
        uberService: _uberService,
        currentPixKey: _user?['pix_key'] ?? '',
        onSaved: () => _loadData(), // Recarregar dados após salvar
      ),
    );
  }

  Future<void> _logout() async {
    await _api.clearToken();
    if (mounted) context.go('/login');
  }
}

class _PaymentMethodsSheet extends StatefulWidget {
  final int userId;
  final UberService uberService;
  final String currentPixKey;
  final VoidCallback onSaved;

  const _PaymentMethodsSheet({
    required this.userId,
    required this.uberService,
    required this.currentPixKey,
    required this.onSaved,
  });

  @override
  State<_PaymentMethodsSheet> createState() => _PaymentMethodsSheetState();
}

class _PaymentMethodsSheetState extends State<_PaymentMethodsSheet> {
  bool _acceptsPix = true;
  bool _acceptsCardMachine = false;
  late TextEditingController _pixKeyController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pixKeyController = TextEditingController(text: widget.currentPixKey);
    _load();
  }

  @override
  void dispose() {
    _pixKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await widget.uberService.getDriverPaymentPreferences(
      widget.userId,
    );
    setState(() {
      _acceptsPix = prefs['pix_direct'] ?? true;
      _acceptsCardMachine = prefs['card_machine'] ?? false;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('users')
          .update({
            'accepts_pix_direct': _acceptsPix,
            'accepts_card_machine': _acceptsCardMachine,
            'pix_key': _pixKeyController.text.trim(),
          })
          .eq('id', widget.userId);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Erro ao salvar pagamentos: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Métodos de Pagamento",
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Selecione quais métodos você aceita receber",
              style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            _buildOption(
              "PIX Direto",
              "Receba na sua conta via chave PIX",
              _acceptsPix,
              (v) => setState(() => _acceptsPix = v),
            ),

            // Campo de Chave PIX (aparece quando PIX está ativo)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              child: _acceptsPix
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SUA CHAVE PIX",
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade500,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _pixKeyController,
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  "CPF, telefone, e-mail ou chave aleatória",
                              hintStyle: GoogleFonts.manrope(
                                fontSize: 14,
                                color: Colors.grey.shade400,
                              ),
                              prefixIcon: const Icon(
                                Icons.pix,
                                color: Color(0xFF00BDAE),
                                size: 22,
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFFFD700),
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            _buildOption(
              "Máquina de Cartão",
              "Você possui maquininha física",
              _acceptsCardMachine,
              (v) => setState(() => _acceptsCardMachine = v),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      "SALVAR",
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                    ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(String title, String sub, bool val, Function(bool) on) {
    return SwitchListTile(
      title: Text(
        title,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(sub, style: GoogleFonts.manrope(fontSize: 12)),
      value: val,
      onChanged: on,
      activeThumbColor: const Color(0xFFFFD700),
    );
  }
}
