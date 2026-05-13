import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  late final AudioRecorder _audioRecorder;

  Timer? _timer;
  int _recordDuration = 0;
  String _fileSize = '0 KB';

  Position? _lastPosition;
  DateTime? _recordedAt;
  String? _lastFilePath;

  String _locationString = 'Waiting...';

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<Position?> _captureLocation() async {
    setState(() {
      _locationString = 'Getting GPS...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationString = 'GPS Disabled');
        if (mounted) {
          _showLocationServiceDialog();
        }
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
        if (mounted) {
          _showOpenAppSettingsDialog();
        }
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
          'Ai blocat permisiunea de locație pentru această aplicație. Deschide setările și activeaz-o manual.',
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

  /// Deschide ecranul cu harta - dacă avem o poziție o folosim,
  /// altfel încercăm să o capturăm acum.
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
        _recordedAt = timestamp;
        _lastFilePath = filePath;
        _lastPosition = null;
      });

      _captureLocation().then((position) {
        if (mounted && position != null) {
          setState(() {
            _lastPosition = position;
          });
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

      if (path != null) {
        final file = File(path);
        final bytes = await file.length();
        final kb = (bytes / 1024).toStringAsFixed(1);

        // Dacă a fost prea scurt, ștergem fișierul și anunțăm userul
        if (wasTooShort) {
          try {
            if (await file.exists()) {
              await file.delete();
            }
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
                  'Recording too short (${_recordDuration}s). Minimum 10s required for classification.',
                ),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        // Recording valid - salvăm metadata
        setState(() {
          _isRecording = false;
          _fileSize = '$kb KB';
          _lastFilePath = path;
        });

        debugPrint('File saved to: $path');
        debugPrint('Timestamp: ${_recordedAt?.toIso8601String()}');
        if (_lastPosition != null) {
          debugPrint(
            'Position: ${_lastPosition!.latitude}, ${_lastPosition!.longitude} '
                '(±${_lastPosition!.accuracy.toStringAsFixed(1)}m)',
          );
        }

        // Fallback dacă GPS-ul nu a venit în timpul recording-ului
        if (_lastPosition == null) {
          final position = await _captureLocation();
          if (mounted && position != null) {
            setState(() => _lastPosition = position);
          }
        }
      } else {
        setState(() => _isRecording = false);
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
      setState(() => _isRecording = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        _recordDuration++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    String displayLocation = _locationString;
    if (_lastPosition != null && !_isRecording) {
      displayLocation =
      '${_lastPosition!.latitude.toStringAsFixed(4)}, ${_lastPosition!.longitude.toStringAsFixed(4)}';
    }

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
              _isRecording ? 'RECORDING...' : 'READY',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: _isRecording ? Colors.redAccent : Colors.grey.shade400,
                letterSpacing: 2.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: () {
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
                  color: _isRecording
                      ? Colors.redAccent.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isRecording ? Colors.redAccent : Colors.blue,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isRecording
                          ? Colors.redAccent.withValues(alpha: 0.3)
                          : Colors.blue.withValues(alpha: 0.3),
                      blurRadius: _isRecording ? 40 : 20,
                      spreadRadius: _isRecording ? 10 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
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
                  : 'Record (minimum of 10s)',
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
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
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
                  // Location este acum tappable - deschide harta
                  InkWell(
                    onTap: _openMap,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _MetadataItem(
                        icon: Icons.location_on_outlined,
                        label: 'Location',
                        value: displayLocation,
                        tappable: true,
                      ),
                    ),
                  ),
                  _MetadataItem(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: '${_recordDuration}s',
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
// Map Screen - afișează poziția curentă cu un pin pe OpenStreetMap
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
                urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.noise_mapper',
              ),
              // Cerc care reprezintă acuratețea GPS
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
              // Pin-ul propriu-zis
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
          // Card cu info în partea de jos
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