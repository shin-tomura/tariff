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

  // 各資源の1年あたりの必要量（購入要求量）を定義したマップ
  final Map<String, double> requiredResourceAmounts = {
    'Food': 10.0,
    'Wood': 10.0,
    'Metal': 10.0,
    'Oil': 10.0,
  };

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

    // ★追加: ログが500件を超えたら一番古いものを削除してメモリを節約
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

    // --- 1. 資源の算出と住民の加齢・UBI分配 ---
    for (var c in allCountries) {
      c.exportLedger.clear();
      c.importLedger.clear();

      for (var entry in c.resources.entries) {
        await _yieldCpu();
        if (entry.key == 'Food') {
          // 食料は長持ちしないため、消費されなかった分は消滅し今年の生産量のみとなる
          entry.value.availableAmount = entry.value.annualProduction;
        } else {
          // それ以外の資源は在庫として蓄積される
          entry.value.availableAmount += entry.value.annualProduction;
        }
      }

      for (var resident in c.residents) {
        await _yieldCpu();
        resident.lastYearActivities.clear();
        resident.previousWeight = resident.weight;

        resident.age += 1;
        // 餓死判定を削除し、純粋な寿命(10歳)のみで転生
        if (resident.age >= 10) {
          double totalTaxPaid = 0.0;
          for (var cur in resident.wallet.keys.toList()) {
            double amt = resident.wallet[cur]! * c.inheritanceTaxRate;
            c.reserves[cur] = (c.reserves[cur] ?? 0.0) + amt;
            resident.wallet[cur] = resident.wallet[cur]! - amt;
            totalTaxPaid += amt;
          }

          resident.lastYearActivities.add(
            "Reincarnated (Lost wealth due to death). Paid approx ${totalTaxPaid.toStringAsFixed(1)} tax in various currencies.",
          );
          resident.age = 0;
          resident.weight = 60.0;
          resident.previousWeight = 60.0;
          resident.woodStock = 0.0;
          resident.metalStock = 0.0;
          resident.oilStock = 0.0;
        }
      }

      // UBI（分配金）の計算：政府の外貨準備高をすべて国民に分配する
      Map<String, double> ubiPerResident = {};
      if (c.residents.isNotEmpty) {
        for (var cur in c.reserves.keys) {
          double amount = c.reserves[cur] ?? 0.0;
          if (amount > 0) {
            ubiPerResident[cur] = amount / c.residents.length;
            c.reserves[cur] = 0.0; // 配布してリセット
          }
        }
      }

      for (var resident in c.residents) {
        await _yieldCpu();
        List<String> receivedUbi = [];
        for (var cur in ubiPerResident.keys) {
          double ubiAmt = ubiPerResident[cur]!;
          resident.wallet[cur] = (resident.wallet[cur] ?? 0.0) + ubiAmt;
          receivedUbi.add("${ubiAmt.toStringAsFixed(1)} $cur");
        }

        if (receivedUbi.isNotEmpty) {
          resident.lastYearActivities.add(
            "Received UBI: ${receivedUbi.join(', ')}",
          );
        }

        resident.woodStock = max(0, resident.woodStock * 0.90);
        resident.metalStock = max(0, resident.metalStock * 0.95);
        resident.oilStock = 0.0;
      }
    }

    // --- 2. 国際オークション（ゼロサム・トレード） ---
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

          double requiredAmount = requiredResourceAmounts[rType] ?? 10.0;

          String desiredRes = 'Wood';
          if (resident.civilizationLevel == 2)
            desiredRes = 'Metal';
          else if (resident.civilizationLevel == 3)
            desiredRes = 'Oil';

          if (rType == 'Food' || rType == desiredRes) {
            // 生存本能ロジック（体重50kg未満の飢餓状態なら、Food以外の入札を放棄してWTPを実質ゼロにする）
            if (rType != 'Food' && resident.weight < 50.0) {
              resident.lastYearActivities.add(
                "Skipped bidding for $rType due to starvation (Weight: ${resident.weight.toStringAsFixed(1)}kg).",
              );
              continue; // 予算ゼロ扱いとして入札処理自体をスキップ
            }

            Country? bestSeller;
            double bestEstCost = double.infinity;

            var shuffledSellers = allCountries.toList()..shuffle(Random());
            for (var sellerC in shuffledSellers) {
              if (sellerC.resources[rType]!.availableAmount < requiredAmount)
                continue;

              // 売り手国が自国以外かつ、対象品目の輸出を禁止している場合はスキップ
              if (buyerC.id != sellerC.id &&
                  (sellerC.exportBans[rType] ?? false)) {
                continue;
              }

              String sellerCur = sellerC.currencyName;
              double tariff = buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
              double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

              // AMMレートによる予想価格
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

              // 自国通貨の予算（Foodは全額、それ以外は30%）
              double localBudget = resident.wallet[buyerLocal] ?? 0.0;
              if (rType != 'Food') localBudget *= 0.3;

              double wtpS = 0.0;
              if (buyerLocal == sellerCur) {
                wtpS = localBudget / (1 + tariff);
              } else {
                // 定数積(AMM)の公式から、予算内で取得できる外貨の最大額を逆算
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
              // 餓死で即転生はしないが、ペナルティとして体重は減少する
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
          // 食料かつ自国民優先フラグがONの場合
          if (rType == 'Food' && sellerC.foodDomesticPriority) {
            bool aIsDomestic = a['buyerC'].id == sellerC.id;
            bool bIsDomestic = b['buyerC'].id == sellerC.id;

            // 自国民を無条件でWTPより優先して上位に持ってくる
            if (aIsDomestic && !bIsDomestic) return -1;
            if (!aIsDomestic && bIsDomestic) return 1;
          }

          int cmp = b['wtpS'].compareTo(a['wtpS']);
          if (cmp == 0) return a['rand'].compareTo(b['rand']);
          return cmp;
        });

        var res = sellerC.resources[rType]!;

        double reqAmt = requiredResourceAmounts[rType] ?? 10.0;
        int maxWinners = (res.availableAmount / reqAmt).floor();

        double clearingPriceS = res.lastMarketPrice;
        if (bids.isNotEmpty) {
          clearingPriceS = max(
            1.0,
            bids[min(bids.length - 1, maxWinners - 1)]['wtpS'],
          );
        } else {
          // 誰も入札しなかった場合、食糧は大暴落、食糧以外の資源については価格下落率を50パーセントに変更
          double fallRate = (rType == 'Food') ? 0.01 : 0.50;
          clearingPriceS = max(1.0, clearingPriceS * fallRate);
        }

        // 1回目のオークションのクリアリング価格を保存
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
                securedResidents.add(buyer); // 確保記録
                winnersCount++;
              } else {
                _executeTradeFailure(buyer, rType, sellerC);
              }
            } else {
              double poolIn = exchange.liquidityPool[buyerLocal] ?? 1.0;
              double poolOut = exchange.liquidityPool[sellerCur] ?? 1.0;

              if (shortage > 0) {
                if (poolOut <= shortage) continue; // AMM枯渇回避
                inputNeeded = (poolIn * shortage) / (poolOut - shortage);
              }

              // 関税は「自国通貨に換算したフルコスト」から計算
              double tariffRate = buyerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
              double fullLocalEq = (poolIn * P) / (poolOut - P);
              tariffAmt = fullLocalEq * tariffRate;

              if ((buyer.wallet[buyerLocal] ?? 0.0) >=
                  inputNeeded + tariffAmt) {
                // 買手の財布から引く
                buyer.wallet[buyerLocal] =
                    buyer.wallet[buyerLocal]! - (inputNeeded + tariffAmt);
                if (P - shortage > 0) {
                  buyer.wallet[sellerCur] =
                      buyer.wallet[sellerCur]! - (P - shortage);
                }

                // AMMプールの更新
                if (shortage > 0) {
                  exchange.liquidityPool[buyerLocal] =
                      exchange.liquidityPool[buyerLocal]! + inputNeeded;
                  exchange.liquidityPool[sellerCur] =
                      exchange.liquidityPool[sellerCur]! - shortage;
                }

                // 売手国と関税の徴収
                sellerC.reserves[sellerCur] =
                    (sellerC.reserves[sellerCur] ?? 0.0) + P;
                buyerC.reserves[buyerLocal] =
                    (buyerC.reserves[buyerLocal] ?? 0.0) + tariffAmt;

                // レジャー（帳簿）の更新
                String impKey = "${sellerC.id}:$rType";
                buyerC.importLedger[impKey] =
                    (buyerC.importLedger[impKey] ?? 0.0) + P;
                String expKey = "${buyerC.id}:$rType";
                sellerC.exportLedger[expKey] =
                    (sellerC.exportLedger[expKey] ?? 0.0) + P;

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
                securedResidents.add(buyer); // 確保記録
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

        // --- 食糧の2回目入札と余剰価格調整 ---
        if (rType == 'Food') {
          // 2回目入札の参加者（自国民のみ）とWTPをリスト化して再オークションを実施
          List<Map<String, dynamic>> round2Bids = [];
          double tariffRate = sellerC.tariffs['${sellerC.id}:$rType'] ?? 0.0;
          double clearingPriceS2 = 0.0;

          for (var resident in sellerC.residents) {
            // 十分な余剰がないか、既に確保できている人はスキップ
            if (securedResidents.contains(resident)) continue;

            // 手持ちの予算から、2回目の入札でのWTPを算出
            double localBudget = resident.wallet[sellerCur] ?? 0.0;
            double wtpS = localBudget / (1 + tariffRate);

            round2Bids.add({
              'resident': resident,
              'wtpS': wtpS,
              'rand': Random().nextDouble(),
            });
          }

          if (round2Bids.isNotEmpty && res.availableAmount >= reqAmt) {
            // 2回目の入札額でソート
            round2Bids.sort((a, b) {
              int cmp = b['wtpS'].compareTo(a['wtpS']);
              if (cmp == 0) return a['rand'].compareTo(b['rand']);
              return cmp;
            });

            int maxWinners2 = (res.availableAmount / reqAmt).floor();

            // 2回目のクリアリング価格（自国民の財布事情に合わせた適正価格）
            clearingPriceS2 = max(
              1.0,
              round2Bids[min(round2Bids.length - 1, maxWinners2 - 1)]['wtpS'],
            );

            // 1回目の暴騰価格（外国人の失敗入札など）よりは高くならないよう制限
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

                  // 過食バグの修正箇所: 1回目の失敗ペナルティ相殺時にも、70.0kgの上限を適用する
                  resident.weight = min(70.0, resident.weight + 5.0);

                  winnersCount++;
                }
              }
            }
          }

          // 2回目の入札が終わった後の余剰量率分価格を下落させる
          double clearingPriceAll;
          if (clearingPriceS2 > 0.0) {
            clearingPriceAll = clearingPriceS2;
          } else {
            clearingPriceAll = clearingPriceS;
          }
          double production = res.annualProduction;
          double surplus = res.availableAmount;
          double surplusRatio = (production > 0) ? (surplus / production) : 0.0;
          surplusRatio = min(0.99, surplusRatio); // 全量余っても99パーセントの下落率で留める

          double surplusBasedPrice = clearingPriceAll * (1.0 - surplusRatio);

          // 既存のロジックで既に決定された価格がこの余剰率から算出される価格よりも低ければ既存のロジックを採用 (最低価格は1.0)
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
      // 通貨インデックスは「AMM内のUSDとの比率」でリアルタイム算出
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

      // 国内の自国通貨総保有量（政府の外貨準備高 + 国民の財布）の計算
      double residentLocalMoney = c.residents.fold(
        0.0,
        (sum, r) => sum + (r.wallet[c.currencyName] ?? 0.0),
      );
      double govtLocalMoney = c.reserves[c.currencyName] ?? 0.0;
      double totalDomesticMoney = govtLocalMoney + residentLocalMoney;

      // 両替所の自国通貨プール量
      double currentAmmLiquidity =
          exchange.liquidityPool[c.currencyName] ?? 0.0;

      // 純輸出（貿易収支）の計算
      double totalExp = c.exportLedger.values.fold(0.0, (a, b) => a + b);
      double totalImp = c.importLedger.values.fold(0.0, (a, b) => a + b);
      double netTradeBal = totalExp - totalImp;

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
        ),
      );

      // ★追加: 履歴が100件を超えたら一番古い年を削除してメモリを節約
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
    // 上限を70kgとし、回復量を+2.0に設定
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
    // 食料が買えなかった場合は体重が減少するのみ
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

  // 輸出禁止措置の設定メソッド
  void updateExportBan(Country c, String resType, bool isBanned) {
    c.exportBans[resType] = isBanned;
    c.save();
    String status = isBanned ? "banned" : "allowed";
    logUserAction(
      'Policy Update: ${c.name} has $status the export of $resType.',
    );
    notifyListeners();
  }

  // 食料の自国民優先設定メソッド
  void updateFoodDomesticPriority(Country c, bool isPrioritized) {
    c.foodDomesticPriority = isPrioritized;
    c.save();
    String status = isPrioritized ? "enabled" : "disabled";
    logUserAction(
      'Policy Update: ${c.name} has $status Food Domestic Priority.',
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

    for (var c in countries) {
      double avgW =
          c.residents.map((e) => e.weight).reduce((a, b) => a + b) / 10;
      double avgCiv =
          c.residents.map((e) => e.civilizationLevel).reduce((a, b) => a + b) /
          10;

      b.writeln('Country: ${c.name} (${c.currencyName})');

      String resStr = c.reserves.entries
          .map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}')
          .join(', ');
      b.writeln('- Govt Reserves (Next UBI): [$resStr]');

      b.writeln(
        '- Avg Weight: ${avgW.toStringAsFixed(1)}kg | Avg Civ: ${avgCiv.toStringAsFixed(2)}',
      );
      b.writeln(
        '- Currency Strength Index: ${c.currencyIndex.toStringAsFixed(4)} (vs USD)',
      );

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
