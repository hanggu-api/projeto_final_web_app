import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'widgetbook_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  runApp(const Service101WidgetbookApp());
}
