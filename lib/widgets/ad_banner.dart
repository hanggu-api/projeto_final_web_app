import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AdBanner extends StatefulWidget {
  final String? url;
  final double height;

  const AdBanner({super.key, this.url, this.height = 250});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  WebViewController? _controller;
  bool _isLoading = true;
  Uri? _initialUri;

  @override
  void initState() {
    super.initState();

    if (widget.url != null && widget.url!.isNotEmpty) {
      _initialUri = Uri.tryParse(widget.url!);
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) async {
              final requested = Uri.tryParse(request.url);
              if (requested == null) return NavigationDecision.navigate;

              final isHttp = requested.scheme == 'http' || requested.scheme == 'https';
              if (!isHttp) return NavigationDecision.navigate;

              final initial = _initialUri;
              final isSameAsInitial = initial != null && request.url == initial.toString();
              if (isSameAsInitial) return NavigationDecision.navigate;

              await launchUrl(requested, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            },
            onProgress: (int progress) {},
            onPageStarted: (String url) {},
            onPageFinished: (String url) {
              if (mounted) setState(() => _isLoading = false);
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) setState(() => _isLoading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url!));
    } else {
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url == null || widget.url!.isEmpty) {
      return Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'Fique ligado nas novidades!\nEm breve ofertas exclusivas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
