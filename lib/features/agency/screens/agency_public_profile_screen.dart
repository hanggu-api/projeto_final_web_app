
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AgencyPublicProfileScreen extends StatelessWidget {
  final String userId;
  const AgencyPublicProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    // In a real app, fetch data by userId
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualização Pública'),
        actions: [
          IconButton(onPressed: (){}, icon: const Icon(LucideIcons.share2))
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            Container(
              height: 200,
              width: double.infinity,
              color: Colors.grey.shade300,
              child: const Center(child: Icon(LucideIcons.image, size: 64, color: Colors.grey)),
            ),
            
            // Info
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).primaryColor,
                    child: const Text('LOGO', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Minha Empresa Inc.',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Soluções em Construção e Reformas',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  
                  // Contact Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (){},
                        icon: const Icon(LucideIcons.messageCircle),
                        label: const Text('WhastApp'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: (){},
                        icon: const Icon(LucideIcons.instagram),
                        label: const Text('Instagram'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const Divider(),
            
            // Catalog
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nossos Serviços', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: 4,
                    itemBuilder: (ctx, i) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0,2))
                          ]
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Container(color: Colors.grey.shade200)),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Serviço ${i+1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const Text('R\$ 150,00', style: TextStyle(color: Colors.green)),
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
