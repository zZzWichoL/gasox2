import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/esp32_service.dart';

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '8080');

  bool _isScanning = false;
  bool _isTesting = false;
  String _connectionStatus = '';

  final ESP32Service _esp32Service = ESP32Service();

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ipController.text = prefs.getString('esp32_ip') ?? '';
    _portController.text = (prefs.getInt('esp32_port') ?? 8080).toString();
  }

  Future<void> _testConnection() async {
    try {
      await _esp32Service.connect(
          _ipController.text, int.tryParse(_portController.text) ?? 8080);
      setState(() {
        _connectionStatus = '✅ Conexión exitosa';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = '❌ Error: $e';
      });
    }
  }

  Future<void> _scanForESP32() async {
    setState(() {
      _isScanning = true;
      _connectionStatus = '🔍 Verificando permisos...';
    });

    // Solicitar permisos
    final locationStatus = await Permission.location.request();
    final nearbyDevicesStatus = await Permission.nearbyWifiDevices.request();

    if (locationStatus.isDenied || nearbyDevicesStatus.isDenied) {
      setState(() {
        _isScanning = false;
        _connectionStatus = '❌ Se requieren permisos para escanear la red';
      });
      return;
    }

    try {
      setState(() {
        _connectionStatus = '🔍 Buscando dispositivo en la red...';
      });

      final foundIP = await _esp32Service.scanForESP32();

      if (foundIP != null) {
        setState(() {
          _ipController.text = foundIP;
          _connectionStatus = '✅ Dispositivo encontrado automáticamente';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dispositivo encontrado en: $foundIP')),
        );
      } else {
        setState(() {
          _connectionStatus =
              '❌ No se encontró el dispositivo. Asegúrate de que esté encendido y conectado a la misma red.';
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = '❌ Error durante la búsqueda: $e';
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  // Modifica el método _saveIpAndPort:
  Future<void> _saveIpAndPort(String ip, String portStr) async {
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa una IP válida')),
      );
      return;
    }

    setState(() {
      _connectionStatus = '🔒 Guardando y verificando...';
    });

    final port = int.tryParse(portStr) ?? 8080;

    try {
      // Usa connect() en lugar de testConnection()
      await _esp32Service.connect(ip, port);

      // Si llegamos aquí, la conexión fue exitosa
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('esp32_ip', ip);
      await prefs.setInt('esp32_port', port);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ Conexión verificada y configuración guardada')),
      );
      setState(() {
        _connectionStatus = '✅ Dirección guardada correctamente';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ No se pudo conectar a $ip:$port')),
      );
      setState(() {
        _connectionStatus =
            '❌ Falló la verificación. Verifica la IP y conexión.';
      });
    }
  }

  Future<void> _resetWiFi() async {
    try {
      await _esp32Service.forgetWiFi();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ Comando enviado. El ESP32 reiniciará su WiFi.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración de Red')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Información sobre conexión automática
          Card(
            color: Colors.orange.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Conexión automática',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'La app intentará conectarse automáticamente a gasox.local.\n'
                    'Si no funciona, usa las opciones de abajo.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Botón para abrir portal de configuración
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Abrir portal de configuración'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                final url = Uri.parse('http://192.168.4.1');
                if (!await launchUrl(url,
                    mode: LaunchMode.externalApplication)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('No se pudo abrir el navegador.')),
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 32),

          // Sección de configuración manual
          Card(
            color: Colors.green.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wifi, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Configuración manual',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Botón de escaneo automático
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search),
                      label: Text(_isScanning
                          ? 'Escaneando...'
                          : 'Buscar ESP32 automáticamente'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isScanning ? null : _scanForESP32,
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  const Text(
                    'O ingresa la IP manualmente:',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),

                  // Campos de IP y puerto
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          decoration: InputDecoration(
                            labelText: 'IP del ESP32',
                            hintText: 'Ejemplo: 192.168.100.65',
                            filled: true,
                            fillColor: Colors.white10,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: 'Puerto',
                            hintText: '8080',
                            filled: true,
                            fillColor: Colors.white10,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Botones de acción
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_find),
                          label: Text(_isTesting ? 'Probando...' : 'Probar'),
                          onPressed: _isTesting ? null : _testConnection,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save, color: Colors.orange),
                          label: const Text('Guardar'),
                          onPressed: () => _saveIpAndPort(
                              _ipController.text, _portController.text),
                        ),
                      ),
                    ],
                  ),

                  // Estado de conexión
                  if (_connectionStatus.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _connectionStatus.startsWith('✅')
                            ? Colors.green.withOpacity(0.2)
                            : _connectionStatus.startsWith('❌')
                                ? Colors.red.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _connectionStatus,
                        style: TextStyle(
                          color: _connectionStatus.startsWith('✅')
                              ? Colors.green
                              : _connectionStatus.startsWith('❌')
                                  ? Colors.red
                                  : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Botón para resetear WiFi
          ElevatedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reiniciar WiFi del ESP32'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: _resetWiFi,
          ),
        ],
      ),
    );
  }
}
