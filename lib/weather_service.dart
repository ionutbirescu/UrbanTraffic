import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Model pentru datele meteo - structurat ca să fie ușor de trimis la AWS
class WeatherData {
  final double temperature; // Celsius
  final double feelsLike;
  final int humidity; // %
  final double windKph;
  final String windDirection; // N, NE, E, etc.
  final double precipitationMm;
  final String conditionText; // "Sunny", "Cloudy", etc.
  final String conditionIcon; // URL la icon
  final int conditionCode; // pentru maparea proprie
  final double pressureMb;
  final double uvIndex;
  final int cloudCover; // %
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

  /// Parsează răspunsul JSON de la WeatherAPI
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final location = json['location'] as Map<String, dynamic>;
    final condition = current['condition'] as Map<String, dynamic>;

    return WeatherData(
      temperature: (current['temp_c'] as num).toDouble(),
      feelsLike: (current['feelslike_c'] as num).toDouble(),
      humidity: current['humidity'] as int,
      windKph: (current['wind_kph'] as num).toDouble(),
      windDirection: current['wind_dir'] as String,
      precipitationMm: (current['precip_mm'] as num).toDouble(),
      conditionText: condition['text'] as String,
      conditionIcon: 'https:${condition['icon']}', // icon URL e fără schema
      conditionCode: condition['code'] as int,
      pressureMb: (current['pressure_mb'] as num).toDouble(),
      uvIndex: (current['uv'] as num).toDouble(),
      cloudCover: current['cloud'] as int,
      visibilityKm: (current['vis_km'] as num).toDouble(),
      localTime: location['localtime'] as String,
      fetchedAt: DateTime.now(),
    );
  }

  /// Pentru upload la AWS - format flat, ușor de pus în DynamoDB
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
  // ⚠️ Înlocuiește cu key-ul tău de pe weatherapi.com
  static const String _apiKey = '6d93692f26d04d4fa8f142534261305';
  static const String _baseUrl = 'https://api.weatherapi.com/v1';

  /// Capturează datele meteo curente pentru o locație GPS.
  /// Returnează null dacă apelul eșuează.
  static Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    if (_apiKey == 'YOUR_API_KEY_HERE' || _apiKey.isEmpty) {
      debugPrint('⚠️ WeatherAPI key not configured!');
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
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return WeatherData.fromJson(json);
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