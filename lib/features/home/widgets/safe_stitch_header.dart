import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SafeStitchHeader extends StatelessWidget {
  final int unreadCount;
  final AnimationController bellController;
  final bool showChatPreview;
  final String? chatPreviewTitle;
  final String? chatPreviewMessage;
  final VoidCallback? onChatPreviewTap;

  const SafeStitchHeader({
    super.key,
    required this.unreadCount,
    required this.bellController,
    this.showChatPreview = false,
    this.chatPreviewTitle,
    this.chatPreviewMessage,
    this.onChatPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: showChatPreview ? onChatPreviewTap : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  axis: Axis.horizontal,
                  child: child,
                ),
              ),
              child: showChatPreview
                  ? _buildChatPreviewPill()
                  : _buildDefaultPill(),
            ),
          ),
          _buildCircleButton(
            Icons.notifications_none,
            () {},
            badgeCount: unreadCount,
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultPill() {
    return Container(
      key: const ValueKey('default-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: _pillDecoration(),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt, color: AppTheme.primaryYellow, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '101 SERVICE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.darkBlueText,
                  fontSize: 12,
                ),
              ),
              Text(
                'Painel Stitch',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkBlueText.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatPreviewPill() {
    return Container(
      key: const ValueKey('chat-preview-pill'),
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _pillDecoration(),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              color: AppTheme.primaryBlue,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (chatPreviewTitle ?? 'Nova mensagem').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.darkBlueText,
                    fontSize: 12,
                  ),
                ),
                Text(
                  (chatPreviewMessage ?? 'Toque para abrir a conversa').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkBlueText.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _pillDecoration() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
      ),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    VoidCallback onTap, {
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: AppTheme.textDark),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
