import '../models/loaded_remote_screen.dart';
import '../models/remote_screen_request.dart';

abstract class RemoteScreenRepository {
  Future<LoadedRemoteScreen?> fetchScreen(RemoteScreenRequest request);

  Future<LoadedRemoteScreen?> readCachedScreen(String screenKey);

  Future<void> invalidateScreen(String screenKey);
}
