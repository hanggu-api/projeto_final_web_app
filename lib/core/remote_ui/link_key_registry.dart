class LinkKeyRegistry {
  static final Map<String, Uri> _links = {
    'support_phone': Uri(scheme: 'tel', path: '08000001010'),
    'support_whatsapp': Uri.parse('https://wa.me/5580000001010'),
    'play101_site': Uri.parse('https://play101.com.br'),
    'support_email': Uri(
      scheme: 'mailto',
      path: 'suporte@play101.com.br',
    ),
  };

  static bool isAllowed(String linkKey) => _links.containsKey(linkKey);

  static Uri? resolve(String linkKey) => _links[linkKey];
}
