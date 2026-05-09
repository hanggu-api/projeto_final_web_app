import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../services/payment/mercado_pago_connect_service.dart';

class MercadoPagoConnectWebViewScreen extends StatefulWidget {
  final String role;
  const MercadoPagoConnectWebViewScreen({super.key, required this.role});

  @override
  State<MercadoPagoConnectWebViewScreen> createState() =>
      _MercadoPagoConnectWebViewScreenState();
}

class _MercadoPagoConnectWebViewScreenState
    extends State<MercadoPagoConnectWebViewScreen> {
  final _api = ApiService();
  WebViewController? _controller;
  bool _loading = true;
  String? _authUrl;
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final userId = _api.userId;
      if (userId == null) throw Exception('Usuário não autenticado');

      final mp = MercadoPagoConnectService(_api);
      final url = await mp.getAuthUrl(userId, role: widget.role);
      if (!mounted) return;

      _authUrl = url;
      if (!kIsWeb) {
        _controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) => setState(() => _loading = true),
              onPageFinished: (url) {
                if (!mounted) return;
                setState(() => _loading = false);
                // Quando o callback finalizar, voltamos para a tela anterior e atualizamos status.
                if (url.contains('/functions/v1/mp-connect-callback')) {
                  Navigator.of(context).pop(true);
                }
              },
              onWebResourceError: (error) {
                if (!mounted) return;
                setState(() {
                  _loading = false;
                  _error = 'Falha ao carregar a página do Mercado Pago.';
                });
              },
            ),
          )
          ..loadRequest(Uri.parse(url));
      }

      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openInBrowser() async {
    final url = _authUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  Future<void> _checkConnectedAndClose() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final userId = _api.userId;
      if (userId == null) return;
      final mp = MercadoPagoConnectService(_api);
      final ok = await mp.isConnected(userId, role: widget.role);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ainda não conectou. Finalize no Mercado Pago e tente novamente.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryYellow,
        title: const Text('Conectar Mercado Pago'),
        actions: [
          if (_authUrl != null)
            IconButton(
              tooltip: 'Recarregar',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                if (_authUrl == null) return;
                if (kIsWeb) {
                  _openInBrowser();
                  return;
                }
                if (_controller == null) return;
                _controller!.loadRequest(Uri.parse(_authUrl!));
              },
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          : kIsWeb
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Para conectar, abra o Mercado Pago no navegador e autorize a conexão.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _openInBrowser,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Abrir Mercado Pago'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _checking ? null : _checkConnectedAndClose,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(_checking ? 'Verificando...' : 'Já conectei'),
                      ),
                      const SizedBox(height: 12),
                      if (_authUrl != null)
                        SelectableText(
                          _authUrl!,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                )
              : Stack(
              children: [
                if (_controller != null) WebViewWidget(controller: _controller!),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
    );
  }
}
