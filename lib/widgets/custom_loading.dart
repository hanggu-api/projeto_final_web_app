import 'package:flutter/material.dart';

class CustomLoadingAnimation extends StatefulWidget {
  final double size;
  final Color? color;

  const CustomLoadingAnimation({
    super.key,
    this.size = 150.0, // Aumentado para acomodar a imagem melhor
    this.color,
  });

  @override
  State<CustomLoadingAnimation> createState() => _CustomLoadingAnimationState();
}

class _CustomLoadingAnimationState extends State<CustomLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true); // Sobe e desce suavemente

    // Efeito de "respiração" (escala sutil)
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // Efeito de opacidade sutil (brilho)
    _fadeAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.5),
                      blurRadius: 20 * _controller.value,
                      spreadRadius: 5 * _controller.value,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/preload.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback se a imagem não existir
                    return Icon(
                      Icons.settings_suggest,
                      size: widget.size * 0.5,
                      color: Theme.of(context).primaryColor,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Full Screen Splash Widget
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).primaryColor, // Fundo amarelo conforme a imagem
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CustomLoadingAnimation(
              size: 200, // Tamanho maior para destaque
            ),
            const SizedBox(height: 50),
            // Preload retangular clássico preto
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                backgroundColor: Colors.black.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
