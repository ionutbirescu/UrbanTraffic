
import 'package:dio/dio.dart';
import 'recording_model.dart';

class ApiService {
  static const String _baseUrl =
      'https://xc2v8ify10.execute-api.eu-central-1.amazonaws.com';

  final Dio _dio;

  ApiService() : _dio = Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
  }

  Future<List<Recording>> listRecordings(String deviceId) async {
    final resp = await _dio.get(
      '$_baseUrl/recordings',
      queryParameters: {'device_id': deviceId},
    );

    final data = resp.data;
    final List items = (data is Map && data['recordings'] is List)
        ? data['recordings'] as List
        : <dynamic>[];

    return items
        .whereType<Map>()
        .map((m) => Recording.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<Recording> getRecording(String recordingId) async {
    final resp = await _dio.get('$_baseUrl/recordings/$recordingId');
    return Recording.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<Recording> getResult(String recordingId) async {
    final resp = await _dio.get('$_baseUrl/result/$recordingId');
    return Recording.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<void> deleteRecording(String recordingId) async {
    await _dio.delete('$_baseUrl/recordings/$recordingId');
  }
}
