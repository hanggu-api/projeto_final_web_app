import 'remote_screen.dart';

enum RemoteScreenSource { remote, cache }

class LoadedRemoteScreen {
  const LoadedRemoteScreen({required this.screen, required this.source});

  final RemoteScreen screen;
  final RemoteScreenSource source;
}
