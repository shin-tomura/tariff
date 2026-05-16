import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'models.dart';

class ResidentActivityScreen extends StatelessWidget {
  const ResidentActivityScreen({Key? key}) : super(key: key);

  String _formatWeightDiff(Resident r) {
    double diff = r.weight - r.previousWeight;
    String sign = diff > 0 ? '+' : '';
    return '${r.weight.toStringAsFixed(1)}kg ($sign${diff.toStringAsFixed(1)}kg)';
  }

  // ★追加: 多通貨ウォレットを文字列化するヘルパー
  String _formatWallet(Resident r) {
    if (r.wallet.isEmpty) return 'Empty';
    String balances = r.wallet.entries
        .where((e) => e.value > 0.01) // 0.01以下のダストは非表示
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(1)}')
        .join(', ');
    return balances.isNotEmpty ? balances : '0.0';
  }

  String _exportAllActivities(SimulationEngine engine) {
    StringBuffer b = StringBuffer();
    int targetYear = engine.currentYear - 1;
    b.writeln('=== Resident Activity Logs for Year $targetYear ===');
    for (var c in engine.countries) {
      b.writeln('\n[ Country: ${c.name} ]');
      for (var r in c.residents) {
        // ★変更: money を wallet 出力に変更
        b.writeln(
          '- ${r.name} (Age ${r.age} | Weight: ${_formatWeightDiff(r)} | Wallet: [ ${_formatWallet(r)} ]):',
        );
        if (r.lastYearActivities.isEmpty) {
          b.writeln('  -> No significant market activity.');
        } else {
          for (var act in r.lastYearActivities) {
            b.writeln('  -> $act');
          }
        }
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    int targetYear = engine.currentYear - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('Activities in Year $targetYear'),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Activity Logs',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: _exportAllActivities(engine)),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied all activity logs!')),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: engine.countries.length,
        itemBuilder: (context, index) {
          Country c = engine.countries[index];
          return ExpansionTile(
            title: Text(
              '${c.name} Residents Activity',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: true,
            children: c.residents.map((r) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: Colors.blueGrey[800],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.name}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // ★変更: money を wallet 表示に変更
                      Text(
                        'Age: ${r.age} | Weight: ${_formatWeightDiff(r)} | Wallet: [ ${_formatWallet(r)} ]',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                        softWrap: true,
                      ),
                      const Divider(color: Colors.white24),
                      if (r.lastYearActivities.isEmpty)
                        const SelectableText(
                          'No significant market activity.',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.white70,
                          ),
                        )
                      else
                        ...r.lastYearActivities.map(
                          (act) => Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: SelectableText(
                              '• $act',
                              style: const TextStyle(fontSize: 13, height: 1.3),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
