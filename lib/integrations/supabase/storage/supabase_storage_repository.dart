import 'dart:io';
import 'dart:typed_data';

import '../../../core/network/backend_api_client.dart';
import '../../../domains/storage/storage_bucket.dart';
import '../../../domains/storage/storage_repository.dart';

class SupabaseStorageRepository implements StorageRepository {
  SupabaseStorageRepository({
    this.rootBucket = 'uploads',
  });

  final String rootBucket;
  final BackendApiClient _backend = const BackendApiClient();

  @override
  Future<String> uploadFile({
    required File file,
    required StorageBucket bucket,
  }) async {
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final bytes = Uint8List.fromList(await file.readAsBytes());
    final response = await _backend.postJson(
      '/api/v1/media/upload',
      body: {
        'bucket': rootBucket,
        'path': '${bucket.name}/$fileName',
        'bytes': bytes,
        'filename': file.path.split('/').last,
      },
    );
    final url = (response?['url'] ?? response?['public_url'] ?? '').toString();
    if (url.trim().isEmpty) {
      throw Exception('Upload sem URL de retorno.');
    }
    return url;
  }
}
