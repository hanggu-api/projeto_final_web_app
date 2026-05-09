import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

class HomeUpcomingAppointmentBanner extends StatelessWidget {
  final String providerName;
  final String serviceName;
  final String address;
  final String dateTimeLabel;
  final String timeLabel;
  final bool isOverdue;
  final bool isVeryClose;
  final String remainingLabel;
  final String leaveInLabel;
  final double distanceKm;
  final int travelTimeMin;
  final String? chatPreviewMessage;
  final int unreadChatCount;
  final VoidCallback? onOpenChat;
  final VoidCallback onOpenDetails;

  const HomeUpcomingAppointmentBanner({
    super.key,
    required this.providerName,
    required this.serviceName,
    required this.address,
    required this.dateTimeLabel,
    required this.timeLabel,
    required this.isOverdue,
    required this.isVeryClose,
    required this.remainingLabel,
    required this.leaveInLabel,
    required this.distanceKm,
    required this.travelTimeMin,
    this.chatPreviewMessage,
    this.unreadChatCount = 0,
    this.onOpenChat,
    required this.onOpenDetails,
  });

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    Color? backgroundColor,
    Color? textColor,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? Colors.grey.shade700),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: textColor ?? Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = isOverdue
        ? Colors.grey.shade700
        : (isVeryClose ? const Color(0xFFDC2626) : AppTheme.primaryBlue);
    final accentSurface = isOverdue
        ? const Color(0xFFF2F3F5)
        : (isVeryClose ? const Color(0xFFFFF1F2) : const Color(0xFFF4F8FF));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onOpenDetails,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentSurface, Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: accentColor.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        isOverdue
                            ? Icons.history
                            : (isVeryClose
                                  ? Icons.alarm
                                  : Icons.event_available),
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              isOverdue
                                  ? 'Agendamento em andamento'
                                  : 'Proximo compromisso',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            serviceName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkBlueText,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            providerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.darkBlueText.withValues(
                                alpha: 0.72,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.darkBlueText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateTimeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.darkBlueText.withValues(alpha: 0.64),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      icon: Icons.schedule_rounded,
                      label: isOverdue
                          ? 'Servico em andamento ou atrasado'
                          : 'Falta $remainingLabel',
                      backgroundColor: Colors.white,
                      textColor: accentColor,
                      iconColor: accentColor,
                    ),
                    _buildInfoChip(
                      icon: Icons.route_outlined,
                      label: '${distanceKm.toStringAsFixed(1)} km',
                      backgroundColor: Colors.white,
                    ),
                    _buildInfoChip(
                      icon: Icons.directions_car_filled_outlined,
                      label: '~$travelTimeMin min',
                      backgroundColor: Colors.white,
                    ),
                    if (!isOverdue)
                      _buildInfoChip(
                        icon: Icons.alarm_rounded,
                        label: 'Saia em $leaveInLabel',
                        backgroundColor: Colors.white,
                        textColor: accentColor,
                        iconColor: accentColor,
                      ),
                  ],
                ),
                if (chatPreviewMessage != null &&
                    chatPreviewMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  LucideIcons.messageCircle,
                                  size: 16,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      unreadChatCount > 0
                                          ? 'Nova mensagem'
                                          : 'Última mensagem',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      chatPreviewMessage!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.darkBlueText.withValues(
                                          alpha: 0.76,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (onOpenChat != null) ...[
                        const SizedBox(width: 10),
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: onOpenChat,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(
                                  child: Icon(
                                    LucideIcons.messageSquare,
                                    size: 20,
                                    color: accentColor,
                                  ),
                                ),
                                if (unreadChatCount > 0)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        unreadChatCount > 9
                                            ? '9+'
                                            : unreadChatCount.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onOpenDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.darkBlueText,
                      backgroundColor: Colors.white.withValues(alpha: 0.92),
                      side: BorderSide(
                        color: accentColor.withValues(alpha: 0.16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Ver detalhes',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
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
