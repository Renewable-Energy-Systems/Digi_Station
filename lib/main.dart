import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/kiosk_shell.dart';
import 'config/api_constants.dart';
import 'socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize centralized WebSocket service (Dewpoint)
  SocketService().connectDewpoint(ApiConstants.detWsUrl);

  // Lock orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const RESKioskApp());
}

class RESKioskApp extends StatelessWidget {
  const RESKioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF304FFE), // deep-ish blue accent for UI
      scaffoldBackgroundColor: const Color(0xFFF5F6FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: Colors.black,
        ),
      ),
    );

    return MaterialApp(
      title: 'RES Production Kiosk',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: KioskShell(
        apiHost: ApiConstants.detApiHost,
      ),
    );
  }
}
