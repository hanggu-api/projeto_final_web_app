import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/global_startup_manager.dart';
import '../services/app_config_service.dart';
import '../core/config/supabase_config.dart';
import 'ad_embed_banner.dart';

class AdCarousel extends StatefulWidget {
  final double height;
  final String placement;
  final String appContext;
  const AdCarousel({
    super.key,
    this.height = 300,
    this.placement = 'home-banner',
    this.appContext = 'home',
  });

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

// Desativado: endpoint externo estava retornando 500 e não está sendo usado agora.
const bool _kEnableRemoteCampaignFetch = false;

class _AdCarouselState extends State<AdCarousel> {
  static const String _embedHeightRaw = String.fromEnvironment(
    'HOME_AD_HEIGHT',
    defaultValue: '',
  );
  static const String _homeAdApiUrlEnv = String.fromEnvironment(
    'HOME_AD_API_URL',
    defaultValue: '',
  );
  static const String _trackingAdApiUrlEnv = String.fromEnvironment(
    'TRACKING_AD_API_URL',
    defaultValue: '',
  );
  final PageController _pageController = PageController();
  List<String> _imageUrls = const [];
  bool _isLoading = false;
  Timer? _timer;
  int _currentPage = 0;
  bool _hasFetched = false;
  bool _placementLoaded = false;
  bool _placementFetchScheduled = false;
  bool _campaignFetchScheduled = false;
  bool _configLoadScheduled = false;
  DateTime? _lastFetchAttemptAt;
  String? _activePublishUrl;
  String? _activeClickUrl;
  String? _activeCampaignId;
  final Set<String> _impressionTracked = <String>{};
  final AppConfigService _appConfig = AppConfigService();
  final String _sessionId = '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _ensureAppConfigLoaded() async {
    if (_appConfig.isLoaded) return;
    await _appConfig.preload();
    if (mounted) setState(() {});
  }

  String get _resolvedPlacementApiUrl {
    final configRaw = widget.placement == 'tracking-banner'
        ? _appConfig.marketingTrackingAdApiUrl.trim()
        : _appConfig.marketingHomeAdApiUrl.trim();
    final envRaw = widget.placement == 'tracking-banner'
        ? _trackingAdApiUrlEnv.trim()
        : _homeAdApiUrlEnv.trim();
    final raw = configRaw.isNotEmpty ? configRaw : envRaw;
    if (raw.isEmpty) return raw;
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;

    final loopbackHosts = {'127.0.0.1', 'localhost', '::1'};
    if (!loopbackHosts.contains(uri.host)) return raw;

    final supabaseUri = Uri.tryParse(SupabaseConfig.url);
    if (supabaseUri == null || supabaseUri.host.isEmpty) return raw;

    return uri.replace(host: supabaseUri.host).toString();
  }

  bool _isDirectEmbedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.contains('/api/marketing/embed/') ||
        path.contains('/api/marketing/creative');
  }

  bool _isPlacementApiUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.path.toLowerCase().contains('/api/marketing/placement/');
  }

  String _buildEmbedUrlFromPlacementApi(String apiUrl) {
    final uri = Uri.tryParse(apiUrl);
    if (uri == null) return apiUrl;
    return uri.replace(path: '/api/marketing/embed/${widget.placement}').toString();
  }

  double get _resolvedHeight {
    final fromConfig = widget.placement == 'tracking-banner'
        ? _appConfig.marketingTrackingAdHeight
        : _appConfig.marketingHomeAdHeight;
    final fromEnv = double.tryParse(_embedHeightRaw.trim());
    final base = fromEnv ?? widget.height;
    final resolved = fromConfig > 0 ? fromConfig : base;
    return resolved.clamp(120.0, 700.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String _deviceLabel() {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  Uri? _resolveImpressionUri() {
    final placementUri = Uri.tryParse(_resolvedPlacementApiUrl);
    if (placementUri == null) return null;
    return placementUri.replace(
      path: '/api/marketing/impression',
      queryParameters: null,
      fragment: null,
    );
  }

  Future<void> _trackImpressionIfNeeded() async {
    final campaignId = _activeCampaignId;
    if (campaignId == null || campaignId.isEmpty) return;
    if (_impressionTracked.contains(campaignId)) return;

    final uri = _resolveImpressionUri();
    if (uri == null) return;

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'campaign_id': campaignId,
              'placement': widget.placement,
              'source': 'mobile_app_home',
              'device': _deviceLabel(),
              'session_id': _sessionId,
              'app_context': widget.appContext,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _impressionTracked.add(campaignId);
      }
    } catch (_) {
      // Silencioso por ser telemetria.
    }
  }

  Future<void> _fetchPlacementCampaign() async {
    _placementFetchScheduled = false;
    final apiUrl = _resolvedPlacementApiUrl;
    if (apiUrl.isEmpty || _placementLoaded) return;
    _placementLoaded = true;
    if (mounted) setState(() => _isLoading = true);

    try {
      if (_isDirectEmbedUrl(apiUrl)) {
        _activePublishUrl = apiUrl;
        _activeClickUrl = null;
        _activeCampaignId = null;
        return;
      }

      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final publishUrl = (data['publish_url'] ?? '').toString().trim();
          final clickUrl = (data['click_url'] ?? '').toString().trim();
          final campaignId = (data['campaign_id'] ?? '').toString().trim();

          if (publishUrl.isNotEmpty) {
            // Quando a configuração aponta para /placement, renderiza o /embed
            // para exibir TODAS campanhas ativas (rotação no servidor).
            final shouldForceEmbed = _isPlacementApiUrl(apiUrl);
            _activePublishUrl = shouldForceEmbed
                ? _buildEmbedUrlFromPlacementApi(apiUrl)
                : publishUrl;
            _activeClickUrl = clickUrl.isNotEmpty ? clickUrl : null;
            _activeCampaignId = campaignId.isNotEmpty ? campaignId : null;
            await _trackImpressionIfNeeded();
          }
        }
      }
    } catch (_) {
      // fallback silencioso
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openTrackedClick() async {
    final clickUrl = _activeClickUrl;
    if (clickUrl == null || clickUrl.isEmpty) return;
    final uri = Uri.tryParse(clickUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _fetchCampaignImages() async {
    _campaignFetchScheduled = false;
    if (!_kEnableRemoteCampaignFetch) {
      _hasFetched = true;
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (_hasFetched) return;
    // Se já tentamos recentemente, não tenta de novo (evita spam de 500 na Home).
    final now = DateTime.now();
    if (_lastFetchAttemptAt != null &&
        now.difference(_lastFetchAttemptAt!) < const Duration(minutes: 10)) {
      _hasFetched = true;
      return;
    }
    _hasFetched = true;
    _lastFetchAttemptAt = now;
    if (mounted) setState(() => _isLoading = true);

    try {
      // Use Cloudflare Worker proxy to avoid CORS on web
      final response = await http
          .get(
            Uri.parse(
              'https://projeto-central-backend.carrobomebarato.workers.dev/api/campaign/baraiba01',
            ),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        final items = (data is Map) ? (data['items'] as List?) : null;

        if (items != null) {
          final urls = items
              .where((item) => item['type'] == 'image' && item['url'] != null)
              .map((item) => item['url'] as String)
              .toList();

          if (mounted) {
            setState(() {
              _imageUrls = urls;
              _isLoading = false;
            });
            _startAutoPlay();
          }
          return;
        }
      }

      debugPrint(
        '[AdCarousel] campaign fetch failed status=${response.statusCode}',
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('[AdCarousel] campaign fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (_imageUrls.length <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        int nextPage = _currentPage + 1;
        if (nextPage >= _imageUrls.length) {
          nextPage = 0;
        }
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escutar o Gerenciador Global de Inicialização
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalStartupManager.instance.canLoadHeavyWidgets,
      builder: (context, canLoad, child) {
        // Se ainda não pode carregar, mostra esqueleto
        if (!canLoad) {
          return _buildSkeleton();
        }

        if (!_appConfig.isLoaded && !_configLoadScheduled) {
          _configLoadScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_ensureAppConfigLoaded());
          });
        }

        // Se pode carregar e ainda não buscou, busca agora
        if (_kEnableRemoteCampaignFetch && !_hasFetched) {
          if (!_campaignFetchScheduled) {
            _campaignFetchScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_fetchCampaignImages());
            });
          }
        }

        if (_resolvedPlacementApiUrl.isNotEmpty && !_placementLoaded) {
          if (!_placementFetchScheduled) {
            _placementFetchScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_fetchPlacementCampaign());
            });
          }
        }

        if (_isLoading) {
          return _buildSkeleton();
        }

        final hasRuntimeCampaign = (_activePublishUrl ?? '').isNotEmpty;
        if (hasRuntimeCampaign) {
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: Stack(
              children: [
                AdEmbedBanner(url: _activePublishUrl!, height: _resolvedHeight),
                if ((_activeClickUrl ?? '').isNotEmpty)
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openTrackedClick,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }

        if (_imageUrls.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: _resolvedHeight,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: _imageUrls.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final String imgUrl = _imageUrls[index];

                  // Checa se a imagem é um asset local
                  if (imgUrl.startsWith('assets/')) {
                    return Image.asset(
                      imgUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 1200,
                    );
                  }

                  return CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    // OTIMIZAÇÃO CRÍTICA: Reduzir tamanho em memória (VRAM)
                    // Redimensiona a imagem para ~largura da tela antes de decodificar
                    memCacheWidth:
                        600, // HD width suficiente para mobile, evita 4K textures
                    maxWidthDiskCache: 1200,
                    placeholder: (context, url) => _buildSkeleton(),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(Icons.error_outline, color: Colors.grey),
                    ),
                  );
                },
              ),

              // Indicator Dots
              if (_imageUrls.length > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_imageUrls.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Colors.white
                              : Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: _resolvedHeight,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
