import 'package:flutter/material.dart';

import 'ad_banner.dart';

class AdEmbedBanner extends StatelessWidget {
  final String url;
  final double height;

  const AdEmbedBanner({super.key, required this.url, this.height = 300});

  @override
  Widget build(BuildContext context) {
    return AdBanner(url: url, height: height);
  }
}

