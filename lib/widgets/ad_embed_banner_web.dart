// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

import 'package:flutter/material.dart';

class AdEmbedBanner extends StatefulWidget {
  final String url;
  final double height;

  const AdEmbedBanner({super.key, required this.url, this.height = 300});

  @override
  State<AdEmbedBanner> createState() => _AdEmbedBannerState();
}

class _AdEmbedBannerState extends State<AdEmbedBanner> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'ad-iframe-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = widget.url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'autoplay; encrypted-media; fullscreen; picture-in-picture'
        ..allowFullscreen = true;

      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
