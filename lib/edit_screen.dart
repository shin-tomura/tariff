import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'engine.dart';
import 'models.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({Key? key}) : super(key: key);
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  String _entityType = 'Country';
  Country? _selectedCountry;
  Resident? _selectedResident;

  final _cNameCtrl = TextEditingController();
  final _rNameCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _woodCtrl = TextEditingController();
  final _metalCtrl = TextEditingController();
  final _oilCtrl = TextEditingController();

  final List<String> _globalCurrencies = ['USD', 'CNY', 'JPY'];
  final Map<String, TextEditingController> _reservesCtrls = {};
  final Map<String, TextEditingController> _walletCtrls = {};

  @override
  void initState() {
    super.initState();
    for (var cur in _globalCurrencies) {
      _reservesCtrls[cur] = TextEditingController();
      _walletCtrls[cur] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _cNameCtrl.dispose();
    _rNameCtrl.dispose();
    _weightCtrl.dispose();
    _woodCtrl.dispose();
    _metalCtrl.dispose();
    _oilCtrl.dispose();
    for (var ctrl in _reservesCtrls.values) {
      ctrl.dispose();
    }
    for (var ctrl in _walletCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _loadCountryData(Country c) {
    _selectedCountry = c;
    _cNameCtrl.text = c.name;
    for (var cur in _globalCurrencies) {
      _reservesCtrls[cur]?.text = (c.reserves[cur] ?? 0.0).toStringAsFixed(2);
    }
    setState(() {});
  }

  void _loadResidentData(Resident r) {
    _selectedResident = r;
    _rNameCtrl.text = r.name;
    _weightCtrl.text = r.weight.toStringAsFixed(2);
    _woodCtrl.text = r.woodStock.toStringAsFixed(2);
    _metalCtrl.text = r.metalStock.toStringAsFixed(2);
    _oilCtrl.text = r.oilStock.toStringAsFixed(2);

    // ★変更: 住民は自国通貨しか持てないため、自国通貨のみロードする
    String localCur = _selectedCountry!.currencyName;
    _walletCtrls[localCur]?.text = (r.wallet[localCur] ?? 0.0).toStringAsFixed(
      2,
    );

    setState(() {});
  }

  void _saveChanges(SimulationEngine engine) {
    List<String> changes = [];
    void checkNum(String label, double oldVal, double newVal) {
      if ((oldVal - newVal).abs() > 0.01) {
        changes.add(
          '$label from ${oldVal.toStringAsFixed(2)} to ${newVal.toStringAsFixed(2)}',
        );
      }
    }

    void checkStr(String label, String oldVal, String newVal) {
      if (oldVal != newVal && newVal.isNotEmpty) {
        changes.add('$label from "$oldVal" to "$newVal"');
      }
    }

    if (_entityType == 'Country' && _selectedCountry != null) {
      Country c = _selectedCountry!;
      String nName = _cNameCtrl.text.trim();

      checkStr('Name', c.name, nName);
      if (nName.isNotEmpty) c.name = nName;

      for (var cur in _globalCurrencies) {
        double oldVal = c.reserves[cur] ?? 0.0;
        double nVal = double.tryParse(_reservesCtrls[cur]!.text) ?? oldVal;
        checkNum('Reserves ($cur)', oldVal, nVal);
        c.reserves[cur] = nVal;
      }

      c.save();
      if (changes.isNotEmpty) {
        engine.logUserAction('Manual Edit [${c.id}]: ${changes.join(", ")}');
      }
    } else if (_entityType == 'Resident' && _selectedResident != null) {
      Resident r = _selectedResident!;
      String nName = _rNameCtrl.text.trim();
      double nW = double.tryParse(_weightCtrl.text) ?? r.weight;
      double nWood = double.tryParse(_woodCtrl.text) ?? r.woodStock;
      double nMetal = double.tryParse(_metalCtrl.text) ?? r.metalStock;
      double nOil = double.tryParse(_oilCtrl.text) ?? r.oilStock;

      checkStr('Name', r.name, nName);
      checkNum('Weight', r.weight, nW);
      checkNum('Wood', r.woodStock, nWood);
      checkNum('Metal', r.metalStock, nMetal);
      checkNum('Oil', r.oilStock, nOil);

      if (nName.isNotEmpty) r.name = nName;
      r.weight = nW;
      r.woodStock = nWood;
      r.metalStock = nMetal;
      r.oilStock = nOil;

      // ★変更: 住民は自国通貨のみセーブする
      String localCur = _selectedCountry!.currencyName;
      double oldVal = r.wallet[localCur] ?? 0.0;
      double nVal = double.tryParse(_walletCtrls[localCur]!.text) ?? oldVal;
      checkNum('Wallet ($localCur)', oldVal, nVal);
      r.wallet[localCur] = nVal;

      r.save();
      if (changes.isNotEmpty) {
        engine.logUserAction('Manual Edit [${r.id}]: ${changes.join(", ")}');
      }
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved and Logged!')));
    engine.notifyListeners();
  }

  void _showFoodPriorityDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    bool tempPriority = c.foodDomesticPriority;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Food Security in ${c.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'If enabled, domestic residents will have absolute priority to buy domestic food production before any is exported to other countries.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text(
                      'Domestic Priority',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    activeColor: Colors.tealAccent,
                    value: tempPriority,
                    onChanged: (val) {
                      setDialogState(() {
                        tempPriority = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  onPressed: () {
                    if (c.foodDomesticPriority != tempPriority) {
                      engine.updateFoodDomesticPriority(c, tempPriority);
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Food Security Policy updated!'),
                      ),
                    );
                  },
                  child: const Text('Confirm & Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showUbiPayoutRatioDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    final TextEditingController ratioCtrl = TextEditingController(
      text: (c.ubiPayoutRatio * 100).toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('UBI Payout Ratio in ${c.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the percentage of Government Reserves to distribute as UBI each year. The remainder stays in the government pool.\nValid range: 0.0 to 100.0',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ratioCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Payout Ratio (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              onPressed: () {
                double parsed = double.tryParse(ratioCtrl.text) ?? -1.0;
                if (parsed >= 0.0 && parsed <= 100.0) {
                  double newRatio = parsed / 100.0;
                  if (c.ubiPayoutRatio != newRatio) {
                    engine.updateUbiPayoutRatio(c, newRatio);
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('UBI Payout Ratio updated!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invalid input. Please enter a value between 0 and 100.',
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('Confirm & Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showUbiDistributionDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    bool isProgressive = c.useProgressiveUbi;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('UBI Distribution Model in ${c.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select how UBI is distributed among residents.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<bool>(
                    title: const Text('Flat (Universal)'),
                    subtitle: const Text(
                      'Everyone gets the exact same amount.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: false,
                    groupValue: isProgressive,
                    activeColor: Colors.deepOrange,
                    onChanged: (val) {
                      setDialogState(() {
                        isProgressive = val!;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    title: const Text('Progressive (Welfare)'),
                    subtitle: const Text(
                      'More money given to the poorest (based on HWI).',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: true,
                    groupValue: isProgressive,
                    activeColor: Colors.deepOrange,
                    onChanged: (val) {
                      setDialogState(() {
                        isProgressive = val!;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  onPressed: () {
                    if (c.useProgressiveUbi != isProgressive) {
                      engine.updateProgressiveUbi(c, isProgressive);
                    }
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('UBI Distribution Model updated!'),
                      ),
                    );
                  },
                  child: const Text('Confirm & Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showExportBanDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    List<String> resTypes = ['Food', 'Wood', 'Metal', 'Oil'];

    Map<String, bool> tempBans = {};
    for (var res in resTypes) {
      tempBans[res] = c.exportBans[res] ?? false;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Export Bans in ${c.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: resTypes.map((resType) {
                  return SwitchListTile(
                    title: Text(
                      'Ban $resType Export',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    activeColor: Colors.redAccent,
                    value: tempBans[resType] ?? false,
                    onChanged: (val) {
                      setDialogState(() {
                        tempBans[resType] = val;
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                  ),
                  onPressed: () {
                    tempBans.forEach((resType, isBanned) {
                      if ((c.exportBans[resType] ?? false) != isBanned) {
                        engine.updateExportBan(c, resType, isBanned);
                      }
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export Bans updated!')),
                    );
                  },
                  child: const Text('Confirm & Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTariffDialog(
    BuildContext context,
    SimulationEngine engine,
    Country from,
  ) {
    Map<String, double> tempTariffs = Map.from(from.tariffs);
    List<String> resTypes = ['Food', 'Wood', 'Metal', 'Oil'];
    Map<String, TextEditingController> ctrls = {};

    for (var to in engine.countries.where((c) => c.id != from.id)) {
      for (var resType in resTypes) {
        String key = '${to.id}:$resType';
        double currentRate = tempTariffs[key] ?? 0.0;
        ctrls[key] = TextEditingController(
          text: (currentRate * 100).toStringAsFixed(1),
        );
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Item-specific Tariffs by ${from.name}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    'Set the tariff rate (%) for each import.\nValid range: 0.0 to 1000.0 (1000%)',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                ...engine.countries.where((c) => c.id != from.id).map((to) {
                  return Card(
                    color: Colors.blueGrey[800],
                    child: ExpansionTile(
                      title: Text(
                        'Imports from ${to.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: resTypes.map((resType) {
                        String key = '${to.id}:$resType';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  resType,
                                  style: const TextStyle(color: Colors.amber),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: ctrls[key],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    labelText: 'Tariff (%)',
                                    border: OutlineInputBorder(),
                                    suffixText: '%',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              onPressed: () {
                bool hasError = false;
                Map<String, double> newRates = {};

                ctrls.forEach((key, ctrl) {
                  double parsed = double.tryParse(ctrl.text) ?? -1.0;
                  if (parsed >= 0.0 && parsed <= 1000.0) {
                    newRates[key] = parsed / 100.0;
                  } else {
                    hasError = true;
                  }
                });

                if (hasError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invalid input. Enter values between 0 and 1000.',
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                newRates.forEach((key, rate) {
                  if ((from.tariffs[key] ?? 0.0) != rate) {
                    var parts = key.split(':');
                    if (parts.length == 2) {
                      engine.updateTariff(
                        from,
                        engine.countries.firstWhere((c) => c.id == parts[0]),
                        parts[1],
                        rate,
                      );
                    }
                  }
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Item-specific Tariffs enacted!'),
                  ),
                );
              },
              child: const Text('Confirm & Apply'),
            ),
          ],
        );
      },
    );
  }

  void _showTaxDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    final TextEditingController taxCtrl = TextEditingController(
      text: (c.inheritanceTaxRate * 100).toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Inheritance Tax in ${c.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set the inheritance tax rate (%).\nValid range: 0.0 to 100.0',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: taxCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tax Rate (%)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              onPressed: () {
                double parsed = double.tryParse(taxCtrl.text) ?? -1.0;

                if (parsed >= 0.0 && parsed <= 100.0) {
                  double newRate = parsed / 100.0;
                  if (c.inheritanceTaxRate != newRate) {
                    engine.updateTax(c, newRate);
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tax reform officially enacted!'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Invalid input. Please enter a value between 0 and 100.',
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('Confirm & Apply'),
            ),
          ],
        );
      },
    );
  }

  // ★追加: 為替介入（Currency Intervention）のダイアログ
  void _showInterventionDialog(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    String sourceCurrency = c.currencyName; // デフォルトは自国通貨売り
    String targetCurrency = _globalCurrencies.firstWhere(
      (cur) => cur != c.currencyName,
    );
    final TextEditingController amountCtrl = TextEditingController(
      text: '1000',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double currentReserves = c.reserves[sourceCurrency] ?? 0.0;

            return AlertDialog(
              title: Text('Currency Intervention by ${c.name}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Directly swap government reserves on the Global AMM to manipulate exchange rates.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Sell (Source):'),
                              DropdownButton<String>(
                                value: sourceCurrency,
                                items: _globalCurrencies.map((cur) {
                                  return DropdownMenuItem(
                                    value: cur,
                                    child: Text(cur),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      sourceCurrency = val;
                                      if (sourceCurrency == targetCurrency) {
                                        targetCurrency = _globalCurrencies
                                            .firstWhere(
                                              (c) => c != sourceCurrency,
                                            );
                                      }
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Buy (Target):'),
                              DropdownButton<String>(
                                value: targetCurrency,
                                items: _globalCurrencies.map((cur) {
                                  return DropdownMenuItem(
                                    value: cur,
                                    // 送金元と同じ通貨は選べないようにする
                                    enabled: cur != sourceCurrency,
                                    child: Text(
                                      cur,
                                      style: TextStyle(
                                        color: cur == sourceCurrency
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null && val != sourceCurrency) {
                                    setDialogState(() {
                                      targetCurrency = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Available $sourceCurrency Reserves: ${currentReserves.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Amount to Sell',
                        border: const OutlineInputBorder(),
                        suffixText: sourceCurrency,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      sourceCurrency == c.currencyName
                          ? '⚠️ This will devalue your currency (Boost Exports).'
                          : '⚠️ This will strengthen your currency (Protect Value).',
                      style: TextStyle(
                        color: sourceCurrency == c.currencyName
                            ? Colors.orangeAccent
                            : Colors.cyanAccent,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                  onPressed: () {
                    double amount = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amount > 0 && amount <= currentReserves) {
                      engine.executeCurrencyIntervention(
                        c,
                        sourceCurrency,
                        targetCurrency,
                        amount,
                      );
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Intervention executed: Sold $amount $sourceCurrency for $targetCurrency!',
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Invalid amount or insufficient reserves.',
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  child: const Text('Execute Intervention'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmHelicopterMoney(
    BuildContext context,
    SimulationEngine engine,
    Country c,
  ) {
    final TextEditingController amountCtrl = TextEditingController(
      text: '1000',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Helicopter Money'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Specify the amount to indiscriminately drop to ALL residents of ${c.name}.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount (${c.currencyName})',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.blueGrey[800],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
              onPressed: () {
                double amount = double.tryParse(amountCtrl.text) ?? 0.0;
                if (amount > 0) {
                  engine.applyHelicopterMoney(c, amount);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Helicopter Money (${amount.toStringAsFixed(0)} ${c.currencyName}) deployed in ${c.name}!',
                      ),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid positive amount.'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('Deploy Funds'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Parameters & Policies'),
        backgroundColor: Colors.blueGrey[900],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: _entityType,
              isExpanded: true,
              items: ['Country', 'Resident']
                  .map(
                    (e) =>
                        DropdownMenuItem(value: e, child: Text('Edit $e Data')),
                  )
                  .toList(),
              onChanged: (val) => setState(() {
                _entityType = val!;
                _selectedCountry = null;
                _selectedResident = null;
              }),
            ),
            const SizedBox(height: 16),

            if (_entityType == 'Country') ...[
              DropdownButton<Country>(
                hint: const Text('Select Country'),
                isExpanded: true,
                value: _selectedCountry,
                items: engine.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => _loadCountryData(c!),
              ),
              if (_selectedCountry != null) ...[
                const SizedBox(height: 16),
                _buildStringField('Country Name', _cNameCtrl),

                const SizedBox(height: 16),
                const Text(
                  'Government Reserves:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                for (var cur in _globalCurrencies)
                  _buildNumField('Reserve: $cur', _reservesCtrls[cur]!),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.deepOrange,
                    ),
                    onPressed: () => _saveChanges(engine),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const Divider(height: 50, thickness: 2),
                const Text(
                  'Country Policies & Actions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.security),
                      label: const Text('Set Item Tariffs'),
                      onPressed: () =>
                          _showTariffDialog(context, engine, _selectedCountry!),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.account_balance),
                      label: const Text('Set Inheritance Tax'),
                      onPressed: () =>
                          _showTaxDialog(context, engine, _selectedCountry!),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.block),
                      label: const Text('Export Bans'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[900],
                      ),
                      onPressed: () => _showExportBanDialog(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.food_bank),
                      label: const Text('Food Security'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[700],
                      ),
                      onPressed: () => _showFoodPriorityDialog(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.percent),
                      label: const Text('Set UBI Payout Ratio'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[700],
                      ),
                      onPressed: () => _showUbiPayoutRatioDialog(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.balance),
                      label: const Text('UBI Distribution Model'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[600],
                      ),
                      onPressed: () => _showUbiDistributionDialog(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                    // ★追加: 為替介入ボタン
                    ElevatedButton.icon(
                      icon: const Icon(Icons.currency_exchange),
                      label: const Text('Currency Intervention'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent[700],
                      ),
                      onPressed: () => _showInterventionDialog(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.attach_money),
                      label: const Text('Helicopter Money'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                      ),
                      onPressed: () => _confirmHelicopterMoney(
                        context,
                        engine,
                        _selectedCountry!,
                      ),
                    ),
                  ],
                ),
              ],
            ],

            if (_entityType == 'Resident') ...[
              DropdownButton<Country>(
                hint: const Text('Filter by Country'),
                isExpanded: true,
                value: _selectedCountry,
                items: engine.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => setState(() {
                  _selectedCountry = c;
                  _selectedResident = null;
                }),
              ),
              if (_selectedCountry != null)
                DropdownButton<Resident>(
                  hint: const Text('Select Resident'),
                  isExpanded: true,
                  value: _selectedResident,
                  items: _selectedCountry!.residents
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                      )
                      .toList(),
                  onChanged: (r) => _loadResidentData(r!),
                ),
              if (_selectedResident != null) ...[
                const SizedBox(height: 16),
                _buildStringField('Resident Name', _rNameCtrl),
                _buildNumField('Weight', _weightCtrl),

                const SizedBox(height: 16),
                const Text(
                  'Resident Wallet (Local Currency Only):',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
                // ★変更: 自国通貨のウォレット欄のみを描画
                _buildNumField(
                  'Wallet: ${_selectedCountry!.currencyName}',
                  _walletCtrls[_selectedCountry!.currencyName]!,
                ),

                const SizedBox(height: 16),
                const Text(
                  'Resources:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
                _buildNumField('Wood Stock', _woodCtrl),
                _buildNumField('Metal Stock', _metalCtrl),
                _buildNumField('Oil Stock', _oilCtrl),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.deepOrange,
                    ),
                    onPressed: () => _saveChanges(engine),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNumField(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _buildStringField(String label, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextField(
      controller: ctrl,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.blueGrey[800],
      ),
    ),
  );
}
