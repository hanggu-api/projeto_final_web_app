import '../data/remote_screen_repository.dart';
import '../models/loaded_remote_screen.dart';
import '../models/remote_screen.dart';
import '../models/remote_screen_request.dart';

class LoadRemoteScreenUseCase {
  LoadRemoteScreenUseCase(this._repository);

  final RemoteScreenRepository _repository;

  static const int minimumSupportedContractVersion = 1;
  static const int maximumSupportedContractVersion = 1;

  Future<LoadedRemoteScreen?> execute(RemoteScreenRequest request) async {
    final remote = await _repository.fetchScreen(request);
    if (_isUsable(remote?.screen)) {
      return remote;
    }

    final cached = await _repository.readCachedScreen(request.screenKey);
    if (_isUsable(cached?.screen)) {
      return cached;
    }

    return null;
  }

  bool _isUsable(RemoteScreen? screen) {
    if (screen == null) return false;
    if (!screen.isEnabled) return false;
    if (screen.version < minimumSupportedContractVersion) return false;
    if (screen.version > maximumSupportedContractVersion) return false;
    if (screen.screen.isEmpty || screen.revision.isEmpty) return false;
    return true;
  }
}
