import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../services/media_service.dart';

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  Uint8List? _avatarBytes;
  final _media = MediaService();

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (bytes != null) {
        setState(() => _avatarBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _editAvatar() async {
    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res != null && res.files.isNotEmpty && res.files.first.bytes != null) {
        final file = res.files.first;
        final mime = file.extension != null ? 'image/${file.extension}' : 'image/jpeg';
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _loadAvatar();
      }
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Usar câmera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Escolher da galeria'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final xfile = await _media.pickImageMobile(source);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      await _media.uploadAvatarBytes(bytes, xfile.name, 'image/jpeg');
      await _loadAvatar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Gray 50
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppTheme.primaryPurple,
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange]),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.successGreen, width: 4),
                          ),
                          child: ClipOval(
                            child: _avatarBytes == null
                                ? const Center(child: Text('CS', style: TextStyle(fontSize: 32, color: Colors.grey)))
                                : Image.memory(_avatarBytes!, fit: BoxFit.cover, width: 80, height: 80),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: InkWell(
                            onTap: _editAvatar,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Icon(Icons.edit, size: 16, color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Carlos Silva', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.successGreen, borderRadius: BorderRadius.circular(20)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.checkCircle, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Verificado', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  // Specialties
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Especialidades', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            'Chuveiros', 'Disjuntores', 'Torneiras', 'Instalação elétrica'
                          ].map((e) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(e, style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Metrics
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(LucideIcons.trendingUp, Colors.orange, '4.9', '128 avaliações'),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildMetricCard(LucideIcons.zap, Colors.green, '92%', 'Taxa de aceitação'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  Widget _buildMetricCard(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
