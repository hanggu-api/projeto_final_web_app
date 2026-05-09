import 'package:flutter/widgets.dart';

import '../models/remote_action.dart';

abstract class RemoteActionExecutor {
  Future<void> execute(RemoteAction action, BuildContext context);
}
