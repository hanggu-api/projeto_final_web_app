import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';

class HomeSavedPlaces extends StatelessWidget {
  final List<dynamic> savedPlaces;
  final Function(dynamic) onPlaceTap;

  const HomeSavedPlaces({
    super.key,
    required this.savedPlaces,
    required this.onPlaceTap,
  });

  @override
  Widget build(BuildContext context) {
    if (savedPlaces.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: savedPlaces.map((place) => _buildSavedPlaceItem(
          place['title'] ?? 'Lugar',
          place['address'] ?? '',
          place['type'] == 'home' ? LucideIcons.home : LucideIcons.briefcase,
          () => onPlaceTap(place),
        )).toList(),
      ),
    );
  }

  Widget _buildSavedPlaceItem(String title, String address, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: AppTheme.textDark),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    Text(
                      address,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
