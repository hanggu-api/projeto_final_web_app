import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/client/service_request_screen.dart';
import 'features/client/payment_screen.dart';
import 'features/client/confirmation_screen.dart';
import 'features/client/tracking_screen.dart';
import 'features/provider/provider_home_screen.dart';
import 'features/provider/service_details_screen.dart';
import 'features/provider/provider_profile_screen.dart';
import 'features/shared/chat_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'features/shared/warranty_screen.dart';
import 'features/dev/simulation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  await api.loadToken();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('auth_token');
  final role = prefs.getString('user_role');
  final initial = token == null
      ? '/login'
      : (role == 'provider' ? '/provider-home' : '/home');
  runApp(ProviderScope(child: MyApp(initialLocation: initial)));
}

GoRouter _buildRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  redirect: (context, state) {
    final api = ApiService();
    final logged = api.isLoggedIn;
    final loggingIn = state.matchedLocation == '/login';
    if (!logged && !loggingIn) {
      return '/login';
    }
    if (logged && loggingIn) {
      return (api.role == 'provider') ? '/provider-home' : '/home';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/create-service',
      builder: (context, state) => const ServiceRequestScreen(),
    ),
    GoRoute(
      path: '/payment',
      builder: (context, state) => const PaymentScreen(),
    ),
    GoRoute(
      path: '/confirmation',
      builder: (context, state) => const ConfirmationScreen(),
    ),
    GoRoute(
      path: '/tracking',
      builder: (context, state) => const TrackingScreen(),
    ),
    GoRoute(
      path: '/provider-home',
      builder: (context, state) => const ProviderHomeScreen(),
    ),
    GoRoute(
      path: '/service-details',
      builder: (context, state) {
        final serviceId = state.extra as String;
        return ServiceDetailsScreen(serviceId: serviceId);
      },
    ),
    GoRoute(
      path: '/provider-profile',
      builder: (context, state) => const ProviderProfileScreen(),
    ),
    GoRoute(
      path: '/client-settings',
      builder: (context, state) => const _ClientSettingsScreen(),
    ),
    GoRoute(
      path: '/provider-settings',
      builder: (context, state) => const _ProviderSettingsScreen(),
    ),
    GoRoute(
      path: '/chats',
      builder: (context, state) => const _ChatListScreen(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) {
         final serviceId = state.extra as String;
         return ChatScreen(serviceId: serviceId);
      },
    ),
    GoRoute(
      path: '/warranty',
      builder: (context, state) => const WarrantyScreen(),
    ),
    GoRoute(
      path: '/simulate',
      builder: (context, state) => const SimulationScreen(),
    ),
  ],
);

class MyApp extends StatelessWidget {
  final String initialLocation;
  const MyApp({super.key, this.initialLocation = '/login'});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Conserta+',
      theme: AppTheme.lightTheme,
      routerConfig: _buildRouter(initialLocation),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ClientSettingsScreen extends StatelessWidget {
  const _ClientSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text('Conta', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sair'),
                    onTap: () async {
                      await ApiService().clearToken();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}

class _ProviderSettingsScreen extends StatelessWidget {
  const _ProviderSettingsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text('Conta', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text('Sair'),
                    onTap: () async {
                      await ApiService().clearToken();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}

class _ChatListScreen extends StatefulWidget {
  const _ChatListScreen();

  @override
  State<_ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<_ChatListScreen> {
  final _api = ApiService();
  List<dynamic> _services = [];
  bool _loading = true;
  String? _role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _role = prefs.getString('user_role');
      final list = await _api.getMyServices();
      final filtered = list.where((s) {
        final status = (s['status'] ?? '').toString();
        if (_role == 'provider') {
          return status == 'accepted' || status == 'in_progress';
        }
        return status == 'created' || status == 'accepted' || status == 'in_progress';
      }).toList();
      setState(() {
        _services = filtered;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_services.isEmpty
              ? const Center(child: Text('Nenhum serviço ativo'))
              : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final s = _services[index];
                final status = (s['status'] ?? '').toString();
                final isActive = status == 'accepted' || status == 'in_progress' || status == 'created';
                final otherName = (_role == 'provider' ? s['client_name'] : s['provider_name']) ?? 'Serviço';
                final lat = (s['latitude'] is num) ? (s['latitude'] as num).toDouble() : double.tryParse('${s['latitude']}');
                final lon = (s['longitude'] is num) ? (s['longitude'] as num).toDouble() : double.tryParse('${s['longitude']}');
                return ListTile(
                  leading: (lat != null && lon != null)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: LatLng(lat, lon),
                                initialZoom: 14,
                                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c'],
                                ),
                              ],
                            ),
                          ),
                        )
                      : const CircleAvatar(child: Icon(Icons.work)),
                  title: Text(otherName.toString()),
                  subtitle: Text((s['address'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Icon(isActive ? Icons.chat_bubble : Icons.check_circle, color: isActive ? Colors.deepPurple : Colors.green),
                  onTap: () {
                    final id = s['id']?.toString();
                    if (id != null) {
                      context.go('/chat', extra: id);
                    }
                  },
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: _services.length,
            )),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}
