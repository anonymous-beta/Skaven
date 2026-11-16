
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

class ScanFinding {
  final String title;
  final String detail;
  final String severity;
  final String module;

  const ScanFinding({
    required this.title,
    required this.detail,
    required this.severity,
    required this.module,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'severity': severity,
        'module': module,
      };

  factory ScanFinding.fromJson(Map<String, dynamic> json) {
    return ScanFinding(
      title: json['title']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'info',
      module: json['module']?.toString() ?? 'General',
    );
  }
}

class ScanReport {
  final String target;
  final DateTime timestamp;
  final int pagesVisited;
  final String status;
  final List<ScanFinding> findings;

  const ScanReport({
    required this.target,
    required this.timestamp,
    required this.pagesVisited,
    required this.status,
    required this.findings,
  });

  int get criticalCount =>
      findings.where((f) => f.severity == 'critical').length;

  int get highCount => findings.where((f) => f.severity == 'high').length;

  int get mediumCount => findings.where((f) => f.severity == 'medium').length;

  Map<String, dynamic> toJson() => {
        'target': target,
        'timestamp': timestamp.toIso8601String(),
        'pagesVisited': pagesVisited,
        'status': status,
        'findings': findings.map((f) => f.toJson()).toList(),
      };

  factory ScanReport.fromJson(Map<String, dynamic> json) {
    return ScanReport(
      target: json['target']?.toString() ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
              DateTime.now(),
      pagesVisited: (json['pagesVisited'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'Unknown',
      findings: (json['findings'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => ScanFinding.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }
}

class _PageResult {
  final Uri uri;
  final int statusCode;
  final Map<String, List<String>> headers;
  final String body;

  const _PageResult({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  String header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.join(', ');
      }
    }
    return '';
  }
}

class ReconService {
  static const int maxPages = 12;
  static const int maxBodyCharacters = 1500000;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 12),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': 'SKAVEN-Public-Recon/1.0',
        'Accept': 'text/html,application/javascript,text/css,*/*',
      },
    ),
  );

  final List<ScanFinding> _findings = [];
  final Set<String> _visited = {};
  final Set<String> _endpoints = {};
  final Set<String> _technologies = {};

  void _add(
    String title,
    String detail, {
    String severity = 'info',
    String module = 'General',
  }) {
    _findings.add(
      ScanFinding(
        title: title,
        detail: detail,
        severity: severity,
        module: module,
      ),
    );
  }

  Future<ScanReport> scan(
    String input, {
    void Function(String message)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _findings.clear();
    _visited.clear();
    _endpoints.clear();
    _technologies.clear();

    final now = DateTime.now();
    final target = _normalizeTarget(input);

    if (target == null) {
      _add(
        'Invalid target',
        'Enter a valid public website hostname or HTTP/HTTPS URL.',
        severity: 'high',
      );

      return ScanReport(
        target: input,
        timestamp: now,
        pagesVisited: 0,
        status: 'Invalid target',
        findings: List.unmodifiable(_findings),
      );
    }

    onProgress?.call('Checking DNS resolution...');

    try {
      final addresses = await InternetAddress.lookup(target.host)
          .timeout(const Duration(seconds: 10));

      if (addresses.isEmpty) {
        throw const SocketException('No DNS addresses returned.');
      }

      final resolved = addresses.map((a) => a.address).join(', ');

      _add(
        'DNS resolution',
        'Resolved ${target.host} to $resolved.',
        module: 'Network intelligence',
      );
    } catch (error) {
      _add(
        'DNS resolution failed',
        'The hostname could not be resolved. Check the domain spelling, DNS records, and network connection. Details: $error',
        severity: 'high',
        module: 'Network intelligence',
      );

      return ScanReport(
        target: target.toString(),
        timestamp: now,
        pagesVisited: 0,
        status: 'DNS failed',
        findings: List.unmodifiable(_findings),
      );
    }

    final queue = <Uri>[target];
    _add(
      'Scan scope',
      'This scan is limited to public HTTP/HTTPS resources on the supplied origin. It does not attempt authentication or exploitation.',
      module: 'General',
    );

    while (queue.isNotEmpty && _visited.length < maxPages) {
      if (cancelToken?.isCancelled == true) {
        break;
      }

      final current = queue.removeAt(0);
      final normalized = _normalizePage(current);

      if (normalized == null || !_visited.add(normalized.toString())) {
        continue;
      }

      onProgress?.call(
        'Inspecting page ${_visited.length}/$maxPages: ${normalized.path}',
      );

      try {
        final result = await _fetch(
          normalized,
          cancelToken: cancelToken,
        );

        if (result == null) continue;

        _inspectHeaders(result);
        _inspectTechnology(result);
        _inspectSource(result);

        final contentType = result.header('content-type').toLowerCase();

        if (contentType.contains('text/html') ||
            result.body.trimLeft().startsWith('<!DOCTYPE html') ||
            result.body.trimLeft().startsWith('<html')) {
          _discoverLinks(result, queue);
        }
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) break;

        _add(
          'Page request failed',
          '${normalized.toString()} — ${error.message ?? error.type.name}',
          severity: 'medium',
          module: 'Website crawler',
        );
      } catch (error) {
        _add(
          'Page inspection error',
          '${normalized.toString()} — $error',
          severity: 'low',
          module: 'Website crawler',
        );
      }
    }

    if (cancelToken?.isCancelled == true) {
      _add(
        'Scan cancelled',
        'The scan was stopped before all queued pages were inspected.',
        module: 'General',
      );
    }

    onProgress?.call('Inspecting public discovery files...');

    if (cancelToken?.isCancelled != true) {
      await _inspectDiscoveryFile(target, '/robots.txt', 'Robots.txt');
      await _inspectDiscoveryFile(target, '/sitemap.xml', 'Sitemap');
      await _inspectDiscoveryFile(target, '/.well-known/security.txt',
          'Security.txt');
    }

    if (_endpoints.isNotEmpty) {
      _add(
        'Potential API references',
        _endpoints.take(80).join('\n'),
        module: 'API discovery',
      );
    } else {
      _add(
        'No API references detected',
        'No matching endpoint references were found in the inspected public source. This does not prove that the website has no API.',
        module: 'API discovery',
      );
    }

    if (_technologies.isNotEmpty) {
      _add(
        'Technology indicators',
        _technologies.join('\n'),
        module: 'Source intelligence',
      );
    }

    final status = cancelToken?.isCancelled == true
        ? 'Cancelled'
        : 'Completed';

    onProgress?.call('Scan finished.');

    return ScanReport(
      target: target.toString(),
      timestamp: now,
      pagesVisited: _visited.length,
      status: status,
      findings: List.unmodifiable(_findings),
    );
  }

  Uri? _normalizeTarget(String input) {
    var value = input.trim();

    if (value.isEmpty) return null;

    if (!value.contains('://')) {
      value = 'https://$value';
    }

    final uri = Uri.tryParse(value);

    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      return null;
    }

    return uri.replace(
      fragment: '',
      query: '',
      path: uri.path.isEmpty ? '/' : uri.path,
    );
  }

  Uri? _normalizePage(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    return uri.replace(fragment: '');
  }

  bool _sameOrigin(Uri a, Uri b) {
    return a.scheme == b.scheme &&
        a.host.toLowerCase() == b.host.toLowerCase() &&
        a.port == b.port;
  }

  Future<_PageResult?> _fetch(
    Uri uri, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<String>(
      uri.toString(),
      cancelToken: cancelToken,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    final finalUri = response.realUri;

    if (!_sameOrigin(uri, finalUri)) {
      _add(
        'Cross-origin redirect blocked',
        'The requested URL redirected outside the original website origin.',
        severity: 'medium',
        module: 'Website crawler',
      );
      return null;
    }

    final rawBody = response.data ?? '';
    final body = rawBody.length > maxBodyCharacters
        ? rawBody.substring(0, maxBodyCharacters)
        : rawBody;

    return _PageResult(
      uri: finalUri,
      statusCode: response.statusCode ?? 0,
      headers: response.headers.map,
      body: body,
    );
  }

  void _inspectHeaders(_PageResult result) {
    final headers = result.headers;

    _add(
      'HTTP response',
      '${result.uri} returned HTTP ${result.statusCode}.',
      module: 'Website crawler',
    );

    final checks = <String, String>{
      'Strict-Transport-Security':
          'HSTS helps enforce HTTPS connections.',
      'Content-Security-Policy':
          'CSP can help reduce certain content injection risks.',
      'X-Content-Type-Options':
          'Helps prevent MIME type sniffing.',
      'X-Frame-Options':
          'Can help prevent unwanted framing.',
      'Referrer-Policy':
          'Controls referrer information sent by the browser.',
      'Permissions-Policy':
          'Controls access to selected browser features.',
    };

    for (final entry in checks.entries) {
      final present = result.header(entry.key).isNotEmpty;

      if (!present) {
        _add(
          'Missing ${entry.key}',
          entry.value,
          severity: 'low',
          module: 'Security analysis',
        );
      }
    }

    final server = result.header('server');
    if (server.isNotEmpty) {
      _technologies.add('Server header: $server');
    }

    final powered = result.header('x-powered-by');
    if (powered.isNotEmpty) {
      _technologies.add('X-Powered-By: $powered');
    }

    final cookies = headers.entries
        .where((entry) => entry.key.toLowerCase() == 'set-cookie')
        .expand((entry) => entry.value)
        .toList();

    for (final cookie in cookies) {
      final lower = cookie.toLowerCase();
      final cookieName = cookie.split('=').first;

      final flags = <String>[];
      if (lower.contains('secure')) flags.add('Secure');
      if (lower.contains('httponly')) flags.add('HttpOnly');
      if (lower.contains('samesite')) flags.add('SameSite');

      _add(
        'Cookie metadata: $cookieName',
        flags.isEmpty
            ? 'The Set-Cookie header does not visibly include Secure, HttpOnly, or SameSite attributes. Review the cookie in its application context.'
            : 'Observed attributes: ${flags.join(', ')}.',
        severity: flags.isEmpty ? 'medium' : 'info',
        module: 'Security analysis',
      );
    }
  }

  void _inspectTechnology(_PageResult result) {
    final server = result.header('server');
    final powered = result.header('x-powered-by');

    if (server.isNotEmpty) _technologies.add('Server: $server');
    if (powered.isNotEmpty) _technologies.add('Platform: $powered');

    final body = result.body.toLowerCase();

    final indicators = <String, String>{
      'wp-content': 'WordPress indicator',
      'wp-includes': 'WordPress indicator',
      'drupal.settings': 'Drupal indicator',
      'cdn.shopify.com': 'Shopify indicator',
      'react': 'React-related source indicator',
      'next/static': 'Next.js indicator',
      'ng-version': 'Angular indicator',
      'jquery': 'jQuery indicator',
    };

    for (final entry in indicators.entries) {
      if (body.contains(entry.key)) {
        _technologies.add(entry.value);
      }
    }
  }

  void _inspectSource(_PageResult result) {
    final body = result.body;

    final endpointPattern = RegExp(
      r'''["']((?:https?:)?//[^"'\s]+|/(?:api|graphql|rest|v[0-9]+)[^"'\s]*)["']''',
      caseSensitive: false,
    );

    for (final match in endpointPattern.allMatches(body)) {
      final value = match.group(1);
      if (value == null || value.length > 500) continue;

      _endpoints.add(value);
    }

    final sourcePattern = RegExp(
      r'''<script[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );

    for (final match in sourcePattern.allMatches(body)) {
      final value = match.group(1);
      if (value != null) {
        _endpoints.add('JavaScript resource: $value');
      }
    }

    final graphql = body.toLowerCase().contains('graphql');
    if (graphql) {
      _endpoints.add('GraphQL reference detected in public source');
    }
  }

  void _discoverLinks(_PageResult result, List<Uri> queue) {
    final document = html_parser.parse(result.body);

    for (final element in document.querySelectorAll('a[href]')) {
      final href = element.attributes['href'];

      if (href == null || href.trim().isEmpty) continue;

      final uri = Uri.tryParse(href.trim());
      if (uri == null) continue;

      final resolved = result.uri.resolveUri(uri);
      final normalized = _normalizePage(resolved);

      if (normalized == null) continue;
      if (!_sameOrigin(result.uri, normalized)) continue;

      if (!_visited.contains(normalized.toString()) &&
          !queue.contains(normalized)) {
        queue.add(normalized);
      }
    }
  }

  Future<void> _inspectDiscoveryFile(
    Uri target,
    String path,
    String label,
  ) async {
    final uri = target.replace(
      path: path,
      query: '',
      fragment: '',
    );

    try {
      final result = await _fetch(uri);

      if (result == null) return;

      if (result.statusCode >= 200 && result.statusCode < 300) {
        _add(
          '$label found',
          '${result.uri}\n\n${result.body.substring(
            0,
            result.body.length > 4000 ? 4000 : result.body.length,
          )}',
          module: 'Discovery files',
        );
      } else {
        _add(
          '$label not available',
          'The server returned HTTP ${result.statusCode}.',
          module: 'Discovery files',
        );
      }
    } catch (error) {
      _add(
        '$label inspection failed',
        error.toString(),
        severity: 'low',
        module: 'Discovery files',
      );
    }
  }

  void dispose() {
    _dio.close(force: true);
  }
}
