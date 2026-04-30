// lib/services/process_slip_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/process_slip_model.dart';
import '../config/api_constants.dart';
import 'config_service.dart';

class ProcessSlipService {
  Future<ProcessSlip?> fetchLatestSlip(String workstationId) async {
    try {
      final baseUrl = await ConfigService().getOpsDigiBaseUrl();
      final response = await http.get(
        Uri.parse('$baseUrl/api_latest_slip.php?workstation_id=$workstationId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['slip'] != null) {
          return ProcessSlip.fromJson(data['slip']);
        } else {
          throw Exception(data['message'] ?? 'Failed to load slip data');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
