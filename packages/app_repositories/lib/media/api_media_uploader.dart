import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import '../api/api_client.dart';

class ApiMediaUploader {
  const ApiMediaUploader(this._client);

  final ApiClient _client;

  Future<String> upload({
    required String kind,
    required Uint8List bytes,
    required String fileName,
    String? fallbackMediaType,
  }) async {
    final detected = lookupMimeType(
      fileName,
      headerBytes: bytes.take(32).toList(),
    );
    final contentType =
        detected ?? (fallbackMediaType == 'video' ? 'video/mp4' : 'image/jpeg');
    final intent = apiObject(await _client.post('media/upload-intents', body: {
      'clientRequestId': _uuidV4(),
      'kind': kind,
      'contentType': contentType,
      'sizeBytes': bytes.length,
    },),);
    final headers = <String, String>{};
    final rawHeaders = intent['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        headers[key.toString()] = value.toString();
      });
    }
    await _client.putBytes(
      Uri.parse(intent['uploadUrl'] as String),
      bytes,
      headers: headers,
    );
    final completed = apiObject(await _client.post(
      'media/uploads/complete',
      body: {'objectId': intent['objectId']},
    ),);
    return completed['key'] as String;
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
