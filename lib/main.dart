// Responsive font scaling implementation
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'engine.dart';
import 'residents_screen.dart';
import 'resident_activity_screen.dart';
import 'edit_screen.dart';
import 'advanced_edit_screen.dart';
import 'history_screen.dart';
import 'debug_export_screen.dart';
import 'chart_screen.dart';
import 'save_management_screen.dart';
import 'rules_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // アダプターの登録
  Hive.registerAdapter(CountryAdapter());
  Hive.registerAdapter(ResidentAdapter());
  Hive.registerAdapter(ResourceInfoAdapter());
  Hive.registerAdapter(EventLogAdapter());
  Hive.registerAdapter(YearlyMetricsAdapter());
  Hive.registerAdapter(GlobalExchangeAdapter());
  Hive.registerAdapter(SimulationSettingsAdapter()); // 設定用アダプター

  await Hive.openBox<Resident>('residents');
  await Hive.openBox<Country>('countries');
  await Hive.openBox<EventLog>('logs');
  await Hive.openBox('settings');
  await Hive.openBox<GlobalExchange>('exchange');

  await _initializeDataIfEmpty();

  runApp(
    ChangeNotifierProvider(
      create: (_) => SimulationEngine(),
      child: const TrumpTariffApp(),
    ),
  );
}

Future<void> _initializeDataIfEmpty() async {
  var cBox = Hive.box<Country>('countries');
  var rBox = Hive.box<Resident>('residents');

  if (cBox.isEmpty) {
    var settings = Hive.box('settings');
    // 【1】文明レベルの閾値
    settings.put('civWoodThreshold', 20.0);
    settings.put('civMetalThreshold', 30.0);
    settings.put('currentYear', 1);

    // 【2】シミュレーション設定の最適化（需給バランスと維持費の調整）
    if (!settings.containsKey('sim_rules')) {
      settings.put(
        'sim_rules',
        SimulationSettings(
          // ---------------------------------------------------
          // ① 年間消費量（世界人口30人に対する生産量にジャストフィット）
          // ---------------------------------------------------
          annualConsumption: {
            'Food': 12.0, // 世界総生産360にマッチ
            'Wood': 6.0, // 世界総生産180にマッチ
            'Metal': 5.0, // 世界総生産150にマッチ
            'Oil': 1.5, // 世界総生産45にマッチ
          },
          // ---------------------------------------------------
          // ② 住民の消滅率（「閾値ギリギリ」をキープさせる絶妙な調整）
          // ---------------------------------------------------
          residentDepreciationRates: {
            'Food': 1.0,
            'Wood': 0.20,
            'Metal': 0.10,
            'Oil': 1.0,
          },
          // ---------------------------------------------------
          // ③ 国家の消滅率は微調整（過剰在庫対策）
          // ---------------------------------------------------
          countryDepreciationRates: {
            'Food': 1.0,
            'Wood': 0.15,
            'Metal': 0.10,
            'Oil': 0.05,
          },
        ),
      );
    }

    List<String> ids = ['USA', 'CHN', 'JPN'];
    List<String> cNames = ['America', 'China', 'Japan'];
    List<String> currencies = ['USD', 'CNY', 'JPY'];

    for (int i = 0; i < 3; i++) {
      HiveList<Resident> hRes = HiveList(rBox);
      for (int j = 0; j < 10; j++) {
        // ---------------------------------------------------
        // ④ 初期状態の非同期化（スパイダーウェブ現象の完全防止）
        // ---------------------------------------------------
        var r = Resident(
          id: '${ids[i]}_r$j',
          name: '${cNames[i]} Citizen $j',
          age: j,
          weight: 60.0,
          wallet: {currencies[i]: 300.0 + (j * 40.0)},
        );

        // 最初から文明レベル2以上の富裕層（年長者）を市場に混ぜておく
        r.woodStock = j * 2.5;
        r.metalStock = j > 5 ? (j - 5) * 5.0 : 0.0;

        rBox.add(r);
        hRes.add(r);
      }

      // ---------------------------------------------------
      // ⑤ 国ごとのリアルな資源設定（AMERICA FIRST 仕様）
      // 世界の総生産量をUSAに大きく偏らせ、覇権を握らせる
      // ---------------------------------------------------
      Map<String, ResourceInfo> countryResources = {};
      if (ids[i] == 'USA') {
        countryResources = {
          'Food': ResourceInfo(
            type: 'Food',
            availableAmount: 0,
            annualProduction: 180,
            lastMarketPrice: 10.0,
          ),
          'Wood': ResourceInfo(
            type: 'Wood',
            availableAmount: 50,
            annualProduction: 80,
            lastMarketPrice: 20.0,
          ),
          'Metal': ResourceInfo(
            type: 'Metal',
            availableAmount: 50,
            annualProduction: 70,
            lastMarketPrice: 50.0,
          ),
          'Oil': ResourceInfo(
            type: 'Oil',
            availableAmount: 30,
            annualProduction: 30,
            lastMarketPrice: 100.0,
          ),
        };
      } else if (ids[i] == 'CHN') {
        countryResources = {
          'Food': ResourceInfo(
            type: 'Food',
            availableAmount: 0,
            annualProduction: 150,
            lastMarketPrice: 10.0,
          ),
          'Wood': ResourceInfo(
            type: 'Wood',
            availableAmount: 50,
            annualProduction: 70,
            lastMarketPrice: 20.0,
          ),
          'Metal': ResourceInfo(
            type: 'Metal',
            availableAmount: 50,
            annualProduction: 60,
            lastMarketPrice: 50.0,
          ),
          'Oil': ResourceInfo(
            type: 'Oil',
            availableAmount: 15,
            annualProduction: 15,
            lastMarketPrice: 100.0,
          ),
        };
      } else if (ids[i] == 'JPN') {
        countryResources = {
          'Food': ResourceInfo(
            type: 'Food',
            availableAmount: 0,
            annualProduction: 30,
            lastMarketPrice: 10.0,
          ),
          'Wood': ResourceInfo(
            type: 'Wood',
            availableAmount: 20,
            annualProduction: 30,
            lastMarketPrice: 20.0,
          ),
          'Metal': ResourceInfo(
            type: 'Metal',
            availableAmount: 10,
            annualProduction: 20,
            lastMarketPrice: 50.0,
          ),
          'Oil': ResourceInfo(
            type: 'Oil',
            availableAmount: 0,
            annualProduction: 0,
            lastMarketPrice: 100.0,
          ),
        };
      }

      // 各国政府の初期資金を設定
      Map<String, double> initialReserves = {};
      for (var cur in currencies) {
        if (cur == currencies[i]) {
          initialReserves[cur] = 0.0;
        } else {
          initialReserves[cur] = 1000.0;
        }
      }

      var c = Country(
        id: ids[i],
        name: cNames[i],
        currencyName: currencies[i],
        tariffs: {},
        inheritanceTaxRate: 0.1,
        ubiPayoutRatio: 1.0,
        useProgressiveUbi: false,
        reserves: initialReserves,
        residents: hRes,
        resources: countryResources,
        exportLedger: {},
        importLedger: {},
        history: [],
      );
      cBox.add(c);
    }
  }
}

class TrumpTariffApp extends StatelessWidget {
  const TrumpTariffApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 画面幅に応じてフォント・アイコンのスケールファクターを決定
        double scale = 1.0;
        if (constraints.maxWidth >= 900) {
          scale = 1.4; // PC・大型タブレット向け
        } else if (constraints.maxWidth >= 600) {
          scale = 1.25; // タブレット向け
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Trump Tariff Simulator',
          theme: ThemeData.dark().copyWith(
            primaryColor: Colors.deepOrange,
            // アプリ全体の標準アイコンサイズもスケールさせる
            iconTheme: IconThemeData(size: 24.0 * scale),
          ),
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            // デバイスのOS設定などのベーススケールを取得
            final baseScale = mediaQuery.textScaler.scale(1.0);

            // TextScalerを使用してアプリ全体のテキストサイズを一括調整
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(baseScale * scale),
              ),
              child: child!,
            );
          },
          home: const DashboardScreen(),
        );
      },
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  // データを初期状態にリセットする関数
  Future<void> _factoryReset(
    BuildContext context,
    SimulationEngine engine,
  ) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '⚠️ Factory Reset',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Are you sure you want to completely reset the simulation?\n\n'
          'All progress, trade history, event logs, and custom parameters will be permanently lost, and the game will return to Year 1.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'RESET ALL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 全てのHiveボックスのデータを削除
      await Hive.box<Country>('countries').clear();
      await Hive.box<Resident>('residents').clear();
      await Hive.box<EventLog>('logs').clear();
      await Hive.box('settings').clear();
      await Hive.box<GlobalExchange>('exchange').clear();

      // 初期データを再生成
      await _initializeDataIfEmpty();

      // エンジンの状態をリセットしてUIを再描画
      engine.currentYear = 1;
      await Hive.box('settings').put('currentYear', 1);
      engine.logUserAction('Simulation Factory Reset (Returned to Year 1).');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Simulation has been fully reset to initial state.'),
        ),
      );
    }
  }

  // はみ出し防止用・アイコン付き政策タグ（RichTextで折り返し対応）
  Widget _buildPolicyTag(
    IconData icon,
    String label,
    String value,
    Color valueColor,
  ) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Icon(icon, size: 14, color: Colors.white54),
            ),
          ),
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: Colors.white54),
          ),
          TextSpan(
            text: value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Year ${engine.currentYear}'),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy All Dashboard Data',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: engine.exportDashboardState()),
              );
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied!')));
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blueGrey),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.show_chart, color: Colors.greenAccent),
              title: const Text(
                'Macroeconomic Charts',
                style: TextStyle(color: Colors.greenAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChartScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('All Residents'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ResidentsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment),
              title: const Text('Resident Activities'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ResidentActivityScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Parameters & Policies'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const EditScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.build_circle),
              title: const Text('Advanced Edit (God Mode)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdvancedEditScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Event History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.cyanAccent),
              title: const Text(
                'LLM Debug Export',
                style: TextStyle(color: Colors.cyanAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DebugExportScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.sd_card, color: Colors.amberAccent),
              title: const Text(
                'Save Data Management',
                style: TextStyle(color: Colors.amberAccent),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SaveManagementScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book, color: Colors.amber),
              title: const Text(
                'Laws of the Sandbox',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RulesScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: engine.isSimulating
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                // 地球共通両替所の流動性プールUI（スクロール領域内）
                Card(
                  margin: const EdgeInsets.all(8),
                  color: Colors.black45,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(
                      color: Colors.indigoAccent,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '🌍 Global Liquidity Pool (AMM)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigoAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: engine.globalExchange.liquidityPool.entries
                              .map((e) {
                                return Text(
                                  '${e.key}: ${e.value.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.yellowAccent,
                                  ),
                                );
                              })
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                // 各国のカード展開
                ...engine.countries.map((c) {
                  // 自国通貨の流通量計算
                  double residentLocalMoney = c.residents.fold(
                    0.0,
                    (sum, r) => sum + (r.wallet[c.currencyName] ?? 0.0),
                  );
                  double govtLocalMoney = c.reserves[c.currencyName] ?? 0.0;
                  double totalDomesticMoney =
                      govtLocalMoney + residentLocalMoney;
                  double avgResidentLocalMoney = c.residents.isNotEmpty
                      ? residentLocalMoney / c.residents.length
                      : 0.0;

                  // エンジン側で計算済みの最新指標を取得
                  double gini = c.history.isNotEmpty
                      ? c.history.last.giniIndex
                      : 0.0;
                  double avgHwi = c.history.isNotEmpty
                      ? c.history.last.avgHwi
                      : 0.0;

                  // ジニ係数の色分けロジック
                  Color giniColor = Colors.lightGreenAccent; // 平等
                  if (gini > 0.5) {
                    giniColor = Colors.redAccent; // 深刻な格差
                  } else if (gini > 0.3) {
                    giniColor = Colors.orangeAccent; // 警戒水域
                  }

                  // 全世界共通の輸出禁止されている品目の文字列生成
                  String bannedItems = c.exportBans.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .join(', ');
                  if (bannedItems.isEmpty) bannedItems = "None";

                  // ターゲット国指定の輸出禁止措置（Targeted Export Bans）の文字列生成
                  String targetedBannedItems = c.targetedExportBans.entries
                      .where((e) => e.value)
                      .map((e) {
                        var parts = e.key.split(':');
                        if (parts.length == 2) {
                          var targetCountry = engine.countries.firstWhere(
                            (x) => x.id == parts[0],
                            orElse: () => c,
                          );
                          return '${targetCountry.name} (${parts[1]})';
                        }
                        return e.key;
                      })
                      .join(', ');
                  if (targetedBannedItems.isEmpty) targetedBannedItems = "None";

                  // ダッシュボード上で流動性プールからリアルタイムの対USDレートを計算する
                  double poolUsd =
                      engine.globalExchange.liquidityPool['USD'] ?? 1.0;
                  double poolLocal =
                      engine.globalExchange.liquidityPool[c.currencyName] ??
                      1.0;
                  // 万が一0割りを防ぐ
                  double liveCurrencyIndex = poolLocal > 0
                      ? (poolUsd / poolLocal)
                      : 0.0;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: Colors.blueGrey[800],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${c.name} (${c.currencyName})',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Flexible(
                                child: SelectableText(
                                  'C. Index: ${liveCurrencyIndex.toStringAsFixed(4)}\n(vs USD)',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const Divider(),

                          // 政府の全保有通貨（外貨準備高含む）
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.4),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Government Reserves (Foreign & Local):',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12.0,
                                  runSpacing: 8.0,
                                  children: c.reserves.entries.map((e) {
                                    bool isLocal = e.key == c.currencyName;
                                    return _buildPolicyTag(
                                      isLocal
                                          ? Icons.account_balance_wallet
                                          : Icons.currency_exchange,
                                      '${e.key}:',
                                      e.value.toStringAsFixed(1),
                                      isLocal
                                          ? Colors.yellowAccent
                                          : Colors.lightBlueAccent,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),

                          // 財政・福祉政策（Fiscal Policies & Welfare）の表示パネル
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.purple.withOpacity(0.5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fiscal Policies & Welfare:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12.0,
                                  runSpacing: 8.0,
                                  children: [
                                    _buildPolicyTag(
                                      Icons.account_balance,
                                      'Inheritance Tax:',
                                      '${(c.inheritanceTaxRate * 100).toInt()}%',
                                      Colors.orangeAccent,
                                    ),
                                    _buildPolicyTag(
                                      Icons.percent,
                                      'UBI Payout Ratio:',
                                      '${(c.ubiPayoutRatio * 100).toInt()}%',
                                      Colors.purpleAccent,
                                    ),
                                    _buildPolicyTag(
                                      Icons.balance,
                                      'UBI Model:',
                                      c.useProgressiveUbi
                                          ? 'Progressive (Welfare)'
                                          : 'Flat (Universal)',
                                      c.useProgressiveUbi
                                          ? Colors.lightGreenAccent
                                          : Colors.lightBlueAccent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blueGrey.withOpacity(0.5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Trade Policies & Security:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      c.foodDomesticPriority
                                          ? Icons.security
                                          : Icons.public,
                                      size: 14,
                                      color: c.foodDomesticPriority
                                          ? Colors.tealAccent
                                          : Colors.white54,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Food Domestic Priority: ',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: c.foodDomesticPriority
                                            ? Colors.tealAccent
                                            : Colors.white54,
                                      ),
                                    ),
                                    Text(
                                      c.foodDomesticPriority ? 'ON' : 'OFF',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: c.foodDomesticPriority
                                            ? Colors.tealAccent
                                            : Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.block,
                                      size: 14,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      // ★ Columnに変更して文字サイズが大きくても折り返すように調整
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Global Bans: $bannedItems',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: bannedItems == "None"
                                                  ? Colors.white54
                                                  : Colors.redAccent,
                                              fontWeight: bannedItems == "None"
                                                  ? FontWeight.normal
                                                  : FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Targeted Bans: $targetedBannedItems',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color:
                                                  targetedBannedItems == "None"
                                                  ? Colors.white54
                                                  : Colors.redAccent,
                                              fontWeight:
                                                  targetedBannedItems == "None"
                                                  ? FontWeight.normal
                                                  : FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceAround,
                              spacing: 12.0,
                              runSpacing: 8.0,
                              children: [
                                _buildMiniStat(
                                  'Domestic Money (${c.currencyName})',
                                  totalDomesticMoney.toStringAsFixed(1),
                                  Colors.purpleAccent,
                                ),
                                _buildMiniStat(
                                  'Avg Resident (${c.currencyName})',
                                  avgResidentLocalMoney.toStringAsFixed(1),
                                  Colors.pinkAccent,
                                ),

                                _buildMiniStat(
                                  'Gini Index (Wealth)',
                                  gini.toStringAsFixed(3),
                                  giniColor,
                                ),
                                _buildMiniStat(
                                  'Avg HWI (Welfare)',
                                  avgHwi.toStringAsFixed(1),
                                  Colors.cyanAccent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          _buildStats(c, engine.countries),
                        ],
                      ),
                    ),
                  );
                }).toList(),

                // 画面最下部のファクトリーリセットボタン
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.delete_forever, color: Colors.white),
                    label: const Text(
                      'FACTORY RESET (Restart Game)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: () => _factoryReset(context, engine),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color.fromARGB(190, 1, 249, 38),
        onPressed: engine.isSimulating ? null : () => engine.advanceOneYear(),
        icon: const Icon(Icons.fast_forward, color: Colors.black),
        label: const Text(
          'Advance 1 Year',
          style: TextStyle(color: Colors.black),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStats(Country c, List<Country> allCountries) {
    double avgW =
        c.residents.map((e) => e.weight).reduce((a, b) => a + b) /
        max(1, c.residents.length);
    double avgCiv =
        c.residents.map((e) => e.civilizationLevel).reduce((a, b) => a + b) /
        max(1, c.residents.length);

    double totalExp = c.exportLedger.values.fold(0.0, (a, b) => a + b);
    double totalImp = c.importLedger.values.fold(0.0, (a, b) => a + b);
    double tradeBalance = totalExp - totalImp;
    String tbSign = tradeBalance > 0 ? '+' : '';

    Color tbColor = tradeBalance > 0
        ? Colors.lightGreenAccent
        : (tradeBalance < 0 ? Colors.redAccent : Colors.white70);

    List<Widget> tradeWidgets = [
      SelectableText(
        'Trade Balance: $tbSign${tradeBalance.toStringAsFixed(1)} (Exp: ${totalExp.toStringAsFixed(1)} / Imp: ${totalImp.toStringAsFixed(1)})',
        style: TextStyle(color: tbColor, fontWeight: FontWeight.bold),
      ),
    ];

    for (var partner in allCountries.where((x) => x.id != c.id)) {
      double pExpTotal = 0;
      double pImpTotal = 0;
      List<String> expDetails = [];
      List<String> impDetails = [];

      for (var res in ['Food', 'Wood', 'Metal', 'Oil']) {
        double eVal = c.exportLedger["${partner.id}:$res"] ?? 0.0;
        if (eVal > 0) {
          pExpTotal += eVal;
          expDetails.add('$res: ${eVal.toStringAsFixed(1)}');
        }

        double iVal = c.importLedger["${partner.id}:$res"] ?? 0.0;
        if (iVal > 0) {
          pImpTotal += iVal;
          impDetails.add('$res: ${iVal.toStringAsFixed(1)}');
        }
      }

      if (pExpTotal > 0 || pImpTotal > 0) {
        double pBal = pExpTotal - pImpTotal;
        String pSign = pBal > 0 ? '+' : '';
        Color pColor = pBal > 0
            ? Colors.lightGreenAccent
            : (pBal < 0 ? Colors.redAccent : Colors.white70);

        tradeWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: SelectableText(
              '  ↳ With ${partner.name}: $pSign${pBal.toStringAsFixed(1)}',
              style: TextStyle(color: pColor, fontSize: 13),
            ),
          ),
        );
        if (expDetails.isNotEmpty) {
          tradeWidgets.add(
            SelectableText(
              '      Exported: ${expDetails.join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          );
        }
        if (impDetails.isNotEmpty) {
          tradeWidgets.add(
            SelectableText(
              '      Imported: ${impDetails.join(', ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          );
        }
      }
    }

    List<Widget> tariffWidgets = [];
    c.tariffs.forEach((k, v) {
      if (v > 0) {
        var parts = k.split(':');
        if (parts.length == 2) {
          var targetCountry = allCountries.firstWhere(
            (x) => x.id == parts[0],
            orElse: () => c,
          );
          tariffWidgets.add(
            SelectableText(
              '  -> On ${targetCountry.name} (${parts[1]}): ${(v * 100).toInt()}%',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          );
        }
      }
    });

    if (tariffWidgets.isNotEmpty) {
      tradeWidgets.add(
        const Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text(
            'Active Tariffs:',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
        ),
      );
      tradeWidgets.addAll(tariffWidgets);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...tradeWidgets,
        const SizedBox(height: 8),
        SelectableText(
          'Avg Weight: ${avgW.toStringAsFixed(1)} kg | Avg Civ: ${avgCiv.toStringAsFixed(2)}',
        ),
        const SizedBox(height: 8),
        const Text(
          'Resource Prices (Local):',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        ...c.resources.values.map((r) {
          return SelectableText(
            '- ${r.type}: ${r.availableAmount.toStringAsFixed(0)} (Prod: +${r.annualProduction.toStringAsFixed(0)}) / Price: ${r.lastMarketPrice.toStringAsFixed(1)}',
          );
        }),
      ],
    );
  }
}
