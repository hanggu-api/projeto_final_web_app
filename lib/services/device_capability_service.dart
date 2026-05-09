import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

enum PerformanceMode { full, balanced, basic }

class DeviceCapabilityService {
  DeviceCapabilityService._internal();
  static final DeviceCapabilityService instance =
      DeviceCapabilityService._internal();
  factory DeviceCapabilityService() => instance;

  bool _initialized = false;
  PerformanceMode _performanceMode = PerformanceMode.balanced;
  bool _isLowMemoryDevice = false;
  bool _prefersLightweightMaps = false;
  bool _prefersReducedBackground = false;
  bool _prefersSimplifiedDocumentScan = false;
  bool _prefersSimplifiedFaceLiveness = false;
  bool _prefersLowResolutionImages = false;
  String _debugSummary = 'uninitialized';

  bool get isInitialized => _initialized;
  PerformanceMode get performanceMode => _performanceMode;
  bool get isLowMemoryDevice => _isLowMemoryDevice;
  bool get prefersLightweightMaps => _prefersLightweightMaps;
  bool get prefersReducedBackground => _prefersReducedBackground;
  bool get prefersSimplifiedDocumentScan => _prefersSimplifiedDocumentScan;
  bool get prefersSimplifiedFaceLiveness => _prefersSimplifiedFaceLiveness;
  bool get prefersLowResolutionImages => _prefersLowResolutionImages;
  bool get isLowEndDevice => _performanceMode == PerformanceMode.basic;
  String get debugSummary => _debugSummary;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (kIsWeb) {
        _performanceMode = PerformanceMode.balanced;
        _prefersLightweightMaps = true;
        _prefersReducedBackground = true;
        _prefersSimplifiedDocumentScan = true;
        _prefersSimplifiedFaceLiveness = true;
        _prefersLowResolutionImages = true;
        _debugSummary = 'web/balanced';
        return;
      }

      final deviceInfo = DeviceInfoPlugin();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await deviceInfo.androidInfo;
          final sdkInt = info.version.sdkInt;
          final lowMemory =
              info.isLowRamDevice ||
              info.physicalRamSize <= 3072 ||
              info.availableRamSize <= 1536 ||
              sdkInt <= 26;
          final veryConstrained =
              info.isLowRamDevice ||
              info.physicalRamSize <= 2048 ||
              info.availableRamSize <= 1024 ||
              sdkInt <= 25;
          _isLowMemoryDevice = lowMemory;
          _performanceMode = veryConstrained
              ? PerformanceMode.basic
              : (lowMemory ? PerformanceMode.balanced : PerformanceMode.full);
          _prefersLightweightMaps = lowMemory;
          _prefersReducedBackground = lowMemory;
          _prefersSimplifiedDocumentScan = lowMemory;
          _prefersSimplifiedFaceLiveness = veryConstrained;
          _prefersLowResolutionImages = lowMemory;
          _debugSummary =
              'android sdk=$sdkInt lowRam=${info.isLowRamDevice} ram=${info.physicalRamSize}MB free=${info.availableRamSize}MB mode=${_performanceMode.name}';
          break;
        case TargetPlatform.iOS:
          final info = await deviceInfo.iosInfo;
          final lowMemory =
              info.physicalRamSize <= 3072 || info.availableRamSize <= 1536;
          final veryConstrained =
              info.physicalRamSize <= 2048 || info.availableRamSize <= 1024;
          _isLowMemoryDevice = lowMemory;
          _performanceMode = veryConstrained
              ? PerformanceMode.basic
              : (lowMemory ? PerformanceMode.balanced : PerformanceMode.full);
          _prefersLightweightMaps = lowMemory;
          _prefersReducedBackground = lowMemory;
          _prefersSimplifiedDocumentScan = lowMemory;
          _prefersSimplifiedFaceLiveness = veryConstrained;
          _prefersLowResolutionImages = lowMemory;
          _debugSummary =
              'ios ram=${info.physicalRamSize}MB free=${info.availableRamSize}MB mode=${_performanceMode.name}';
          break;
        default:
          _performanceMode = PerformanceMode.balanced;
          _prefersLightweightMaps = true;
          _prefersReducedBackground = true;
          _prefersSimplifiedDocumentScan = true;
          _prefersSimplifiedFaceLiveness = true;
          _prefersLowResolutionImages = true;
          _debugSummary = '${defaultTargetPlatform.name}/balanced';
          break;
      }
    } catch (e) {
      debugPrint(
        '⚠️ [DeviceCapabilityService] Falha ao detectar capacidade do aparelho: $e',
      );
      _performanceMode = PerformanceMode.balanced;
      _prefersLightweightMaps = true;
      _prefersReducedBackground = true;
      _prefersSimplifiedDocumentScan = true;
      _prefersSimplifiedFaceLiveness = true;
      _prefersLowResolutionImages = true;
      _debugSummary = 'fallback/balanced';
    } finally {
      _initialized = true;
      debugPrint('📱 [DeviceCapabilityService] $_debugSummary');
    }
  }
}
