import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windKph;
  final String windDirection;
  final double precipitationMm;
  final String conditionText;
  final String conditionIcon;
  final int conditionCode;
  final double pressureMb;
  final double uvIndex;
  final int cloudCover;
  final double visibilityKm;
  final String localTime;
  final DateTime fetchedAt;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windKph,
    required this.windDirection,
    required this.precipitationMm,
    required this.conditionText,
    required this.conditionIcon,
    required this.conditionCode,
    required this.pressureMb,
    required this.uvIndex,
    required this.cloudCover,
    required this.visibilityKm,
    required this.localTime,
    required this.fetchedAt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final location = json['location'] as Map<String, dynamic>;
    final condition = current['condition'] as Map<String, dynamic>;

    return WeatherData(
      temperature: (current['temp_c'] as num?)?.toDouble() ?? 0.0,
      feelsLike: (current['feelslike_c'] as num?)?.toDouble() ?? 0.0,
      humidity: (current['humidity'] as num?)?.toInt() ?? 0,
      windKph: (current['wind_kph'] as num?)?.toDouble() ?? 0.0,
      windDirection: (current['wind_dir'] as String?) ?? 'N/A',
      precipitationMm: (current['precip_mm'] as num?)?.toDouble() ?? 0.0,
      conditionText: (condition['text'] as String?) ?? 'Unknown',
      conditionIcon: 'https:${(condition['icon'] as String?) ?? ''}',
      conditionCode: (condition['code'] as num?)?.toInt() ?? 0,
      pressureMb: (current['pressure_mb'] as num?)?.toDouble() ?? 0.0,
      uvIndex: (current['uv'] as num?)?.toDouble() ?? 0.0,
      cloudCover: (current['cloud'] as num?)?.toInt() ?? 0,
      visibilityKm: (current['vis_km'] as num?)?.toDouble() ?? 0.0,
      localTime: (location['localtime'] as String?) ?? '',
      fetchedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toMetadataJson() {
    return {
      'temp_c': temperature,
      'feels_like_c': feelsLike,
      'humidity': humidity,
      'wind_kph': windKph,
      'wind_dir': windDirection,
      'precip_mm': precipitationMm,
      'condition': conditionText,
      'condition_code': conditionCode,
      'pressure_mb': pressureMb,
      'cloud_cover': cloudCover,
      'visibility_km': visibilityKm,
      'fetched_at': fetchedAt.toIso8601String(),
    };
  }
}

class WeatherService {
  static const String _apiKey = '6d93692f26d04d4fa8f142534261305';
  static const String _baseUrl = 'https://api.weatherapi.com/v1';

  static Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey == 'YOUR_API_KEY_HERE' || _apiKey.isEmpty) {
      debugPrint(' WeatherAPI key not configured!');
      return null;
    }

    try {
      final uri = Uri.parse(
        '$_baseUrl/current.json?key=$_apiKey&q=$latitude,$longitude&aqi=no',
      );

      final response = await http.get(uri).timeout(
        const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
        return WeatherData.fromJson(jsonBody);
      } else {
        debugPrint('Weather API error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
      return null;
    }
  }
}