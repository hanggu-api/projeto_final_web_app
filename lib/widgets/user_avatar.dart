import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/media_service.dart';
import '../services/realtime_service.dart';

class UserAvatar extends StatefulWidget {
  final String? avatar;
  final String name;
  final String? userId;
  final double radius;
  final bool showOnlineStatus;

  const UserAvatar({
    super.key,
    required this.avatar,
    required this.name,
    this.userId,
    this.radius = 18,
    this.showOnlineStatus = false,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String? _resolvedUrl;
  Uint8List? _resolvedBytes;
  bool _loading = false;
  bool _isOnline = false;

  @override
  void initState() {
    super.initState();
    _resolve();
    if (widget.showOnlineStatus) {
      _checkOnline();
    }
  }

  void _checkOnline() {
    if (widget.userId == null) return;
    RealtimeService().checkStatus(widget.userId!, (online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatar != oldWidget.avatar ||
        widget.userId != oldWidget.userId) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    // 1. Try URL/Key if present
    final raw = widget.avatar;
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('http')) {
        if (mounted) setState(() => _resolvedUrl = raw);
        return;
      }

      // Assume it is a key
      if (mounted) setState(() => _loading = true);
      try {
        final bytes = await ApiService().getMediaBytes(raw);
        if (mounted) setState(() => _resolvedBytes = bytes);
        return; // Success with key
      } catch (_) {
        // Fallback to userId
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    // 2. Try User ID (Blob)
    if (widget.userId != null) {
      if (mounted) setState(() => _loading = true);
      try {
        final bytes = await MediaService().loadUserAvatarBytes(widget.userId!);
        if (mounted && bytes != null) {
          setState(() => _resolvedBytes = bytes);
        }
      } catch (_) {
        // Ignore
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? bgImage;
    if (_resolvedUrl != null) {
      bgImage = NetworkImage(_resolvedUrl!);
    } else if (_resolvedBytes != null) {
      bgImage = MemoryImage(_resolvedBytes!);
    }

    final avatarWidget = CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.secondary,
      radius: widget.radius,
      backgroundImage: bgImage,
      child: bgImage == null
          ? (_loading
                ? SizedBox(
                    width: widget.radius * 0.7,
                    height: widget.radius * 0.7,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.name.isNotEmpty
                        ? widget.name.substring(0, 1).toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: widget.radius,
                    ),
                  ))
          : null,
    );

    if (!widget.showOnlineStatus) return avatarWidget;

    return Stack(
      children: [
        avatarWidget,
        if (_isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: widget.radius * 0.6,
              height: widget.radius * 0.6,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
