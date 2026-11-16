
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

const Color skavenOrange = Color(0xFFFF5722);
const Color skavenRed = Color(0xFFE51C23);
const Color skavenBlack = Color(0xFF090909);
const Color skavenPanel = Color(0xFF151515);
const Color skavenSteel = Color(0xFFD6D6D6);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkavenApp());
}

class SkavenApp extends StatelessWidget {
  const SkavenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SKAVEN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: skavenBlack,
        colorScheme: const ColorScheme.dark(
          primary: skavenOrange,
          secondary: skavenRed,
          surface: skavenPanel,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: skavenBlack,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: skavenPanel,
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: skavenOrange),
          ),
        ),
      ),
      home: const SkavenHome(),
    );
  }
}

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
}

class ScanReport {
  final String target;
  final DateTime started;
  DateTime completed = DateTime.now();

  String? resolvedIp;
  String? server;
  String? contentType;
  String? redirect;
  String? waf;
  String? tlsSummary;
  int? statusCode;

  final List<String> pages = [];
  final List<String> scripts = [];
  final List<String> stylesheets = [];
  final List<String> endpoints = [];
  final List<String> technologies = [];
  final Map<String, String> headers = {};
  final List<Finding> findings = [];

  bool cancelled = false;
  String? error;

  ScanReport(this.target) : started = DateTime.now();

  int get highCount =>
      findings.where((f) => f.level == FindingLevel.high).length;

  int get mediumCount =>
      findings.where((f) => f.level == FindingLevel.medium).length;

  int get lowCount =>
      findings.where((f) => f.level == FindingLevel.low).length;

  Map<String, dynamic> toJson() => {
        'target': target,
        'started': started.toIso8601String(),
        'completed': completed.toIso8601String(),
        'statusCode': statusCode,
        'resolvedIp': resolvedIp,
        'server': server,
        'contentType': contentType,
        'redirect': redirect,
        'waf': waf,
        'tlsSummary': tlsSummary,
        'pages': pages,
        'scripts': scripts,
        'stylesheets': stylesheets,
        'endpoints': endpoints,
        'technologies': technologies,
        'headers': headers,
        'findings': findings.map((f) => f.toJson()).toList(),
        'cancelled': cancelled,
        'error': error,
      };

  String toReportText() {
    final buffer = StringBuffer();

    buffer.writeln('SKAVEN WEB INTELLIGENCE REPORT');
    buffer.writeln('=' * 42);
    buffer.writeln('Target: $target');
    buffer.writeln('Started: ${started.toIso8601String()}');
    buffer.writeln('Completed: ${completed.toIso8601String()}');
    buffer.writeln('HTTP status: ${statusCode ?? "Unknown"}');
    buffer.writeln('Resolved IP: ${resolvedIp ?? "Unavailable"}');
    buffer.writeln('Server: ${server ?? "Not disclosed"}');
    buffer.writeln('Content type: ${contentType ?? "Unknown"}');
    buffer.writeln('WAF indication: ${waf ?? "Not identified"}');
    buffer.writeln('TLS: ${tlsSummary ?? "Not inspected"}');

    buffer.writeln('\nTECHNOLOGIES');
    for (final item in technologies) {
      buffer.writeln('- $item');
    }

    buffer.writeln('\nPAGES');
    for (final item in pages) {
      buffer.writeln('- $item');
    }

    buffer.writeln('\nSCRIPTS');
    for (final item in scripts) {
      buffer.writeln('- $item');
    }

    buffer.writeln('\nSTYLESHEETS');
    for (final item in stylesheets) {
      buffer.writeln('- $item');
    }

    buffer.writeln('\nOBSERVED ENDPOINTS');
    for (final item in endpoints) {
      buffer.writeln('- $item');
    }

    buffer.writeln('\nRESPONSE HEADERS');
    headers.forEach((key, value) {
      buffer.writeln('$key: $value');
    });

    buffer.writeln('\nFINDINGS');
    for (final finding in findings) {
      buffer.writeln(
        '[${finding.level.name.toUpperCase()}] '
        '${finding.category}: ${finding.title}',
      );
      buffer.writeln('  ${finding.detail}');
    }

    buffer.writeln('\nGenerated by SKAVEN.');
    buffer.writeln('Creator: Anonymous-beta (Chinedu)');
    buffer.writeln('Authorized reconnaissance only.');

    return buffer.toString();
  }
}

class ReconService {
  static const int maxPages = 30;
  static const int maxAssets = 35;
  static const int maxResponseBytes = 2 * 1024 * 1024;
  static const int maxAssetBytes = 1024 * 1024;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      maxRedirects: 0,
      responseType: ResponseType.plain,
      validateStatus: (status) => status != null,
      headers: const {
        'User-Agent': 'SKAVEN-Recon/1.0',
        'Accept': 'text/html,application/xhtml+xml,application/json,*/*',
      },
    ),
  );

  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
  }

  Future<ScanReport> scan(String input) async {
    _cancelRequested = false;

    final target = _normalizeTarget(input);
    final report = ScanReport(target);

    try {
      final root = Uri.parse(target);

      await _validatePublicHost(root);
      report.resolvedIp = await _resolvePublicIp(root.host);

      if (root.scheme == 'https') {
        report.tlsSummary = await _inspectTls(root.host);
      }

      final queue = <Uri>[root];
      final visited = <String>{};
      final assetQueue = <Uri>{};

      while (queue.isNotEmpty &&
          visited.length < maxPages &&
          !_cancelRequested) {
        final current = queue.removeAt(0);
        final key = current.toString();

        if (!visited.add(key)) continue;

        try {
          await _validatePublicHost(current);

          final response = await _request(current, maxResponseBytes);
          final status = response.statusCode ?? 0;

          if (current == root) {
            report.statusCode = status;
            report.server = _header(response, 'server');
            report.contentType = _header(response, 'content-type');
            _copyHeaders(response, report);
            _identifyWaf(response, report);
            _analyzeHeaders(report);
          }

          if (status >= 300 && status < 400) {
            final location = _header(response, 'location');

            if (location != null) {
              report.redirect = location;
              report.findings.add(
                Finding(
                  title: 'HTTP redirect observed',
                  detail: 'The server returned a redirect to $location. '
                      'SKAVEN does not automatically follow redirects.',
                  level: FindingLevel.info,
                  category: 'HTTP',
                ),
              );
            }
            continue;
          }

          if (status < 200 || status >= 300) {
            report.findings.add(
              Finding(
                title: 'Non-success HTTP response',
                detail: '$current returned HTTP $status.',
                level: FindingLevel.low,
                category: 'HTTP',
              ),
            );
            continue;
          }

          final body = response.data?.toString() ?? '';
          report.pages.add(current.toString());

          _fingerprint(body, report);
          _extractEndpoints(body, current, report);

          final document = html_parser.parse(body);

          for (final element in document.querySelectorAll('script[src]')) {
            final src = element.attributes['src'];
            final uri = _safeSameOriginUri(src, current);

            if (uri != null) {
              _addUnique(report.scripts, uri.toString());
              assetQueue.add(uri);
            }
          }

          for (final element in document.querySelectorAll(
            'link[rel~="stylesheet"][href]',
          )) {
            final href = element.attributes['href'];
            final uri = _safeSameOriginUri(href, current);

            if (uri != null) {
              _addUnique(report.stylesheets, uri.toString());
              assetQueue.add(uri);
            }
          }

          for (final element in document.querySelectorAll('a[href]')) {
            if (visited.length + queue.length >= maxPages) break;

            final href = element.attributes['href'];
            final uri = _safeSameOriginUri(href, current);

            if (uri != null && !_isLikelyBinary(uri)) {
              if (!visited.contains(uri.toString()) &&
                  !queue.any((item) => item.toString() == uri.toString())) {
                queue.add(uri);
              }
            }
          }

          for (final element in document.querySelectorAll(
            'iframe[src], img[src], source[src]',
          )) {
            final src = element.attributes['src'];
            final uri = _safeSameOriginUri(src, current);

            if (uri != null) {
              _extractPathEndpoint(uri, report);
            }
          }
        } on DioException catch (e) {
          report.findings.add(
            Finding(
              title: 'Request failed',
              detail: '$current: ${e.message ?? "Network error"}',
              level: FindingLevel.low,
              category: 'Network',
            ),
          );
        } catch (e) {
          report.findings.add(
            Finding(
              title: 'Page inspection error',
              detail: '$current: $e',
              level: FindingLevel.low,
              category: 'Network',
            ),
          );
        }
      }

      if (_cancelRequested) {
        report.cancelled = true;
      }

      var inspectedAssets = 0;

      for (final asset in assetQueue) {
        if (_cancelRequested || inspectedAssets >= maxAssets) break;
        inspectedAssets++;

        try {
          await _validatePublicHost(asset);

          final response = await _request(asset, maxAssetBytes);
          final status = response.statusCode ?? 0;

          if (status < 200 || status >= 300) continue;

          final source = response.data?.toString() ?? '';

          _extractEndpoints(source, asset, report);
          _fingerprint(source, report);

          report.findings.add(
            Finding(
              title: 'Public asset inspected',
              detail: 'Inspected ${asset.path} '
                  '(${source.length} characters).',
              level: FindingLevel.info,
              category: 'Source',
            ),
          );
        } catch (_) {
          // An unavailable asset does not abort the entire scan.
        }
      }

      report.completed = DateTime.now();

      if (report.pages.isEmpty && report.error == null) {
        report.error = 'No readable pages were discovered.';
      }

      return report;
    } catch (e) {
      report.error = e.toString();
      report.completed = DateTime.now();

      report.findings.add(
        Finding(
          title: 'Scan could not complete',
          detail: e.toString(),
          level: FindingLevel.high,
          category: 'Scanner',
        ),
      );

      return report;
    }
  }

  String _normalizeTarget(String input) {
    var value = input.trim();

    if (value.isEmpty) {
      throw const FormatException('Enter a website address.');
    }

    if (!value.contains('://')) {
      value = 'https://$value';
    }

    final uri = Uri.parse(value);

    if (!uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException('Invalid website address.');
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('Only HTTP and HTTPS are supported.');
    }

    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Addresses containing usernames or passwords are not allowed.',
      );
    }

    if (uri.hasPort &&
        !((uri.scheme == 'http' && uri.port == 80) ||
            (uri.scheme == 'https' && uri.port == 443))) {
      throw const FormatException(
        'Only standard HTTP and HTTPS ports are supported.',
      );
    }

    return uri.replace(fragment: '').toString();
  }

  Future<void> _validatePublicHost(Uri uri) async {
    if (uri.host.toLowerCase() == 'localhost') {
      throw const FormatException('Localhost targets are not allowed.');
    }

    final addresses = await InternetAddress.lookup(
      uri.host,
      type: InternetAddressType.any,
    ).timeout(const Duration(seconds: 8));

    if (addresses.isEmpty) {
      throw const SocketException('The hostname did not resolve.');
    }

    for (final address in addresses) {
      if (!_isPublicAddress(address)) {
        throw const FormatException(
          'The hostname resolves to a private or reserved IP address.',
        );
      }
    }
  }

  bool _isPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;

    if (address.type == InternetAddressType.IPv4) {
      final a = bytes[0];
      final b = bytes[1];

      if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
      if (a == 100 && b >= 64 && b <= 127) return false;
      if (a == 169 && b == 254) return false;
      if (a == 172 && b >= 16 && b <= 31) return false;
      if (a == 192 && b == 168) return false;
      if (a == 192 && b == 0) return false;
      if (a == 198 && (b == 18 || b == 19)) return false;
      if (a == 198 && b == 51) return false;
      if (a == 203 && b == 0) return false;

      return true;
    }

    if (address.type == InternetAddressType.IPv6) {
      final allZero = bytes.every((b) => b == 0);
      if (allZero) return false;

      final loopback =
          bytes.take(15).every((b) => b == 0) && bytes[15] == 1;

      if (loopback) return false;
      if ((bytes[0] & 0xFE) == 0xFC) return false;

      if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) {
        return false;
      }

      if (bytes[0] == 0xFF) return false;

      final mapped = bytes.take(10).every((b) => b == 0) &&
          bytes[10] == 0xFF &&
          bytes[11] == 0xFF;

      if (mapped) {
        final v4 = InternetAddress.fromRawAddress(
          bytes.sublist(12),
          type: InternetAddressType.IPv4,
        );
        return _isPublicAddress(v4);
      }

      return true;
    }

    return false;
  }

  Future<String> _resolvePublicIp(String host) async {
    final addresses = await InternetAddress.lookup(host);

    if (addresses.isEmpty) return 'Unavailable';

    return addresses.first.address;
  }

  Future<String?> _inspectTls(String host) async {
    try {
      final socket = await SecureSocket.connect(
        host,
        443,
        timeout: const Duration(seconds: 8),
      );

      final certificate = socket.peerCertificate;
      socket.destroy();

      if (certificate == null) {
        return 'Certificate information unavailable';
      }

      return 'Issuer: ${certificate.issuer}; '
          'Expires: ${certificate.endValidity.toIso8601String()}';
    } catch (e) {
      return 'TLS inspection unavailable: $e';
    }
  }

  Future<Response<dynamic>> _request(Uri uri, int maxBytes) {
    return _dio
        .getUri<dynamic>(
          uri,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            maxRedirects: 0,
            headers: const {'Accept-Encoding': 'identity'},
            receiveDataWhenStatusError: true,
          ),
        )
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException('Request timed out.'),
        )
        .then((response) {
          final body = response.data?.toString() ?? '';

          if (body.length > maxBytes) {
            throw const FormatException(
              'Response exceeded the inspection limit.',
            );
          }

          return response;
        });
  }

  String? _header(Response<dynamic> response, String name) {
    final values = response.headers.map.entries
        .where((entry) => entry.key.toLowerCase() == name.toLowerCase())
        .expand((entry) => entry.value);

    if (values.isEmpty) return null;

    return values.join(', ');
  }

  void _copyHeaders(Response<dynamic> response, ScanReport report) {
    response.headers.map.forEach((key, values) {
      report.headers[key.toLowerCase()] = values.join(', ');
    });
  }

  void _analyzeHeaders(ScanReport report) {
    const expected = [
      'strict-transport-security',
      'content-security-policy',
      'x-content-type-options',
      'x-frame-options',
      'referrer-policy',
      'permissions-policy',
    ];

    for (final header in expected) {
      if (!report.headers.containsKey(header)) {
        report.findings.add(
          Finding(
            title: 'Security header not observed',
            detail: '$header was not present in the initial HTTP response.',
            level: header == 'strict-transport-security' ||
                    header == 'content-security-policy'
                ? FindingLevel.medium
                : FindingLevel.low,
            category: 'HTTP Security',
          ),
        );
      }
    }

    final server = report.server;

    if (server != null && server.isNotEmpty) {
      report.findings.add(
        Finding(
          title: 'Server banner disclosed',
          detail: 'The server disclosed: $server',
          level: FindingLevel.info,
          category: 'Information Disclosure',
        ),
      );
    }

    final poweredBy = report.headers['x-powered-by'];

    if (poweredBy != null) {
      report.findings.add(
        Finding(
          title: 'Technology banner disclosed',
          detail: 'X-Powered-By: $poweredBy',
          level: FindingLevel.low,
          category: 'Information Disclosure',
        ),
      );
    }
  }

  void _identifyWaf(Response<dynamic> response, ScanReport report) {
    final combined = [
      response.headers.map.toString(),
      response.data?.toString() ?? '',
    ].join(' ').toLowerCase();

    final signatures = <String, List<String>>{
      'Cloudflare': ['cf-ray', 'cloudflare'],
      'Akamai': ['akamai', 'akamai-ghost'],
      'AWS WAF': ['awselb', 'aws waf'],
      'Sucuri': ['sucuri', 'x-sucuri'],
      'Imperva': ['incap_ses', 'imperva', 'visid_incap'],
      'Fastly': ['fastly', 'x-served-by'],
    };

    for (final entry in signatures.entries) {
      if (entry.value.any(combined.contains)) {
        report.waf = entry.key;

        report.findings.add(
          Finding(
            title: 'Possible WAF or edge service identified',
            detail: 'Observed indicators consistent with ${entry.key}. '
                'This is passive fingerprinting, not definitive proof.',
            level: FindingLevel.info,
            category: 'Infrastructure',
          ),
        );

        return;
      }
    }

    report.waf = 'No recognizable signature';
  }

  void _fingerprint(String body, ScanReport report) {
    final source = body.toLowerCase();

    const signatures = <String, List<String>>{
      'WordPress': ['wp-content', 'wp-includes', 'wordpress'],
      'Drupal': ['drupal.settings', 'sites/default/files'],
      'Joomla': ['com_content', 'joomla'],
      'React': ['react-dom', 'data-reactroot'],
      'Next.js': ['__next_data__', '/_next/static/'],
      'Vue.js': ['vue.js', 'data-v-'],
      'Angular': ['ng-version', 'ng-app'],
      'jQuery': ['jquery.min.js', 'jquery.js'],
      'Bootstrap': ['bootstrap.min.css', 'bootstrap.min.js'],
      'Laravel': ['laravel_session'],
      'Django': ['csrfmiddlewaretoken'],
      'PHP': ['phpsessid'],
    };

    for (final entry in signatures.entries) {
      if (entry.value.any(source.contains)) {
        _addUnique(report.technologies, entry.key);
      }
    }
  }

  void _extractEndpoints(String source, Uri base, ScanReport report) {
    final patterns = <RegExp>[
      RegExp(
        r'''["']((?:https?:)?//[^"' ]+|/[^"' ]*(?:api|graphql|rest|v[0-9]+)[^"' ]*)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''(?:fetch|axios\.(?:get|post|put|delete)|XMLHttpRequest)[\s\S]{0,100}?["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''["'](/(?:api|graphql|rest|v[0-9]+)(?:/[^"']*)?)["']''',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final value = match.group(1);

        if (value == null || value.isEmpty) continue;

        final uri = _safeSameOriginUri(value, base);

        if (uri != null) {
          _addUnique(report.endpoints, uri.toString());
        }
      }
    }
  }

  void _extractPathEndpoint(Uri uri, ScanReport report) {
    final path = uri.path.toLowerCase();

    if (path.contains('/api') ||
        path.contains('/graphql') ||
        path.contains('/rest/') ||
        RegExp(r'/v[0-9]+/').hasMatch(path)) {
      _addUnique(report.endpoints, uri.toString());
    }
  }

  Uri? _safeSameOriginUri(String? value, Uri base) {
    if (value == null || value.trim().isEmpty) return null;

    try {
      final uri = base.resolve(value.trim());

      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      if (uri.host.toLowerCase() != base.host.toLowerCase()) return null;
      if (uri.port != base.port) return null;
      if (uri.userInfo.isNotEmpty) return null;

      return uri.replace(fragment: '');
    } catch (_) {
      return null;
    }
  }

  bool _isLikelyBinary(Uri uri) {
    final path = uri.path.toLowerCase();

    const extensions = [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.svg',
      '.pdf',
      '.zip',
      '.mp4',
      '.mp3',
      '.woff',
      '.woff2',
      '.ttf',
      '.ico',
      '.exe',
      '.apk',
    ];

    return extensions.any(path.endsWith);
  }

  void _addUnique(List<String> list, String value) {
    if (!list.contains(value)) {
      list.add(value);
    }
  }

  void dispose() {
    _dio.close(force: true);
  }
}

class SkavenHome extends StatefulWidget {
  const SkavenHome({super.key});

  @override
  State<SkavenHome> createState() => _SkavenHomeState();
}

class _SkavenHomeState extends State<SkavenHome> {
  final TextEditingController _targetController = TextEditingController();
  final ReconService _scanner = ReconService();

  ScanReport? _report;
  bool _scanning = false;
  String _status = 'SYSTEM READY';
  int _selectedTab = 0;
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _history = prefs.getStringList('skaven_history') ?? [];
    });
  }

  Future<void> _saveHistory(String target) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList('skaven_history') ?? [];

    items.remove(target);
    items.insert(0, target);

    await prefs.setStringList(
      'skaven_history',
      items.take(20).toList(),
    );

    if (!mounted) return;

    setState(() {
      _history = items.take(20).toList();
    });
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    if (_targetController.text.trim().isEmpty) {
      _message('Enter a target first.');
      return;
    }

    setState(() {
      _scanning = true;
      _report = null;
      _status = 'INITIALIZING RECONNAISSANCE';
    });

    try {
      final report = await _scanner.scan(_targetController.text);

      if (!mounted) return;

      setState(() {
        _report = report;
        _scanning = false;
        _status = report.error == null
            ? 'RECONNAISSANCE COMPLETE'
            : 'SCAN COMPLETED WITH ERRORS';
      });

      await _saveHistory(report.target);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _scanning = false;
        _status = 'SCAN FAILED';
      });

      _message(e.toString());
    }
  }

  void _cancelScan() {
    _scanner.cancel();

    setState(() {
      _status = 'CANCELLATION REQUESTED';
    });
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> _exportReport() async {
    final report = _report;

    if (report == null) return;

    await Clipboard.setData(
      ClipboardData(text: report.toReportText()),
    );

    if (!mounted) return;

    _message('Report copied to clipboard.');
  }

  void _openHistoryTarget(String target) {
    _targetController.text = target;

    setState(() {
      _selectedTab = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              width: 34,
              height: 34,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.pets,
                color: skavenOrange,
                size: 30,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'SKAVEN',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'About SKAVEN',
            onPressed: _about,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _dashboard(),
          _findingsPage(),
          _intelligencePage(),
          _historyPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: skavenPanel,
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber),
            label: 'Findings',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree),
            label: 'Intel',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    final report = _report;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _hero(),
        const SizedBox(height: 20),
        _sectionTitle('TARGET RECONNAISSANCE'),
        const SizedBox(height: 10),
        TextField(
          controller: _targetController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.language),
            hintText: 'https://example.com',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: const Icon(Icons.radar),
                label: Text(_scanning ? 'SCANNING...' : 'START SCAN'),
                style: FilledButton.styleFrom(
                  backgroundColor: skavenOrange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            if (_scanning) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _cancelScan,
                icon: const Icon(Icons.stop),
                style: IconButton.styleFrom(
                  backgroundColor: skavenRed,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _statusPanel(),
        if (report != null) ...[
          const SizedBox(height: 20),
          _summaryCards(report),
          const SizedBox(height: 20),
          _sectionTitle('TARGET OVERVIEW'),
          _dataTile('Target', report.target),
          _dataTile('HTTP status', '${report.statusCode ?? "Unknown"}'),
          _dataTile('Resolved IP', report.resolvedIp ?? 'Unknown'),
          _dataTile('Server', report.server ?? 'Not disclosed'),
          _dataTile('Content type', report.contentType ?? 'Unknown'),
          _dataTile('WAF indication', report.waf ?? 'Not identified'),
          _dataTile('TLS', report.tlsSummary ?? 'Not inspected'),
          if (report.error != null)
            _dataTile('Scan note', report.error!),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _exportReport,
            icon: const Icon(Icons.copy),
            label: const Text('COPY FULL REPORT'),
          ),
        ],
        const SizedBox(height: 24),
        _sectionTitle('RECONNAISSANCE MODULES'),
        _moduleTile(
          Icons.travel_explore,
          'Website crawler',
          'Bounded same-origin page discovery',
        ),
        _moduleTile(
          Icons.code,
          'Source intelligence',
          'Public HTML, JavaScript and CSS inspection',
        ),
        _moduleTile(
          Icons.api,
          'API discovery',
          'Observable REST and GraphQL route extraction',
        ),
        _moduleTile(
          Icons.dns,
          'Network intelligence',
          'DNS resolution and TLS certificate details',
        ),
        _moduleTile(
          Icons.security,
          'Security analysis',
          'Response headers and passive WAF indicators',
        ),
        const SizedBox(height: 25),
        _creatorFooter(),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF30140D), Color(0xFF151515)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: skavenOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE HUNT BEGINS.',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: skavenOrange,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Web intelligence. Asset discovery. '
            'Infrastructure fingerprinting.',
            style: TextStyle(color: skavenSteel),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(
                Icons.circle,
                color: Colors.greenAccent,
                size: 9,
              ),
              SizedBox(width: 7),
              Text(
                'RECON ENGINE ONLINE',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          if (_scanning)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: skavenOrange,
              ),
            )
          else
            const Icon(Icons.terminal, color: skavenOrange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCards(ScanReport report) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.8,
      children: [
        _statCard('PAGES', '${report.pages.length}', Icons.web),
        _statCard(
          'ASSETS',
          '${report.scripts.length + report.stylesheets.length}',
          Icons.insert_drive_file,
        ),
        _statCard('ENDPOINTS', '${report.endpoints.length}', Icons.api),
        _statCard('FINDINGS', '${report.findings.length}', Icons.bug_report),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: skavenOrange),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _findingsPage() {
    final report = _report;

    if (report == null) {
      return _emptyState(
        Icons.warning_amber,
        'NO FINDINGS YET',
        'Run a reconnaissance scan to populate this page.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('SECURITY & INFORMATION FINDINGS'),
        _summaryCards(report),
        const SizedBox(height: 16),
        if (report.findings.isEmpty)
          const Text('No findings were recorded.')
        else
          ...report.findings.map(_findingTile),
      ],
    );
  }

  Widget _findingTile(Finding finding) {
    final color = switch (finding.level) {
      FindingLevel.info => Colors.blueAccent,
      FindingLevel.low => Colors.greenAccent,
      FindingLevel.medium => Colors.orangeAccent,
      FindingLevel.high => skavenRed,
    };

    return Card(
      color: skavenPanel,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.shield_outlined, color: color),
        title: Text(finding.title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${finding.category}\n${finding.detail}',
            style: const TextStyle(height: 1.4),
          ),
        ),
        trailing: Text(
          finding.level.name.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _intelligencePage() {
    final report = _report;

    if (report == null) {
      return _emptyState(
        Icons.account_tree,
        'NO INTELLIGENCE',
        'Scan a target to inspect its discovered resources.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('DISCOVERED TECHNOLOGIES'),
        ..._stringList(
          report.technologies,
          'No technologies fingerprinted.',
        ),
        const SizedBox(height: 18),
        _sectionTitle('OBSERVED API ENDPOINTS'),
        ..._stringList(
          report.endpoints,
          'No recognizable endpoints found.',
        ),
        const SizedBox(height: 18),
        _sectionTitle('PUBLIC JAVASCRIPT'),
        ..._stringList(
          report.scripts,
          'No scripts discovered.',
        ),
        const SizedBox(height: 18),
        _sectionTitle('PUBLIC STYLESHEETS'),
        ..._stringList(
          report.stylesheets,
          'No stylesheets discovered.',
        ),
        const SizedBox(height: 18),
        _sectionTitle('CRAWLED PAGES'),
        ..._stringList(
          report.pages,
          'No pages crawled.',
        ),
        const SizedBox(height: 18),
        _sectionTitle('HTTP RESPONSE HEADERS'),
        ...report.headers.entries.map(
          (entry) => _dataTile(entry.key, entry.value),
        ),
      ],
    );
  }

  List<Widget> _stringList(List<String> values, String emptyText) {
    if (values.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            emptyText,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      ];
    }

    return values
        .map(
          (value) => Card(
            color: skavenPanel,
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.chevron_right,
                color: skavenOrange,
              ),
              title: SelectableText(
                value,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                _message('Copied.');
              },
            ),
          ),
        )
        .toList();
  }

  Widget _historyPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('RECENT TARGETS'),
        if (_history.isEmpty)
          const Text(
            'No saved targets yet.',
            style: TextStyle(color: Colors.white54),
          ),
        ..._history.map(
          (target) => Card(
            color: skavenPanel,
            child: ListTile(
              leading: const Icon(
                Icons.language,
                color: skavenOrange,
              ),
              title: Text(target),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 14,
              ),
              onTap: () => _openHistoryTarget(target),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'History stores target addresses on this device. '
          'It does not store authentication tokens or website credentials.',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String detail,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: skavenOrange, size: 55),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataTile(String title, String value) {
    return Card(
      color: skavenPanel,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: skavenOrange,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 5),
            SelectableText(value),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: skavenOrange,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _moduleTile(
    IconData icon,
    String title,
    String detail,
  ) {
    return Card(
      color: skavenPanel,
      child: ListTile(
        leading: Icon(icon, color: skavenOrange),
        title: Text(title),
        subtitle: Text(detail),
      ),
    );
  }

  Widget _creatorFooter() {
    return const Center(
      child: Text(
        'SKAVEN  •  BUILT BY ANONYMOUS-BETA (CHINEDU)',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white30,
          fontSize: 10,
          letterSpacing: 1,
        ),
      ),
    );
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: 'SKAVEN',
      applicationVersion: '1.0.0',
      applicationLegalese:
          'Created by Anonymous-beta (Chinedu).\n'
          'Authorized web reconnaissance and intelligence.',
      children: const [
        Text(
          'SKAVEN inspects publicly accessible website resources. '
          'Only scan systems you own or have permission to assess.',
        ),
      ],
    );
  }
}
