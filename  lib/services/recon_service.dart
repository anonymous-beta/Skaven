
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

enum FindingLevel { info, low, medium, high }

class Finding {
  final String title;
  final String detail;
  final FindingLevel level;
  final String category;

  const Finding({
    required this.title,
    required this.detail,
    required this.level,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'level': level.name,
        'category': category,
      };

  factory Finding.fromJson(Map<String, dynamic> json) => Finding(
        title: json['title']?.toString() ?? '',
        detail: json['detail']?.toString() ?? '',
        level: FindingLevel.values.firstWhere(
          (value) => value.name == json['level'],
          orElse: () => FindingLevel.info,
        ),
        category: json['category']?.toString() ?? 'General',
      );
}

class ScanReport {
  final String target;
  final DateTime started;
  DateTime? completed;

  String? resolvedIp;
  String? server;
  String? contentType;
  String? redirect;
  String? waf;
  String? tlsSummary;
  String? error;
  int? statusCode;

  bool cancelled = false;
  bool dnsResolved = false;

  final List<String> pages = [];
  final List<String> scripts = [];
  final List<String> stylesheets = [];
  final List<String> endpoints = [];
  final List<String> technologies = [];
  final List<String> robotsEntries = [];
  final List<String> sitemapEntries = [];
  final Map<String, String> headers = {};
  final List<Finding> findings = [];

  ScanReport({
    required this.target,
    required this.started,
  });

  Map<String, dynamic> toJson() => {
        'target': target,
        'started': started.toIso8601String(),
        'completed': completed?.toIso8601String(),
        'resolvedIp': resolvedIp,
        'server': server,
        'contentType': contentType,
        'redirect': redirect,
        'waf': waf,
        'tlsSummary': tlsSummary,
        'error': error,
        'statusCode': statusCode,
        'cancelled': cancelled,
        'dnsResolved': dnsResolved,
        'pages': pages,
        'scripts': scripts,
        'stylesheets': stylesheets,
        'endpoints': endpoints,
        'technologies': technologies,
        'robotsEntries': robotsEntries,
        'sitemapEntries': sitemapEntries,
        'headers': headers,
        'findings': findings.map((item) => item.toJson()).toList(),
      };

  factory ScanReport.fromJson(Map<String, dynamic> json) {
    final report = ScanReport(
      target: json['target']?.toString() ?? '',
      started: DateTime.tryParse(json['started']?.toString() ?? '') ??
          DateTime.now(),
    );

    report.completed =
        DateTime.tryParse(json['completed']?.toString() ?? '');
    report.resolvedIp = json['resolvedIp']?.toString();
    report.server = json['server']?.toString();
    report.contentType = json['contentType']?.toString();
    report.redirect = json['redirect']?.toString();
    report.waf = json['waf']?.toString();
    report.tlsSummary = json['tlsSummary']?.toString();
    report.error = json['error']?.toString();
    report.statusCode = json['statusCode'] is int
        ? json['statusCode'] as int
        : int.tryParse(json['statusCode']?.toString() ?? '');
    report.cancelled = json['cancelled'] == true;
    report.dnsResolved = json['dnsResolved'] == true;

    void addList(String key, List<String> destination) {
      final value = json[key];
      if (value is List) {
        destination.addAll(value.map((item) => item.toString()));
      }
    }

    addList('pages', report.pages);
    addList('scripts', report.scripts);
    addList('stylesheets', report.stylesheets);
    addList('endpoints', report.endpoints);
    addList('technologies', report.technologies);
    addList('robotsEntries', report.robotsEntries);
    addList('sitemapEntries', report.sitemapEntries);

    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        report.headers[key.toString()] = value.toString();
      });
    }

    final rawFindings = json['findings'];
    if (rawFindings is List) {
      for (final item in rawFindings) {
        if (item is Map) {
          report.findings.add(
            Finding.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return report;
  }

  String toReportText() {
    final output = StringBuffer();

    output.writeln('SKAVEN WEB RECONNAISSANCE REPORT');
    output.writeln('=' * 42);
    output.writeln('Target: $target');
    output.writeln('Started: ${started.toLocal()}');
    output.writeln('Completed: ${completed?.toLocal() ?? 'Incomplete'}');
    output.writeln('HTTP status: ${statusCode ?? 'Not available'}');
    output.writeln('Resolved IP: ${resolvedIp ?? 'Not resolved'}');
    output.writeln('Server: ${server ?? 'Not disclosed'}');
    output.writeln('Content type: ${contentType ?? 'Unknown'}');
    output.writeln('TLS: ${tlsSummary ?? 'Not inspected'}');
    output.writeln('WAF/CDN: ${waf ?? 'Not identified'}');

    if (redirect != null) output.writeln('Redirect: $redirect');
    if (error != null) output.writeln('\nScan error: $error');
    if (cancelled) output.writeln('\nScan was cancelled.');

    void section(String title, List<String> values) {
      output.writeln('\n$title (${values.length})');
      output.writeln('-' * 35);
      if (values.isEmpty) {
        output.writeln('No entries discovered.');
      } else {
        for (final value in values) {
          output.writeln(value);
        }
      }
    }

    section('Discovered pages', pages);
    section('JavaScript resources', scripts);
    section('Stylesheets', stylesheets);
    section('Observable endpoint references', endpoints);
    section('Technology indicators', technologies);
    section('robots.txt entries', robotsEntries);
    section('Sitemap entries', sitemapEntries);

    output.writeln('\nHTTP RESPONSE HEADERS');
    headers.forEach((key, value) {
      output.writeln('$key: $value');
    });

    output.writeln('\nFINDINGS (${findings.length})');
    for (final finding in findings) {
      output.writeln(
        '[${finding.level.name.toUpperCase()}] '
        '${finding.category}: ${finding.title}',
      );
      output.writeln(finding.detail);
      output.writeln();
    }

    output.writeln('\nGenerated by SKAVEN.');
    output.writeln('Creator: Anonymous-beta (Chinedu)');

    return output.toString();
  }
}

class _PageResult {
  final ResponseBody response;
  final String body;
  final Uri finalUri;

  const _PageResult({
    required this.response,
    required this.body,
    required this.finalUri,
  });
}

class ReconService {
  static const int maxPages = 30;
  static const int maxAssets = 40;
  static const int maxPageBytes = 2 * 1024 * 1024;
  static const int maxAssetBytes = 1024 * 1024;
  static const int maxRedirects = 5;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.stream,
      followRedirects: false,
      validateStatus: (status) => status != null,
      headers: {
        HttpHeaders.userAgentHeader: 'SKAVEN-Recon/1.0',
        HttpHeaders.acceptHeader:
            'text/html,application/xhtml+xml,application/javascript,text/javascript,text/css,application/json,*/*;q=0.5',
        HttpHeaders.acceptEncodingHeader: 'identity',
      },
    ),
  );

  CancelToken? _cancelToken;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('Scan cancelled by user.');
  }

  void dispose() {
    cancel();
    _dio.close(force: true);
  }

  Future<ScanReport> scan(String input) async {
    final started = DateTime.now();
    Uri target;

    try {
      target = _normalizeTarget(input);
    } catch (error) {
      final report = ScanReport(target: input, started: started);
      report.error = error.toString();
      report.completed = DateTime.now();
      report.findings.add(
        Finding(
          title: 'Invalid target',
          detail: error.toString(),
          level: FindingLevel.high,
          category: 'Input validation',
        ),
      );
      return report;
    }

    final report = ScanReport(
      target: target.toString(),
      started: started,
    );

    _cancelled = false;
    _cancelToken = CancelToken();

    try {
      final addresses = await InternetAddress.lookup(target.host)
          .timeout(const Duration(seconds: 10));

      if (addresses.isEmpty) {
        throw const SocketException('DNS returned no addresses.');
      }

      final publicAddresses = addresses
          .where((address) => _isPublicAddress(address.address))
          .toList();

      if (publicAddresses.isEmpty) {
        throw const SocketException(
          'The hostname did not resolve to an acceptable public IP address.',
        );
      }

      report.dnsResolved = true;
      report.resolvedIp = publicAddresses.first.address;

      report.findings.add(
        Finding(
          title: 'Hostname resolved',
          detail:
              '${target.host} resolved to ${report.resolvedIp}. This confirms DNS resolution, not that the website is healthy.',
          level: FindingLevel.info,
          category: 'DNS',
        ),
      );

      if (target.scheme == 'https') {
        report.tlsSummary = await _inspectTls(target);
      }

      final queue = <Uri>[target];
      final visited = <String>{};
      final assetQueue = <Uri>[];

      while (queue.isNotEmpty &&
          visited.length < maxPages &&
          !_cancelled) {
        final current = queue.removeAt(0);
        final key = current.toString();

        if (!visited.add(key)) continue;

        try {
          final result = await _request(
            current,
            maxPageBytes,
          );

          if (result == null) continue;

          final response = result.response;
          final finalUri = result.finalUri;
          final status = response.statusCode ?? 0;

          report.statusCode ??= status;
          report.server ??= _header(response, 'server');
          report.contentType ??= _header(response, 'content-type');

          if (current == target && finalUri != target) {
            report.redirect = finalUri.toString();
          }

          if (current == target) {
            report.headers.clear();
            response.headers.forEach((key, values) {
              report.headers[key] = values.join(', ');
            });
            _analyzeHeaders(report);
            report.waf = _identifyWaf(response.headers);
          }

          if (status >= 400) {
            report.findings.add(
              Finding(
                title: 'HTTP response $status',
                detail: '$finalUri returned HTTP $status.',
                level: status >= 500
                    ? FindingLevel.medium
                    : FindingLevel.low,
                category: 'HTTP',
              ),
            );
            continue;
          }

          final type = (_header(response, 'content-type') ?? '').toLowerCase();

          if (type.isNotEmpty &&
              !type.contains('text/html') &&
              !type.contains('application/xhtml')) {
            continue;
          }

          report.pages.add(finalUri.toString());
          _fingerprint(report, result.body, response.headers);

          final document = html_parser.parse(result.body);

          for (final element in document.querySelectorAll('a[href]')) {
            final href = element.attributes['href'];
            if (href == null) continue;

            final uri = _safeSameOriginUri(finalUri, href);
            if (uri == null || _isLikelyBinary(uri.path)) continue;

            if (queue.length + visited.length < maxPages * 2) {
              queue.add(uri);
            }
          }

          for (final element in document.querySelectorAll('script[src]')) {
            final src = element.attributes['src'];
            if (src == null) continue;
            final uri = _safeSameOriginUri(finalUri, src);
            if (uri == null) continue;

            _addUnique(report.scripts, uri.toString());
            if (assetQueue.length < maxAssets) assetQueue.add(uri);
          }

          for (final element
              in document.querySelectorAll('link[rel="stylesheet"][href]')) {
            final href = element.attributes['href'];
            if (href == null) continue;
            final uri = _safeSameOriginUri(finalUri, href);
            if (uri == null) continue;

            _addUnique(report.stylesheets, uri.toString());
            if (assetQueue.length < maxAssets) assetQueue.add(uri);
          }

          for (final element in document.querySelectorAll(
              'iframe[src], img[src], source[src]')) {
            final src = element.attributes['src'];
            if (src == null) continue;
            final uri = _safeSameOriginUri(finalUri, src);
            if (uri == null || _isLikelyBinary(uri.path)) continue;
            _extractEndpointFromText(report, uri.toString());
          }

          _extractEndpoints(report, result.body);
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) {
            _cancelled = true;
            break;
          }
          _recordRequestError(report, current, error);
        } on SocketException catch (error) {
          _recordSocketError(report, current, error);
          if (current == target) rethrow;
        } on TimeoutException catch (error) {
          report.findings.add(
            Finding(
              title: 'Request timed out',
              detail: '$current: $error',
              level: FindingLevel.medium,
              category: 'Network',
            ),
          );
        } catch (error) {
          report.findings.add(
            Finding(
              title: 'Page inspection failed',
              detail: '$current: $error',
              level: FindingLevel.low,
              category: 'Crawler',
            ),
          );
        }
      }

      for (final asset in assetQueue.take(maxAssets)) {
        if (_cancelled) break;

        try {
          final result = await _request(asset, maxAssetBytes);
          if (result == null) continue;

          final contentType =
              (_header(result.response, 'content-type') ?? '').toLowerCase();

          if (contentType.contains('javascript') ||
              contentType.contains('text/') ||
              contentType.contains('json') ||
              contentType.isEmpty) {
            _extractEndpoints(report, result.body);
            _fingerprint(report, result.body, result.response.headers);
          }
        } catch (_) {
          // An individual asset failure should not terminate the scan.
        }
      }

      if (!_cancelled) {
        await _inspectWellKnownFiles(report, target);
      }

      if (report.pages.isEmpty && report.error == null) {
        report.findings.add(
          const Finding(
            title: 'No HTML pages inspected',
            detail:
                'The target resolved, but no HTML page was successfully inspected. Check its response status, redirects, access restrictions and content type.',
            level: FindingLevel.medium,
            category: 'Crawler',
          ),
        );
      }
    } on SocketException catch (error) {
      report.error = _friendlySocketError(error);
      report.findings.add(
        Finding(
          title: 'Network or DNS failure',
          detail: report.error!,
          level: FindingLevel.high,
          category: 'Network',
        ),
      );
    } on DioException catch (error) {
      report.error = _friendlyDioError(error);
      report.findings.add(
        Finding(
          title: 'Connection failed',
          detail: report.error!,
          level: FindingLevel.high,
          category: 'Network',
        ),
      );
    } catch (error) {
      report.error = error.toString();
      report.findings.add(
        Finding(
          title: 'Scan failed',
          detail: report.error!,
          level: FindingLevel.high,
          category: 'Engine',
        ),
      );
    } finally {
      report.cancelled = _cancelled;
      report.completed = DateTime.now();
    }

    return report;
  }

  Uri _normalizeTarget(String input) {
    var value = input.trim();

    if (value.isEmpty) {
      throw const FormatException('Enter a website address.');
    }

    if (!value.contains('://')) {
      value = 'https://$value';
    }

    final uri = Uri.parse(value);

    if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
      throw const FormatException('Only HTTP and HTTPS targets are supported.');
    }

    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Enter a valid hostname without credentials.');
    }

    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      throw const FormatException(
        'Only standard web ports 80 and 443 are supported.',
      );
    }

    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      fragment: '',
      path: uri.path.isEmpty ? '/' : uri.path,
    );
  }

  bool _isPublicAddress(String value) {
    final address = InternetAddress.tryParse(value);
    if (address == null) return false;

    if (address.type == InternetAddressType.IPv4) {
      final parts = value.split('.').map(int.parse).toList();
      final a = parts[0];
      final b = parts[1];

      if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
      if (a == 100 && b >= 64 && b <= 127) return false;
      if (a == 169 && b == 254) return false;
      if (a == 172 && b >= 16 && b <= 31) return false;
      if (a == 192 && b == 168) return false;
      if (a == 192 && b == 0) return false;
      if (a == 192 && b == 2) return false;
      if (a == 198 && (b == 18 || b == 19 || b == 51)) return false;
      if (a == 203 && b == 0) return false;

      return true;
    }

    final normalized = value.toLowerCase();

    if (normalized == '::' || normalized == '::1') return false;
    if (normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe8') ||
        normalized.startsWith('fe9') ||
        normalized.startsWith('fea') ||
        normalized.startsWith('feb') ||
        normalized.startsWith('ff')) {
      return false;
    }

    return true;
  }

  Future<String> _inspectTls(Uri uri) async {
    SecureSocket? socket;

    try {
      socket = await SecureSocket.connect(
        uri.host,
        uri.port,
        timeout: const Duration(seconds: 8),
        onBadCertificate: (_) => false,
      );

      final certificate = socket.peerCertificate;

      if (certificate == null) {
        return 'TLS connection established; certificate details unavailable.';
      }

      final subject = certificate.subject;
      final issuer = certificate.issuer;
      final validFrom = certificate.startValidity;
      final validTo = certificate.endValidity;

      return 'TLS handshake successful. Subject: $subject. Issuer: $issuer. '
          'Valid: $validFrom to $validTo.';
    } catch (error) {
      return 'TLS inspection failed: $error';
    } finally {
      socket?.destroy();
    }
  }

  Future<_PageResult?> _request(Uri initialUri, int maxBytes) async {
    Uri current = initialUri;

    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      if (_cancelled) return null;

      final addresses = await InternetAddress.lookup(current.host)
          .timeout(const Duration(seconds: 8));

      if (addresses.isEmpty ||
          addresses.every((address) => !_isPublicAddress(address.address))) {
        throw const SocketException(
          'Hostname did not resolve to an acceptable public address.',
        );
      }

      final response = await _dio.get<ResponseBody>(
        current.toString(),
        cancelToken: _cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) => status != null,
        ),
      );

      final status = response.statusCode ?? 0;

      if ([301, 302, 303, 307, 308].contains(status)) {
        final location = _header(response, 'location');

        if (location == null || redirects == maxRedirects) {
          return null;
        }

        final next = current.resolve(location);

        if (!_isAllowedRedirect(current, next)) {
          throw const SocketException(
            'Redirect blocked because it changes origin or uses an unsupported destination.',
          );
        }

        current = next;
        continue;
      }

      final bodyStream = response.data?.stream;
      if (bodyStream == null) return null;

      final bytes = <int>[];

      await for (final chunk in bodyStream) {
        if (_cancelled) return null;

        if (bytes.length + chunk.length > maxBytes) {
          final remaining = maxBytes - bytes.length;
          if (remaining > 0) bytes.addAll(chunk.take(remaining));
          break;
        }

        bytes.addAll(chunk);
      }

      final body = utf8.decode(bytes, allowMalformed: true);

      return _PageResult(
        response: response.data!,
        body: body,
        finalUri: current,
      );
    }

    return null;
  }

  bool _isAllowedRedirect(Uri from, Uri to) {
    if (!['http', 'https'].contains(to.scheme)) return false;
    if (to.userInfo.isNotEmpty) return false;
    if (to.host.toLowerCase() != from.host.toLowerCase()) return false;
    if (to.port != from.port) return false;
    return true;
  }

  Future<void> _inspectWellKnownFiles(
    ScanReport report,
    Uri target,
  ) async {
    final paths = [
      '/robots.txt',
      '/sitemap.xml',
      '/.well-known/security.txt',
    ];

    for (final path in paths) {
      if (_cancelled) return;

      try {
        final uri = target.replace(path: path, query: '', fragment: '');
        final result = await _request(uri, 256 * 1024);
        if (result == null) continue;

        final status = result.response.statusCode ?? 0;
        if (status < 200 || status >= 300) continue;

        if (path == '/robots.txt') {
          report.robotsEntries.addAll(
            result.body
                .split('\n')
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty && !line.startsWith('#'))
                .take(100),
          );
        } else if (path == '/sitemap.xml') {
          final matches = RegExp(
            r'<loc>\s*(.*?)\s*</loc>',
            caseSensitive: false,
            dotAll: true,
          ).allMatches(result.body);

          for (final match in matches.take(100)) {
            final value = match.group(1)?.trim();
            if (value != null && value.isNotEmpty) {
              report.sitemapEntries.add(value);
            }
          }
        } else {
          report.findings.add(
            Finding(
              title: 'security.txt is publicly available',
              detail:
                  'A security contact policy was found at ${uri.toString()}.',
              level: FindingLevel.info,
              category: 'Security policy',
            ),
          );
        }
      } catch (_) {
        // These files are optional. A failed request is not a scan failure.
      }
    }
  }

  void _analyzeHeaders(ScanReport report) {
    final headers = report.headers.map(
      (key, value) => MapEntry(key.toLowerCase(), value),
    );

    void check({
      required String header,
      required String title,
      required String detail,
      required FindingLevel level,
    }) {
      if (!headers.containsKey(header)) {
        report.findings.add(
          Finding(
            title: title,
            detail: detail,
            level: level,
            category: 'HTTP security headers',
          ),
        );
      }
    }

    if (report.target.startsWith('https://')) {
      check(
        header: 'strict-transport-security',
        title: 'HSTS header not observed',
        detail:
            'The inspected response did not include Strict-Transport-Security.',
        level: FindingLevel.medium,
      );
    }

    check(
      header: 'content-security-policy',
      title: 'Content Security Policy not observed',
      detail:
          'The inspected response did not include a Content-Security-Policy header.',
      level: FindingLevel.low,
    );

    check(
      header: 'x-content-type-options',
      title: 'MIME-sniffing protection not observed',
      detail:
          'The inspected response did not include X-Content-Type-Options.',
      level: FindingLevel.low,
    );

    if (!headers.containsKey('x-frame-options') &&
        !headers.containsKey('content-security-policy')) {
      report.findings.add(
        const Finding(
          title: 'Clickjacking protection not confirmed',
          detail:
              'Neither X-Frame-Options nor a Content-Security-Policy header was observed. Inspect frame-ancestors policy manually.',
          level: FindingLevel.low,
          category: 'HTTP security headers',
        ),
      );
    }

    if (headers.containsKey('server')) {
      report.findings.add(
        Finding(
          title: 'Server banner disclosed',
          detail: 'Server: ${headers['server']}',
          level: FindingLevel.info,
          category: 'Information disclosure',
        ),
      );
    }

    if (headers.containsKey('x-powered-by')) {
      report.findings.add(
        Finding(
          title: 'Technology banner disclosed',
          detail: 'X-Powered-By: ${headers['x-powered-by']}',
          level: FindingLevel.info,
          category: 'Information disclosure',
        ),
      );
    }
  }

  String? _identifyWaf(Headers headers) {
    final combined = headers.map.entries
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .join('\n')
        .toLowerCase();

    if (combined.contains('cloudflare') ||
        headers.value('cf-ray') != null) {
      return 'Cloudflare indicator observed';
    }
    if (combined.contains('akamai')) return 'Akamai indicator observed';
    if (combined.contains('sucuri')) return 'Sucuri indicator observed';
    if (combined.contains('imperva')) return 'Imperva indicator observed';
    if (combined.contains('awselb') ||
        combined.contains('aws')) {
      return 'AWS infrastructure indicator observed';
    }
    if (combined.contains('fastly')) return 'Fastly indicator observed';

    return 'No recognizable WAF/CDN header signature';
  }

  void _fingerprint(
    ScanReport report,
    String body,
    Headers headers,
  ) {
    final text = body.toLowerCase();
    final server = _header(headers, 'server')?.toLowerCase() ?? '';
    final powered = _header(headers, 'x-powered-by')?.toLowerCase() ?? '';

    void add(String value) => _addUnique(report.technologies, value);

    if (text.contains('wp-content') || text.contains('wp-includes')) {
      add('WordPress indicator');
    }
    if (text.contains('drupal-settings-json') ||
        text.contains('sites/default/files')) {
      add('Drupal indicator');
    }
    if (text.contains('joomla')) add('Joomla indicator');
    if (text.contains('__next')) add('Next.js indicator');
    if (text.contains('__nuxt')) add('Nuxt indicator');
    if (text.contains('react')) add('React indicator');
    if (text.contains('ng-version')) add('Angular indicator');
    if (text.contains('data-v-')) add('Vue.js indicator');
    if (text.contains('laravel_session')) add('Laravel indicator');
    if (text.contains('csrf-token') && text.contains('laravel')) {
      add('Laravel framework indicator');
    }
    if (text.contains('shopify')) add('Shopify indicator');
    if (text.contains('woocommerce')) add('WooCommerce indicator');
    if (text.contains('jquery')) add('jQuery indicator');

    if (server.contains('nginx')) add('Nginx server banner');
    if (server.contains('apache')) add('Apache server banner');
    if (server.contains('microsoft-iis')) add('Microsoft IIS banner');

    if (powered.contains('php')) add('PHP technology banner');
    if (powered.contains('asp.net')) add('ASP.NET technology banner');
    if (powered.contains('express')) add('Express.js technology banner');

    if (report.technologies.isEmpty) {
      add('No recognizable technology signature');
    }
  }

  void _extractEndpoints(ScanReport report, String source) {
    final patterns = [
      RegExp(
        r'''["']((?:https?:)?//[^"' ]+|/(?:api|graphql|rest|v[0-9]+|oauth|auth|wp-json|\\.well-known)/[^"' ]*)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:fetch|axios\\.(?:get|post|put|delete)|XMLHttpRequest)[\\s\\S]{0,120}?["']([^"']+)["']''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final value = match.group(1)?.trim();
        if (value == null || value.isEmpty) continue;
        _extractEndpointFromText(report, value);
      }
    }
  }

  void _extractEndpointFromText(ScanReport report, String value) {
    if (value.length > 500) return;

    final lower = value.toLowerCase();

    if (lower.contains('/api/') ||
        lower.contains('/graphql') ||
        lower.contains('/rest/') ||
        lower.contains('/oauth') ||
        lower.contains('/auth/') ||
        lower.contains('/wp-json') ||
        lower.contains('/v1/') ||
        lower.contains('/v2/') ||
        lower.contains('/v3/')) {
      _addUnique(report.endpoints, value);
    }
  }

  Uri? _safeSameOriginUri(Uri base, String reference) {
    try {
      final resolved = base.resolve(reference).replace(fragment: '');

      if (!['http', 'https'].contains(resolved.scheme)) return null;
      if (resolved.host.toLowerCase() != base.host.toLowerCase()) {
        return null;
      }
      if (resolved.port != base.port || resolved.userInfo.isNotEmpty) {
        return null;
      }

      return resolved;
    } catch (_) {
      return null;
    }
  }

  bool _isLikelyBinary(String path) {
    final lower = path.toLowerCase();

    const extensions = [
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg',
      '.ico', '.pdf', '.zip', '.gz', '.rar', '.7z',
      '.mp3', '.mp4', '.mov', '.avi', '.woff', '.woff2',
      '.ttf', '.eot', '.otf', '.exe', '.apk', '.dmg',
      '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    ];

    return extensions.any(lower.endsWith);
  }

  String? _header(Response<dynamic> response, String name) {
    return response.headers.value(name);
  }

  String? _header(Headers headers, String name) {
    return headers.value(name);
  }

  void _addUnique(List<String> list, String value) {
    if (!list.contains(value)) list.add(value);
  }

  void _recordSocketError(
    ScanReport report,
    Uri uri,
    SocketException error,
  ) {
    report.findings.add(
      Finding(
        title: 'Socket connection error',
        detail: '$uri: ${_friendlySocketError(error)}',
        level: FindingLevel.medium,
        category: 'Network',
      ),
    );
  }

  void _recordRequestError(
    ScanReport report,
    Uri uri,
    DioException error,
  ) {
    report.findings.add(
      Finding(
        title: 'HTTP request failed',
        detail: '$uri: ${_friendlyDioError(error)}',
        level: FindingLevel.medium,
        category: 'Network',
      ),
    );
  }

  String _friendlySocketError(SocketException error) {
    final message = error.message.toLowerCase();

    if (message.contains('failed host lookup') ||
        message.contains('no address associated')) {
      return 'DNS lookup failed. The hostname could not be translated into an IP address. Check the spelling, domain registration, DNS records and the device internet connection. This is not evidence of a website vulnerability.';
    }

    if (message.contains('connection refused')) {
      return 'The destination refused the connection. The web service may be stopped or unavailable on that port.';
    }

    if (message.contains('network is unreachable')) {
      return 'The device cannot reach the network destination. Check connectivity and routing.';
    }

    return 'Network socket error: ${error.message}';
  }

  String _friendlyDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out. The host did not establish a connection in time.';
      case DioExceptionType.receiveTimeout:
        return 'The server did not return data before the receive timeout.';
      case DioExceptionType.sendTimeout:
        return 'The request timed out while being sent.';
      case DioExceptionType.connectionError:
        return 'A network connection error occurred: ${error.message}';
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        return error.message ?? error.toString();
    }
  }
}
