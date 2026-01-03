import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const MyApp());

// UUIDs Blue-ST (depuis ton script MicroPython)
const String BLUEST_SERVICE_UUID = "00000000-0001-11e1-ac36-0002a5d5c51b";
const String TEMPERATURE_UUID = "00040000-0001-11e1-ac36-0002a5d5c51b";
const String SWITCH_UUID = "20000000-0001-11e1-ac36-0002a5d5c51b";

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT BLE Sensor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ScannerPage(),
    );
  }
}

// === PAGE SCANNER ===
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initBle();
  }

  Future<void> _initBle() async {
    if (await FlutterBluePlus.isSupported == false) return;
    if (Platform.isAndroid) await FlutterBluePlus.turnOn();

    FlutterBluePlus.scanResults.listen((results) {
      setState(() => _scanResults = results);
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      setState(() => _isScanning = scanning);
    });
  }

  void _startScan() async {
    setState(() => _scanResults = []);
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
      androidUsesFineLocation: true,
    );
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {}

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DevicePage(device: device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Scanner')),
      body: ListView.builder(
        itemCount: _scanResults.length,
        itemBuilder: (context, index) {
          final result = _scanResults[index];
          return ListTile(
            title: Text(
              result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : 'Appareil inconnu',
            ),
            subtitle: Text('${result.device.remoteId}'),
            trailing: Text('${result.rssi} dBm'),
            onTap: () => _connectToDevice(result.device),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        child: _isScanning
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.bluetooth_searching),
      ),
    );
  }
}

// === PAGE APPAREIL CONNECTÉ ===
class DevicePage extends StatefulWidget {
  final BluetoothDevice device;

  const DevicePage({super.key, required this.device});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  bool _isConnecting = true;
  bool _isConnected = false;
  BluetoothCharacteristic? _tempCharacteristic;
  BluetoothCharacteristic? _switchCharacteristic;

  double? _temperature;
  bool _ledOn = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      print('Connexion à ${widget.device.remoteId}...');
      await widget.device.connect(timeout: const Duration(seconds: 10));
      print('Connecté !');
      setState(() {
        _isConnecting = false;
        _isConnected = true;
      });
      await _setupBlueST();
    } catch (e) {
      print('Erreur connexion: $e');
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
    }
  }

  Future<void> _setupBlueST() async {
    final services = await widget.device.discoverServices();
    print('Services découverts: ${services.length}');

    for (var service in services) {
      print('Service: ${service.uuid}');

      if (service.uuid.toString().toLowerCase() == BLUEST_SERVICE_UUID) {
        print('Service Blue-ST trouvé !');

        for (var c in service.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          print('  Caractéristique: $uuid');

          if (uuid == TEMPERATURE_UUID) {
            _tempCharacteristic = c;
            print('  -> Température trouvée');

            // S'abonner aux notifications
            await c.setNotifyValue(true);
            c.onValueReceived.listen((value) {
              if (value.length >= 4) {
                // Décoder le float little-endian
                final bytes = Uint8List.fromList(value);
                final byteData = ByteData.sublistView(bytes);
                final temp = byteData.getFloat32(0, Endian.little);
                setState(() {
                  _temperature = temp;
                });
                print('Température reçue: $temp °C');
              }
            });
          }

          if (uuid == SWITCH_UUID) {
            _switchCharacteristic = c;
            print('  -> Switch trouvé');
          }
        }
      }
    }

    setState(() {});
  }

  Future<void> _toggleLed() async {
    if (_switchCharacteristic == null) return;

    _ledOn = !_ledOn;
    await _switchCharacteristic!.write([
      _ledOn ? 1 : 0,
    ], withoutResponse: false);
    setState(() {});
  }

  Future<void> _disconnect() async {
    await widget.device.disconnect();
    Navigator.pop(context);
  }

  @override
  void dispose() {
    widget.device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.platformName.isNotEmpty
              ? widget.device.platformName
              : 'Appareil',
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isConnecting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isConnected) {
      return const Center(child: Text('Connexion échouée'));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status connexion
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  _tempCharacteristic != null
                      ? 'Connecté - Blue-ST OK'
                      : 'Connecté - Service non trouvé',
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Affichage température
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.thermostat, size: 48, color: Colors.blue),
                const SizedBox(height: 8),
                Text(
                  _temperature != null
                      ? '${_temperature!.toStringAsFixed(1)} °C'
                      : '-- °C',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Text('Température', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Bouton LED
          if (_switchCharacteristic != null)
            ElevatedButton.icon(
              onPressed: _toggleLed,
              icon: Icon(_ledOn ? Icons.lightbulb : Icons.lightbulb_outline),
              label: Text(_ledOn ? 'LED ON' : 'LED OFF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _ledOn ? Colors.amber : Colors.grey[300],
                foregroundColor: _ledOn ? Colors.black : Colors.grey[700],
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
