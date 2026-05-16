import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'engine.dart';
import 'models.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  String _exportAllHistory(List<EventLog> logs) {
    StringBuffer b = StringBuffer();
    b.writeln('=== Event History Log ===');
    for (var log in logs) {
      b.writeln(log.message);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SimulationEngine>();
    final logs = Hive.box<EventLog>('logs').values.toList().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event History'),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Full History',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _exportAllHistory(logs)));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied full event history!')),
              );
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('No events recorded yet.'))
          : ListView.builder(
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: Colors.blueGrey[800],
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      child: Text(
                        log.year.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: SelectableText(
                      log.message,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
