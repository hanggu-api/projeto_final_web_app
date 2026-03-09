import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';

class HomeCategoryRow extends StatelessWidget {
  final Function(int) onCategoryTap;

  const HomeCategoryRow({super.key, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _buildCategoryItem(
            'Todos',
            LucideIcons.layoutGrid,
            () => onCategoryTap(0),
            color: AppTheme.primaryBlue,
            iconColor: Colors.white,
          ),
          const SizedBox(width: 12),
          _buildCategoryItem(
            'Beleza',
            LucideIcons.sparkles,
            () => onCategoryTap(1),
          ),
          const SizedBox(width: 12),
          _buildCategoryItem(
            'Saúde',
            LucideIcons.heartPulse,
            () => onCategoryTap(2),
          ),
          const SizedBox(width: 12),
          _buildCategoryItem(
            'Aulas',
            LucideIcons.graduationCap,
            () => onCategoryTap(3),
          ),
          const SizedBox(width: 12),
          _buildCategoryItem(
            'Reformas',
            LucideIcons.hammer,
            () => onCategoryTap(4),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryItem(
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color ?? AppTheme.backgroundLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
              boxShadow: [
                BoxShadow(
                  color: (color ?? AppTheme.primaryYellow).withValues(
                    alpha: 0.3,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor ?? AppTheme.textDark, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
