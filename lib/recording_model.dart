class Recording {
  final String recordingId;
  final String? deviceId;
  final String timestamp;
  final String status;
  final double? lat;
  final double? lon;
  final Map<String, double> scores;
  final String? topClass;
  final WeatherInfo? weather;

  Recording({
    required this.recordingId,
    required this.timestamp,
    required this.status,
    this.deviceId,
    this.lat,
    this.lon,
    this.scores = const {},
    this.topClass,
    this.weather,
  });

  bool get isDone => status == 'DONE';
  bool get isPending => status == 'PENDING';
  bool get isError => status == 'ERROR';

  bool get hasScores => scores.values.any((v) => v > 0);

  String get dominantClass {
    if (topClass != null && topClass!.isNotEmpty) return topClass!;
    if (scores.isEmpty) return 'Unknown';
    return scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  factory Recording.fromJson(Map<String, dynamic> json) {
    Map<String, double> parsedScores = {};
    String? parsedTopClass;

    final cls = json['classification'];
    if (cls is Map) {
      if (cls.containsKey('scores')) {
        final s = cls['scores'];
        if (s is Map) {
          s.forEach((k, v) => parsedScores[k.toString()] = _toDouble(v));
        }
        parsedTopClass = cls['top_class']?.toString();
      } else {
        cls.forEach((k, v) => parsedScores[k.toString()] = _toDouble(v));
      }
    }

    return Recording(
      recordingId: json['recording_id']?.toString() ?? '',
      deviceId: json['device_id']?.toString(),
      timestamp: json['timestamp']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      lat: json['lat'] == null ? null : _toDouble(json['lat']),
      lon: json['lon'] == null ? null : _toDouble(json['lon']),
      scores: parsedScores,
      topClass: parsedTopClass,
      weather: json['weather'] is Map
          ? WeatherInfo.fromJson(Map<String, dynamic>.from(json['weather']))
          : null,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

class WeatherInfo {
  final double? tempC;
  final String? condition;
  final double? windKph;
  final String? windDir;
  final double? precipMm;
  final int? humidity;

  WeatherInfo({
    this.tempC,
    this.condition,
    this.windKph,
    this.windDir,
    this.precipMm,
    this.humidity,
  });

  factory WeatherInfo.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
    int? i(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

    return WeatherInfo(
      tempC: d(json['temp_c']),
      condition: json['condition']?.toString(),
      windKph: d(json['wind_kph']),
      windDir: json['wind_dir']?.toString(),
      precipMm: d(json['precip_mm']),
      humidity: i(json['humidity']),
    );
  }
}
