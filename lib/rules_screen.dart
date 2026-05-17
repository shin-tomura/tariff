import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({Key? key}) : super(key: key);

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  bool _isEnglish = true;

  List<String> _getRules(bool isEnglish) {
    if (isEnglish) {
      return [
        'Residents hold only local currency. All international trade is settled via the Global AMM.',
        'Exporting does not yield foreign currency; it strictly strengthens the local currency value in the AMM.',
        'Government foreign reserves are accumulated ONLY through "Currency Interventions" (selling local currency to buy foreign currency via the AMM).',
        'UBI is distributed strictly in local currency. The government cannot distribute foreign reserves to its residents.',
        'Physical assets (Wood, Metal, Oil) confiscated via inheritance tax are fully recycled into the domestic market supply.',
        // ★修正: Priorityの効果と、第2ラウンドが常時発動のセーフティネットであることを正確に記述
        '"Food Domestic Priority" unconditionally prioritizes domestic buyers in the 1st-round food auction. Regardless of this setting, a 2nd-round is always held for domestic residents if surplus food remains, securing it at a capped lower price.',
      ];
    } else {
      return [
        '住民は自国通貨のみを所持し、国際貿易はすべて世界共通のAMMを経由して行われる。',
        '輸出によって外貨を獲得することはなく、AMMにおける自国通貨の価値が上昇する。',
        '政府の外貨準備高は、AMMで自国通貨を売り外貨を買う「為替介入」によってのみ蓄積される。',
        '住民に支給されるUBIは自国通貨に限定され、政府の外貨準備を直接分配することはできない。',
        '相続税で没収された実物資産は消失せず、すべて国内市場の在庫に還元される。',
        // ★修正: Priorityの効果と、第2ラウンドが常時発動のセーフティネットであることを正確に記述
        '「Food Domestic Priority」有効時は第1ラウンドで自国民が絶対優先される。また設定に関わらず、食料に余剰があれば常に自国民向けの第2ラウンド入札が実施され、安値で保護される。',
      ];
    }
  }

  String _getAllRulesText() {
    final rules = _getRules(_isEnglish);
    return rules.map((r) => '• $r').join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final rules = _getRules(_isEnglish);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEnglish ? 'Rules & Specifications' : 'シミュレーション仕様'),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: _isEnglish ? 'Copy All' : '全文コピー',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _getAllRulesText()));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isEnglish
                        ? 'Copied all rules to clipboard!'
                        : 'すべてのルールをクリップボードにコピーしました！',
                  ),
                ),
              );
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.translate, color: Colors.white),
            label: Text(
              _isEnglish ? '日本語' : 'English',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              setState(() {
                _isEnglish = !_isEnglish;
              });
            },
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        itemCount: rules.length,
        separatorBuilder: (context, index) =>
            const Divider(color: Colors.white24, height: 40),
        itemBuilder: (context, index) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '• ',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: SelectableText(
                    rules[index],
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
