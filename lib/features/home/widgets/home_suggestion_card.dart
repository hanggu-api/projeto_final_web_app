import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

class HomeSuggestionCard extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback onTap;
  final bool isBig;
  final List<String>? customIcons;

  const HomeSuggestionCard({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.isBig = false,
    this.customIcons,
  });

  @override
  Widget build(BuildContext context) {
    final size = isBig ? 85.0 : 70.0;

    // Importante: Em alguns devices/webviews o DraggableScrollableSheet pode
    // engolir taps pequenos. Usamos GestureDetector (opaque) para garantir
    // hit-test consistente, mantendo o ripple do InkWell.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        debugPrint('👆 [HomeSuggestionCard] tap="$label"');
        onTap();
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            debugPrint('💧 [HomeSuggestionCard] inkwell="$label"');
            onTap();
          },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: AppTheme.surfacedCardDecoration(
                    color: color,
                    radius: 24,
                  ),
                  child: customIcons != null
                      ? Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: customIcons!
                                .map(
                                  (path) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Image.asset(
                                      path,
                                      width: isBig ? 36 : 28,
                                      height: isBig ? 36 : 28,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        )
                      : Icon(
                          icon,
                          color: AppTheme.textDark,
                          size: isBig ? 40 : 32,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
