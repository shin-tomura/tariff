import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'models.dart';

class DebugExportScreen extends StatelessWidget {
  const DebugExportScreen({Key? key}) : super(key: key);

  String _generateDebugDump(SimulationEngine engine) {
    final buffer = StringBuffer();
    var settings = Hive.box('settings');

    buffer.writeln('=========================================');
    buffer.writeln('      LLM DEBUG & VERIFICATION DUMP      ');
    buffer.writeln('=========================================');
    buffer.writeln('Current Year: ${engine.currentYear}');

    // ★旧式（計算式）の介入ステータスを削除し、AMMの稼働状況を明記
    buffer.writeln('Engine Architecture: Multi-Currency AMM (Global Exchange)');

    buffer.writeln(
      'Civ Level 2 (Wood) Threshold: ${settings.get('civWoodThreshold', defaultValue: 20.0)}',
    );
    buffer.writeln(
      'Civ Level 3 (Metal) Threshold: ${settings.get('civMetalThreshold', defaultValue: 30.0)}',
    );
    buffer.writeln('-----------------------------------------\n');

    // ★追加: 地球共通両替所（AMM）の流動性プール状況をダンプ
    var exchange = engine.globalExchange;
    buffer.writeln('>>> GLOBAL EXCHANGE (AMM LIQUIDITY POOL)');
    if (exchange.liquidityPool.isEmpty) {
      buffer.writeln('  (Pool is empty)');
    } else {
      exchange.liquidityPool.forEach((cur, amt) {
        buffer.writeln('  $cur: $amt');
      });
    }
    buffer.writeln('-----------------------------------------\n');

    for (var c in engine.countries) {
      buffer.writeln('>>> COUNTRY: ${c.name} (ID: ${c.id})');
      buffer.writeln('  [Base Stats]');
      buffer.writeln('  Currency Name: ${c.currencyName}');
      buffer.writeln(
        '  Currency Index: ${c.currencyIndex} (Real-time AMM ratio vs USD)',
      );

      // ★変更: 多通貨の外貨準備高をダンプ
      String reservesStr = c.reserves.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      buffer.writeln('  Government Reserves (Next UBI Pool): { $reservesStr }');
      buffer.writeln('  Inheritance Tax Rate: ${c.inheritanceTaxRate}');

      // ★追加: 輸出禁止措置と食料安全保障の設定状況をダンプ
      buffer.writeln('\n  [Trade Policies & Security]');
      buffer.writeln(
        '    Food Domestic Priority: ${c.foodDomesticPriority ? "ENABLED" : "DISABLED"}',
      );
      if (c.exportBans.isEmpty) {
        buffer.writeln('    Export Bans: None');
      } else {
        buffer.writeln('    Export Bans:');
        c.exportBans.forEach((k, v) {
          buffer.writeln('      $k: ${v ? "BANNED" : "Allowed"}');
        });
      }

      buffer.writeln('\n  [Tariffs (Item-Specific)]');
      if (c.tariffs.isEmpty) {
        buffer.writeln('    None');
      } else {
        c.tariffs.forEach(
          (k, v) => buffer.writeln('    $k: ${(v * 100).toInt()}%'),
        );
      }

      buffer.writeln('\n  [Trade Ledgers (Last Year)]');
      if (c.exportLedger.isEmpty)
        buffer.writeln('    Exports: None');
      else
        c.exportLedger.forEach(
          (k, v) => buffer.writeln('    Exported ($k): $v'),
        );

      if (c.importLedger.isEmpty)
        buffer.writeln('    Imports: None');
      else
        c.importLedger.forEach(
          (k, v) => buffer.writeln('    Imported ($k): $v'),
        );

      buffer.writeln('\n  [Resources]');
      for (var res in c.resources.values) {
        buffer.writeln(
          '    ${res.type}: Available=${res.availableAmount}, AnnualProd=${res.annualProduction}, LastPrice=${res.lastMarketPrice}',
        );
      }

      buffer.writeln('\n  [Residents (Total: ${c.residents.length})]');
      for (var r in c.residents) {
        buffer.writeln('    --- Resident: ${r.name} (ID: ${r.id}) ---');
        buffer.writeln('      Age: ${r.age}');
        buffer.writeln(
          '      Weight: Current=${r.weight} | Previous=${r.previousWeight}',
        );

        // ★変更: 住民の多通貨ウォレットをダンプ
        String walletStr = r.wallet.entries
            .map((e) => '${e.key}=${e.value}')
            .join(' | ');
        buffer.writeln('      Wallet: [ $walletStr ]');

        buffer.writeln(
          '      Stocks: Wood=${r.woodStock} | Metal=${r.metalStock} | Oil=${r.oilStock}',
        );
        buffer.writeln('      Calculated CivLevel: ${r.civilizationLevel}');
        buffer.writeln('      [Last Year Activities]:');
        if (r.lastYearActivities.isEmpty) {
          buffer.writeln('        (No activities)');
        } else {
          for (var act in r.lastYearActivities) {
            buffer.writeln('        * $act');
          }
        }
      }
      buffer.writeln('\n=========================================\n');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    final dumpText = _generateDebugDump(engine);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Verification Export'),
        backgroundColor: Colors.deepPurple[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy for LLM',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dumpText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Copied all AMM & Trade parameters to clipboard!',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Paste this text directly into an LLM. Ask it to analyze currency flows, AMM liquidity changes, trade deficits, and simulate "play-by-play" economic commentary.',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  border: Border.all(color: Colors.cyan, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    dumpText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: dumpText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied all AMM & Trade parameters to clipboard!'),
            ),
          );
        },
        icon: const Icon(Icons.copy_all),
        label: const Text('Copy to Clipboard'),
        backgroundColor: Colors.cyan[700],
      ),
    );
  }
}
