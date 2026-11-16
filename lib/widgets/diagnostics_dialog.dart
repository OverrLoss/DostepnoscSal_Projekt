import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/diagnostics_service.dart';
import '../theme/app_theme.dart';

class DiagnosticsDialog extends StatefulWidget {
  const DiagnosticsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const DiagnosticsDialog(),
    );
  }

  @override
  State<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends State<DiagnosticsDialog> {
  Map<String, dynamic>? _report;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    final media = MediaQuery.of(context);
    final data = await DiagnosticsService.instance.gatherDiagnosticReport(
      screenWidth: media.size.width,
      screenHeight: media.size.height,
      pixelRatio: media.devicePixelRatio,
    );
    if (mounted) {
      setState(() {
        _report = data;
        _isLoading = false;
      });
    }
  }

  void _copyReportToClipboard() {
    if (_report == null) return;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_report);
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Raport diagnostyczny skopiowany do schowka!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = _report?['client'] as Map<String, dynamic>?;
    final server = _report?['server'] as Map<String, dynamic>?;
    final syncStatus = client?['sync_status'] as Map<String, dynamic>?;
    final db = client?['local_database'] as Map<String, dynamic>?;
    final serverDb = server?['database'] as Map<String, dynamic>?;
    final traffic = server?['traffic_metrics'] as Map<String, dynamic>?;

    return AlertDialog(
      backgroundColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.analytics, color: Colors.blueAccent, size: 20),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Diagnostyka Serwisowa',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: _isLoading
            ? const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Klient
                    _buildSectionHeader('📱 Urządzenie & Klient', AppColors.cyan),
                    _buildInfoCard([
                      _buildRow('Platforma:', client?['platform']?.toString() ?? '-'),
                      _buildRow('System operacyjny:', client?['os_version']?.toString() ?? '-'),
                      _buildRow('Wersja aplikacji:', client?['app_version']?.toString() ?? '-'),
                      _buildRow(
                        'Ekran (piksele):',
                        '${client?['display']?['width']}x${client?['display']?['height']} (skala: ${client?['display']?['pixel_ratio']})',
                      ),
                      _buildRow('Lokalny silnik bazy:', db?['engine']?.toString() ?? '-'),
                      _buildRow('Lokalna liczba sal:', '${db?['records_count'] ?? 0} sal'),
                    ]),

                    const SizedBox(height: 12),

                    // Section 2: Sieć i Tunel
                    _buildSectionHeader('🌐 Łączność & Tunel Cloudflare', AppColors.success),
                    _buildInfoCard([
                      _buildRow('Status synchronizacji:', syncStatus?['connection_state']?.toString().toUpperCase() ?? '-'),
                      _buildRow('Adres serwera:', syncStatus?['server_url']?.toString() ?? '-'),
                      _buildRow(
                        'Opóźnienie (Ping API):',
                        (syncStatus?['ping_latency_ms'] ?? -1) >= 0
                            ? '${syncStatus?['ping_latency_ms']} ms ⚡'
                            : 'Brak odpowiedzi ❌',
                      ),
                      _buildRow('Ostatnia synchronizacja:', syncStatus?['last_sync']?.toString() ?? '-'),
                    ]),

                    const SizedBox(height: 12),

                    // Section 3: Serwer Bazy Danych
                    _buildSectionHeader('🖥️ Serwer Synchronizacji (SQLite)', AppColors.warning),
                    if (server != null && server['status'] != 'unreachable')
                      _buildInfoCard([
                        _buildRow('Czas działania (Uptime):', server['uptime_human']?.toString() ?? '-'),
                        _buildRow('Środowisko serwera:', '${server['server_os']} / Python ${server['python_version']}'),
                        _buildRow('Silnik SQLite serwera:', 'v${server['sqlite_version']}'),
                        _buildRow('Rozmiar bazy SQLite:', serverDb?['size_formatted']?.toString() ?? '-'),
                        _buildRow('Zapisanych sal na serwerze:', '${serverDb?['total_rooms'] ?? 0} (Wolne: ${serverDb?['free_rooms']}, Zajęte: ${serverDb?['occupied_rooms']})'),
                        _buildRow('Obsłużonych zapytań HTTP:', '${traffic?['total_requests'] ?? 0}'),
                        _buildRow('Pobrań instalatora APK:', '${traffic?['file_downloads'] ?? 0}'),
                      ])
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.cloud_off, color: AppColors.danger, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Serwer synchronizacji jest obecnie niedostępny lub w trybie offline.',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        IconButton(
          tooltip: 'Odśwież dane serwisowe',
          icon: const Icon(Icons.refresh, color: Colors.white70),
          onPressed: _loadReport,
        ),
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16, color: Colors.blueAccent),
          label: const Text('Kopiuj JSON', style: TextStyle(color: Colors.blueAccent)),
          onPressed: _copyReportToClipboard,
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2A2A2A),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Zamknij'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
