import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'models.dart';

class AdvancedEditScreen extends StatefulWidget {
  const AdvancedEditScreen({Key? key}) : super(key: key);
  @override
  State<AdvancedEditScreen> createState() => _AdvancedEditScreenState();
}

class _AdvancedEditScreenState extends State<AdvancedEditScreen> {
  String _editCategory = 'Resources';
  Country? _selectedCountry;
  String? _selectedResourceType;
  Resident? _selectedResident;

  final _availAmtCtrl = TextEditingController();
  final _annualProdCtrl = TextEditingController();
  final _lastMarketPriceCtrl = TextEditingController();

  final _currencyNameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  final _civWoodCtrl = TextEditingController();
  final _civMetalCtrl = TextEditingController();

  final List<String> _globalCurrencies = ['USD', 'CNY', 'JPY'];
  final List<String> _resourceTypes = ['Food', 'Wood', 'Metal', 'Oil'];

  // 両替所の流動性プール編集用コントローラー
  final Map<String, TextEditingController> _poolCtrls = {};

  // ★追加: シミュレーションルール編集用コントローラー
  final Map<String, TextEditingController> _annualConsCtrls = {};
  final Map<String, TextEditingController> _resDepCtrls = {};
  final Map<String, TextEditingController> _ctyDepCtrls = {};

  @override
  void initState() {
    super.initState();
    for (var cur in _globalCurrencies) {
      _poolCtrls[cur] = TextEditingController();
    }
    for (var res in _resourceTypes) {
      _annualConsCtrls[res] = TextEditingController();
      _resDepCtrls[res] = TextEditingController();
      _ctyDepCtrls[res] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _availAmtCtrl.dispose();
    _annualProdCtrl.dispose();
    _lastMarketPriceCtrl.dispose();
    _currencyNameCtrl.dispose();
    _ageCtrl.dispose();
    _civWoodCtrl.dispose();
    _civMetalCtrl.dispose();
    for (var ctrl in _poolCtrls.values) {
      ctrl.dispose();
    }
    for (var res in _resourceTypes) {
      _annualConsCtrls[res]?.dispose();
      _resDepCtrls[res]?.dispose();
      _ctyDepCtrls[res]?.dispose();
    }
    super.dispose();
  }

  void _loadResourceData(Country c, String resType) {
    _selectedCountry = c;
    _selectedResourceType = resType;
    var res = c.resources[resType]!;
    _availAmtCtrl.text = res.availableAmount.toStringAsFixed(2);
    _annualProdCtrl.text = res.annualProduction.toStringAsFixed(2);
    _lastMarketPriceCtrl.text = res.lastMarketPrice.toStringAsFixed(2);
    setState(() {});
  }

  void _loadCountryBaseData(Country c) {
    _selectedCountry = c;
    _currencyNameCtrl.text = c.currencyName;
    setState(() {});
  }

  void _loadResidentBaseData(Resident r) {
    _selectedResident = r;
    _ageCtrl.text = r.age.toString();
    setState(() {});
  }

  void _loadGlobalSettings() {
    var settings = Hive.box('settings');
    _civWoodCtrl.text = settings
        .get('civWoodThreshold', defaultValue: 20.0)
        .toStringAsFixed(1);
    _civMetalCtrl.text = settings
        .get('civMetalThreshold', defaultValue: 30.0)
        .toStringAsFixed(1);
    setState(() {});
  }

  void _loadGlobalExchangeData(SimulationEngine engine) {
    var exchange = engine.globalExchange;
    for (var cur in _globalCurrencies) {
      _poolCtrls[cur]?.text = (exchange.liquidityPool[cur] ?? 0.0)
          .toStringAsFixed(2);
    }
    setState(() {});
  }

  // ★追加: シミュレーションルールの読み込み
  void _loadSimulationRules() {
    var settings = Hive.box('settings');
    SimulationSettings rules =
        settings.get('sim_rules') ?? SimulationSettings();
    for (var res in _resourceTypes) {
      _annualConsCtrls[res]?.text = (rules.annualConsumption[res] ?? 10.0)
          .toStringAsFixed(2);
      _resDepCtrls[res]?.text = (rules.residentDepreciationRates[res] ?? 0.0)
          .toStringAsFixed(2);
      _ctyDepCtrls[res]?.text = (rules.countryDepreciationRates[res] ?? 0.0)
          .toStringAsFixed(2);
    }
    setState(() {});
  }

  void _saveChanges(SimulationEngine engine) {
    List<String> changes = [];
    void _checkNum(String label, double oldVal, double newVal) {
      if ((oldVal - newVal).abs() > 0.01) {
        changes.add(
          '$label from ${oldVal.toStringAsFixed(2)} to ${newVal.toStringAsFixed(2)}',
        );
      }
    }

    void _checkInt(String label, int oldVal, int newVal) {
      if (oldVal != newVal) changes.add('$label from $oldVal to $newVal');
    }

    void _checkStr(String label, String oldVal, String newVal) {
      if (oldVal != newVal && newVal.isNotEmpty) {
        changes.add('$label from "$oldVal" to "$newVal"');
      }
    }

    if (_editCategory == 'Resources' &&
        _selectedCountry != null &&
        _selectedResourceType != null) {
      Country c = _selectedCountry!;
      var res = c.resources[_selectedResourceType!]!;

      double nAvail =
          double.tryParse(_availAmtCtrl.text) ?? res.availableAmount;
      double nProd =
          double.tryParse(_annualProdCtrl.text) ?? res.annualProduction;
      double nMarket =
          double.tryParse(_lastMarketPriceCtrl.text) ?? res.lastMarketPrice;

      _checkNum('${res.type} Supply', res.availableAmount, nAvail);
      _checkNum('${res.type} Annual Prod', res.annualProduction, nProd);
      _checkNum('${res.type} Base Price', res.lastMarketPrice, nMarket);

      res.availableAmount = nAvail;
      res.annualProduction = nProd;
      res.lastMarketPrice = nMarket;
      c.save();
      if (changes.isNotEmpty) {
        engine.logUserAction(
          'God Mode [${c.name} Resources]: ${changes.join(", ")}',
        );
      }
    } else if (_editCategory == 'Country Base' && _selectedCountry != null) {
      Country c = _selectedCountry!;
      String nCurr = _currencyNameCtrl.text.trim();
      _checkStr('Currency Name', c.currencyName, nCurr);
      if (nCurr.isNotEmpty) c.currencyName = nCurr;
      c.save();
      if (changes.isNotEmpty) {
        engine.logUserAction('God Mode [${c.name}]: ${changes.join(", ")}');
      }
    } else if (_editCategory == 'Resident Base' && _selectedResident != null) {
      Resident r = _selectedResident!;
      int nAge = int.tryParse(_ageCtrl.text) ?? r.age;
      _checkInt('Age', r.age, nAge);
      r.age = nAge;

      r.save();
      if (changes.isNotEmpty) {
        engine.logUserAction('God Mode [${r.name}]: ${changes.join(", ")}');
      }
    } else if (_editCategory == 'Global Settings') {
      var settings = Hive.box('settings');
      double oldWood = settings.get('civWoodThreshold', defaultValue: 20.0);
      double oldMetal = settings.get('civMetalThreshold', defaultValue: 30.0);

      double nWood = double.tryParse(_civWoodCtrl.text) ?? oldWood;
      double nMetal = double.tryParse(_civMetalCtrl.text) ?? oldMetal;

      _checkNum('Civ Lvl 2 (Wood) Threshold', oldWood, nWood);
      _checkNum('Civ Lvl 3 (Metal) Threshold', oldMetal, nMetal);

      settings.put('civWoodThreshold', nWood);
      settings.put('civMetalThreshold', nMetal);

      if (changes.isNotEmpty) {
        engine.logUserAction(
          'God Mode [Global Settings]: ${changes.join(", ")}',
        );
      }
    } else if (_editCategory == 'Global Exchange') {
      var exchange = engine.globalExchange;
      for (var cur in _globalCurrencies) {
        double oldVal = exchange.liquidityPool[cur] ?? 0.0;
        double nVal = double.tryParse(_poolCtrls[cur]!.text) ?? oldVal;
        if (nVal <= 0) nVal = 1.0;
        _checkNum('AMM Pool ($cur)', oldVal, nVal);
        exchange.liquidityPool[cur] = nVal;
      }
      exchange.save();
      if (changes.isNotEmpty) {
        engine.logUserAction(
          'God Mode [Global Exchange AMM]: ${changes.join(", ")}',
        );
      }
    } else if (_editCategory == 'Simulation Rules') {
      // ★追加: シミュレーションルールの保存
      var settings = Hive.box('settings');
      SimulationSettings rules =
          settings.get('sim_rules') ?? SimulationSettings();

      for (var res in _resourceTypes) {
        double oldCons = rules.annualConsumption[res] ?? 10.0;
        double nCons = double.tryParse(_annualConsCtrls[res]!.text) ?? oldCons;
        _checkNum('Annual Consumption ($res)', oldCons, nCons);
        rules.annualConsumption[res] = nCons;

        double oldResDep = rules.residentDepreciationRates[res] ?? 0.0;
        double nResDep = double.tryParse(_resDepCtrls[res]!.text) ?? oldResDep;
        _checkNum('Resident Dep Rate ($res)', oldResDep, nResDep);
        rules.residentDepreciationRates[res] = nResDep;

        double oldCtyDep = rules.countryDepreciationRates[res] ?? 0.0;
        double nCtyDep = double.tryParse(_ctyDepCtrls[res]!.text) ?? oldCtyDep;
        _checkNum('Country Dep Rate ($res)', oldCtyDep, nCtyDep);
        rules.countryDepreciationRates[res] = nCtyDep;
      }

      settings.put('sim_rules', rules);
      if (rules.isInBox) rules.save();

      if (changes.isNotEmpty) {
        engine.logUserAction(
          'God Mode [Simulation Rules]: ${changes.join(", ")}',
        );
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Advanced Parameters Saved & Logged!')),
    );
    engine.notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Parameters (God Mode)'),
        backgroundColor: Colors.deepPurple[900],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.blueGrey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _editCategory,
                  items:
                      [
                            'Resources',
                            'Country Base',
                            'Resident Base',
                            'Global Exchange',
                            'Global Settings',
                            'Simulation Rules', // ★追加
                          ]
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                'Target: $e',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() {
                      _editCategory = val!;
                      _selectedCountry = null;
                      _selectedResourceType = null;
                      _selectedResident = null;

                      if (_editCategory == 'Global Settings') {
                        _loadGlobalSettings();
                      } else if (_editCategory == 'Global Exchange') {
                        _loadGlobalExchangeData(engine);
                      } else if (_editCategory == 'Simulation Rules') {
                        _loadSimulationRules(); // ★追加
                      }
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (_editCategory == 'Simulation Rules') ...[
              const Text(
                'Annual Consumption per Resident',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'The base amount of each resource a resident attempts to secure every year.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              for (var res in _resourceTypes)
                _buildNumField('$res Target Amount', _annualConsCtrls[res]!),
              const SizedBox(height: 30),

              const Text(
                'Resident Depreciation Rates (0.0 to 1.0)',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'How much of a resident\'s privately hoarded stock disappears each year. (e.g., 0.1 = 10% lost, 1.0 = 100% lost)',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              for (var res in _resourceTypes)
                _buildNumField('$res Rate', _resDepCtrls[res]!),
              const SizedBox(height: 30),

              const Text(
                'Country Depreciation Rates (0.0 to 1.0)',
                style: TextStyle(
                  color: Colors.lightBlueAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'How much of the unsold market inventory disappears each year before new production is added.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              for (var res in _resourceTypes)
                _buildNumField('$res Rate', _ctyDepCtrls[res]!),
            ],

            if (_editCategory == 'Global Exchange') ...[
              const Text(
                '🌍 AMM Liquidity Pool',
                style: TextStyle(
                  color: Colors.indigoAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Directly manipulate the global exchange reserves. Lowering a currency\'s pool amount increases its relative value (strength). Warning: Do not set to 0.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              for (var cur in _globalCurrencies)
                _buildNumField('$cur Pool Amount', _poolCtrls[cur]!),
            ],

            if (_editCategory == 'Resources') ...[
              DropdownButton<Country>(
                isExpanded: true,
                hint: const Text('Select Country'),
                value: _selectedCountry,
                items: engine.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => setState(() {
                  _selectedCountry = c;
                  _selectedResourceType = null;
                }),
              ),
              if (_selectedCountry != null)
                DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text('Select Resource'),
                  value: _selectedResourceType,
                  items: _selectedCountry!.resources.keys
                      .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                      .toList(),
                  onChanged: (k) => _loadResourceData(_selectedCountry!, k!),
                ),
              if (_selectedResourceType != null) ...[
                _buildNumField('Physical Supply', _availAmtCtrl),
                _buildNumField(
                  'Last Market Price (Clearing Price)',
                  _lastMarketPriceCtrl,
                ),
                _buildNumField(
                  'Annual Production (+X per year)',
                  _annualProdCtrl,
                ),
              ],
            ],

            if (_editCategory == 'Country Base') ...[
              DropdownButton<Country>(
                isExpanded: true,
                hint: const Text('Select Country'),
                value: _selectedCountry,
                items: engine.countries
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: (c) => _loadCountryBaseData(c!),
              ),
              if (_selectedCountry != null) ...[
                _buildStringField('Currency Name', _currencyNameCtrl),
              ],
            ],

            if (_editCategory == 'Resident Base') ...[
              DropdownButton<Country>(
                isExpanded: true,
                hint: const Text('Filter by Country'),
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
                  isExpanded: true,
                  hint: const Text('Select Resident'),
                  value: _selectedResident,
                  items: _selectedCountry!.residents
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                      )
                      .toList(),
                  onChanged: (r) => _loadResidentBaseData(r!),
                ),
              if (_selectedResident != null) ...[
                _buildNumField('Age (0 to 9)', _ageCtrl, isInt: true),
              ],
            ],

            if (_editCategory == 'Global Settings') ...[
              const Text(
                'Civilization Level Rules',
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Set the required resource stock for residents to advance their civilization level and start demanding higher-tier resources.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              _buildNumField('Wood Stock required for Level 2', _civWoodCtrl),
              _buildNumField('Metal Stock required for Level 3', _civMetalCtrl),
            ],

            const SizedBox(height: 40),
            if ((_editCategory == 'Resources' &&
                    _selectedResourceType != null) ||
                (_editCategory == 'Country Base' && _selectedCountry != null) ||
                (_editCategory == 'Resident Base' &&
                    _selectedResident != null) ||
                (_editCategory == 'Global Exchange') ||
                (_editCategory == 'Global Settings') ||
                (_editCategory == 'Simulation Rules')) // ★追加
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.deepPurpleAccent,
                  ),
                  onPressed: () => _saveChanges(engine),
                  child: const Text(
                    'Execute Advanced Override',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumField(
    String label,
    TextEditingController ctrl, {
    bool isInt = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.black26,
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
        fillColor: Colors.black26,
      ),
    ),
  );
}
