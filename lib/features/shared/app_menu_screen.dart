import 'package:flutter/material.dart';

import '../../widgets/app_drawer.dart';

class AppMenuScreen extends StatelessWidget {
  const AppMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppDrawer(asPage: true);
  }
}
