import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SearchingState extends StatelessWidget {
  final String? pickupAddress;
  final String? dropoffAddress;

  const SearchingState({super.key, this.pickupAddress, this.dropoffAddress});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Procurando motoristas...',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Aguarde um momento',
                    style: GoogleFonts.manrope(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            backgroundColor: Colors.blue.withOpacity(0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.mapPin,
              color: const Color(0xff141B34).withOpacity(0.4),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'Embarque',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xff141B34).withOpacity(0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildLocationRow(
          icon: LucideIcons.circle,
          address: pickupAddress ?? 'Endereço de partida',
          color: Colors.blue,
          iconColor: Colors.blueAccent,
        ),
        const SizedBox(height: 12),
        _buildLocationRow(
          icon: LucideIcons.square,
          address: dropoffAddress ?? 'Endereço de destino',
          color: Colors.green,
          iconColor: Colors.greenAccent,
        ),
      ],
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required String address,
    required Color color,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 12),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                address,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
