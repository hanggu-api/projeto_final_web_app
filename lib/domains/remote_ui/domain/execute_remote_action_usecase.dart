import 'package:flutter/widgets.dart';

import '../models/remote_action.dart';
import 'remote_action_executor.dart';

class ExecuteRemoteActionUseCase {
  ExecuteRemoteActionUseCase(this._executor);

  final RemoteActionExecutor _executor;

  Future<void> execute(RemoteAction action, BuildContext context) {
    return _executor.execute(action, context);
  }
}
