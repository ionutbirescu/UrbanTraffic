import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weather_service.dart';
import 'weather_screen.dart';

void main() {
  runApp(const NoiseMapperApp());
}

class NoiseMapperApp extends StatelessWidget {
  const NoiseMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urban Noise Mapping',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF1E293B),
      ),
      home: const RecordScreen(),
    );
  }
}

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  bool _isRecording = false;
  bool _isUploading = false;
  late final AudioRecorder _audioRecorder;

  Timer? _timer;
  int _recordDuration = 0;
  String _fileSize = '0 KB';

  Position? _lastPosition;
  DateTime? _recordedAt;
  String? _lastFilePath;
  WeatherData? _lastWeather;

  String _locationString = 'Waiting...';
  String _weatherString = 'Waiting...';

  // Network & identity
  final Dio _dio = Dio();
  String? _deviceId;

  // API Gateway endpoint
  static const String _apiBaseUrl =
      'https://xc2v8ify10.execute-api.eu-central-1.amazonaws.com';

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();

    // Timeout-uri rezonabile pentru rețele mobile
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 60);

    _loadOrCreateDeviceId();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  /// Salvează/încarcă device_id-ul persistat - acelasi UUID pe tot device-ul,
  /// indiferent câte ori se redeschide app-ul. Critic pentru History screen.
  Future<void> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
      debugPrint('Generated NEW device_id: $id');
    } else {
      debugPrint('Loaded existing device_id: $id');
    }
    if (mounted) {
      setState(() => _deviceId = id);
    }
  }

  // ============================================================
  // GPS
  // ============================================================
  Future<Position?> _captureLocation() async {
    setState(() => _locationString = 'Getting GPS...');

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationString = 'GPS Disabled');
        if (mounted) _showLocationServiceDialog();
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationString = 'GPS Denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationString = 'Perm. Denied');
        if (mounted) _showOpenAppSettingsDialog();
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      setState(() {
        _locationString =
        '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });

      return position;
    } catch (e) {
      setState(() => _locationString = 'GPS Timeout/Error');
      debugPrint('Eroare GPS: $e');
      return null;
    }
  }

  // ============================================================
  // Weather
  // ============================================================
  Future<WeatherData?> _captureWeather(Position position) async {
    setState(() => _weatherString = 'Fetching...');

    final weather = await WeatherService.fetchWeather(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    if (weather != null) {
      setState(() => _weatherString = '${weather.temperature.toStringAsFixed(1)}°C');
    } else {
      setState(() => _weatherString = 'Failed');
    }

    return weather;
  }

  // ============================================================
  // Dialoge GPS
  // ============================================================
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS dezactivat'),
        content: const Text(
          'Activează serviciul de localizare al telefonului ca să poți înregistra punctele pe hartă.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            child: const Text('Deschide setări'),
          ),
        ],
      ),
    );
  }

  void _showOpenAppSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permisiune refuzată permanent'),
        content: const Text(
          'Ai blocat permisiunea de locație. Deschide setările și activeaz-o manual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anulează'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Deschide setări'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AWS Upload
  // ============================================================
  Future<void> _uploadDataToAWS(
      File audioFile,
      Position gpsPosition,
      DateTime time,
      WeatherData? weather,
      ) async {
    if (_deviceId == null) {
      debugPrint('Upload anulat: device_id nu e încă disponibil.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device not ready, try again')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    try {
      // 1. Cere presigned URL
      debugPrint('1/3 Cerem presigned URL...');
      final urlResponse = await _dio.get('$_apiBaseUrl/upload-url');

      if (urlResponse.statusCode != 200) {
        throw Exception('upload-url returned ${urlResponse.statusCode}');
      }

      final presignedUrl = urlResponse.data['uploadUrl'] as String;
      final recordingId = urlResponse.data['recording_id'] as String;
      debugPrint('Got recording_id: $recordingId');

      // 2. PUT fișierul WAV în S3
      debugPrint('2/3 Upload S3...');
      final putResponse = await _dio.put(
        presignedUrl,
        data: audioFile.openRead(),
        options: Options(
          headers: {
            Headers.contentLengthHeader: await audioFile.length(),
            'Content-Type': 'audio/wav',
          },
        ),
      );

      if (putResponse.statusCode != 200) {
        throw Exception('S3 PUT returned ${putResponse.statusCode}');
      }

      // 3. POST metadata cu retry (PUT a reușit deja, fișierul e în S3 -
      // dacă POST-ul eșuează am rămâne cu orfan în S3, deci merită retry)
      debugPrint('3/3 POST metadata...');

      final metadataPayload = <String, dynamic>{
        'device_id': _deviceId,
        'recording_id': recordingId,
        'timestamp': time.toUtc().toIso8601String(),
        'lat': gpsPosition.latitude,
        'lon': gpsPosition.longitude,
        'accuracy_m': gpsPosition.accuracy,
        'status': 'PENDING',
      };

      if (weather != null) {
        metadataPayload['weather'] = weather.toMetadataJson();
      }

      await _postMetadataWithRetry(metadataPayload);

      debugPrint('✅ SUCCES! Datele au ajuns în AWS.');

      // 4. Curățăm fișierul local - e deja în S3
      try {
        if (await audioFile.exists()) {
          await audioFile.delete();
          debugPrint('Local WAV șters: ${audioFile.path}');
        }
      } catch (e) {
        debugPrint('Nu am putut șterge fișierul local: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Upload successful! Processing on AWS...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on DioException catch (e) {
      debugPrint('Dio Error: ${e.type} - ${e.message}');
      debugPrint('Response: ${e.response?.statusCode} ${e.response?.data}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.type.name}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('AWS Upload Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  /// Retry exponențial pentru POST /metadata - PUT-ul reușise deja, fișierul e
  /// în S3, deci e bine să încercăm mai mult timp decât să rămânem cu orfani.
  Future<void> _postMetadataWithRetry(Map<String, dynamic> payload) async {
    const maxRetries = 3;
    int retries = 0;

    while (true) {
      try {
        final response = await _dio.post('$_apiBaseUrl/metadata', data: payload);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return;
        }
        throw Exception('metadata returned ${response.statusCode}');
      } catch (e) {
        retries++;
        if (retries >= maxRetries) {
          debugPrint('Metadata POST a eșuat după $maxRetries încercări');
          rethrow;
        }
        final delay = Duration(seconds: retries * 2);
        debugPrint('Metadata POST eșuat, retry $retries în ${delay.inSeconds}s');
        await Future.delayed(delay);
      }
    }
  }

  // ============================================================
  // Navigare
  // ============================================================
  Future<void> _openMap() async {
    Position? position = _lastPosition;

    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Getting location...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      position = await _captureLocation();
      if (mounted && position != null) {
        setState(() => _lastPosition = position);
      }
    }

    if (position == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get location')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapScreen(position: position!),
        ),
      );
    }
  }

  Future<void> _openWeather() async {
    WeatherData? weather = _lastWeather;

    if (weather == null) {
      Position? position = _lastPosition;
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Getting location first...')),
          );
        }
        position = await _captureLocation();
        if (mounted && position != null) {
          setState(() => _lastPosition = position);
        }
      }

      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get location')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fetching weather...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      weather = await _captureWeather(position);
      if (mounted && weather != null) {
        setState(() => _lastWeather = weather);
      }
    }

    if (weather == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch weather')),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeatherScreen(weather: weather!),
        ),
      );
    }
  }

  // ============================================================
  // Recording
  // ============================================================
  Future<void> _startRecording() async {
    try {
      var micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }

      final appDocDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now();
      final String filePath =
          '${appDocDir.path}/recording_${timestamp.millisecondsSinceEpoch}.wav';

      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      await _audioRecorder.start(config, path: filePath);

      setState(() {
        _isRecording = true;
        _recordDuration = 0;
        _fileSize = 'Recording...';
        _locationString = 'Getting GPS...';
        _weatherString = 'Waiting...';
        _recordedAt = timestamp;
        _lastFilePath = filePath;
        _lastPosition = null;
        _lastWeather = null;
      });

      // GPS → vremea (vremea are nevoie de lat/lon)
      _captureLocation().then((position) async {
        if (!mounted || position == null) return;
        setState(() => _lastPosition = position);

        final weather = await _captureWeather(position);
        if (mounted && weather != null) {
          setState(() => _lastWeather = weather);
        }
      });

      _startTimer();
    } catch (e) {
      debugPrint('Error starting record: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();

    try {
      final path = await _audioRecorder.stop();
      final wasTooShort = _recordDuration < 10;

      if (path == null) {
        setState(() => _isRecording = false);
        return;
      }

      final file = File(path);
      final bytes = await file.length();
      final kb = (bytes / 1024).toStringAsFixed(1);

      // Recording prea scurt → șterge fișierul, notifică, nu fa upload
      if (wasTooShort) {
        try {
          if (await file.exists()) await file.delete();
        } catch (e) {
          debugPrint('Could not delete short recording: $e');
        }

        setState(() {
          _isRecording = false;
          _fileSize = '0 KB';
          _lastFilePath = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Recording too short (${_recordDuration}s). Minimum 10s required.',
              ),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      // Recording valid
      setState(() {
        _isRecording = false;
        _fileSize = '$kb KB';
        _lastFilePath = path;
      });

      debugPrint('File saved: $path');
      debugPrint('Timestamp: ${_recordedAt?.toIso8601String()}');

      // Fallback GPS + vremea dacă nu au venit în paralel cu recording-ul
      if (_lastPosition == null) {
        final position = await _captureLocation();
        if (mounted && position != null) {
          setState(() => _lastPosition = position);
          if (_lastWeather == null) {
            final weather = await _captureWeather(position);
            if (mounted && weather != null) {
              setState(() => _lastWeather = weather);
            }
          }
        }
      } else if (_lastWeather == null) {
        final weather = await _captureWeather(_lastPosition!);
        if (mounted && weather != null) {
          setState(() => _lastWeather = weather);
        }
      }

      // Lansăm upload-ul (vremea e opțională - dacă a eșuat, mergem fără)
      if (_lastPosition != null && _recordedAt != null) {
        await _uploadDataToAWS(
          file,
          _lastPosition!,
          _recordedAt!,
          _lastWeather,
        );
      } else {
        debugPrint('Upload anulat: lipsă GPS.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload skipped: no GPS data'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
      setState(() => _isRecording = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
      // FĂRĂ stop automat - userul oprește când vrea, minim 10s.
    });
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    String displayLocation = _locationString;
    if (_lastPosition != null && !_isRecording) {
      displayLocation =
      '${_lastPosition!.latitude.toStringAsFixed(4)}, ${_lastPosition!.longitude.toStringAsFixed(4)}';
    }

    String displayWeather = _weatherString;
    if (_lastWeather != null && !_isRecording) {
      displayWeather = '${_lastWeather!.temperature.toStringAsFixed(1)}°C';
    }

    final statusText = _isUploading
        ? 'UPLOADING TO AWS...'
        : (_isRecording ? 'RECORDING...' : 'READY');

    final statusColor = _isUploading
        ? Colors.orangeAccent
        : (_isRecording ? Colors.redAccent : Colors.grey.shade400);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Urban Noise',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Text(
              statusText,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: statusColor,
                letterSpacing: 2.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: () {
                if (_isUploading) return; // blocat în timpul upload-ului
                if (_isRecording) {
                  _stopRecording();
                } else {
                  _startRecording();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 220,
                width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isUploading
                      ? Colors.orange.withValues(alpha: 0.15)
                      : (_isRecording
                      ? Colors.redAccent.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.1)),
                  border: Border.all(
                    color: _isUploading
                        ? Colors.orange
                        : (_isRecording ? Colors.redAccent : Colors.blue),
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isUploading
                          ? Colors.orange.withValues(alpha: 0.3)
                          : (_isRecording
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : Colors.blue.withValues(alpha: 0.3)),
                      blurRadius: _isRecording || _isUploading ? 40 : 20,
                      spreadRadius: _isRecording || _isUploading ? 10 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.orange)
                      : Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 80,
                    color: _isRecording ? Colors.redAccent : Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              _isRecording
                  ? (_recordDuration < 10
                  ? '${10 - _recordDuration}s left'
                  : '${_recordDuration}s recorded')
                  : 'Record (minimum 10s)',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
                color: _isRecording && _recordDuration >= 10
                    ? Colors.greenAccent
                    : null,
              ),
            ),
            if (_lastPosition != null && !_isRecording) ...[
              const SizedBox(height: 8),
              Text(
                'GPS accuracy: ±${_lastPosition!.accuracy.toStringAsFixed(1)}m',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  InkWell(
                    onTap: _openMap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: _MetadataItem(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        value: displayLocation,
                        tappable: true,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _openWeather,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: _MetadataItem(
                        icon: Icons.cloud_outlined,
                        label: 'Weather',
                        value: displayWeather,
                        tappable: true,
                      ),
                    ),
                  ),
                  _MetadataItem(
                    icon: Icons.folder_outlined,
                    label: 'Size',
                    value: _fileSize,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool tappable;

  const _MetadataItem({
    required this.icon,
    required this.label,
    required this.value,
    this.tappable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 24,
          color: tappable ? Colors.lightBlueAccent : Colors.blueAccent,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade400,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: tappable ? Colors.lightBlueAccent : Colors.white,
            decoration: tappable ? TextDecoration.underline : null,
            decorationColor: Colors.lightBlueAccent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ============================================================
// Map Screen
// ============================================================
class MapScreen extends StatelessWidget {
  final Position position;

  const MapScreen({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    final LatLng userLocation = LatLng(position.latitude, position.longitude);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Location',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: userLocation,
              initialZoom: 16.0,
              minZoom: 3.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.noise_mapper',
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: userLocation,
                    radius: position.accuracy,
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderColor: Colors.blue.withValues(alpha: 0.5),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: userLocation,
                    width: 60,
                    height: 60,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 50,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    color: Colors.blueAccent,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current location',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Accuracy: ±${position.accuracy.toStringAsFixed(1)}m',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}