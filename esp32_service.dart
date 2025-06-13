import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multicast_dns/multicast_dns.dart';

class ESP32Service {
  String? _host;
  int? _port;
  static const Duration timeout = Duration(seconds: 5);
  static const int defaultPort = 8080;

  Future<InternetAddress?> _resolveMdns(String hostname) async {
    final MDnsClient client = MDnsClient();
    try {
      await client.start();
      await for (final PtrResourceRecord ptr
          in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_http._tcp'),
      )) {
        await for (final SrvResourceRecord srv
            in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          if (srv.target.contains(hostname)) {
            await for (final IPAddressResourceRecord ip
                in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
              client.stop();
              return ip.address;
            }
          }
        }
      }
      client.stop();
    } catch (_) {
      client.stop();
    }
    return null;
  }

  Future<void> connect(String host, int port) async {
    _host = host;
    _port = port;
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    await setESP32IP(host, port);
  }

  Future<bool> ping() async {
    try {
      final response = await sendCommand('PING');
      return response.contains('PONG');
    } catch (e) {
      return false;
    }
  }

  Future<String> sendCommand(String command) async {
    if (_host == null || _port == null) {
      throw Exception('No hay conexión establecida');
    }

    final socket = await Socket.connect(_host!, _port!, timeout: timeout);
    final completer = Completer<String>();
    List<int> buffer = [];
    late StreamSubscription sub;

    sub = socket.listen(
      (data) {
        buffer.addAll(data);
        String response = utf8.decode(buffer).trim();
        if (!completer.isCompleted) {
          completer.complete(response);
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError('Conexión cerrada sin respuesta');
        }
      },
      cancelOnError: true,
    );

    socket.write('$command\n');
    await socket.flush();

    try {
      String response = await completer.future.timeout(timeout);
      print('Respuesta cruda de ESP32: $response'); // Para depuración
      await sub.cancel();
      await socket.close();
      return response;
    } catch (e) {
      await sub.cancel();
      await socket.close();
      rethrow;
    }
  }

  Future<bool> testConnection(String ip, int port) async {
    try {
      final response = await sendCommand('GET_VALUES');
      return response.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> setESP32IP(String ip, [int port = defaultPort]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_ip', ip);
    await prefs.setInt('esp32_port', port);
  }

  Future<String?> scanForESP32() async {
    final resolved = await _resolveMdns('gasox');
    if (resolved != null) return resolved.address;

    try {
      final interfaces = await NetworkInterface.list();
      String? networkBase;
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              networkBase = '${parts[0]}.${parts[1]}.${parts[2]}';
              break;
            }
          }
        }
        if (networkBase != null) break;
      }
      if (networkBase == null) {
        throw Exception('No se encontró una interfaz de red válida');
      }
      for (int i = 100; i <= 110; i++) {
        final testIP = '$networkBase.$i';
        if (await testConnection(testIP, defaultPort)) {
          return testIP;
        }
      }
    } catch (e) {
      throw Exception('Error al escanear la red: $e');
    }
    return null;
  }

  Future<void> forgetWiFi() async {
    try {
      await sendCommand('FORGET_WIFI');
    } catch (_) {
      try {
        await sendCommand('FORGET_WIFI');
      } catch (e2) {
        throw Exception(
            'Error al olvidar WiFi: no se pudo conectar ni a la red local ni al portal');
      }
    }
  }

  Future<Map<String, int>> getSensorValues() async {
    final response = await sendCommand('GET_VALUES');
    print('Respuesta cruda de ESP32: $response');
    int mq4 = 0, mq7 = 0;
    final parts = response.trim().split(RegExp(r'[,\n\r]+'));
    for (var part in parts) {
      if (part.trim().startsWith('MQ4:')) {
        mq4 = int.tryParse(part.split(':')[1].trim()) ?? 0;
      } else if (part.trim().startsWith('MQ7:')) {
        mq7 = int.tryParse(part.split(':')[1].trim()) ?? 0;
      }
    }
    print('Valores parseados: mq4=$mq4, mq7=$mq7');
    return {'mq4': mq4, 'mq7': mq7};
  }

  Future<bool> getAlarmState() async {
    final response = await sendCommand('GET_ALARM');
    return response.trim() == 'ON';
  }

  Future<void> setMQ4Threshold(int threshold) async {
    await sendCommand('SET_MQ4:$threshold');
  }

  Future<void> setMQ7Threshold(int threshold) async {
    await sendCommand('SET_MQ7:$threshold');
  }

  Future<void> checkAlarmBackground() async {
    await getAlarmState();
  }
}
