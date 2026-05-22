import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'models.dart';

class SimulationEngine extends ChangeNotifier {
  late int currentYear;
  bool isSimulating = false;

  final Stopwatch _yieldTimer = Stopwatch();
  final Stopwatch _coolDownTimer = Stopwatch();
  final int ecoWaitMs = 100;

  // =================================================================
  // 【バランス調整用】 デバフ＆体重増減の定数設定エリア
  // =================================================================

  // ラウンドごとの取得量デバフ（Quality Multiplier）
  // インデックス番号がラウンド数に一致します（インデックス0は不使用）。
  // 例: 第1R=100%, 第2R=85%, 第3R=70%, 第4R(自国救済)=65%
  //最初の1.0はダミーなので、第1Rは2個目の1.0なので注意
  final List<double> roundQualityMultipliers = [1.0, 1.0, 0.85, 0.7, 0.65];

  // 食料充足率（Ratio）に基づく体重増減（線形補間）の定数
  final double foodWeightLossMax = 5.0; // Ratio 0.0 (絶食時) の減少量
  final double foodWeightGainMax = 2.0; // Ratio 1.0 (満腹時) の増加量

  // =================================================================

  SimulationEngine() {
    var settings = Hive.box('settings');
    if (settings.containsKey('currentYear')) {
      currentYear = settings.get('currentYear');
    } else {
      var logs = Hive.box<EventLog>('logs');
      currentYear = logs.isNotEmpty
          ? logs.values.map((e) => e.year).reduce(max) + 1
          : 1;
      settings.put('currentYear', currentYear);
    }
  }

  // グローバルなシミュレーション設定を読み込むゲッター
  SimulationSettings get simRules {
    var box = Hive.box('settings');
    return box.get('sim_rules') ?? SimulationSettings();
  }

  List<Country> get countries => Hive.box<Country>('countries').values.toList();
  Box<EventLog> get logBox => Hive.box<EventLog>('logs');

  // 地球共通両替所（AMM）の取得・初期化
  GlobalExchange get globalExchange {
    var box = Hive.box<GlobalExchange>('exchange');
    if (box.isEmpty) {
      box.add(GlobalExchange(liquidityPool: {}));
    }
    GlobalExchange exchange = box.values.first;

    // 初期流動性が空の場合は、各国通貨を注入
    if (exchange.liquidityPool.isEmpty) {
      for (var c in countries) {
        exchange.liquidityPool[c.currencyName] = 5000.0;
      }
      exchange.save();
    }
    return exchange;
  }

  void logUserAction(String message) {
    logBox.add(
      EventLog(
        year: currentYear,
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    if (logBox.length > 500) {
      final oldestKey = logBox.keys.first;
      logBox.delete(oldestKey);
    }

    notifyListeners();
  }

  Future<void> _yieldCpu() async {
    if (_coolDownTimer.elapsedMilliseconds > 500) {
      await Future.delayed(
        ecoWaitMs > 0 ? Duration(milliseconds: ecoWaitMs) : Duration.zero,
      );
      _coolDownTimer.reset();
      _yieldTimer.reset();
    } else if (_yieldTimer.elapsedMilliseconds > 14) {
      await Future.delayed(Duration.zero);
      _yieldTimer.reset();
    }
  }

  Future<void> advanceOneYear() async {
    if (isSimulating) return;
    isSimulating = true;
    notifyListeners();
    _yieldTimer.start();
    _coolDownTimer.start();

    final allCountries = countries;
    GlobalExchange exchange = globalExchange;
    SimulationSettings rules = simRules;

    Map<String, double> realGrossTradeVolumes = {
      for (var c in allCountries) c.id: 0.0,
    };

    // =================================================================
    // 動的HWIウェイト（重み）の事前計算
    // =================================================================
    int totalPopulation = allCountries.fold(
      0,
      (sum, c) => sum + c.residents.length,
    );

    Map<String, double> globalDemand = {
      'Wood':
          (rules.annualConsumption['Wood'] ?? 6.0) * max(1, totalPopulation),
      'Metal':
          (rules.annualConsumption['Metal'] ?? 5.0) * max(1, totalPopulation),
      'Oil': (rules.annualConsumption['Oil'] ?? 1.5) * max(1, totalPopulation),
    };

    Map<String, double> globalSupply = {'Wood': 0.0, 'Metal': 0.0, 'Oil': 0.0};
    for (var c in allCountries) {
      globalSupply['Wood'] =
          globalSupply['Wood']! +
          (c.resources['Wood']?.availableAmount ?? 0.0) +
          (c.resources['Wood']?.annualProduction ?? 0.0);
      globalSupply['Metal'] =
          globalSupply['Metal']! +
          (c.resources['Metal']?.availableAmount ?? 0.0) +
          (c.resources['Metal']?.annualProduction ?? 0.0);
      globalSupply['Oil'] =
          globalSupply['Oil']! +
          (c.resources['Oil']?.availableAmount ?? 0.0) +
          (c.resources['Oil']?.annualProduction ?? 0.0);
      for (var r in c.residents) {
        globalSupply['Wood'] = globalSupply['Wood']! + r.woodStock;
        globalSupply['Metal'] = globalSupply['Metal']! + r.metalStock;
        globalSupply['Oil'] = globalSupply['Oil']! + r.oilStock;
      }
    }

    double totalAnnualConsumption =
        (rules.annualConsumption['Food'] ?? 12.0) +
        (rules.annualConsumption['Wood'] ?? 6.0) +
        (rules.annualConsumption['Metal'] ?? 5.0) +
        (rules.annualConsumption['Oil'] ?? 1.5);

    double assetScoreMultiplier = 10.0;

    double getDynamicWeight(String rType) {
      double demand = globalDemand[rType]!;
      double supply = max(1.0, globalSupply[rType]!);
      double scarcityRatio = (demand / supply).clamp(0.2, 5.0);
      double shareInverse =
          totalAnnualConsumption /
          max(0.1, rules.annualConsumption[rType] ?? 1.0);
      return shareInverse * scarcityRatio * assetScoreMultiplier;
    }

    double dynWoodWeight = getDynamicWeight('Wood');
    double dynMetalWeight = getDynamicWeight('Metal');
    double dynOilWeight = getDynamicWeight('Oil');

    // --- 1. 資源の算出と住民の加齢・UBI分配 ---
    for (var c in allCountries) {
      c.exportLedger.clear();
      c.importLedger.clear();

      for (var entry in c.resources.entries) {
        await _yieldCpu();
        double depRate = rules.countryDepreciationRates[entry.key] ?? 0.0;
        entry.value.availableAmount =
            max(0.0, entry.value.availableAmount * (1.0 - depRate)) +
            entry.value.annualProduction;
      }

      for (var resident in c.residents) {
        await _yieldCpu();
        resident.lastYearActivities.clear();
        resident.previousWeight = resident.weight;
        resident.age += 1;

        if (resident.age >= 10) {
          double totalTaxPaid = 0.0;
          for (var cur in resident.wallet.keys.toList()) {
            double amt = resident.wallet[cur]! * c.inheritanceTaxRate;
            c.reserves[cur] = (c.reserves[cur] ?? 0.0) + amt;
            resident.wallet[cur] = resident.wallet[cur]! - amt;
            totalTaxPaid += amt;
          }

          double safeTaxRate = max(0.0, min(1.0, c.inheritanceTaxRate));
          double inheritRatio = 1.0 - safeTaxRate;
          double taxRatio = safeTaxRate;

          if (c.resources.containsKey('Wood'))
            c.resources['Wood']!.availableAmount +=
                resident.woodStock * taxRatio;
          if (c.resources.containsKey('Metal'))
            c.resources['Metal']!.availableAmount +=
                resident.metalStock * taxRatio;
          if (c.resources.containsKey('Oil'))
            c.resources['Oil']!.availableAmount += resident.oilStock * taxRatio;

          resident.woodStock = max(0.0, resident.woodStock * inheritRatio);
          resident.metalStock = max(0.0, resident.metalStock * inheritRatio);
          resident.oilStock = max(0.0, resident.oilStock * inheritRatio);

          resident.lastYearActivities.add(
            "Reincarnated. Inherited ${(inheritRatio * 100).toInt()}% of physical assets. Paid approx ${totalTaxPaid.toStringAsFixed(1)} tax in currencies.",
          );

          resident.age = 0;
          resident.weight = 60.0;
          resident.previousWeight = 60.0;
        }
      }

      // UBI事前計算
      List<double> preUbiFinancialWealths = [];
      for (var r in c.residents) {
        double w = 0.0;
        r.wallet.forEach((cur, amt) {
          double pLocal = exchange.liquidityPool[c.currencyName] ?? 1.0;
          double pForeign = exchange.liquidityPool[cur] ?? 1.0;
          if (pForeign <= 0.0) pForeign = 1.0;
          w += amt * (pLocal / pForeign);
        });
        preUbiFinancialWealths.add(max(0.0, w));
      }
      double preUbiAvgFinWealth =
          preUbiFinancialWealths.fold(0.0, (a, b) => a + b) /
          max(1, c.residents.length);

      List<double> preUbiHwi = [];
      double totalInverseHwi = 0.0;
      for (int i = 0; i < c.residents.length; i++) {
        Resident r = c.residents[i];
        double stockScore =
            (r.woodStock * dynWoodWeight) +
            (r.metalStock * dynMetalWeight) +
            (r.oilStock * dynOilWeight);
        double healthScore = max(0.0, (r.weight - 50.0) * 100.0);
        double ratio = preUbiAvgFinWealth > 0.0
            ? (preUbiFinancialWealths[i] / preUbiAvgFinWealth)
            : 0.0;
        double finScore = 1000.0 * (log(1.0 + max(0.0, ratio)) / ln2);

        double hwi = max(0.0, stockScore + healthScore + finScore);
        preUbiHwi.add(hwi);
        if (c.useProgressiveUbi) totalInverseHwi += 1.0 / max(1.0, hwi);
      }

      Map<String, double> ubiPool = {};
      double safePayoutRatio = max(0.0, min(1.0, c.ubiPayoutRatio));
      String localCur = c.currencyName;
      double amount = c.reserves[localCur] ?? 0.0;
      double payoutAmount = amount * safePayoutRatio;
      if (payoutAmount > 0) {
        ubiPool[localCur] = payoutAmount;
        c.reserves[localCur] = amount - payoutAmount;
      }

      for (int i = 0; i < c.residents.length; i++) {
        await _yieldCpu();
        Resident resident = c.residents[i];
        List<String> receivedUbi = [];

        double shareRatio = 0.0;
        if (c.residents.isNotEmpty) {
          if (c.useProgressiveUbi && totalInverseHwi > 0.0) {
            shareRatio = (1.0 / max(1.0, preUbiHwi[i])) / totalInverseHwi;
          } else {
            shareRatio = 1.0 / c.residents.length;
          }
        }

        for (var cur in ubiPool.keys) {
          double ubiAmt = ubiPool[cur]! * shareRatio;
          if (ubiAmt > 0) {
            resident.wallet[cur] = (resident.wallet[cur] ?? 0.0) + ubiAmt;
            receivedUbi.add("${ubiAmt.toStringAsFixed(1)} $cur");
          }
        }

        if (receivedUbi.isNotEmpty) {
          String distType = c.useProgressiveUbi ? "Progressive" : "Flat";
          resident.lastYearActivities.add(
            "Received UBI ($distType): ${receivedUbi.join(', ')}",
          );
        }

        double woodDep = rules.residentDepreciationRates['Wood'] ?? 0.10;
        double metalDep = rules.residentDepreciationRates['Metal'] ?? 0.05;
        double oilDep = rules.residentDepreciationRates['Oil'] ?? 1.0;

        resident.woodStock = max(0.0, resident.woodStock * (1.0 - woodDep));
        resident.metalStock = max(0.0, resident.metalStock * (1.0 - metalDep));
        resident.oilStock = max(0.0, resident.oilStock * (1.0 - oilDep));
      }
    }

    // --- 2. 国際オークション（最大4ラウンド制） ---
    var settingsBox = Hive.box('settings');
    double woodThreshold = settingsBox.get(
      'civWoodThreshold',
      defaultValue: 20.0,
    );
    double metalThreshold = settingsBox.get(
      'civMetalThreshold',
      defaultValue: 30.0,
    );

    List<String> resTypes = ['Food', 'Wood', 'Metal', 'Oil'];
    for (String rType in resTypes) {
      await _yieldCpu();

      Set<Resident> securedResidents = {};
      Map<Resident, Set<String>> visitedCountries = {};

      // 食料の充足率を管理するマップ（柔軟な体重増減用）
      Map<Resident, double> foodObtainedRatios = {};

      Map<String, double> latestClearingPrices = {
        for (var c in allCountries) c.id: c.resources[rType]!.lastMarketPrice,
      };
      Map<String, int> totalBiddersAcrossRounds = {
        for (var c in allCountries) c.id: 0,
      };

      // 食料のみ自国救済用の4ラウンド目を設ける
      int maxRounds = (rType == 'Food') ? 4 : 3;

      for (int round = 1; round <= maxRounds; round++) {
        await _yieldCpu();
        Map<String, List<Map<String, dynamic>>> marketBids = {
          for (var c in allCountries) c.id: [],
        };

        // 当ラウンドの品質デバフ倍率を取得
        double qualityMultiplier = roundQualityMultipliers[round];

        // --- 買手側の入札先決定 ---
        for (var buyerC in allCountries) {
          String buyerLocal = buyerC.currencyName;
          double poolIn = exchange.liquidityPool[buyerLocal] ?? 1.0;

          for (var resident in buyerC.residents) {
            await _yieldCpu();
            if (securedResidents.contains(resident)) continue;

            double requiredAmount = rules.annualConsumption[rType] ?? 10.0;
            bool wantsToBuy = false;

            if (rType == 'Food') {
              wantsToBuy = true;
            } else if (rType == 'Wood') {
              if (resident.civilizationLevel == 1) {
                wantsToBuy = true;
              } else if (resident.civilizationLevel >= 2) {
                double depRate =
                    rules.residentDepreciationRates['Wood'] ?? 0.30;
                if ((resident.woodStock * (1.0 - depRate)) <= woodThreshold)
                  wantsToBuy = true;
              }
            } else if (rType == 'Metal') {
              if (resident.civilizationLevel == 2) {
                wantsToBuy = true;
              } else if (resident.civilizationLevel >= 3) {
                double depRate =
                    rules.residentDepreciationRates['Metal'] ?? 0.40;
                if ((resident.metalStock * (1.0 - depRate)) <= metalThreshold)
                  wantsToBuy = true;
              }
            } else if (rType == 'Oil') {
              if (resident.civilizationLevel >= 3) wantsToBuy = true;
            }

            if (!wantsToBuy) continue;

            visitedCountries.putIfAbsent(resident, () => {});

            // 餓死寸前での非食料入札スキップ判定 (ログ重複を避けるため初回のみ記録)
            if (rType != 'Food' && resident.weight < 50.0) {
              if (visitedCountries[resident]!.isEmpty) {
                resident.lastYearActivities.add(
                  "Too frail to care about $rType (Weight: ${resident.weight.toStringAsFixed(1)}kg). Survival comes first.",
                );
                visitedCountries[resident]!.add('STARVING');
              }
              continue;
            }

            if (round == 4 && rType == 'Food') {
              // ラウンド4: 自国市場への泣きつき（国内在庫がある場合のみ）
              if (!visitedCountries[resident]!.contains(buyerC.id)) {
                double localAvailable =
                    buyerC.resources[rType]!.availableAmount;
                if (localAvailable >= requiredAmount) {
                  double tariff = buyerC.tariffs['${buyerC.id}:$rType'] ?? 0.0;
                  double localBudget = resident.wallet[buyerLocal] ?? 0.0;
                  double wtpS = localBudget / (1 + tariff);

                  visitedCountries[resident]!.add(buyerC.id);
                  marketBids[buyerC.id]!.add({
                    'resident': resident,
                    'buyerC': buyerC,
                    'wtpS': wtpS,
                    'amount': requiredAmount,
                    'rand': Random().nextDouble(),
                  });
                }
              }
            } else if (round <= 3) {
              // ラウンド1-3: 未訪問の国から最も安く買えそうな場所を探す
              Country? bestSeller;
              double bestEstCost = double.infinity;

              var shuffledSellers = allCountries.toList()..shuffle(Random());
              for (var sellerC in shuffledSellers) {
                if (visitedCountries[resident]!.contains(sellerC.id)) continue;
                if (sellerC.resources[rType]!.availableAmount < requiredAmount)
                  continue;

                // 全面禁輸、またはターゲット国指定の禁輸に引っかかる場合はスキップ
                if (buyerC.id != sellerC.id &&
                    ((sellerC.exportBans[rType] ?? false) ||
                        (sellerC.targetedExportBans['${buyerC.id}:$rType'] ??
                            false))) {
                  continue;
                }

                String sellerCur = sellerC.currencyName;
                double tariff = buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
                double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

                double estCost =
                    latestClearingPrices[sellerC.id]! *
                    (poolIn / poolOut) *
                    (1 + tariff);

                if (estCost < bestEstCost) {
                  bestEstCost = estCost;
                  bestSeller = sellerC;
                }
              }

              if (bestSeller != null) {
                String sellerCur = bestSeller.currencyName;
                double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;
                double tariff =
                    buyerC.tariffs['${bestSeller.id}:$rType'] ?? 0.0;

                double localBudget = resident.wallet[buyerLocal] ?? 0.0;
                if (rType != 'Food') localBudget *= 0.3;

                double wtpS = 0.0;
                if (buyerLocal == sellerCur) {
                  wtpS = localBudget / (1 + tariff);
                } else {
                  wtpS =
                      (localBudget * poolOut) /
                      (poolIn * (1 + tariff) + localBudget);
                }

                visitedCountries[resident]!.add(bestSeller.id);
                marketBids[bestSeller.id]!.add({
                  'resident': resident,
                  'buyerC': buyerC,
                  'wtpS': wtpS,
                  'amount': requiredAmount,
                  'rand': Random().nextDouble(),
                });
              }
            }
          }
        }

        // --- 売り手側の落札処理 ---
        for (var sellerC in allCountries) {
          await _yieldCpu();
          String sellerCur = sellerC.currencyName;
          var bids = marketBids[sellerC.id]!;
          if (bids.isEmpty) continue;

          totalBiddersAcrossRounds[sellerC.id] =
              totalBiddersAcrossRounds[sellerC.id]! + bids.length;

          bids.sort((a, b) {
            if (rType == 'Food' && sellerC.foodDomesticPriority) {
              bool aIsDomestic = a['buyerC'].id == sellerC.id;
              bool bIsDomestic = b['buyerC'].id == sellerC.id;
              if (aIsDomestic && !bIsDomestic) return -1;
              if (!aIsDomestic && bIsDomestic) return 1;
            }
            int cmp = b['wtpS'].compareTo(a['wtpS']);
            if (cmp == 0) return a['rand'].compareTo(b['rand']);
            return cmp;
          });

          var res = sellerC.resources[rType]!;
          double reqAmt = rules.annualConsumption[rType] ?? 10.0;
          int maxWinners = (res.availableAmount / reqAmt).floor();

          double currentPriceS = latestClearingPrices[sellerC.id]!;
          double clearingPriceS = currentPriceS;

          if (bids.length > maxWinners && maxWinners > 0) {
            clearingPriceS = max(1.0, bids[maxWinners - 1]['wtpS']);
          } else {
            clearingPriceS = max(1.0, min(currentPriceS, bids.last['wtpS']));
          }
          latestClearingPrices[sellerC.id] = clearingPriceS;

          int winnersCount = 0;
          for (var bid in bids) {
            Resident buyer = bid['resident'];
            Country buyerC = bid['buyerC'];
            String buyerLocal = buyerC.currencyName;

            if (winnersCount < maxWinners && bid['wtpS'] >= clearingPriceS) {
              double P = clearingPriceS;
              double shortage = max(0.0, P - (buyer.wallet[sellerCur] ?? 0.0));
              double inputNeeded = 0.0;
              double tariffAmt = 0.0;

              if (buyerLocal == sellerCur) {
                tariffAmt = P * (buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0);
                inputNeeded = P;
                if ((buyer.wallet[buyerLocal] ?? 0.0) >=
                    inputNeeded + tariffAmt) {
                  buyer.wallet[buyerLocal] =
                      buyer.wallet[buyerLocal]! - (inputNeeded + tariffAmt);
                  sellerC.reserves[sellerCur] =
                      (sellerC.reserves[sellerCur] ?? 0.0) + P;
                  buyerC.reserves[buyerLocal] =
                      (buyerC.reserves[buyerLocal] ?? 0.0) + tariffAmt;

                  if (rType == 'Food') {
                    foodObtainedRatios[buyer] = qualityMultiplier;
                  }

                  _executeTradeSuccess(
                    buyer,
                    buyerC,
                    sellerC,
                    res,
                    rType,
                    reqAmt,
                    inputNeeded + tariffAmt,
                    P,
                    round,
                    qualityMultiplier,
                  );
                  securedResidents.add(buyer);
                  winnersCount++;
                } else {
                  _executeTradeFailure(buyer, rType, sellerC, round);
                }
              } else {
                double poolIn = exchange.liquidityPool[buyerLocal] ?? 1.0;
                double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

                if (shortage > 0) {
                  if (poolOut <= shortage) continue;
                  inputNeeded = (poolIn * shortage) / (poolOut - shortage);
                }

                double tariffRate =
                    buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
                double fullLocalEq = (poolIn * P) / (poolOut - P);
                tariffAmt = fullLocalEq * tariffRate;

                if ((buyer.wallet[buyerLocal] ?? 0.0) >=
                    inputNeeded + tariffAmt) {
                  buyer.wallet[buyerLocal] =
                      buyer.wallet[buyerLocal]! - (inputNeeded + tariffAmt);
                  if (P - shortage > 0) {
                    buyer.wallet[sellerCur] =
                        buyer.wallet[sellerCur]! - (P - shortage);
                  }

                  if (shortage > 0) {
                    exchange.liquidityPool[buyerLocal] =
                        exchange.liquidityPool[buyerLocal]! + inputNeeded;
                    exchange.liquidityPool[sellerCur] =
                        exchange.liquidityPool[sellerCur]! - shortage;
                  }

                  sellerC.reserves[sellerCur] =
                      (sellerC.reserves[sellerCur] ?? 0.0) + P;
                  buyerC.reserves[buyerLocal] =
                      (buyerC.reserves[buyerLocal] ?? 0.0) + tariffAmt;

                  String impKey = "${sellerC.id}:$rType";
                  buyerC.importLedger[impKey] =
                      (buyerC.importLedger[impKey] ?? 0.0) + P;
                  String expKey = "${buyerC.id}:$rType";
                  sellerC.exportLedger[expKey] =
                      (sellerC.exportLedger[expKey] ?? 0.0) + P;

                  double tradePoints = 0.0;
                  if (rType == 'Food')
                    tradePoints = reqAmt * 10.0;
                  else if (rType == 'Wood')
                    tradePoints = reqAmt * 20.0;
                  else if (rType == 'Metal')
                    tradePoints = reqAmt * 50.0;
                  else if (rType == 'Oil')
                    tradePoints = reqAmt * 100.0;

                  realGrossTradeVolumes[buyerC.id] =
                      (realGrossTradeVolumes[buyerC.id] ?? 0.0) + tradePoints;
                  realGrossTradeVolumes[sellerC.id] =
                      (realGrossTradeVolumes[sellerC.id] ?? 0.0) + tradePoints;

                  if (rType == 'Food') {
                    foodObtainedRatios[buyer] = qualityMultiplier;
                  }

                  _executeTradeSuccess(
                    buyer,
                    buyerC,
                    sellerC,
                    res,
                    rType,
                    reqAmt,
                    inputNeeded + tariffAmt,
                    P,
                    round,
                    qualityMultiplier,
                  );
                  securedResidents.add(buyer);
                  winnersCount++;
                } else {
                  _executeTradeFailure(buyer, rType, sellerC, round);
                }
              }
            } else {
              buyer.lastYearActivities.add(
                "Outbid for $rType in ${sellerC.name} (Round $round). Bid: ${bid['wtpS'].toStringAsFixed(1)}, Cleared at: ${clearingPriceS.toStringAsFixed(1)} ${sellerC.currencyName}.",
              );
            }
          }
        }
      } // 全ラウンド終了

      // --- ラウンド終了後の全体判定＆ペナルティ付与＆体重計算 ---
      for (var buyerC in allCountries) {
        for (var resident in buyerC.residents) {
          bool wantedToBuy = visitedCountries[resident]?.isNotEmpty ?? false;

          if (rType == 'Food') {
            // 食料の体重増減計算（線形補間）
            double ratio = foodObtainedRatios[resident] ?? 0.0; // 買えなかった人は 0.0
            double weightRange = foodWeightLossMax + foodWeightGainMax;
            double weightChange = -foodWeightLossMax + (weightRange * ratio);

            resident.weight = min(70.0, resident.weight + weightChange);

            if (ratio == 0.0) {
              resident.lastYearActivities.add(
                "Ended up totally empty-handed for Food. Lost ${foodWeightLossMax.toStringAsFixed(1)}kg due to starvation. Dark times.",
              );
            } else if (weightChange < 0.0) {
              // 補間計算の結果、体重が減少した場合（粗悪品の摂取）
              resident.lastYearActivities.add(
                "Survived on low-quality Food. Lost ${weightChange.abs().toStringAsFixed(1)}kg.",
              );
            }
          } else {
            // Food以外の空振りペナルティ判定
            if (wantedToBuy &&
                !visitedCountries[resident]!.contains('STARVING') &&
                !securedResidents.contains(resident)) {
              resident.lastYearActivities.add(
                "Ended up totally empty-handed for $rType after $maxRounds grueling bidding rounds. Supply chains are brutal.",
              );
            }
          }
        }
      }

      // --- 価格更新処理 ---
      for (var sellerC in allCountries) {
        var res = sellerC.resources[rType]!;
        double clearingPriceAll = latestClearingPrices[sellerC.id]!;

        // 全ラウンドを通じて入札がゼロなら価格暴落
        if (totalBiddersAcrossRounds[sellerC.id] == 0) {
          double fallRate = (rType == 'Food') ? 0.01 : 0.50;
          clearingPriceAll = max(1.0, clearingPriceAll * fallRate);
        }

        double production = res.annualProduction;
        double surplus = res.availableAmount;
        double surplusRatio = (production > 0) ? (surplus / production) : 0.0;
        surplusRatio = min(0.99, surplusRatio);

        // 売れ残り比率に応じた割引
        double surplusBasedPrice = clearingPriceAll * (1.0 - surplusRatio);
        res.lastMarketPrice = max(
          1.0,
          min(clearingPriceAll, surplusBasedPrice),
        );
      }
    }

    // --- 3. マクロ経済の更新と履歴保存 ---
    exchange.save();
    double baseUsdLiquidity = exchange.liquidityPool['USD'] ?? 1.0;

    for (var c in allCountries) {
      double cLiquidity = exchange.liquidityPool[c.currencyName] ?? 1.0;
      c.currencyIndex = baseUsdLiquidity / cLiquidity;

      double avgW =
          c.residents.map((e) => e.weight).reduce((a, b) => a + b) /
          max(1, c.residents.length);
      double avgCiv =
          c.residents.map((e) => e.civilizationLevel).reduce((a, b) => a + b) /
          max(1, c.residents.length);

      Map<String, double> avgWallet = {};
      for (var r in c.residents) {
        r.wallet.forEach((key, value) {
          avgWallet[key] = (avgWallet[key] ?? 0.0) + value / c.residents.length;
        });
      }

      double residentLocalMoney = c.residents.fold(
        0.0,
        (sum, r) => sum + (r.wallet[c.currencyName] ?? 0.0),
      );
      double govtLocalMoney = c.reserves[c.currencyName] ?? 0.0;
      double totalDomesticMoney = govtLocalMoney + residentLocalMoney;

      double currentAmmLiquidity =
          exchange.liquidityPool[c.currencyName] ?? 0.0;
      double totalExp = c.exportLedger.values.fold(0.0, (a, b) => a + b);
      double totalImp = c.importLedger.values.fold(0.0, (a, b) => a + b);
      double netTradeBal = totalExp - totalImp;
      double grossTradeVol = realGrossTradeVolumes[c.id] ?? 0.0;

      List<double> financialWealths = [];
      for (var r in c.residents) {
        double totalWealthLocalEq = 0.0;
        r.wallet.forEach((cur, amt) {
          if (cur == c.currencyName) {
            totalWealthLocalEq += amt;
          } else {
            double pLocal = exchange.liquidityPool[c.currencyName] ?? 1.0;
            double pForeign = exchange.liquidityPool[cur] ?? 1.0;
            if (pForeign <= 0.0) pForeign = 1.0;
            totalWealthLocalEq += amt * (pLocal / pForeign);
          }
        });
        financialWealths.add(max(0.0, totalWealthLocalEq));
      }

      double totalFinWealth = financialWealths.fold(0.0, (a, b) => a + b);
      double avgFinWealth = totalFinWealth / max(1, financialWealths.length);

      List<double> hwiScores = [];
      for (int i = 0; i < c.residents.length; i++) {
        Resident r = c.residents[i];
        double stockScore =
            (r.woodStock * dynWoodWeight) +
            (r.metalStock * dynMetalWeight) +
            (r.oilStock * dynOilWeight);
        double healthScore = max(0.0, (r.weight - 50.0) * 100.0);
        double ratio = avgFinWealth > 0.0
            ? (financialWealths[i] / avgFinWealth)
            : 0.0;
        double financialScore = 1000.0 * (log(1.0 + max(0.0, ratio)) / ln2);
        double totalHwi = max(0.0, stockScore + healthScore + financialScore);
        hwiScores.add(totalHwi);
      }

      hwiScores.sort();
      double totalHwiSum = hwiScores.fold(0.0, (a, b) => a + b);
      double avgHwi = hwiScores.isNotEmpty
          ? totalHwiSum / hwiScores.length
          : 0.0;

      double gini = 0.0;
      if (totalHwiSum > 0 && hwiScores.isNotEmpty) {
        int n = hwiScores.length;
        double sumNumerator = 0.0;
        for (int i = 0; i < n; i++) {
          sumNumerator += (i + 1) * hwiScores[i];
        }
        gini = (2.0 * sumNumerator) / (n * totalHwiSum) - (n + 1.0) / n;
        gini = min(1.0, max(0.0, gini));
      }

      c.history.add(
        YearlyMetrics(
          year: currentYear,
          currencyIndex: c.currencyIndex,
          avgWeight: avgW,
          avgCivLevel: avgCiv,
          avgWallet: avgWallet,
          governmentReserves: Map.from(c.reserves),
          foodPrice: c.resources['Food']?.lastMarketPrice ?? 0.0,
          woodPrice: c.resources['Wood']?.lastMarketPrice ?? 0.0,
          metalPrice: c.resources['Metal']?.lastMarketPrice ?? 0.0,
          oilPrice: c.resources['Oil']?.lastMarketPrice ?? 0.0,
          ammLiquidity: currentAmmLiquidity,
          totalDomesticMoney: totalDomesticMoney,
          netTradeBalance: netTradeBal,
          grossTradeVolume: grossTradeVol,
          giniIndex: gini,
          avgHwi: avgHwi,
          woodInventory: c.resources['Wood']?.availableAmount ?? 0.0,
          metalInventory: c.resources['Metal']?.availableAmount ?? 0.0,
          oilInventory: c.resources['Oil']?.availableAmount ?? 0.0,
        ),
      );

      if (c.history.length > 100) {
        c.history.removeAt(0);
      }
      c.save();
    }

    for (var c in allCountries) {
      for (var r in c.residents) r.save();
    }

    currentYear++;
    Hive.box('settings').put('currentYear', currentYear);

    isSimulating = false;
    _yieldTimer.stop();
    _coolDownTimer.stop();
    notifyListeners();
  }

  void _executeTradeSuccess(
    Resident buyer,
    Country buyerC,
    Country sellerC,
    ResourceInfo res,
    String rType,
    double reqAmt,
    double totalCostLocal,
    double marketPriceForeign,
    int round,
    double qualityMultiplier,
  ) {
    // 在庫は品質に関わらず正規の量が引かれる（不良品も在庫として消費）
    res.availableAmount -= reqAmt;

    // 実際に住民の手に入る量は品質デバフを適用
    if (rType == 'Wood')
      buyer.woodStock += reqAmt * qualityMultiplier;
    else if (rType == 'Metal')
      buyer.metalStock += reqAmt * qualityMultiplier;
    else if (rType == 'Oil')
      buyer.oilStock += reqAmt * qualityMultiplier;

    String tradeType = (buyerC.id == sellerC.id)
        ? "locally"
        : "from ${sellerC.name}";
    String qualityNote = qualityMultiplier < 1.0
        ? " (Quality: ${(qualityMultiplier * 100).toInt()}%)"
        : "";

    buyer.lastYearActivities.add(
      "Scored $rType $tradeType in Round $round$qualityNote for approx ${totalCostLocal.toStringAsFixed(1)} ${buyerC.currencyName} (Market: ${marketPriceForeign.toStringAsFixed(1)} ${sellerC.currencyName}).",
    );
  }

  void _executeTradeFailure(
    Resident buyer,
    String rType,
    Country sellerC,
    int round,
  ) {
    buyer.lastYearActivities.add(
      "Card declined! Insufficient post-swap funds to buy $rType from ${sellerC.name} (Round $round). Currency slippage hurts.",
    );
  }

  void applyHelicopterMoney(Country c, double amount) {
    for (var r in c.residents) {
      r.wallet[c.currencyName] = (r.wallet[c.currencyName] ?? 0.0) + amount;
      r.save();
    }
    logUserAction(
      'Helicopter Money: Added $amount ${c.currencyName} to all residents in ${c.name}',
    );
    notifyListeners();
  }

  void updateTariff(Country from, Country to, String resType, double rate) {
    String key = '${to.id}:$resType';
    double old = from.tariffs[key] ?? 0.0;
    from.tariffs[key] = rate;
    from.save();
    logUserAction(
      'Tariff Update: ${from.name} changed tariff on ${to.name}\'s $resType from ${(old * 100).toInt()}% to ${(rate * 100).toInt()}%',
    );
    notifyListeners();
  }

  void updateTax(Country c, double rate) {
    double old = c.inheritanceTaxRate;
    c.inheritanceTaxRate = rate;
    c.save();
    logUserAction(
      'Tax Update: ${c.name} changed Inheritance Tax from ${(old * 100).toInt()}% to ${(rate * 100).toInt()}%',
    );
    notifyListeners();
  }

  void updateExportBan(Country c, String resType, bool isBanned) {
    c.exportBans[resType] = isBanned;
    c.save();
    String status = isBanned ? "banned" : "allowed";
    logUserAction(
      'Policy Update: ${c.name} has $status the export of $resType.',
    );
    notifyListeners();
  }

  void updateTargetedExportBan(
    Country from,
    Country to,
    String resType,
    bool isBanned,
  ) {
    String key = '${to.id}:$resType';
    from.targetedExportBans[key] = isBanned;
    from.save();

    String action = isBanned ? "embargoed" : "lifted the embargo on";
    logUserAction(
      'Sanctions Update: ${from.name} has $action $resType exports to ${to.name}.',
    );
    notifyListeners();
  }

  void updateFoodDomesticPriority(Country c, bool isPrioritized) {
    c.foodDomesticPriority = isPrioritized;
    c.save();
    String status = isPrioritized ? "enabled" : "disabled";
    logUserAction(
      'Policy Update: ${c.name} has $status Food Domestic Priority.',
    );
    notifyListeners();
  }

  void updateUbiPayoutRatio(Country c, double ratio) {
    double old = c.ubiPayoutRatio;
    c.ubiPayoutRatio = max(0.0, min(1.0, ratio));
    c.save();
    logUserAction(
      'Policy Update: ${c.name} changed UBI Payout Ratio from ${(old * 100).toInt()}% to ${(c.ubiPayoutRatio * 100).toInt()}%',
    );
    notifyListeners();
  }

  void updateProgressiveUbi(Country c, bool isProgressive) {
    c.useProgressiveUbi = isProgressive;
    c.save();
    String status = isProgressive
        ? "Progressive (Welfare)"
        : "Flat (Universal)";
    logUserAction(
      'Policy Update: ${c.name} changed UBI Distribution to $status.',
    );
    notifyListeners();
  }

  void executeCurrencyIntervention(
    Country c,
    String sourceCur,
    String targetCur,
    double amount,
  ) {
    GlobalExchange exchange = globalExchange;
    double poolIn = exchange.liquidityPool[sourceCur] ?? 0.0;
    double poolOut = exchange.liquidityPool[targetCur] ?? 0.0;

    if (poolIn <= 0 || poolOut <= 0 || amount <= 0) return;

    double currentReserveSrc = c.reserves[sourceCur] ?? 0.0;
    if (amount > currentReserveSrc) {
      amount = currentReserveSrc;
    }

    if (amount <= 0) return;

    double outAmount = (poolOut * amount) / (poolIn + amount);
    if (outAmount >= poolOut) {
      outAmount = poolOut * 0.99;
    }

    if (outAmount <= 0) return;

    c.reserves[sourceCur] = currentReserveSrc - amount;
    c.reserves[targetCur] = (c.reserves[targetCur] ?? 0.0) + outAmount;
    exchange.liquidityPool[sourceCur] = poolIn + amount;
    exchange.liquidityPool[targetCur] = poolOut - outAmount;

    c.save();
    exchange.save();

    String interventionType = (sourceCur == c.currencyName)
        ? "Devaluation (Export Boost)"
        : "Revaluation (Value Protection)";

    logUserAction(
      'Currency Intervention [$interventionType] by ${c.name}: '
      'Sold ${amount.toStringAsFixed(1)} $sourceCur for ${outAmount.toStringAsFixed(1)} $targetCur on Global AMM.',
    );

    notifyListeners();
  }

  String exportDashboardState() {
    StringBuffer b = StringBuffer();
    b.writeln('=== Multi-Currency AMM Dashboard: Year $currentYear ===');

    var exchange = globalExchange;
    b.writeln('--- Global Exchange Liquidity Pool ---');
    exchange.liquidityPool.forEach((cur, amt) {
      b.writeln('  $cur Pool: ${amt.toStringAsFixed(0)}');
    });
    b.writeln('--------------------------------------');

    double poolUsd = exchange.liquidityPool['USD'] ?? 1.0;

    for (var c in countries) {
      double avgW =
          c.residents.map((e) => e.weight).reduce((a, b) => a + b) / 10;
      double avgCiv =
          c.residents.map((e) => e.civilizationLevel).reduce((a, b) => a + b) /
          10;

      double poolLocal = exchange.liquidityPool[c.currencyName] ?? 1.0;
      double liveCurrencyIndex = poolLocal > 0 ? (poolUsd / poolLocal) : 0.0;

      b.writeln('Country: ${c.name} (${c.currencyName})');

      String resStr = c.reserves.entries
          .map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}')
          .join(', ');
      b.writeln('- Govt Reserves (Next UBI): [$resStr]');

      b.writeln(
        '- Avg Weight: ${avgW.toStringAsFixed(1)}kg | Avg Civ: ${avgCiv.toStringAsFixed(2)}',
      );
      b.writeln(
        '- Currency Strength Index: ${liveCurrencyIndex.toStringAsFixed(4)} (vs USD)',
      );

      if (c.history.isNotEmpty) {
        var lastMetrics = c.history.last;
        b.writeln(
          '- Gini Index: ${lastMetrics.giniIndex.toStringAsFixed(3)} | Avg HWI: ${lastMetrics.avgHwi.toStringAsFixed(1)}',
        );
      }

      b.writeln('- Resources (Amt / Market Price):');
      c.resources.forEach((k, v) {
        b.writeln(
          '  $k: ${v.availableAmount.toStringAsFixed(0)} / ${v.lastMarketPrice.toStringAsFixed(1)} ${c.currencyName}',
        );
      });
      b.writeln('--------------------------------');
    }
    return b.toString();
  }
}
