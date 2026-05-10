import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
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

  String _formatCurrency(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'R\$ ${parsed.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _normalizedSearchText() => _searchController.text.trim();

  bool _matchesCurrentQuery(Map<String, dynamic> item) {
    final query = _normalizedSearchText().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      item['task_name'],
      item['name'],
      item['profession_name'],
      item['category_name'],
      item['keywords'],
    ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
    return haystack.contains(query);
  }

  List<Map<String, dynamic>> _directSearchResults() {
    final direct = _suggestions.where(_matchesCurrentQuery).toList();
    return direct.isEmpty
        ? _suggestions.take(4).toList()
        : direct.take(4).toList();
  }

  MapEntry<String, List<Map<String, dynamic>>>? _firstProfessionGroup(
    List<Map<String, dynamic>> excluded,
  ) {
    final excludedIds = excluded
        .map(
          (item) =>
              (item['id'] ?? item['task_id'] ?? item['name'] ?? '').toString(),
        )
        .toSet();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in _suggestions) {
      final key = (item['id'] ?? item['task_id'] ?? item['name'] ?? '')
          .toString();
      if (excludedIds.contains(key)) continue;
      final profession = (item['profession_name'] ?? '').toString().trim();
      if (profession.isEmpty) continue;
      groups.putIfAbsent(profession, () => <Map<String, dynamic>>[]).add(item);
    }
    if (groups.isEmpty) return null;
    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return entries.first;
  }

  Widget _buildSiteResultRow(Map<String, dynamic> item) {
    final name = (item['task_name'] ?? item['name'] ?? '').toString().trim();
    final profession = (item['profession_name'] ?? '').toString().trim();
    final price = item['unit_price'] ?? item['price'];
    final isProviderProfile =
        (item['kind'] ?? '').toString() == 'provider_profile';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleSuggestionTap(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
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
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isProviderProfile
                          ? ((item['address'] ?? 'PERFIL').toString())
                          : profession.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey[500],
                        letterSpacing: isProviderProfile ? 0 : 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (price != null && !isProviderProfile)
                Container(
                  constraints: const BoxConstraints(minWidth: 108),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4ECFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFB78AE6).withOpacity(0.28),
                    ),
                  ),
                  child: Text(
                    _formatCurrency(price),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF8A00C4),
                      fontSize: 13,
                    ),
                  ),
                )
              else
                const Icon(LucideIcons.chevronRight, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteResultsPanel() {
    final query = _normalizedSearchText();
    final direct = _directSearchResults();
    final professionGroup = _firstProfessionGroup(direct);

    return Container(
      margin: const EdgeInsets.fromLTRB(5, 8, 5, 0),
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
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Serviços encontrados',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              query.isEmpty
                  ? 'Resultados diretos'
                  : 'Resultados diretos para "$query"',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...direct.expand(
            (item) => [
              _buildSiteResultRow(item),
              Divider(height: 1, color: Colors.grey[100]),
            ],
          ),
          if (professionGroup != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                professionGroup.key,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Todos os serviços dessa profissão',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...professionGroup.value
                .take(8)
                .expand(
                  (item) => [
                    _buildSiteResultRow(item),
                    Divider(height: 1, color: Colors.grey[100]),
                  ],
                ),
          ],
        ],
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
    final suggestionMaxHeight = mediaQuery.size.height * 0.80;
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
          SizedBox(
            height: suggestionMaxHeight,
            child: _buildSiteResultsPanel(),
          ),
      ],
    );
  }
}
