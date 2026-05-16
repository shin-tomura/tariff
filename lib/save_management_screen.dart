import 'dart:io';
import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'save_service.dart';

class SaveManagementScreen extends StatefulWidget {
  const SaveManagementScreen({Key? key}) : super(key: key);

  @override
  State<SaveManagementScreen> createState() => _SaveManagementScreenState();
}

class _SaveManagementScreenState extends State<SaveManagementScreen> {
  final TextEditingController _clipboardController = TextEditingController();
  bool _isLoading = false;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.teal,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- Clipboard (Lightweight) Processing ---

  Future<void> _exportToClipboard() async {
    setState(() => _isLoading = true);
    try {
      final code = await SaveService.exportLightweightToClipboard();
      await Clipboard.setData(ClipboardData(text: code));
      _showSnackBar('Lightweight snapshot copied to clipboard!');
    } catch (e) {
      _showSnackBar('Export failed: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importFromClipboard() async {
    final code = _clipboardController.text.trim();
    if (code.isEmpty) {
      _showSnackBar('Please enter a save code.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await SaveService.importLightweightFromClipboard(code);
      if (!mounted) return;
      _clipboardController.clear();

      final engine = context.read<SimulationEngine>();
      engine.currentYear = Hive.box(
        'settings',
      ).get('currentYear', defaultValue: 1);

      engine.notifyListeners();
      _showSnackBar('Lightweight snapshot imported successfully!');
      Navigator.pop(context);
    } catch (e) {
      _showSnackBar(
        'Import failed. Please verify that the code is correct.',
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- File (Full Backup) Processing ---

  Future<void> _exportToFile(int currentYear) async {
    setState(() => _isLoading = true);
    try {
      final bytes = await SaveService.exportFullToFile();

      // ★修正: bytes パラメータを直接渡し、自前での後続の writeAsBytes を不要にします
      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Save Full Backup Data',
        fileName: 'Hakoniwa_Tariff_Year$currentYear.hknw',
        type: FileType.any,
        bytes: bytes, // パスではなくバイナリを直接OSのセーブ機構に渡す
      );

      if (outputFile != null) {
        _showSnackBar('Full backup data successfully saved to file!');
      }
    } catch (e) {
      print("Failed to save file: $e");
      _showSnackBar('Failed to save file: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importFromFile() async {
    setState(() => _isLoading = true);
    try {
      // Call OS standard file picker dialog
      FilePickerResult? result = await FilePicker.pickFiles(
        dialogTitle: 'Select Save Data File (.hknw)',
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        await SaveService.importFullFromFile(bytes);

        if (!mounted) return;

        final engine = context.read<SimulationEngine>();
        engine.currentYear = Hive.box(
          'settings',
        ).get('currentYear', defaultValue: 1);

        engine.notifyListeners();
        _showSnackBar('Full backup data imported successfully!');
        Navigator.pop(context);
      }
    } catch (e) {
      print("Failed to load file: $e");
      _showSnackBar(
        'Failed to load file. Please ensure it is a valid data file.',
        isError: true,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _clipboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Save Data Management'),
        backgroundColor: Colors.indigo[900],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // 1. Lightweight Snapshot (For SNS/Text sharing)
              _buildSectionCard(
                title: 'Lightweight Snapshot (For SNS/Text)',
                icon: Icons.content_copy,
                color: Colors.orangeAccent,
                description:
                    'Exports only the current economic status as a compact text code. Since past chart history and event logs are excluded, it is perfect for sharing scenarios and custom challenges on Discord or X (Twitter).',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload),
                      label: const Text('Export to Clipboard (Copy)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[800],
                      ),
                      onPressed: _isLoading ? null : _exportToClipboard,
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _clipboardController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Paste Save Code Here',
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.black45,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Import from Clipboard (Paste)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[700],
                      ),
                      onPressed: _isLoading ? null : _importFromClipboard,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Full Backup (For file transfer)
              _buildSectionCard(
                title: 'Full Backup (File Transfer)',
                icon: Icons.save_alt,
                color: Colors.blueAccent,
                description:
                    'Exports a complete binary data file (.hknw) including decades of chart history and event logs. Ideal for personal backups or fully migrating your progress to another device.',
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Save to File (Export)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[800],
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _exportToFile(engine.currentYear),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_download),
                      label: const Text('Load from File (Import)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[600],
                      ),
                      onPressed: _isLoading ? null : _importFromFile,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required String description,
    required Widget content,
  }) {
    return Card(
      color: Colors.blueGrey[900],
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            content,
          ],
        ),
      ),
    );
  }
}
