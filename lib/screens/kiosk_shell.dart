// lib/screens/kiosk_shell.dart
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// use prefixes to avoid name collisions and make it explicit
import 'web_logs_screen.dart' show WebLogsScreen;
import 'home_screen.dart' as home;
import 'wi_list_screen.dart' show WIListScreen;
import 'gauge_screen.dart' as gauge;
import 'det_selector_screen.dart' show DetSelectorScreen;

import 'package:ota_update/ota_update.dart';
import '../services/update_service.dart';

class KioskShell extends StatefulWidget {
  final WebSocketChannel? channel;
  final String apiHost;

  const KioskShell({
    super.key,
    required this.apiHost,
    this.channel,
  });

  @override
  State<KioskShell> createState() => _KioskShellState();
}


class _KioskShellState extends State<KioskShell> {
  late final PageController _controller;
  late final List<Widget> _pages; // cache pages
  int _pageIndex = 1; // start in the middle (Home)
  final UpdateService _updateService = UpdateService();

  // GlobalKey to access HomeScreen functionality
  final GlobalKey<home.HomeScreenState> _homeKey = GlobalKey<home.HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _checkForUpdates();

    _controller = PageController(initialPage: _pageIndex);

    // IMPORTANT: create these widgets ONCE
    // no const because widget constructors are not const
    _pages = [
      WebLogsScreen(), // index 0 (left)
      home.HomeScreen(key: _homeKey), // index 1 (center) — note the prefix
      WIListScreen(), // index 2 (right)
      gauge.GaugeScreen(), // index 3 — note the prefix
      DetSelectorScreen(         // index 4
        apiHost: widget.apiHost,
        channel: widget.channel,
        onDetChanged: () {
          // Trigger refresh on Home Screen
          _homeKey.currentState?.refreshSensorInfo();
        },
      ),
    ];
  }

  Future<void> _checkForUpdates() async {
    // Small delay to let UI build
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final info = await _updateService.checkForUpdate();
    if (info != null && info['updateAvailable'] == true && mounted) {
      _showUpdatePrompt(info);
    }
  }

  void _showUpdatePrompt(Map<String, dynamic> info) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('New Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info['latestVersion']} is available.'),
            const SizedBox(height: 8),
            const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: Text(info['releaseNotes'] ?? ''),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performUpdate(info['downloadUrl']);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _performUpdate(String apkUrl) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(
        stream: _updateService.runUpdate(apkUrl),
        onDone: () => Navigator.pop(ctx),
      ),
    );
  }

  void _goTo(int index) {
    if (index < 0 || index > _pages.length - 1) return;
    setState(() {
      _pageIndex = index;
    });
    _controller.animateToPage(
      _pageIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            physics:
                const NeverScrollableScrollPhysics(), // no swipe, use arrows
            children: _pages,
          ),

          // LEFT arrow
          if (_pageIndex > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _NavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _goTo(_pageIndex - 1),
                ),
              ),
            ),

          // RIGHT arrow
          if (_pageIndex < _pages.length - 1)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _NavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _goTo(_pageIndex + 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, size: 36, color: Colors.blueGrey[800]),
        ),
      ),
    );
  }
}

class _UpdateProgressDialog extends StatelessWidget {
  final Stream<OtaEvent> stream;
  final VoidCallback onDone;

  const _UpdateProgressDialog({super.key, required this.stream, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OtaEvent>(
      stream: stream,
      builder: (context, snapshot) {
        String status = "Starting download...";
        double? progress;

        if (snapshot.hasError) {
          status = "Error: ${snapshot.error}";
        } else if (snapshot.hasData) {
          final event = snapshot.data!;
          status = "${event.status} ${event.value ?? ''}";
          if (event.status == OtaStatus.DOWNLOADING) {
             progress = (int.tryParse(event.value ?? '0') ?? 0) / 100.0;
          }
          if (event.status == OtaStatus.INSTALLING) {
             progress = null; // indeterminate
             status = "Installing...";
          }
        }

        bool isDone = snapshot.connectionState == ConnectionState.done || snapshot.hasError;
        if (snapshot.hasData && snapshot.data!.status.toString().contains('ERROR')) {
           isDone = true;
        }

        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Updating App'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status),
                const SizedBox(height: 10),
                if (!isDone)
                   LinearProgressIndicator(value: progress),
              ],
            ),
            actions: [
                if (isDone)
                  TextButton(onPressed: onDone, child: const Text('Close'))
            ],
          ),
        );
      },
    );
  }
}
