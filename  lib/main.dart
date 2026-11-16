
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/recon_service.dart';

const Color skavenOrange = Color(0xFFFF5722);
const Color skavenRed = Color(0xFFE51C23);
const Color skavenBlack = Color(0xFF090909);
const Color skavenPanel = Color(0xFF151515);
const Color skavenSteel = Color(0xFFD6D6D6);
const Color skavenMuted = Color(0xFF858585);

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
        appBarTheme: const AppBarTheme(
          backgroundColor: skavenBlack,
          foregroundColor: skavenSteel,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: skavenPanel,
          hintStyle: const TextStyle(color: skavenMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(.07)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: skavenOrange),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: skavenPanel,
          indicatorColor: Color(0x33FF5722),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const SkavenHome(),
    );
  }
}

class SkavenHome extends StatefulWidget {
  const SkavenHome({super.key});

  @override
  State<SkavenHome> createState() => _SkavenHomeState();
}

class _SkavenHomeState extends State<SkavenHome> {
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  final ReconService _scanner = ReconService();

  ScanReport? _report;
  bool _scanning = false;
  String _status = 'RECON ENGINE ONLINE';
  int _selectedTab = 0;

  List<ScanReport> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _searchController.dispose();
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('skaven_history') ?? [];

    final loaded = <ScanReport>[];

    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          loaded.add(
            ScanReport.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore damaged history entries.
      }
    }

    if (!mounted) return;

    setState(() {
      _history = loaded;
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final entries = _history
        .take(20)
        .map((report) => jsonEncode(report.toJson()))
        .toList();

    await prefs.setStringList('skaven_history', entries);
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final target = _targetController.text.trim();

    if (target.isEmpty) {
      _message('Enter a target website first.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _scanning = true;
      _status = 'INITIALIZING RECONNAISSANCE...';
      _report = null;
    });

    final report = await _scanner.scan(target);

    if (!mounted) return;

    setState(() {
      _report = report;
      _scanning = false;
      _status = report.error != null
          ? 'SCAN FAILED'
          : report.cancelled
              ? 'SCAN CANCELLED'
              : 'RECONNAISSANCE COMPLETE';
    });

    _history.removeWhere((item) => item.target == report.target);
    _history.insert(0, report);
    await _saveHistory();

    if (!mounted) return;

    if (report.error != null) {
      _message('Scan failed: ${report.error}');
    } else if (report.cancelled) {
      _message('Scan cancelled.');
    } else {
      _message('Reconnaissance completed.');
    }
  }

  void _cancelScan() {
    if (!_scanning) return;

    _scanner.cancel();

    setState(() {
      _status = 'CANCELLING REQUESTS...';
    });
  }

  void _loadReport(ScanReport report) {
    setState(() {
      _report = report;
      _targetController.text = report.target;
      _selectedTab = 0;
    });
  }

  Future<void> _exportReport() async {
    final report = _report;

    if (report == null) {
      _message('There is no report to export.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: report.toReportText()),
    );

    _message('Full report copied to clipboard.');
  }

  Future<void> _copyText(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _message('Copied to clipboard.');
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: skavenPanel,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openModule(String module) {
    final report = _report;

    if (report == null) {
      _message('Run a scan to populate this module.');
      return;
    }

    final Widget page;

    switch (module) {
      case 'Website crawler':
        page = _dataPage(
          'WEBSITE CRAWLER',
          'Pages discovered during the bounded same-origin crawl.',
          report.pages,
          Icons.account_tree_outlined,
        );
        break;
      case 'Source intelligence':
        page = _sourcePage(report);
        break;
      case 'API discovery':
        page = _dataPage(
          'API DISCOVERY',
          'Endpoint references observed in publicly served resources. These are references, not proof that an endpoint is active.',
          report.endpoints,
          Icons.api,
        );
        break;
      case 'Network intelligence':
        page = _networkPage(report);
        break;
      case 'Security analysis':
        page = _findingsPage(report);
        break;
      case 'Robots and sitemap':
        page = _robotsPage(report);
        break;
      default:
        page = _dataPage(
          module.toUpperCase(),
          'Collected reconnaissance data.',
          report.technologies,
          Icons.info_outline,
        );
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => page,
      ),
    );
  }

  Widget _dataPage(
    String title,
    String description,
    List<String> items,
    IconData icon,
  ) {
    return _DetailPage(
      title: title,
      description: description,
      child: items.isEmpty
          ? const _EmptyState(
              title: 'No entries discovered',
              subtitle: 'This module has no collected results yet.',
            )
          : Column(
              children: items
                  .map(
                    (item) => _DataTile(
                      icon: icon,
                      title: item,
                      onTap: () => _copyText(item),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _sourcePage(ScanReport report) {
    return _DetailPage(
      title: 'SOURCE INTELLIGENCE',
      description:
          'Publicly referenced JavaScript and CSS resources. Private server-side source code is not retrieved.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('JAVASCRIPT (${report.scripts.length})'),
          if (report.scripts.isEmpty)
            const _EmptyState(
              title: 'No scripts discovered',
              subtitle: 'No script references were collected.',
            ),
          ...report.scripts.map(
            (item) => _DataTile(
              icon: Icons.javascript,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('STYLESHEETS (${report.stylesheets.length})'),
          if (report.stylesheets.isEmpty)
            const _EmptyState(
              title: 'No stylesheets discovered',
              subtitle: 'No stylesheet references were collected.',
            ),
          ...report.stylesheets.map(
            (item) => _DataTile(
              icon: Icons.style_outlined,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkPage(ScanReport report) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Target', report.target),
      MapEntry('Resolved IP', report.resolvedIp ?? 'Not resolved'),
      MapEntry('DNS status', report.dnsResolved ? 'Resolved' : 'Not resolved'),
      MapEntry('HTTP status', report.statusCode?.toString() ?? 'Not inspected'),
      MapEntry('Server', report.server ?? 'Not disclosed'),
      MapEntry('Content type', report.contentType ?? 'Unknown'),
      MapEntry('Redirect', report.redirect ?? 'No redirect recorded'),
      MapEntry('TLS', report.tlsSummary ?? 'Not inspected'),
      MapEntry('WAF/CDN', report.waf ?? 'Not identified'),
    ];

    return _DetailPage(
      title: 'NETWORK INTELLIGENCE',
      description: 'Connection metadata collected during the scan.',
      child: Column(
        children: rows
            .map(
              (row) => _InfoRow(
                label: row.key,
                value: row.value,
                onTap: () => _copyText(row.value),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _robotsPage(ScanReport report) {
    return _DetailPage(
      title: 'ROBOTS & SITEMAP',
      description:
          'Publicly accessible discovery files. Entries do not grant permission to access restricted resources.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ROBOTS.TXT'),
          if (report.robotsEntries.isEmpty)
            const _EmptyState(
              title: 'No robots entries',
              subtitle: 'robots.txt was not available or contained no entries.',
            ),
          ...report.robotsEntries.map(
            (item) => _DataTile(
              icon: Icons.description_outlined,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('SITEMAP URLS'),
          if (report.sitemapEntries.isEmpty)
            const _EmptyState(
              title: 'No sitemap entries',
              subtitle: 'No sitemap URLs were collected.',
            ),
          ...report.sitemapEntries.map(
            (item) => _DataTile(
              icon: Icons.map_outlined,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
        ],
      ),
    );
  }

  Widget _findingsPage(ScanReport report) {
    return _DetailPage(
      title: 'SECURITY ANALYSIS',
      description:
          'Passive observations based on the responses and public resources inspected. Findings require manual validation.',
      child: _findingsList(report),
    );
  }

  Widget _findingsList(ScanReport report) {
    if (report.findings.isEmpty) {
      return const _EmptyState(
        title: 'No findings recorded',
        subtitle: 'No observations were recorded during this scan.',
      );
    }

    return Column(
      children: report.findings.map(_findingCard).toList(),
    );
  }

  Widget _findingCard(Finding finding) {
    final Color color;

    switch (finding.level) {
      case FindingLevel.high:
        color = skavenRed;
        break;
      case FindingLevel.medium:
        color = skavenOrange;
        break;
      case FindingLevel.low:
        color = Colors.amber;
        break;
      case FindingLevel.info:
        color = Colors.blueGrey;
        break;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finding.title,
                  style: const TextStyle(
                    color: skavenSteel,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                finding.level.name.toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            finding.detail,
            style: const TextStyle(
              color: skavenMuted,
              height: 1.4,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            finding.category.toUpperCase(),
            style: const TextStyle(
              color: skavenOrange,
              fontSize: 9,
              letterSpacing: 1.2,
            ),
          ),
        ],
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
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboard(),
      _findingsTab(),
      _intelTab(),
      _historyTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const Icon(
              Icons.pets,
              color: skavenOrange,
              size: 24,
            ),
            const SizedBox(width: 10),
            const Text(
              'SKAVEN',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: const Color(0x2222CC66),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 7),
                  SizedBox(width: 6),
                  Text(
                    'READY',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.security),
            label: 'Findings',
          ),
          NavigationDestination(
            icon: Icon(Icons.memory),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _heroPanel(),
        const SizedBox(height: 18),
        const Text(
          'TARGET RECONNAISSANCE',
          style: TextStyle(
            color: skavenSteel,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _targetController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.language, color: skavenOrange),
            hintText: 'https://example.com',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: const Icon(Icons.radar),
                  label: const Text(
                    'START SCAN',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: skavenOrange,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: skavenOrange.withOpacity(.3),
                  ),
                ),
              ),
            ),
            if (_scanning) ...[
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _cancelScan,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: skavenRed,
                    side: const BorderSide(color: skavenRed),
                  ),
                  child: const Icon(Icons.stop),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _statusPanel(),
        const SizedBox(height: 20),
        _sectionTitle('RECONNAISSANCE OVERVIEW'),
        _summaryGrid(report),
        const SizedBox(height: 22),
        _sectionTitle('INTELLIGENCE MODULES'),
        _moduleGrid(),
        const SizedBox(height: 22),
        if (report != null) ...[
          _sectionTitle('LATEST TARGET'),
          _targetOverview(report),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _exportReport,
              icon: const Icon(Icons.copy),
              label: const Text('COPY FULL REPORT'),
              style: OutlinedButton.styleFrom(
                foregroundColor: skavenOrange,
                side: const BorderSide(color: skavenOrange),
              ),
            ),
          ),
        ],
        const SizedBox(height: 28),
        const Center(
          child: Text(
            'SKAVEN  •  ANONYMOUS-BETA (CHINEDU)',
            style: TextStyle(
              color: skavenMuted,
              fontSize: 9,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF29130D),
            Color(0xFF111111),
            Color(0xFF171717),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: skavenOrange.withOpacity(.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: skavenOrange.withOpacity(.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.pets,
              color: skavenOrange,
              size: 38,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'THE HUNT BEGINS',
                  style: TextStyle(
                    color: skavenOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'WEB INTELLIGENCE',
                  style: TextStyle(
                    color: skavenSteel,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Public-surface reconnaissance platform',
                  style: TextStyle(
                    color: skavenMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _scanning
              ? skavenOrange.withOpacity(.6)
              : Colors.white.withOpacity(.07),
        ),
      ),
      child: Row(
        children: [
          if (_scanning)
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: skavenOrange,
              ),
            )
          else
            const Icon(
              Icons.circle,
              color: Colors.green,
              size: 9,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              style: const TextStyle(
                color: skavenSteel,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(ScanReport? report) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: [
        _statCard(
          'PAGES',
          '${report?.pages.length ?? 0}',
          Icons.web,
        ),
        _statCard(
          'ENDPOINTS',
          '${report?.endpoints.length ?? 0}',
          Icons.api,
        ),
        _statCard(
          'TECHNOLOGIES',
          '${report?.technologies.length ?? 0}',
          Icons.memory,
        ),
        _statCard(
          'FINDINGS',
          '${report?.findings.length ?? 0}',
          Icons.security,
        ),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: skavenOrange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: skavenSteel,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: skavenMuted,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleGrid() {
    final modules = [
      _Module('Website crawler', Icons.account_tree_outlined),
      _Module('Source intelligence', Icons.code),
      _Module('API discovery', Icons.api),
      _Module('Network intelligence', Icons.hub_outlined),
      _Module('Security analysis', Icons.security),
      _Module('Robots and sitemap', Icons.map_outlined),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (context, index) {
        final module = modules[index];

        return Material(
          color: skavenPanel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openModule(module.title),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(module.icon, color: skavenOrange, size: 23),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          module.title.toUpperCase(),
                          style: const TextStyle(
                            color: skavenSteel,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: .6,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: skavenMuted,
                        size: 11,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _targetOverview(ScanReport report) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.target,
            style: const TextStyle(
              color: skavenOrange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 9),
          _smallRow('IP', report.resolvedIp ?? 'Not resolved'),
          _smallRow('HTTP', '${report.statusCode ?? 'Not inspected'}'),
          _smallRow('SERVER', report.server ?? 'Not disclosed'),
          _smallRow('TLS', report.tlsSummary ?? 'Not inspected'),
        ],
      ),
    );
  }

  Widget _smallRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: skavenMuted,
                fontSize: 9,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: skavenSteel,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _findingsTab() {
    final report = _report;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'SECURITY FINDINGS',
          style: TextStyle(
            color: skavenSteel,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Passive observations from the latest scan.',
          style: TextStyle(color: skavenMuted, fontSize: 11),
        ),
        const SizedBox(height: 18),
        if (report == null)
          const _EmptyState(
            title: 'No scan available',
            subtitle: 'Run a reconnaissance scan to view findings.',
          )
        else
          _findingsList(report),
      ],
    );
  }

  Widget _intelTab() {
    final report = _report;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'COLLECTED INTELLIGENCE',
          style: TextStyle(
            color: skavenSteel,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        if (report == null)
          const _EmptyState(
            title: 'No intelligence collected',
            subtitle: 'Start a scan to populate the intelligence database.',
          )
        else ...[
          _sectionTitle('TECHNOLOGIES'),
          ...report.technologies.map(
            (item) => _DataTile(
              icon: Icons.memory,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('ENDPOINT REFERENCES'),
          ...report.endpoints.map(
            (item) => _DataTile(
              icon: Icons.api,
              title: item,
              onTap: () => _copyText(item),
            ),
          ),
          const SizedBox(height: 14),
          _sectionTitle('RESPONSE HEADERS'),
          ...report.headers.entries.map(
            (entry) => _InfoRow(
              label: entry.key,
              value: entry.value,
              onTap: () => _copyText('${entry.key}: ${entry.value}'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _historyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'SCAN HISTORY',
                style: TextStyle(
                  color: skavenSteel,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Clear history',
              onPressed: _history.isEmpty ? null : _confirmClearHistory,
              icon: const Icon(Icons.delete_outline, color: skavenRed),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          const _EmptyState(
            title: 'No scan history',
            subtitle: 'Completed scans will appear here.',
          )
        else
          ..._history.map(
            (report) => _HistoryTile(
              report: report,
              onTap: () => _loadReport(report),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: skavenPanel,
        title: const Text('Clear scan history?'),
        content: const Text(
          'This removes locally saved scan history from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'CLEAR',
              style: TextStyle(color: skavenRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _history.clear());
    await _saveHistory();
    _message('Scan history cleared.');
  }
}

class _Module {
  final String title;
  final IconData icon;

  const _Module(this.title, this.icon);
}

class _DetailPage extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _DetailPage({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: skavenBlack,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            letterSpacing: 1.3,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            description,
            style: const TextStyle(
              color: skavenMuted,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DataTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: skavenPanel,
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: skavenOrange, size: 19),
        title: Text(
          title,
          style: const TextStyle(
            color: skavenSteel,
            fontSize: 11,
          ),
        ),
        trailing: const Icon(
          Icons.copy,
          color: skavenMuted,
          size: 15,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: skavenPanel,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: skavenOrange,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: skavenSteel,
                  fontSize: 11,
                ),
              ),
            ),
            const Icon(Icons.copy, color: skavenMuted, size: 13),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.radar,
            color: skavenOrange,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: skavenSteel,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: skavenMuted,
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ScanReport report;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.report,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: skavenPanel,
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(
          Icons.language,
          color: skavenOrange,
        ),
        title: Text(
          report.target,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: skavenSteel,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${report.pages.length} pages  •  '
          '${report.endpoints.length} endpoints  •  '
          '${report.findings.length} findings',
          style: const TextStyle(
            color: skavenMuted,
            fontSize: 10,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: skavenMuted,
          size: 13,
        ),
      ),
    );
  }
}
