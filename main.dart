import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/esp32_service.dart';
import 'services/database_service.dart';
import 'screens/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final esp32 = ESP32Service();
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('esp32_ip');
    final port = prefs.getInt('esp32_port') ?? 8080;
    if (ip != null && ip.isNotEmpty) {
      await esp32.connect(ip, port);
      final alarm = await esp32.getAlarmState();
      if (alarm) {
        const AndroidNotificationDetails androidPlatformChannelSpecifics =
            AndroidNotificationDetails(
          'alarm_channel',
          'Alarmas',
          channelDescription: 'Notificaciones de alarma de gas',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          playSound: true,
        );
        const NotificationDetails platformChannelSpecifics =
            NotificationDetails(android: androidPlatformChannelSpecifics);
        await flutterLocalNotificationsPlugin.show(
          0,
          '¡PELIGRO!',
          'Se detectaron niveles peligrosos de gas',
          platformChannelSpecifics,
          payload: 'alarm',
        );
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar base de datos
  await DatabaseService.instance.database;

  // Inicializa notificaciones locales
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Solicitar permisos
  await _requestPermissions();

  // Inicializa Workmanager
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // Programa la tarea periódica (cada 15 minutos es el mínimo en Android)
  Workmanager().registerPeriodicTask(
    "1",
    "checkAlarmTask",
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(seconds: 10),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  runApp(const GasoxApp());
}

Future<void> _requestPermissions() async {
  await [
    Permission.location,
    Permission.nearbyWifiDevices,
  ].request();
}

class GasoxApp extends StatelessWidget {
  const GasoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GASOX',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.orange,
        colorScheme: ColorScheme.dark(
          primary: Colors.orange,
          secondary: Colors.orangeAccent,
          background: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.orange,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFD32F2F),
          foregroundColor: Colors.white,
        ),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Colors.orange,
          thumbColor: Colors.orangeAccent,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
