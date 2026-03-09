import 'package:flutter/cupertino.dart';

class CategoriaHelper {
  static IconData getIcon(String category) {
    String c = category.toLowerCase();

    // Mapeamento TomTom/Photon -> Cupertino
    if (c.contains('grocer') ||
        c.contains('shop') ||
        c.contains('supermarket') ||
        c.contains('mall') ||
        c.contains('store')) {
      return CupertinoIcons.cart_fill;
    }
    if (c.contains('restaurant') ||
        c.contains('food') ||
        c.contains('cafe') ||
        c.contains('bakery') ||
        c.contains('burger') ||
        c.contains('pizza') ||
        c.contains('pub') ||
        c.contains('bar')) {
      return CupertinoIcons.bag_fill;
    }
    if (c.contains('petrol') || c.contains('gas') || c.contains('fuel')) {
      return CupertinoIcons.drop_fill;
    }
    if (c.contains('hospital') ||
        c.contains('health') ||
        c.contains('pharmacy') ||
        c.contains('clinic')) {
      return CupertinoIcons.heart_circle_fill;
    }
    if (c.contains('hotel') || c.contains('accommodation')) {
      return CupertinoIcons.bed_double_fill;
    }
    if (c.contains('parking')) return CupertinoIcons.car_detailed;
    if (c.contains('school') ||
        c.contains('university') ||
        c.contains('college')) {
      return CupertinoIcons.book_fill;
    }
    if (c.contains('bank') || c.contains('atm')) {
      return CupertinoIcons.money_dollar_circle_fill;
    }

    return CupertinoIcons.location_solid; // Ícone padrão
  }

  static Color getColor(String category) {
    String c = category.toLowerCase();
    if (c.contains('shop') ||
        c.contains('supermarket') ||
        c.contains('grocer') ||
        c.contains('mall') ||
        c.contains('store')) {
      return CupertinoColors.systemOrange;
    }
    if (c.contains('food') ||
        c.contains('restaurant') ||
        c.contains('cafe') ||
        c.contains('bakery') ||
        c.contains('burger') ||
        c.contains('pizza') ||
        c.contains('pub') ||
        c.contains('bar')) {
      return CupertinoColors.systemRed;
    }
    if (c.contains('petrol') || c.contains('gas') || c.contains('fuel')) {
      return CupertinoColors.systemBlue;
    }
    if (c.contains('health') ||
        c.contains('hospital') ||
        c.contains('pharmacy') ||
        c.contains('clinic')) {
      return CupertinoColors.systemGreen;
    }
    if (c.contains('hotel') || c.contains('accommodation')) {
      return CupertinoColors.systemIndigo;
    }
    if (c.contains('school') || c.contains('university')) {
      return CupertinoColors.systemPurple;
    }
    return CupertinoColors.systemGrey;
  }
}
