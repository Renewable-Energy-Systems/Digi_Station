import 'package:flutter/material.dart';
import '../models/work_instruction.dart';
import '../widgets/wi_card.dart';
import 'video_player_screen.dart';
// Import the gauge screen
import '../services/config_service.dart';

import '../constants/work_instructions.dart'; // Import constants

class WIListScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSettings;

  const WIListScreen({super.key, this.onNavigateToSettings});

  @override
  State<WIListScreen> createState() => _WIListScreenState();
}

class _WIListScreenState extends State<WIListScreen> {
  // Configured videos (Map logic removed in favor of Settings config)
  List<WorkInstruction> _currentWis = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final configService = ConfigService();
    // 1. Get enabled video IDs from Settings
    final enabledIds = await configService.getEnabledVideoIds();

    if (enabledIds.isNotEmpty) {
      // 2. Filter master list based on enabled IDs
      // Using master list from shared constants
      final all = WorkInstructionsConstants.allWis;
      final filtered = all.where((wi) => enabledIds.contains(wi.id)).toList();

      if (mounted) {
        setState(() {
          _currentWis = filtered;
          _isLoading = false;
        });
      }
    } else {
      // 3. Fallback: Show empty list (user must configure)
      if (mounted) {
        setState(() {
          _currentWis = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Work Instructions',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: _currentWis.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No videos configured for this Workstation ID.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: widget.onNavigateToSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Configure Videos in Settings'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _currentWis.length,
              itemBuilder: (context, index) {
                final wi = _currentWis[index];
                return WICard(
                  wi: wi,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          title: wi.title,
                          videoPath: wi.videoPath,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
