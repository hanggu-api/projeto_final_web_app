import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class IconKeyResolver {
  static IconData resolve(String? key) {
    switch ((key ?? '').trim().toLowerCase()) {
      case 'message_circle':
        return LucideIcons.messageCircle;
      case 'phone':
        return LucideIcons.phone;
      case 'shield_check':
        return LucideIcons.shieldCheck;
      case 'home':
        return LucideIcons.home;
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'wand':
        return LucideIcons.wand2;
      case 'calendar':
        return LucideIcons.calendarDays;
      case 'scissors':
        return LucideIcons.scissors;
      case 'badge_help':
        return LucideIcons.helpCircle;
      default:
        return LucideIcons.circle;
    }
  }
}
