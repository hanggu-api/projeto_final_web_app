class AudioRecorder {
  Future<bool> hasPermission() async => false;
  Future<void> start() async {}
  Future<String?> stop() async => null;
}