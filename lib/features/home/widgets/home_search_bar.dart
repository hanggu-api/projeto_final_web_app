import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fixed_schedule_gate.dart';
import '../../../core/home/backend_home_api.dart';
import '../../../core/utils/service_icon_mapper.dart';
import '../../../services/task_semantic_search_service.dart';

class HomeSearchBar extends StatefulWidget {
  final String? currentAddress;
  final bool isLoadingLocation;
  final bool isEnabled;
  final bool autoFocus;
  final VoidCallback? onTap;
  final Function? onServiceTypeSelected;
  final Function? onSuggestionSelected;
  final void Function(String)? onQueryChanged;
  final Function? onQuerySubmitted;
  final VoidCallback? onCloseTap;
  final List<dynamic> autocompleteItems;
  final String? seedQuery;
  final int seedVersion;
  final bool prominent;
  final bool useInternalSearch;
  final bool launcherMode;

  const HomeSearchBar({
    super.key,
    this.currentAddress,
    this.isLoadingLocation = false,
    this.isEnabled = true,
    this.autoFocus = false,
    this.onTap,
    this.onServiceTypeSelected,
    this.onSuggestionSelected,
    this.onQueryChanged,
    this.onQuerySubmitted,
    this.onCloseTap,
    this.autocompleteItems = const [],
    this.seedQuery,
    this.seedVersion = 0,
    this.prominent = false,
    this.useInternalSearch = true,
    this.launcherMode = false,
  });

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TaskSemanticSearchService _searchService = TaskSemanticSearchService();
  final BackendHomeApi _backendHomeApi = const BackendHomeApi();

  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;
  int _searchRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    if (widget.seedQuery != null && widget.seedQuery!.isNotEmpty) {
      _searchController.text = widget.seedQuery!;
    }
    _focusNode.addListener(_handleFocusChange);
    _syncExternalAutocompleteItems(widget.autocompleteItems);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incomingSeed = widget.seedQuery ?? '';
    final shouldReseed =
        widget.seedVersion != oldWidget.seedVersion &&
        incomingSeed != _searchController.text;
    if (shouldReseed) {
      _searchController.value = TextEditingValue(
        text: incomingSeed,
        selection: TextSelection.collapsed(offset: incomingSeed.length),
      );
    }

    if (!widget.useInternalSearch ||
        widget.autocompleteItems != oldWidget.autocompleteItems) {
      _syncExternalAutocompleteItems(widget.autocompleteItems);
    }
  }

  void _syncExternalAutocompleteItems(List<dynamic> items) {
    final mapped = items
        .map((item) {
          if (item is Map<String, dynamic>) {
            return Map<String, dynamic>.from(item);
          }
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return <String, dynamic>{};
        })
        .where((item) => item.isNotEmpty)
        .toList();

    if (!mounted) {
      _suggestions = mapped;
      _isLoading = false;
      return;
    }

    setState(() {
      _suggestions = mapped;
      _isLoading = false;
    });
  }

  void _onChanged(String query) {
    widget.onQueryChanged?.call(query);

    if (widget.launcherMode || !widget.useInternalSearch) {
      _debounce?.cancel();
      if (_isLoading) {
        setState(() => _isLoading = false);
      }
      return;
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final requestVersion = ++_searchRequestVersion;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length < 2) {
        setState(() {
          _suggestions = [];
          _isLoading = false;
        });
        return;
      }

      setState(() => _isLoading = true);
      try {
        final snapshot = await _backendHomeApi.fetchClientHome();
        final catalog = List<Map<String, dynamic>>.from(
          snapshot?.services ?? const [],
        );
        final serviceResults = await _searchService.search(
          query: query,
          catalog: catalog,
          context: 'home_search_bar',
        );
        if (!mounted || requestVersion != _searchRequestVersion) return;

        final serviceSuggestions = serviceResults
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

        if (mounted && requestVersion == _searchRequestVersion) {
          setState(() {
            _suggestions = serviceSuggestions;
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('❌ [HomeSearchBar] Erro na busca: $e');
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _handleSuggestionTap(Map<String, dynamic> suggestion) {
    final name = suggestion['task_name'] ?? suggestion['name'] ?? '';
    final type = (suggestion['service_type'] ?? '').toString();
    debugPrint(
      '🖱️ [HomeSearchBar] Sugestão: $name | Type: ${type.isEmpty ? 'NULO' : type}',
    );

    _searchController.text = name.toString();
    setState(() => _suggestions = []);
    widget.onQueryChanged?.call(name.toString());

    if (widget.onSuggestionSelected != null) {
      widget.onSuggestionSelected!(suggestion);
    }
  }

  bool get _isProfessionCatalogMode {
    if (_suggestions.isEmpty) return false;
    if (_suggestions.any(
      (item) => (item['kind'] ?? '').toString() == 'provider_profile',
    )) {
      return false;
    }
    final professionNames = _suggestions
        .map((item) => (item['profession_name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final seededByProfession = _suggestions.every(
      (item) => (item['is_profession_seed'] ?? false) == true,
    );
    return seededByProfession && professionNames.length == 1;
  }

  String _formatCurrency(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'R\$ ${parsed.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _serviceTypeLabel(String rawType) {
    switch (rawType.trim().toLowerCase()) {
      case 'at_provider':
      case 'fixed':
        return 'No estabelecimento';
      case 'on_site':
      case 'mobile':
        return 'Atendimento movel';
      case 'provider_profile':
        return 'Perfil';
      default:
        return 'Servico';
    }
  }

  bool _isCanonicalFixedSuggestion(Map<String, dynamic> item) {
    final service = item['service'] is Map
        ? Map<String, dynamic>.from(item['service'] as Map)
        : <String, dynamic>{};
    final seed = <String, dynamic>{...service, ...item};
    return isCanonicalFixedServiceRecord(seed);
  }

  String _pricingLabel(Map<String, dynamic> item) {
    final pricingType = (item['pricing_type'] ?? '').toString().trim();
    final unitName = (item['unit_name'] ?? '').toString().trim();
    if (unitName.isNotEmpty) {
      return 'Preco por $unitName';
    }
    switch (pricingType) {
      case 'hourly':
        return 'Preco por hora';
      case 'daily':
        return 'Preco por dia';
      case 'fixed':
      default:
        return 'Preco inicial';
    }
  }

  Widget _buildProfessionCatalogList() {
    final professionName =
        (_suggestions.first['profession_name'] ?? 'Profissao').toString();

    return Container(
      margin: const EdgeInsets.fromLTRB(5, 8, 5, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            professionName,
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_suggestions.length} servicos dessa profissao',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 14),
          ..._suggestions.map((item) {
            final name = (item['task_name'] ?? item['name'] ?? '')
                .toString()
                .trim();
            final price = item['unit_price'] ?? item['price'];
            final serviceType = (item['service_type'] ?? '').toString();
            final serviceTypeLabel = _serviceTypeLabel(serviceType);
            final pricingLabel = _pricingLabel(item);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _handleSuggestionTap(item),
                  child: Ink(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundLight,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            ServiceIconMapper.fromService(
                              taskName: name,
                              professionName: professionName,
                            ),
                            color: AppTheme.primaryYellow,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildMetaPill(
                                    label: serviceTypeLabel,
                                    textColor: Colors.blue.shade800,
                                    backgroundColor: Colors.blue.shade50,
                                  ),
                                  _buildMetaPill(
                                    label: pricingLabel,
                                    textColor: Colors.grey.shade700,
                                    backgroundColor: Colors.grey.shade100,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatCurrency(price),
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Icon(LucideIcons.chevronRight, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMetaPill({
    required String label,
    required Color textColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isFocused = _focusNode.hasFocus;
    final showInlineSuggestions =
        !widget.launcherMode && _suggestions.isNotEmpty;
    final suggestionMaxHeight = (mediaQuery.size.height * 0.34).clamp(
      180.0,
      320.0,
    );
    final containerMargin = widget.prominent
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(horizontal: 5);
    final containerPadding = widget.prominent
        ? const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    final containerRadius = widget.prominent ? 28.0 : 26.0;
    final iconSize = widget.prominent ? 24.0 : 22.0;
    final textSize = widget.prominent ? 17.0 : 15.0;
    final hintWeight = widget.prominent ? FontWeight.w600 : FontWeight.w500;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.isEnabled ? widget.onTap : null,
          child: Container(
            margin: containerMargin,
            constraints: BoxConstraints(minHeight: widget.prominent ? 62 : 60),
            padding: containerPadding,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(containerRadius),
              border: Border.all(
                color: isFocused
                    ? AppTheme.primaryBlue
                    : const Color(0xFFD8DEE7),
                width: isFocused ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isFocused
                      ? AppTheme.primaryBlue.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: isFocused ? 16 : 12,
                  offset: Offset(0, isFocused ? 5 : 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  color: AppTheme.primaryYellow,
                  size: iconSize,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('home-search-text-field'),
                    controller: _searchController,
                    focusNode: _focusNode,
                    enabled: widget.isEnabled,
                    readOnly: widget.launcherMode,
                    autofocus: widget.autoFocus,
                    onTap: widget.launcherMode && widget.isEnabled
                        ? widget.onTap
                        : null,
                    onChanged: _onChanged,
                    onSubmitted: (val) => widget.onQuerySubmitted?.call(val),
                    style: GoogleFonts.manrope(
                      fontSize: textSize,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          widget.currentAddress ?? 'O que você precisa hoje?',
                      hintStyle: GoogleFonts.manrope(
                        fontSize: textSize,
                        color: const Color(0xFF98A2B3),
                        fontWeight: hintWeight,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (widget.onCloseTap != null &&
                    _searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _onChanged('');
                      widget.onCloseTap?.call();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
        if (showInlineSuggestions)
          _isProfessionCatalogMode
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: suggestionMaxHeight),
                  child: SingleChildScrollView(
                    child: _buildProfessionCatalogList(),
                  ),
                )
              : Container(
                  margin: const EdgeInsets.fromLTRB(5, 8, 5, 0),
                  constraints: BoxConstraints(maxHeight: suggestionMaxHeight),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ListView.separated(
                    shrinkWrap: false,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _suggestions.length > 6
                        ? 6
                        : _suggestions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[100]),
                    itemBuilder: (context, index) {
                      final item = _suggestions[index];
                      final name = item['task_name'] ?? item['name'] ?? '';
                      final profession = item['profession_name'] ?? '';
                      final price = item['unit_price'] ?? item['price'];
                      final serviceType = (item['service_type'] ?? '')
                          .toString();
                      final isProviderProfile =
                          (item['kind'] ?? '').toString() == 'provider_profile';

                      return ListTile(
                        onTap: () => _handleSuggestionTap(item),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isProviderProfile
                                ? LucideIcons.store
                                : ServiceIconMapper.fromService(
                                    taskName: name,
                                    professionName: profession,
                                  ),
                            color: AppTheme.primaryBlue,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          name,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppTheme.textDark,
                          ),
                        ),
                        subtitle: Text(
                          isProviderProfile
                              ? ((item['address'] ??
                                        'Toque para abrir o perfil')
                                    .toString())
                              : profession.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: isProviderProfile ? 11 : 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey[500],
                            letterSpacing: isProviderProfile ? 0 : 0.3,
                          ),
                        ),
                        trailing: isProviderProfile
                            ? const Icon(LucideIcons.chevronRight, size: 16)
                            : price != null
                            ? (() {
                                final pName = (item['profession_name'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final cName = (item['category_name'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final tName =
                                    (item['task_name'] ?? item['name'] ?? '')
                                        .toString()
                                        .toLowerCase();

                                // Detecção de beleza mais restrita para evitar falsos positivos como "corte de grama"
                                final bool isActuallyBeauty =
                                    pName.contains('barba') ||
                                    pName.contains('cabelo') ||
                                    pName.contains('estét') ||
                                    pName.contains('beleza') ||
                                    cName.contains('beleza') ||
                                    (tName.contains('corte') &&
                                        (pName.contains('cabelo') ||
                                            pName.contains('barbi') ||
                                            pName.contains('cabelei'))) ||
                                    tName.contains('manicure') ||
                                    tName.contains('pedicure') ||
                                    tName.contains('unha');

                                // Prioridade máxima ao que vem do backend. Só inferimos se estiver vazio.
                                final bool isFixed = serviceType.isNotEmpty
                                    ? _isCanonicalFixedSuggestion(item)
                                    : isActuallyBeauty;
                                final accentColor = AppTheme.primaryBlue;

                                return Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 112,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFixed
                                        ? const Color(0xFFEAF3FF)
                                        : const Color(0xFFF4ECFF),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isFixed
                                          ? accentColor.withOpacity(0.22)
                                          : const Color(
                                              0xFFB78AE6,
                                            ).withOpacity(0.28),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'R\$ ${price.toStringAsFixed(2)}',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w900,
                                      color: isFixed
                                          ? accentColor
                                          : const Color(0xFF7A3FC6),
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              })()
                            : const Icon(LucideIcons.chevronRight, size: 16),
                      );
                    },
                  ),
                ),
      ],
    );
  }
}
