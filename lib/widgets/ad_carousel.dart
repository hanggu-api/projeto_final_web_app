import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../services/global_startup_manager.dart';

class AdCarousel extends StatefulWidget {
  final double height;
  const AdCarousel({super.key, this.height = 300});

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  final PageController _pageController = PageController();
  List<String> _imageUrls = ['assets/images/IMG-20260301-WA0001.jpg'];
  bool _isLoading = false;
  Timer? _timer;
  int _currentPage = 0;
  bool _hasFetched = false;

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchCampaignImages() async {
    if (_hasFetched) return;
    _hasFetched = true;

    try {
      // Use Cloudflare Worker proxy to avoid CORS on web
      final response = await http.get(
        Uri.parse(
          'https://projeto-central-backend.carrobomebarato.workers.dev/api/campaign/baraiba01',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List?;

        if (items != null) {
          final urls = items
              .where((item) => item['type'] == 'image' && item['url'] != null)
              .map((item) => item['url'] as String)
              .toList();

          if (mounted) {
            setState(() {
              // Mantém a imagem estática principal em primeiro lugar
              _imageUrls = ['assets/images/IMG-20260301-WA0001.jpg', ...urls];
              _isLoading = false;
            });
            _startAutoPlay();
            _precacheImages();
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar campanha: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _precacheImages() {
    for (final url in _imageUrls) {
      if (url.startsWith('assets/')) continue; // assets locais carregam rápido
      try {
        precacheImage(CachedNetworkImageProvider(url, maxWidth: 600), context);
      } catch (e) {
        debugPrint('Erro ao fazer precache: $e');
      }
    }
  }

  void _startAutoPlay() {
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

        // Se pode carregar e ainda não buscou, busca agora
        if (!_hasFetched) {
          _fetchCampaignImages();
        }

        if (_isLoading) {
          return _buildSkeleton();
        }

        if (_imageUrls.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: widget.height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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
                    return Image.asset(imgUrl, fit: BoxFit.cover);
                  }

                  return CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    // OTIMIZAÇÃO CRÍTICA: Reduzir tamanho em memória (VRAM)
                    // Redimensiona a imagem para ~largura da tela antes de decodificar
                    memCacheWidth:
                        600, // HD width suficiente para mobile, evita 4K textures
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
                              : Colors.white.withValues(alpha: 0.5),
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
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
