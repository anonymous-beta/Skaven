
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/recon_service.dart';

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
        appBarTheme: const AppBarTheme(
          backgroundColor: skavenBlack,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: skavenPanel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: skavenOrange),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: skavenOrange,
            foregroundColor: Colors.black,
            minimumSize: const Size(100, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
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
  final ReconService _service = ReconService();

  CancelToken? _cancelToken;
  ScanReport? _report;
  List<ScanReport> _history = [];

  bool _scanning = false;
  String _status = 'SYSTEM READY';
  String _progress = 'Awaiting target';
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('skaven_history');

    if (raw == null) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final reports = decoded
          .whereType<Map>()
          .map(
            (item) => ScanReport.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      if (mounted) {
        setState(() => _history = reports);
      }
    } catch (_) {
      // Ignore unreadable history data.
    }
  }

  Future<void> _saveHistory(ScanReport report) async {
    _history.insert(0, report);

    if (_history.length > 30) {
      _history = _history.take(30).toList();
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'skaven_history',
      jsonEncode(_history.map((item) => item.toJson()).toList()),
    );

    if (mounted) setState(() {});
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    final target = _targetController.text.trim();

    if (target.isEmpty) {
      _message('Enter a website address first.');
      return;
    }

    setState(() {
      _scanning = true;
      _status = 'SCANNING';
      _progress = 'Initializing reconnaissance...';
      _report = null;
    });

    _cancelToken = CancelToken();

    try {
      final result = await _service.scan(
        target,
        cancelToken: _cancelToken,
        onProgress: (message) {
          if (mounted) {
            setState(() => _progress = message);
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _report = result;
        _status = result.status.toUpperCase();
        _progress = 'Inspection finished';
      });

      await _saveHistory(result);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'SCAN ERROR';
        _progress = error.toString();
      });

      _message('Scan error: $error');
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  void _cancelScan() {
    if (!_scanning) return;

    _cancelToken?.cancel('User cancelled scan');

    setState(() {
      _status = 'CANCELLING';
      _progress = 'Stopping active requests...';
    });
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: skavenPanel,
      ),
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));

    if (mounted) {
      _message('Copied to clipboard.');
    }
  }

  Future<void> _exportReport() async {
    final report = _report;

    if (report == null) {
      _message('There is no scan report to export.');
      return;
    }

    final buffer = StringBuffer()
      ..writeln('SKAVEN RECONNAISSANCE REPORT')
      ..writeln('Creator: Anonymous-beta (Chinedu)')
      ..writeln('Target: ${report.target}')
      ..writeln('Date: ${report.timestamp.toLocal()}')
      ..writeln('Status: ${report.status}')
      ..writeln('Pages inspected: ${report.pagesVisited}')
      ..writeln('')
      ..writeln('FINDINGS')
      ..writeln('================================');

    for (final finding in report.findings) {
      buffer
        ..writeln('[${finding.severity.toUpperCase()}] ${finding.title}')
        ..writeln('Module: ${finding.module}')
        ..writeln(finding.detail)
        ..writeln('--------------------------------');
    }

    await _copy(buffer.toString());
  }

  void _openHistoryReport(ScanReport report) {
    setState(() {
      _report = report;
      _tab = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: [
            const Icon(
              Icons.pets,
              color: skavenOrange,
              size: 28,
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
                color: skavenOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: skavenOrange.withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                'RECON',
                style: TextStyle(
                  color: skavenOrange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _dashboard(),
          _findingsPage(),
          _historyPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: skavenPanel,
        indicatorColor: skavenOrange.withValues(alpha: 0.2),
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: skavenOrange),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_search),
            selectedIcon: Icon(Icons.manage_search, color: skavenOrange),
            label: 'Findings',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: skavenOrange),
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
        const SizedBox(height: 18),
        _sectionTitle('TARGET CONFIGURATION'),
        const SizedBox(height: 10),
        TextField(
          controller: _targetController,
          enabled: !_scanning,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _startScan(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.language, color: skavenOrange),
            hintText: 'https://example.com',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _scanning ? null : _startScan,
                icon: Icon(
                  _scanning ? Icons.sync : Icons.play_arrow,
                ),
                label: Text(
                  _scanning ? 'SCANNING' : 'START SCAN',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_scanning)
              OutlinedButton.icon(
                onPressed: _cancelScan,
                icon: const Icon(
                  Icons.stop,
                  color: skavenRed,
                ),
                label: const Text('STOP'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _statusPanel(),
        const SizedBox(height: 18),
        _sectionTitle('INTELLIGENCE MODULES'),
        const SizedBox(height: 10),
        _moduleGrid(),
        const SizedBox(height: 18),
        _sectionTitle('LATEST SCAN'),
        const SizedBox(height: 10),
        if (report == null)
          _emptyPanel(
            Icons.radar,
            'No scan data available',
            'Enter an authorized website above to begin.',
          )
        else
          _reportSummary(report),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            'SKAVEN  •  BY ANONYMOUS-BETA (CHINEDU)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF25120D),
            skavenPanel,
            Color(0xFF181010),
          ],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: skavenOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PUBLIC-SURFACE INTELLIGENCE',
            style: TextStyle(
              color: skavenOrange,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.6,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'HUNT THE\nEXPOSED SURFACE.',
            style: TextStyle(
              fontSize: 27,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Website discovery, source intelligence, network indicators and security-header auditing.',
            style: TextStyle(
              color: skavenSteel,
              height: 1.5,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _scanning ? Icons.radar : Icons.circle,
                color: _scanning ? skavenOrange : Colors.greenAccent,
                size: 15,
              ),
              const SizedBox(width: 9),
              const Text(
                'SYSTEM STATUS',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                _status,
                style: const TextStyle(
                  color: skavenOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _progress,
            style: const TextStyle(
              fontSize: 12,
              color: skavenSteel,
            ),
          ),
          if (_scanning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              color: skavenOrange,
              backgroundColor: Colors.white12,
            ),
          ],
        ],
      ),
    );
  }

  Widget _moduleGrid() {
    final modules = [
      (Icons.travel_explore, 'Website crawler', 'Page discovery'),
      (Icons.code, 'Source intelligence', 'Public source inspection'),
      (Icons.api, 'API discovery', 'Endpoint references'),
      (Icons.dns, 'Network intelligence', 'DNS resolution'),
      (Icons.shield_outlined, 'Security analysis', 'HTTP headers and cookies'),
      (
        Icons.description_outlined,
        'Discovery files',
        'Robots, sitemap, security.txt',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modules.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, index) {
        final item = modules[index];

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _tab = 1),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: skavenPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.$1, color: skavenOrange, size: 23),
                const SizedBox(height: 8),
                Text(
                  item.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _reportSummary(ScanReport report) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
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
          const SizedBox(height: 12),
          Row(
            children: [
              _metric('PAGES', '${report.pagesVisited}'),
              _metric('FINDINGS', '${report.findings.length}'),
              _metric('HIGH', '${report.highCount}'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _tab = 1),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('VIEW FINDINGS'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _exportReport,
                icon: const Icon(
                  Icons.copy,
                  color: skavenOrange,
                ),
                tooltip: 'Copy report',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              color: skavenOrange,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _findingsPage() {
    final findings = _report?.findings ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('SCAN FINDINGS'),
        const SizedBox(height: 7),
        Text(
          _report?.target ?? 'No active report',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 15),
        if (findings.isEmpty)
          _emptyPanel(
            Icons.manage_search,
            'Nothing to display',
            'Run a scan to populate the findings dashboard.',
          )
        else
          ...findings.map(_findingCard),
      ],
    );
  }

  Widget _findingCard(ScanFinding finding) {
    final color = switch (finding.severity) {
      'critical' => skavenRed,
      'high' => Colors.deepOrangeAccent,
      'medium' => Colors.amber,
      'low' => Colors.lightBlueAccent,
      _ => Colors.greenAccent,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  finding.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  finding.severity.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            finding.module.toUpperCase(),
            style: const TextStyle(
              color: skavenOrange,
              fontSize: 9,
              letterSpacing: 1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            finding.detail,
            style: const TextStyle(
              fontSize: 11,
              color: skavenSteel,
              height: 1.5,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => _copy(
                '${finding.title}\n${finding.detail}',
              ),
              icon: const Icon(
                Icons.copy,
                size: 17,
                color: skavenOrange,
              ),
              tooltip: 'Copy finding',
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('SCAN HISTORY'),
        const SizedBox(height: 12),
        if (_history.isEmpty)
          _emptyPanel(
            Icons.history,
            'No saved scans',
            'Completed scan reports will appear here.',
          )
        else
          ..._history.map(
            (report) => Card(
              color: skavenPanel,
              child: ListTile(
                leading: const Icon(
                  Icons.language,
                  color: skavenOrange,
                ),
                title: Text(
                  report.target,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${report.timestamp.toLocal()} • ${report.findings.length} findings',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: skavenOrange,
                ),
                onTap: () => _openHistoryReport(report),
              ),
            ),
          ),
        if (_history.isNotEmpty)
          TextButton.icon(
            onPressed: _clearHistory,
            icon: const Icon(
              Icons.delete_outline,
              color: skavenRed,
            ),
            label: const Text(
              'CLEAR HISTORY',
              style: TextStyle(color: skavenRed),
            ),
          ),
      ],
    );
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('skaven_history');

    setState(() => _history.clear());
    _message('Scan history cleared.');
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          color: skavenOrange,
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _emptyPanel(
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 28,
      ),
      decoration: BoxDecoration(
        color: skavenPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(icon, color: skavenOrange, size: 30),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
