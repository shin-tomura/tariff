import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'models.dart';

class ResidentsScreen extends StatelessWidget {
  const ResidentsScreen({Key? key}) : super(key: key);

  String _formatWeightDiff(Resident r) {
    double diff = r.weight - r.previousWeight;
    String sign = diff > 0 ? '+' : '';
    return '${r.weight.toStringAsFixed(1)}kg ($sign${diff.toStringAsFixed(1)}kg)';
  }

  // ★追加: 多通貨ウォレットを文字列化するヘルパー
  String _formatWallet(Resident r) {
    if (r.wallet.isEmpty) return 'Empty';
    String balances = r.wallet.entries
        .where((e) => e.value > 0.01) // 0.01以下の塵(ダスト)は非表示
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(1)}')
        .join(', ');
    return balances.isNotEmpty ? balances : '0.0';
  }

  String _exportAllResidents(SimulationEngine engine) {
    StringBuffer b = StringBuffer();
    b.writeln('=== All Residents Data : Year ${engine.currentYear} ===');
    for (var c in engine.countries) {
      b.writeln('\n[ Country: ${c.name} ]');
      for (var r in c.residents) {
        // ★変更: money を wallet 出力に変更
        b.writeln(
          '- ${r.name} (Age ${r.age}): Weight ${_formatWeightDiff(r)}, Wallet [ ${_formatWallet(r)} ], Civ Level ${r.civilizationLevel}',
        );
        b.writeln(
          '  Stocks -> Wood: ${r.woodStock.toStringAsFixed(1)}, Metal: ${r.metalStock.toStringAsFixed(1)}, Oil: ${r.oilStock.toStringAsFixed(1)}',
        );
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Residents Data'),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy All Residents',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: _exportAllResidents(engine)),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied all residents data!')),
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
              '${c.name} Residents (${c.residents.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            initiallyExpanded: true,
            children: c.residents
                .map(
                  (r) => ListTile(
                    title: SelectableText('${r.name} (Age: ${r.age})'),
                    // ★変更: サブタイトルの表示を多通貨ウォレットに対応
                    subtitle: SelectableText(
                      'Weight: ${_formatWeightDiff(r)} | Wallet: [ ${_formatWallet(r)} ]\n'
                      'Stocks: Wood ${r.woodStock.toStringAsFixed(1)}, Metal ${r.metalStock.toStringAsFixed(1)}, Oil ${r.oilStock.toStringAsFixed(1)} | Civ: ${r.civilizationLevel}',
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}
