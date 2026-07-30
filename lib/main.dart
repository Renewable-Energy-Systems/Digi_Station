import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/kiosk_shell.dart';
import 'services/config_service.dart';
import 'socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve the (configurable) Dewpoint server host BEFORE wiring anything, so a
  // change made in Settings takes effect without rebuilding the APK. Defaults to
  // the bundled IP, so behaviour is unchanged until an operator edits it.
  final config = ConfigService();
  final wsUrl = await config.getDetWsUrl();
  final apiHost = await config.getDetApiHost();

  // Initialize centralized WebSocket service (Dewpoint)
  SocketService().connectDewpoint(wsUrl);

  // Lock orientation (fire-and-forget so it doesn't delay the first frame).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(RESKioskApp(apiHost: apiHost));
}

class RESKioskApp extends StatelessWidget {
  final String apiHost;
  const RESKioskApp({super.key, required this.apiHost});

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
      title: 'Digi Station',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: KioskShell(
        apiHost: apiHost,
      ),
    );
  }
}
