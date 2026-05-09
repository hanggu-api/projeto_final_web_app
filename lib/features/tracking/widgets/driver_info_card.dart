import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:service_101/core/theme/app_theme.dart';

class DriverInfoCard extends StatelessWidget {
  final Map<String, dynamic>? driverProfile;
  final double? distanceToPickup;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback? onCancel; // Added for side-by-side style
  final bool showChat;
  final bool compactCancelOnly;

  const DriverInfoCard({
    super.key,
    this.driverProfile,
    this.distanceToPickup,
    required this.onCall,
    required this.onMessage,
    this.onCancel,
    this.showChat = true,
    this.compactCancelOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (driverProfile == null) {
      return const SizedBox.shrink();
    }

    final String firstName =
        driverProfile!['first_name']?.toString() ?? 'Motorista';
    final String carInfo = "${driverProfile!['vehicle_model'] ?? 'Veículo'}";
    final String plate =
        driverProfile!['vehicle_plate']?.toString().trim().isNotEmpty == true
        ? driverProfile!['vehicle_plate']!.toString()
        : 'SEM PLACA';
    final String rating = driverProfile!['rating']?.toString() ?? '5.0';

    // Calcula tempo de chegada estimado Marina! Marina! Marina!
    final String arrivalTime = distanceToPickup != null && distanceToPickup! > 0
        ? "${(distanceToPickup! / 250).toStringAsFixed(0)} min away"
        : "3 min away";

    final bool hasPrimaryActions =
        showChat || (onCancel != null && !compactCancelOnly);
    final bool hasCompactCancel = onCancel != null && compactCancelOnly;
    final bool hasAnyActions = hasPrimaryActions || hasCompactCancel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < 370;
        final double avatarSize = isNarrow ? 68 : 80;
        final double nameFont = isNarrow ? 18 : 24;
        final double subtitleFont = isNarrow ? 13 : 15;
        final double chipFont = isNarrow ? 12 : 13;
        final double actionHeight = isNarrow ? 50 : 56;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar Section Marina! Marina! Marina!
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primaryYellow,
                          width: 2,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade100,
                            image: driverProfile!['avatar_url'] != null
                                ? DecorationImage(
                                    image: NetworkImage(
                                      driverProfile!['avatar_url'],
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: driverProfile!['avatar_url'] == null
                              ? const Icon(
                                  LucideIcons.user,
                                  size: 32,
                                  color: AppTheme.textDark,
                                )
                              : null,
                        ),
                      ),
                    ),
                    // Rating Badge Marina! Marina! Marina!
                    Positioned(
                      bottom: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.blue.shade50),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'star ',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              rating,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: isNarrow ? 12 : 16),
                // Info Section Marina! Marina! Marina!
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        firstName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: nameFont,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        carInfo,
                        maxLines: isNarrow ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: subtitleFont,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryYellow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.car,
                                    size: 14,
                                    color: AppTheme.textDark,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      plate,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.manrope(
                                        fontSize: chipFont,
                                        fontWeight: FontWeight.w900,
                                        color: AppTheme.textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryYellow.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.clock,
                                  size: 14,
                                  color: AppTheme.textDark,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  arrivalTime,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                    fontSize: chipFont,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (hasAnyActions) SizedBox(height: isNarrow ? 10 : 14),
            // Action Buttons side-by-side style Rico Marina! Marina! Marina!
            if (hasPrimaryActions)
              Row(
                children: [
                  if (showChat)
                    Expanded(
                      child: _buildActionButton(
                        icon: LucideIcons.messageSquare,
                        label: 'Chat',
                        onTap: onMessage,
                        isPrimary: true,
                        height: actionHeight,
                        fontSize: isNarrow ? 14 : 16,
                      ),
                    ),
                  if (showChat && onCancel != null) const SizedBox(width: 12),
                  if (onCancel != null && !compactCancelOnly)
                    Expanded(
                      child: _buildActionButton(
                        icon: LucideIcons.x,
                        label: 'Cancel',
                        onTap: onCancel!,
                        isPrimary: false,
                        height: actionHeight,
                        fontSize: isNarrow ? 14 : 16,
                      ),
                    ),
                ],
              ),
            if (hasCompactCancel) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    foregroundColor: Colors.grey.shade700,
                    textStyle: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
    required double height,
    required double fontSize,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: height,
        decoration: AppTheme.surfacedCardDecoration(
          color: isPrimary ? AppTheme.primaryYellow : const Color(0xFFF1F4F8),
          radius: 20,
          border: isPrimary ? AppTheme.cardBorder : AppTheme.cardBorder,
          shadow: isPrimary
              ? [
                  BoxShadow(
                    color: AppTheme.primaryYellow.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppTheme.cardShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppTheme.textDark),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
