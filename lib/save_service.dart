import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // Uint8List用に必要
import 'package:hive/hive.dart';
import 'models.dart';

class SaveService {
  // ==========================================
  // 1. クリップボード用（軽量スナップショット）
  // ==========================================

  /// 軽量データをクリップボード用のテキスト（Base64）として出力します
  static Future<String> exportLightweightToClipboard() async {
    final Map<String, dynamic> data = _gatherMasterData(isLightweight: true);

    final String jsonStr = jsonEncode(data);
    final List<int> utf8Bytes = utf8.encode(jsonStr);
    final List<int> compressedBytes = gzip.encode(utf8Bytes);
    final String base64SaveCode = base64Encode(compressedBytes);

    return 'HKNW-LIGHT-$base64SaveCode';
  }

  /// クリップボードのテキストから軽量データを復元します
  static Future<void> importLightweightFromClipboard(String code) async {
    if (!code.startsWith('HKNW-LIGHT-')) {
      throw Exception('無効なセーブコードです。HKNW-LIGHT- から始まる必要があります。');
    }

    final String base64Data = code.substring('HKNW-LIGHT-'.length).trim();
    final List<int> compressedBytes = base64Decode(base64Data);
    final List<int> decompressedBytes = gzip.decode(compressedBytes);
    final String jsonStr = utf8.decode(decompressedBytes);

    final Map<String, dynamic> masterData = jsonDecode(jsonStr);
    await _restoreMasterData(masterData);
  }

  // ==========================================
  // 2. ファイル用（完全データ）
  // ==========================================

  /// 完全データをファイル書き込み用のバイナリデータ（GZIP）として出力します
  static Future<Uint8List> exportFullToFile() async {
    final Map<String, dynamic> data = _gatherMasterData(isLightweight: false);

    final String jsonStr = jsonEncode(data);
    final List<int> utf8Bytes = utf8.encode(jsonStr);
    final List<int> compressedBytes = gzip.encode(utf8Bytes);

    // バイナリデータをそのまま返す（UI側でファイルとして保存する）
    return Uint8List.fromList(compressedBytes);
  }

  /// ファイルのバイナリデータから完全データを復元します
  static Future<void> importFullFromFile(Uint8List bytes) async {
    final List<int> decompressedBytes = gzip.decode(bytes);
    final String jsonStr = utf8.decode(decompressedBytes);

    final Map<String, dynamic> masterData = jsonDecode(jsonStr);
    await _restoreMasterData(masterData);
  }

  // ==========================================
  // 3. 共通の抽出・復元ロジック（プライベート）
  // ==========================================

  /// 現在のゲーム状態をJSON用のMapに抽出します
  static Map<String, dynamic> _gatherMasterData({required bool isLightweight}) {
    final cBox = Hive.box<Country>('countries');
    final rBox = Hive.box<Resident>('residents');
    final logBox = Hive.box<EventLog>('logs');
    final settingsBox = Hive.box('settings');
    final exchangeBox = Hive.box<GlobalExchange>('exchange');

    final Map<String, dynamic> masterData = {};

    masterData['currentYear'] = settingsBox.get('currentYear', defaultValue: 1);
    masterData['civWoodThreshold'] = settingsBox.get(
      'civWoodThreshold',
      defaultValue: 20.0,
    );
    masterData['civMetalThreshold'] = settingsBox.get(
      'civMetalThreshold',
      defaultValue: 30.0,
    );

    if (exchangeBox.isNotEmpty) {
      masterData['exchange'] = exchangeBox.values.first.liquidityPool;
    }

    final List<Map<String, dynamic>> countriesList = [];
    for (var c in cBox.values) {
      final Map<String, dynamic> cMap = {
        'id': c.id,
        'name': c.name,
        'currencyName': c.currencyName,
        'tariffs': c.tariffs,
        'inheritanceTaxRate': c.inheritanceTaxRate,
        'exportBans': c.exportBans,
        'foodDomesticPriority': c.foodDomesticPriority,
        'reserves': c.reserves,
        'currencyIndex': c.currencyIndex,
        'exportLedger': c.exportLedger,
        'importLedger': c.importLedger,
        'residentIds': c.residents.map((r) => r.id).toList(),
        // 資源データの抽出を正確に追記
        'resources': c.resources.map(
          (k, v) => MapEntry(k, {
            'type': v.type,
            'availableAmount': v.availableAmount,
            'annualProduction': v.annualProduction,
            'lastMarketPrice': v.lastMarketPrice,
          }),
        ),
      };

      if (!isLightweight) {
        cMap['history'] = c.history
            .map(
              (h) => {
                'year': h.year,
                'currencyIndex': h.currencyIndex,
                'avgWeight': h.avgWeight,
                'avgCivLevel': h.avgCivLevel,
                'avgWallet': h.avgWallet,
                'governmentReserves': h.governmentReserves,
                'foodPrice': h.foodPrice,
                'woodPrice': h.woodPrice,
                'metalPrice': h.metalPrice,
                'oilPrice': h.oilPrice,
                'ammLiquidity': h.ammLiquidity,
                'totalDomesticMoney': h.totalDomesticMoney,
                'netTradeBalance': h.netTradeBalance,
              },
            )
            .toList();
      } else {
        cMap['history'] = [];
      }
      countriesList.add(cMap);
    }
    masterData['countries'] = countriesList;

    final List<Map<String, dynamic>> residentsList = [];
    for (var r in rBox.values) {
      residentsList.add({
        'id': r.id,
        'name': r.name,
        'age': r.age,
        'weight': r.weight,
        'previousWeight': r.previousWeight,
        'wallet': r.wallet,
        'woodStock': r.woodStock,
        'metalStock': r.metalStock,
        'oilStock': r.oilStock,
        'lastYearActivities': isLightweight ? <String>[] : r.lastYearActivities,
      });
    }
    masterData['residents'] = residentsList;

    if (!isLightweight) {
      masterData['logs'] = logBox.values
          .map(
            (l) => {
              'year': l.year,
              'message': l.message,
              'timestamp': l.timestamp,
            },
          )
          .toList();
    } else {
      masterData['logs'] = [];
    }

    return masterData;
  }

  /// 読み込んだMapデータをHiveに復元（上書き）します
  static Future<void> _restoreMasterData(
    Map<String, dynamic> masterData,
  ) async {
    final cBox = Hive.box<Country>('countries');
    final rBox = Hive.box<Resident>('residents');
    final logBox = Hive.box<EventLog>('logs');
    final settingsBox = Hive.box('settings');
    final exchangeBox = Hive.box<GlobalExchange>('exchange');

    await cBox.clear();
    await rBox.clear();
    await logBox.clear();
    await exchangeBox.clear();

    await settingsBox.put('currentYear', masterData['currentYear']);
    await settingsBox.put('civWoodThreshold', masterData['civWoodThreshold']);
    await settingsBox.put('civMetalThreshold', masterData['civMetalThreshold']);

    if (masterData.containsKey('exchange')) {
      final Map<String, double> pool = Map<String, double>.from(
        (masterData['exchange'] as Map).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      );
      await exchangeBox.add(GlobalExchange(liquidityPool: pool));
    }

    final List<dynamic> resList = masterData['residents'];
    for (var rMap in resList) {
      final resident = Resident(
        id: rMap['id'],
        name: rMap['name'],
        age: rMap['age'],
        weight: (rMap['weight'] as num).toDouble(),
        previousWeight: (rMap['previousWeight'] as num).toDouble(),
        wallet: Map<String, double>.from(
          (rMap['wallet'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        woodStock: (rMap['woodStock'] as num).toDouble(),
        metalStock: (rMap['metalStock'] as num).toDouble(),
        oilStock: (rMap['oilStock'] as num).toDouble(),
        lastYearActivities: List<String>.from(rMap['lastYearActivities']),
      );
      await rBox.put(resident.id, resident);
    }

    final List<dynamic> countriesList = masterData['countries'];
    for (var cMap in countriesList) {
      final HiveList<Resident> hRes = HiveList(rBox);
      final List<dynamic> resIds = cMap['residentIds'];
      for (String rId in resIds) {
        final rObj = rBox.get(rId);
        if (rObj != null) hRes.add(rObj);
      }

      final List<YearlyMetrics> historyList = [];
      if (cMap['history'] != null) {
        for (var h in cMap['history']) {
          historyList.add(
            YearlyMetrics(
              year: h['year'],
              currencyIndex: (h['currencyIndex'] as num).toDouble(),
              avgWeight: (h['avgWeight'] as num).toDouble(),
              avgCivLevel: (h['avgCivLevel'] as num).toDouble(),
              avgWallet: Map<String, double>.from(
                (h['avgWallet'] as Map).map(
                  (k, v) => MapEntry(k, (v as num).toDouble()),
                ),
              ),
              governmentReserves: Map<String, double>.from(
                (h['governmentReserves'] as Map).map(
                  (k, v) => MapEntry(k, (v as num).toDouble()),
                ),
              ),
              foodPrice: (h['foodPrice'] as num).toDouble(),
              woodPrice: (h['woodPrice'] as num).toDouble(),
              metalPrice: (h['metalPrice'] as num).toDouble(),
              oilPrice: (h['oilPrice'] as num).toDouble(),
              ammLiquidity: (h['ammLiquidity'] as num).toDouble(),
              totalDomesticMoney: (h['totalDomesticMoney'] as num).toDouble(),
              netTradeBalance: (h['netTradeBalance'] as num).toDouble(),
            ),
          );
        }
      }

      final Map<String, ResourceInfo> resourcesMap = {};
      final Map<String, dynamic> resData = cMap['resources'] ?? {};
      final List<String> resourceKeys = ['Food', 'Wood', 'Metal', 'Oil'];
      for (var key in resourceKeys) {
        if (resData.containsKey(key)) {
          var rMap = resData[key];
          resourcesMap[key] = ResourceInfo(
            type: rMap['type'] ?? key,
            availableAmount: (rMap['availableAmount'] as num).toDouble(),
            annualProduction: (rMap['annualProduction'] as num).toDouble(),
            lastMarketPrice: (rMap['lastMarketPrice'] as num).toDouble(),
          );
        } else {
          resourcesMap[key] = ResourceInfo(
            type: key,
            availableAmount: 0,
            annualProduction: 10,
            lastMarketPrice: 1.0,
          );
        }
      }

      final country = Country(
        id: cMap['id'],
        name: cMap['name'],
        currencyName: cMap['currencyName'],
        tariffs: Map<String, double>.from(
          (cMap['tariffs'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        inheritanceTaxRate: (cMap['inheritanceTaxRate'] as num).toDouble(),
        exportBans: Map<String, bool>.from(cMap['exportBans']),
        foodDomesticPriority: cMap['foodDomesticPriority'] ?? false,
        reserves: Map<String, double>.from(
          (cMap['reserves'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        residents: hRes,
        resources: resourcesMap,
        currencyIndex: (cMap['currencyIndex'] as num).toDouble(),
        exportLedger: Map<String, double>.from(
          (cMap['exportLedger'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        importLedger: Map<String, double>.from(
          (cMap['importLedger'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        ),
        history: historyList,
      );

      await cBox.add(country);
    }

    if (masterData.containsKey('logs') && masterData['logs'] != null) {
      for (var lMap in masterData['logs']) {
        await logBox.add(
          EventLog(
            year: lMap['year'],
            message: lMap['message'],
            timestamp: lMap['timestamp'],
          ),
        );
      }
    }
  }
}
