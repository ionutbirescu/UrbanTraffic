import 'package:flutter/material.dart';

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
        // Un fundal "nu chiar așa închis" - un gri-albăstrui modern (Slate 800)
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
  bool isRecording = false;

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

            // Indicator vizual de status
            Text(
              isRecording ? 'RECORDING' : 'READY',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isRecording ? Colors.redAccent : Colors.grey.shade400,
                letterSpacing: 2.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),

            // Butonul mare "Record 10s" cu efect de puls/glow
            GestureDetector(
              onTap: () {
                setState(() {
                  isRecording = !isRecording;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 220,
                width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRecording
                      ? Colors.redAccent.withOpacity(0.15)
                      : Colors.blue.withOpacity(0.1),
                  border: Border.all(
                    color: isRecording ? Colors.redAccent : Colors.blue,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isRecording
                          ? Colors.redAccent.withOpacity(0.3)
                          : Colors.blue.withOpacity(0.3),
                      blurRadius: isRecording ? 40 : 20,
                      spreadRadius: isRecording ? 10 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 80,
                    color: isRecording ? Colors.redAccent : Colors.blue,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // Titlul
            const Text(
              'Record 10s',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),

            const Spacer(),

            // Card de jos pentru afișarea coordonatelor și metadatelor
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                // O nuanță puțin mai deschisă decât fundalul pentru a scoate cardul în evidență (Slate 700)
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MetadataItem(icon: Icons.location_on_outlined, label: 'Lat/Lon', value: 'WAITING for GPS'),
                  _MetadataItem(icon: Icons.timer_outlined, label: 'Time', value: '0.0s'),
                  _MetadataItem(icon: Icons.folder_outlined, label: 'Dimension', value: '0 KB'),
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