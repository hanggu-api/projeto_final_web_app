import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../services/api_service.dart';
import '../../widgets/skeleton_loader.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _services = [];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    try {
      final services = await _api.getMyServices();
      if (mounted) {
        setState(() {
          _services = services.where((s) {
            return s['provider'] != null || s['provider_id'] != null;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 5,
                    itemBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child:
                          CardSkeleton(), // height handled internally by card structure if needed, or pass fixed value
                    ),
                  )
                : _services.isEmpty
                ? const Center(child: Text('Nenhuma conversa iniciada.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _services.length,
                    separatorBuilder: (ctx, i) => Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final service = _services[index];
                      var otherName = 'Usuário';
                      dynamic otherAvatar;

                      // Determine correct display name/avatar based on my role
                      // (Simple heuristic: if I am the provider, show client. If I am client, show provider)
                      // Since we don't have easy access to "my id" here without async,
                      // we can check if the cached role in ApiService is 'provider'
                      final isProvider = _api.role == 'provider';

                      if (isProvider) {
                        // Show Client
                        final client = service['client'];
                        if (client != null) {
                          otherName = client['name'] ?? 'Cliente';
                          otherAvatar = client['avatar'] ?? client['photo'];
                        } else {
                          otherName = service['client_name'] ?? 'Cliente';
                        }
                      } else {
                        // Show Provider
                        final provider = service['provider'];
                        if (provider != null) {
                          otherName = provider['name'] ?? 'Prestador';
                          otherAvatar = provider['avatar'] ?? provider['photo'];
                        } else {
                          otherName = service['provider_name'] ?? 'Prestador';
                        }
                      }

                      final serviceId = service['id'].toString();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          backgroundImage: otherAvatar != null
                              ? CachedNetworkImageProvider(otherAvatar)
                              : null,
                          child: otherAvatar == null
                              ? Text(
                                  otherName.isNotEmpty
                                      ? otherName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        title: Text(
                          otherName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Subtitle removed to reduce clutter
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (service['unread_count'] != null &&
                                service['unread_count'] > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  service['unread_count'].toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const Icon(LucideIcons.chevronRight, size: 20),
                          ],
                        ),
                        onTap: () {
                          context.push(
                            '/chat/$serviceId',
                            extra: {
                              'serviceId': serviceId,
                              'otherName': otherName,
                              'otherAvatar': otherAvatar,
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).primaryColor,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 24,
        left: 24,
        right: 24,
        bottom: 24,
      ),
      child: const Text(
        'Conversas',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }
}
