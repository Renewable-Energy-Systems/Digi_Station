import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:ota_update/ota_update.dart'; // Keeping for UI compatibility (OtaEvent)
import 'package:package_info_plus/package_info_plus.dart';
import 'config_service.dart';

class UpdateService {
  final String _repoOwner = 'Renewable-Energy-Systems';
  final String _repoName = 'Digi_Station';

  // Check for updates from GitHub
  Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final Uri url = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      debugPrint('Checking GitHub update: $url');

      final token = ConfigService.gitHubToken;
      final Map<String, String> headers = {
        'Accept': 'application/vnd.github+json',
      };
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 10));

      debugPrint('Response: ${response.statusCode}');
      if (response.statusCode == 200) {
        // GitHub returns pure UTF-8, no BOM usually, but we stick to utf8 decoding just in case
        final data = json.decode(utf8.decode(response.bodyBytes));

        // 1. Get Version (tag_name)
        String latestVersion = data['tag_name'];
        // Remove 'v' prefix if present common in git tags (e.g. v1.0.0)
        if (latestVersion.startsWith('v')) {
          latestVersion = latestVersion.substring(1);
        }

        // 2. Get APK Asset
        final assets = data['assets'] as List;
        final apkAsset = assets.firstWhere(
          (asset) => asset['name'].toString().endsWith('.apk'),
          orElse: () => null,
        );

        if (apkAsset == null) {
          throw Exception(
            'Released Found ($latestVersion) but no APK file attached.',
          );
        }

        // For private repos, we must use the 'url' (API) with 'Accept: application/octet-stream' header
        // For public repos, 'browser_download_url' works directly.
        // We will assume private/authenticated workflow mostly, or adaptive.
        // We pass the API 'url' to runUpdate, and we'll attach the header there.
        final String downloadUrl = apkAsset['url'];
        // final String browserUrl = apkAsset['browser_download_url'];

        final packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;

        debugPrint('Current: $currentVersion, Latest: $latestVersion');

        if (_isNewer(latestVersion, currentVersion)) {
          return {
            'updateAvailable': true,
            'latestVersion': latestVersion,
            'currentVersion': currentVersion,
            'downloadUrl': downloadUrl,
            'browserUrl':
                apkAsset['browser_download_url'], // fallback for display or public
            'releaseNotes': data['body'] ?? 'GitHub Release',
            'isPrivate': token.isNotEmpty, // flag to use headers
          };
        } else {
          return {'updateAvailable': false, 'currentVersion': currentVersion};
        }
      } else if (response.statusCode == 404) {
        // Distinguish between "Repo Not Found" and "No Releases"
        // Try to fetch repo details
        try {
          final repoUrl = Uri.parse(
            'https://api.github.com/repos/$_repoOwner/$_repoName',
          );
          final repoResponse = await http
              .get(repoUrl, headers: headers)
              .timeout(const Duration(seconds: 5));
          if (repoResponse.statusCode == 200) {
            return {
              'error': 'No Releases found. Please create a Release on GitHub.',
            };
          }
        } catch (_) {}

        return {'error': 'Repo not found. Check Token, Permissions, or URL.'};
      } else if (response.statusCode == 401) {
        return {'error': 'Unauthorized. Check GitHub Token.'};
      } else {
        return {'error': 'GitHub API Error: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      return {'error': e.toString()};
    }
  }

  bool _isNewer(String latest, String current) {
    try {
      List<int> l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> c = current
          .split('.')
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      for (int i = 0; i < 3; i++) {
        int lv = (i < l.length) ? l[i] : 0;
        int cv = (i < c.length) ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
    } catch (e) {
      debugPrint('Version parse error: $e');
    }
    return false;
  }

  // Secure Downloader
  Stream<OtaEvent> runUpdate(String apkUrl) async* {
    yield OtaEvent(OtaStatus.DOWNLOADING, '0');

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/update.apk';

      final dio = Dio();

      final token = ConfigService.gitHubToken;
      Options options = Options();

      // Always attach token if available, assumption is we are authenticated context
      if (token.isNotEmpty) {
        options.headers = {
          'Accept': 'application/octet-stream',
          'Authorization': 'Bearer $token',
        };
      }

      await dio.download(
        apkUrl,
        filePath,
        options: options,
        onReceiveProgress: (received, total) {
          // Basic progress logging
        },
      );

      yield OtaEvent(OtaStatus.DOWNLOADING, '100');

      // Note: GitHub Releases doesn't give us a simple hash in metadata unless we read it from body.
      // For now, we rely on HTTPS transport security from GitHub.
      // FUTURE: We could parse the release notes for "SHA256: xxx" if strictly needed.

      // Install
      yield OtaEvent(OtaStatus.INSTALLING, 'Installing...');
      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done) {
        yield OtaEvent(
          OtaStatus.INTERNAL_ERROR,
          'Install failed: ${result.message}',
        );
      }
    } catch (e) {
      yield OtaEvent(OtaStatus.INTERNAL_ERROR, e.toString());
    }
  }
}
