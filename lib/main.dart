import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  void initState() {
    super.initState();
    // Inițializăm recorder-ul din pachetul 'record'
    _audioRecorder = AudioRecorder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      // 1. Cerem permisiunea pentru microfon
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
        }
        return;
      }

      // 2. Pregătim calea unde salvăm fișierul (Application Documents Directory)
      final appDocDir = await getApplicationDocumentsDirectory();
      final String filePath = '${appDocDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      // 3. Pornim înregistrarea (WAV, Mono, 16kHz)
      final config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      await _audioRecorder.start(config, path: filePath);

      // 4. Actualizăm UI-ul și pornim timer-ul
      setState(() {
        _isRecording = true;
        _recordDuration = 0;
        _fileSize = 'Recording...';
      });

      _startTimer();

    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();

    try {
      final path = await _audioRecorder.stop();

      if (path != null) {
        // Citim dimensiunea fișierului salvat
        final file = File(path);
        final bytes = await file.length();
        final kb = (bytes / 1024).toStringAsFixed(1);

        setState(() {
          _isRecording = false;
          _fileSize = '$kb KB';
        });

        debugPrint('File saved to: $path');
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
      // Oprire automată la 10 secunde conform specificațiilor MVP
      if (_recordDuration >= 10) {
        _stopRecording();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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

            const Text(
              'Record 10s',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),

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
                  const _MetadataItem(icon: Icons.location_on_outlined, label: 'Lat/Lon', value: 'Waiting GPS'),
                  _MetadataItem(icon: Icons.timer_outlined, label: 'Duration', value: '${_recordDuration}s'),
                  _MetadataItem(icon: Icons.folder_outlined, label: 'Size', value: _fileSize),
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

  const _MetadataItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Colors.blueAccent),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }
}