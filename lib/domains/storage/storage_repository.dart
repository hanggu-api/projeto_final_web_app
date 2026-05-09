import 'dart:io';

import 'storage_bucket.dart';

abstract class StorageRepository {
  Future<String> uploadFile({
    required File file,
    required StorageBucket bucket,
  });
}
