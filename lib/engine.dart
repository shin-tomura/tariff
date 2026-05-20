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
    return box.get('sim_rules') ?? SimulationSettings(); // 設定がない場合はデフォルト値を返す
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

    // 今年の計算に使用するルール（年間消費量、消滅率）を取得
    SimulationSettings rules = simRules;

    // 実質貿易量（ポイント）を記録するマップの初期化
    Map<String, double> realGrossTradeVolumes = {
      for (var c in allCountries) c.id: 0.0,
    };

    // --- 1. 資源の算出と住民の加齢・UBI分配 ---
    for (var c in allCountries) {
      c.exportLedger.clear();
      c.importLedger.clear();

      for (var entry in c.resources.entries) {
        await _yieldCpu();

        // 国家（市場）が保有する資源の減価処理を動的に適用
        double depRate = rules.countryDepreciationRates[entry.key] ?? 0.0;
        // 現在の在庫から消滅率分を減らし、そこに今年の生産量を足す
        entry.value.availableAmount =
            max(0.0, entry.value.availableAmount * (1.0 - depRate)) +
            entry.value.annualProduction;
      }

      for (var resident in c.residents) {
        await _yieldCpu();
        resident.lastYearActivities.clear();
        resident.previousWeight = resident.weight;

        resident.age += 1;
        // 餓死判定を削除し、純粋な寿命(10歳)のみで転生
        if (resident.age >= 10) {
          // 没収分は金庫へ行き、自国通貨はUBI原資となる
          double totalTaxPaid = 0.0;
          for (var cur in resident.wallet.keys.toList()) {
            double amt = resident.wallet[cur]! * c.inheritanceTaxRate;
            c.reserves[cur] = (c.reserves[cur] ?? 0.0) + amt;
            resident.wallet[cur] = resident.wallet[cur]! - amt;
            totalTaxPaid += amt;
          }

          // --- 2. 実物資産の相続税処理 ---
          double safeTaxRate = max(0.0, min(1.0, c.inheritanceTaxRate));
          double inheritRatio = 1.0 - safeTaxRate; // 子孫が引き継げる割合
          double taxRatio = safeTaxRate; // 政府が没収する割合

          // 没収された資源は、国内の市場在庫（公売）に還元される
          if (c.resources.containsKey('Wood')) {
            c.resources['Wood']!.availableAmount +=
                resident.woodStock * taxRatio;
          }
          if (c.resources.containsKey('Metal')) {
            c.resources['Metal']!.availableAmount +=
                resident.metalStock * taxRatio;
          }
          if (c.resources.containsKey('Oil')) {
            c.resources['Oil']!.availableAmount += resident.oilStock * taxRatio;
          }

          // 残りは0歳の自分にそのまま引き継ぐ（フェイルセーフでマイナス防止）
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

      // =================================================================
      // UBI（分配金）の計算と傾斜配分のための事前HWI算出
      // =================================================================

      // 1. 分配前の平均金融資産を算出
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

      // 2. 分配前のHWI算出し、傾斜配分用の逆数合計を求める
      List<double> preUbiHwi = [];
      double totalInverseHwi = 0.0;
      for (int i = 0; i < c.residents.length; i++) {
        Resident r = c.residents[i];
        double stockScore =
            (r.woodStock * 20.0) + (r.metalStock * 50.0) + (r.oilStock * 100.0);
        double healthScore = max(0.0, (r.weight - 50.0) * 100.0);
        double ratio = preUbiAvgFinWealth > 0.0
            ? (preUbiFinancialWealths[i] / preUbiAvgFinWealth)
            : 0.0;
        double finScore = 1000.0 * (log(1.0 + max(0.0, ratio)) / ln2);

        double hwi = max(0.0, stockScore + healthScore + finScore);
        preUbiHwi.add(hwi);

        if (c.useProgressiveUbi) {
          totalInverseHwi += 1.0 / max(1.0, hwi);
        }
      }

      // 3. 政府準備高から、Payout Ratio に応じて分配用プールを抽出
      Map<String, double> ubiPool = {};
      double safePayoutRatio = max(0.0, min(1.0, c.ubiPayoutRatio));

      // UBIで国民に配るのは「自国通貨」のみに限定（外貨準備はプールに温存）
      String localCur = c.currencyName;
      double amount = c.reserves[localCur] ?? 0.0;
      double payoutAmount = amount * safePayoutRatio;
      if (payoutAmount > 0) {
        ubiPool[localCur] = payoutAmount;
        c.reserves[localCur] = amount - payoutAmount; // 残りを政府にプール
      }

      // 4. 各住民への実際の配布
      for (int i = 0; i < c.residents.length; i++) {
        await _yieldCpu();
        Resident resident = c.residents[i];
        List<String> receivedUbi = [];

        // 配分シェアの決定
        double shareRatio = 0.0;
        if (c.residents.isNotEmpty) {
          if (c.useProgressiveUbi && totalInverseHwi > 0.0) {
            shareRatio = (1.0 / max(1.0, preUbiHwi[i])) / totalInverseHwi;
          } else {
            shareRatio = 1.0 / c.residents.length; // 均等配分（フラット）
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

        // 住民が保有する資源の減価処理を動的に適用
        double woodDep = rules.residentDepreciationRates['Wood'] ?? 0.10;
        double metalDep = rules.residentDepreciationRates['Metal'] ?? 0.05;
        double oilDep = rules.residentDepreciationRates['Oil'] ?? 1.0;

        resident.woodStock = max(0.0, resident.woodStock * (1.0 - woodDep));
        resident.metalStock = max(0.0, resident.metalStock * (1.0 - metalDep));
        resident.oilStock = max(0.0, resident.oilStock * (1.0 - oilDep));
      }
    }

    // --- 2. 国際オークション（ゼロサム・トレード） ---
    // 文明レベルの閾値を先に取得
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
      Map<String, List<Map<String, dynamic>>> marketBids = {
        for (var c in allCountries) c.id: [],
      };

      // その資源を確保できた住民を追跡（食糧の2回目入札判定用）
      Set<Resident> securedResidents = {};

      // 買手ごとのWTP（支払意志額）の算出
      for (var buyerC in allCountries) {
        String buyerLocal = buyerC.currencyName;
        double poolIn = exchange.liquidityPool[buyerLocal] ?? 1.0;

        for (var resident in buyerC.residents) {
          await _yieldCpu();

          // 資源の要求量を設定モデルから取得
          double requiredAmount = rules.annualConsumption[rType] ?? 10.0;

          // 文明レベルと劣化速度を考慮した複数並行購入のロジック
          bool wantsToBuy = false;

          if (rType == 'Food') {
            wantsToBuy = true;
          } else if (rType == 'Wood') {
            if (resident.civilizationLevel == 1) {
              wantsToBuy = true; // レベル2を目指すために購入
            } else if (resident.civilizationLevel >= 2) {
              double depRate = rules.residentDepreciationRates['Wood'] ?? 0.30;
              double nextYearStock = resident.woodStock * (1.0 - depRate);
              // 消滅を考慮し、来年閾値を割り込む危険がある場合のみ維持のために購入
              if (nextYearStock <= woodThreshold) {
                wantsToBuy = true;
              }
            }
          } else if (rType == 'Metal') {
            if (resident.civilizationLevel == 2) {
              wantsToBuy = true; // レベル3を目指すために購入
            } else if (resident.civilizationLevel >= 3) {
              double depRate = rules.residentDepreciationRates['Metal'] ?? 0.40;
              double nextYearStock = resident.metalStock * (1.0 - depRate);
              // 消滅を考慮し、来年閾値を割り込む危険がある場合のみ維持のために購入
              if (nextYearStock <= metalThreshold) {
                wantsToBuy = true;
              }
            }
          } else if (rType == 'Oil') {
            if (resident.civilizationLevel >= 3) {
              wantsToBuy = true; // オイルは消費し続けるため購入
            }
          }

          if (wantsToBuy) {
            if (rType != 'Food' && resident.weight < 50.0) {
              resident.lastYearActivities.add(
                "Skipped bidding for $rType due to starvation (Weight: ${resident.weight.toStringAsFixed(1)}kg).",
              );
              continue;
            }

            Country? bestSeller;
            double bestEstCost = double.infinity;

            var shuffledSellers = allCountries.toList()..shuffle(Random());
            for (var sellerC in shuffledSellers) {
              if (sellerC.resources[rType]!.availableAmount < requiredAmount)
                continue;

              if (buyerC.id != sellerC.id &&
                  (sellerC.exportBans[rType] ?? false)) {
                continue;
              }

              String sellerCur = sellerC.currencyName;
              double tariff = buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
              double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

              double estCost =
                  sellerC.resources[rType]!.lastMarketPrice *
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
              double tariff = buyerC.tariffs['${bestSeller.id}:$rType'] ?? 0.0;

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

              marketBids[bestSeller.id]!.add({
                'resident': resident,
                'buyerC': buyerC,
                'wtpS': wtpS,
                'amount': requiredAmount,
                'rand': Random().nextDouble(),
              });
            } else {
              resident.lastYearActivities.add(
                "Failed to bid for $rType (No stock available globally).",
              );
              if (rType == 'Food') resident.weight -= 5.0;
            }
          }
        }
      }

      // 落札処理とAMMスワップ実行
      for (var sellerC in allCountries) {
        await _yieldCpu();
        String sellerCur = sellerC.currencyName;
        var bids = marketBids[sellerC.id]!;

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

        // 落札・消費される量を設定モデルから取得
        double reqAmt = rules.annualConsumption[rType] ?? 10.0;
        int maxWinners = (res.availableAmount / reqAmt).floor();

        double clearingPriceS = res.lastMarketPrice;
        if (bids.isNotEmpty) {
          if (bids.length > maxWinners && maxWinners > 0) {
            // 競争がある場合：落札ラインぎりぎりの限界価格を採用
            clearingPriceS = max(1.0, bids[maxWinners - 1]['wtpS']);
          } else {
            // 供給過剰（全員落札可能）な場合：独占高値を防ぐため、最低WTPか前回価格の安い方を採用
            clearingPriceS = max(
              1.0,
              min(res.lastMarketPrice, bids.last['wtpS']),
            );
          }
        } else {
          // 誰も買わなかった場合は暴落
          double fallRate = (rType == 'Food') ? 0.01 : 0.50;
          clearingPriceS = max(1.0, clearingPriceS * fallRate);
        }

        res.lastMarketPrice = clearingPriceS;

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
                _executeTradeSuccess(
                  buyer,
                  buyerC,
                  sellerC,
                  res,
                  rType,
                  reqAmt,
                  inputNeeded + tariffAmt,
                  P,
                  winnersCount,
                );
                securedResidents.add(buyer);
                winnersCount++;
              } else {
                _executeTradeFailure(buyer, rType, sellerC);
              }
            } else {
              double poolIn = exchange.liquidityPool[buyerLocal] ?? 1.0;
              double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

              if (shortage > 0) {
                if (poolOut <= shortage) continue;
                inputNeeded = (poolIn * shortage) / (poolOut - shortage);
              }

              double tariffRate = buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
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

                _executeTradeSuccess(
                  buyer,
                  buyerC,
                  sellerC,
                  res,
                  rType,
                  reqAmt,
                  inputNeeded + tariffAmt,
                  P,
                  winnersCount,
                );
                securedResidents.add(buyer);
                winnersCount++;
              } else {
                _executeTradeFailure(buyer, rType, sellerC);
              }
            }
          } else {
            buyer.lastYearActivities.add(
              "Lost bid for $rType in ${sellerC.name}. Bid: ${bid['wtpS'].toStringAsFixed(1)}, Market: ${clearingPriceS.toStringAsFixed(1)} ${sellerC.currencyName}.",
            );
            if (rType == 'Food') buyer.weight -= 5.0;
          }
        }

        if (rType == 'Food') {
          List<Map<String, dynamic>> round2Bids = [];
          double tariffRate = sellerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
          double clearingPriceS2 = 0.0;

          for (var resident in sellerC.residents) {
            if (securedResidents.contains(resident)) continue;

            double localBudget = resident.wallet[sellerCur] ?? 0.0;
            double wtpS = localBudget / (1 + tariffRate);

            round2Bids.add({
              'resident': resident,
              'wtpS': wtpS,
              'rand': Random().nextDouble(),
            });
          }

          if (round2Bids.isNotEmpty && res.availableAmount >= reqAmt) {
            round2Bids.sort((a, b) {
              int cmp = b['wtpS'].compareTo(a['wtpS']);
              if (cmp == 0) return a['rand'].compareTo(b['rand']);
              return cmp;
            });

            int maxWinners2 = (res.availableAmount / reqAmt).floor();

            if (round2Bids.length > maxWinners2 && maxWinners2 > 0) {
              clearingPriceS2 = max(1.0, round2Bids[maxWinners2 - 1]['wtpS']);
            } else {
              clearingPriceS2 = max(
                1.0,
                min(clearingPriceS, round2Bids.last['wtpS']),
              );
            }

            clearingPriceS2 = min(clearingPriceS, clearingPriceS2);

            for (var bid in round2Bids) {
              if (res.availableAmount < reqAmt) break;

              Resident resident = bid['resident'];
              if (bid['wtpS'] >= clearingPriceS2) {
                double P = clearingPriceS2;
                double tariffAmt = P * tariffRate;
                double totalCost = P + tariffAmt;

                if ((resident.wallet[sellerCur] ?? 0.0) >= totalCost) {
                  resident.wallet[sellerCur] =
                      resident.wallet[sellerCur]! - totalCost;
                  sellerC.reserves[sellerCur] =
                      (sellerC.reserves[sellerCur] ?? 0.0) + totalCost;

                  _executeTradeSuccess(
                    resident,
                    sellerC,
                    sellerC,
                    res,
                    rType,
                    reqAmt,
                    totalCost,
                    P,
                    winnersCount,
                  );
                  securedResidents.add(resident);
                  resident.weight = min(70.0, resident.weight + 5.0);
                  winnersCount++;
                }
              }
            }
          }

          double clearingPriceAll = clearingPriceS2 > 0.0
              ? clearingPriceS2
              : clearingPriceS;
          double production = res.annualProduction;
          double surplus = res.availableAmount;
          double surplusRatio = (production > 0) ? (surplus / production) : 0.0;
          surplusRatio = min(0.99, surplusRatio);

          double surplusBasedPrice = clearingPriceAll * (1.0 - surplusRatio);

          res.lastMarketPrice = max(
            1.0,
            min(clearingPriceAll, surplusBasedPrice),
          );
        }
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
            (r.woodStock * 20.0) + (r.metalStock * 50.0) + (r.oilStock * 100.0);
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

      // ★追加: ターン終了時の各資源の市場在庫量を記録
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
    int winnersCount,
  ) {
    res.availableAmount -= reqAmt;
    if (rType == 'Food')
      buyer.weight = min(70.0, buyer.weight + 2.0);
    else if (rType == 'Wood')
      buyer.woodStock += reqAmt;
    else if (rType == 'Metal')
      buyer.metalStock += reqAmt;
    else if (rType == 'Oil')
      buyer.oilStock += reqAmt;

    String tradeType = (buyerC.id == sellerC.id)
        ? "locally"
        : "from ${sellerC.name}";
    buyer.lastYearActivities.add(
      "Bought $rType $tradeType for approx ${totalCostLocal.toStringAsFixed(1)} ${buyerC.currencyName} (Market: ${marketPriceForeign.toStringAsFixed(1)} ${sellerC.currencyName}).",
    );
  }

  void _executeTradeFailure(Resident buyer, String rType, Country sellerC) {
    buyer.lastYearActivities.add(
      "Failed to buy $rType from ${sellerC.name} (Insufficient post-swap funds).",
    );
    if (rType == 'Food') buyer.weight -= 5.0;
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

    // フェイルセーフ: 政府の金庫にある売却通貨の在庫チェック
    double currentReserveSrc = c.reserves[sourceCur] ?? 0.0;
    if (amount > currentReserveSrc) {
      amount = currentReserveSrc;
    }

    if (amount <= 0) return;

    // AMM定数積モデル (X * Y = K) に基づくスワップ取得額の逆算
    // Delta Y = (Y * Delta X) / (X + Delta X)
    double outAmount = (poolOut * amount) / (poolIn + amount);

    // フェイルセーフ: 両替所（AMM）の枯渇回避（最大でもプールの99%に抑える）
    if (outAmount >= poolOut) {
      outAmount = poolOut * 0.99;
    }

    if (outAmount <= 0) return;

    // 政府の金庫（Reserves）の更新
    c.reserves[sourceCur] = currentReserveSrc - amount;
    c.reserves[targetCur] = (c.reserves[targetCur] ?? 0.0) + outAmount;

    // 地球共通両替所（AMM）プールの更新
    exchange.liquidityPool[sourceCur] = poolIn + amount;
    exchange.liquidityPool[targetCur] = poolOut - outAmount;

    // データの保存
    c.save();
    exchange.save();

    // ログの記録
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

    // 出力用のリアルタイムUSDプールの取得
    double poolUsd = exchange.liquidityPool['USD'] ?? 1.0;

    for (var c in countries) {
      double avgW =
          c.residents.map((e) => e.weight).reduce((a, b) => a + b) / 10;
      double avgCiv =
          c.residents.map((e) => e.civilizationLevel).reduce((a, b) => a + b) /
          10;

      // コピー出力用のテキストでもリアルタイムの為替レートを計算する
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
