import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({Key? key}) : super(key: key);

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  bool _isEnglish = true;

  // 改良: タイトルと本文を分けることでレイアウトを確実に制御
  String _getDisclaimerTitle(bool isEnglish) {
    return isEnglish ? 'IMPORTANT DISCLAIMER' : '免責事項 (重要)';
  }

  String _getDisclaimerBody(bool isEnglish) {
    return isEnglish
        ? 'This app is a 100% offline sandbox simulation. All economic data, charts, and market prices are entirely fictitious. The app DOES NOT fetch real-world financial data nor connect to any external AI/LLM services.'
        : '本アプリは完全オフラインで動作する架空のシミュレーションゲームです。すべての経済データや価格は架空のものであり、現実世界の金融データは一切使用していません。また、外部のAIやLLMサービスとの通信も一切行いません。';
  }

  List<String> _getHowToPlay(bool isEnglish) {
    if (isEnglish) {
      return [
        'Tap the "Advance 1 Year" button to progress the simulation.',
        'Occasionally check the "Macroeconomic Charts" to monitor the global economic situation.',
        'Enact policies like tariffs and currency interventions for each country from the "Edit Parameters & Policies" menu.',
        'Advance the years again and enjoy watching how your decisions dynamically shift the global market!',
        '💡 Fun Tip: Use the "LLM Debug Export" from the menu to copy the raw game data. Paste it into your favorite Generative AI and ask it to analyze the world economy—it\'s a highly recommended way to play!',
      ];
    } else {
      return [
        '「Advance 1 Year」ボタンを押してシミュレーション（時間）を進めます。',
        '時々グラフ（Macroeconomic Charts）を開いて、世界経済の状況を確認しましょう。',
        '「Edit Parameters & Policies」から、各国に対して関税や為替介入などの政策を実行します。',
        '再び時間を進めて、あなたの決断によって市場がどう変化するかを楽しんでください！',
        '💡 おすすめの遊び方: メニューの「LLM Debug Export」からダンプデータをコピーし、お気に入りの生成AIに貼り付けて世界経済を分析してもらうと非常に楽しいですよ！',
      ];
    }
  }

  List<String> _getRules(bool isEnglish) {
    if (isEnglish) {
      return [
        'Residents hold only local currency. All international trade is settled via the Global AMM.',
        'Exporting does not yield foreign currency; it strictly strengthens the local currency value in the AMM.',
        'Government foreign reserves are accumulated ONLY through "Currency Interventions" (selling local currency to buy foreign currency via the AMM).',
        'UBI is distributed strictly in local currency. The government cannot distribute foreign reserves to its residents.',
        'Physical assets (Wood, Metal, Oil) confiscated via inheritance tax are fully recycled into the domestic market supply.',
        '"Food Domestic Priority" unconditionally prioritizes domestic buyers in the 1st-round food auction. Regardless of this setting, a 2nd-round is always held for domestic residents if surplus food remains, securing it at a capped lower price.',
      ];
    } else {
      return [
        '住民は自国通貨のみを所持し、国際貿易はすべて世界共通のAMMを経由して行われる。',
        '輸出によって外貨を獲得することはなく、AMMにおける自国通貨の価値が上昇する。',
        '政府の外貨準備高は、AMMで自国通貨を売り外貨を買う「為替介入」によってのみ蓄積される。',
        '住民に支給されるUBIは自国通貨に限定され、政府の外貨準備を直接分配することはできない。',
        '相続税で没収された実物資産は消失せず、すべて国内市場の在庫に還元される。',
        '「Food Domestic Priority」有効時は第1ラウンドで自国民が絶対優先される。また設定に関わらず、食料に余剰があれば常に自国民向けの第2ラウンド入札が実施され、安値で保護される。',
      ];
    }
  }

  String _getAllRulesText() {
    final title = _getDisclaimerTitle(_isEnglish);
    final body = _getDisclaimerBody(_isEnglish);
    final howTo = _getHowToPlay(_isEnglish);
    final rules = _getRules(_isEnglish);

    final howToTitle = _isEnglish ? '--- How to Play ---' : '--- 簡単な遊び方 ---';
    final rulesTitle = _isEnglish
        ? '--- Rules & Specifications ---'
        : '--- シミュレーション仕様 ---';

    final howToText = howTo.map((r) => '• $r').join('\n\n');
    final rulesText = rules.map((r) => '• $r').join('\n\n');

    return '⚠️ $title\n$body\n\n$howToTitle\n\n$howToText\n\n$rulesTitle\n\n$rulesText';
  }

  @override
  Widget build(BuildContext context) {
    final howTo = _getHowToPlay(_isEnglish);
    final rules = _getRules(_isEnglish);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEnglish ? 'Guide & Specifications' : '遊び方とシミュレーション仕様'),
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
                        ? 'Copied guide and rules to clipboard!'
                        : '遊び方とルールをクリップボードにコピーしました！',
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
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.only(bottom: 32.0),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              border: Border.all(color: Colors.redAccent, width: 1.5),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getDisclaimerTitle(_isEnglish),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _getDisclaimerBody(_isEnglish),
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isEnglish ? 'How to Play' : '簡単な遊び方',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 16),
          ...howTo.map((item) => _buildListItem(item)),

          const SizedBox(height: 16),
          const Divider(color: Colors.white24, thickness: 2),
          const SizedBox(height: 32),

          Text(
            _isEnglish ? 'Rules & Specifications' : 'シミュレーション仕様',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
          const SizedBox(height: 16),
          ...rules.map((item) => _buildListItem(item)),
        ],
      ),
    );
  }

  Widget _buildListItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              fontSize: 20,
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
