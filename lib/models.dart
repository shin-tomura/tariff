import 'package:hive/hive.dart';

// --- 新設: シミュレーションの基本ルール設定 ---
class SimulationSettings extends HiveObject {
  // 住人1人あたりの各資源の年間消費量（要求量）
  Map<String, double> annualConsumption;

  // 住民保有資源のターン経過時の消滅率 (0.0: 全く消滅しない 〜 1.0: 100%消滅)
  Map<String, double> residentDepreciationRates;

  // 国家(市場)保有資源のターン経過時の消滅率 (0.0: 全く消滅しない 〜 1.0: 100%消滅)
  Map<String, double> countryDepreciationRates;

  SimulationSettings({
    Map<String, double>? annualConsumption,
    Map<String, double>? residentDepreciationRates,
    Map<String, double>? countryDepreciationRates,
  }) : annualConsumption =
           annualConsumption ??
           {'Food': 10.0, 'Wood': 10.0, 'Metal': 10.0, 'Oil': 10.0},
       residentDepreciationRates =
           residentDepreciationRates ??
           {
             'Food': 1.0, // 食料は体重に変換されるため実質ストック不可(100%消滅)
             'Wood': 0.10, // 旧仕様: 10%消滅
             'Metal': 0.05, // 旧仕様: 5%消滅
             'Oil': 1.0, // 旧仕様: 100%消滅
           },
       countryDepreciationRates =
           countryDepreciationRates ??
           {
             'Food': 1.0, // 旧仕様: 前年分は全消滅
             'Wood': 0.0, // 旧仕様: 消滅しない(完全蓄積)
             'Metal': 0.0, // 旧仕様: 消滅しない(完全蓄積)
             'Oil': 0.0, // 旧仕様: 消滅しない(完全蓄積)
           };
}

class Country extends HiveObject {
  String id;
  String name;
  String currencyName;

  // 関税設定 (キー: '相手国ID:品目名', 値: 税率)
  Map<String, double> tariffs;

  double inheritanceTaxRate;

  // 各品目の全面輸出禁止措置（キー: 品目名, 値: trueなら全世界へ禁止）
  Map<String, bool> exportBans;

  // ★追加: 特定国向けの輸出禁止措置（キー: '相手国ID:品目名', 値: trueならその国へ禁止）
  Map<String, bool> targetedExportBans;

  // 食料の自国民優先フラグ（trueならオークション時に自国民の落札を最優先する）
  bool foodDomesticPriority;

  // UBIの配分設定
  double ubiPayoutRatio; // 0.0〜1.0（デフォルト1.0＝全額配布）
  bool useProgressiveUbi; // true＝傾斜配分（福祉）、false＝均等配分（フラット）

  // 外貨準備高(多通貨対応)
  Map<String, double> reserves;

  HiveList<Resident> residents;
  Map<String, ResourceInfo> resources;
  double currencyIndex;

  Map<String, double> exportLedger;
  Map<String, double> importLedger;
  List<YearlyMetrics> history;

  Country({
    required this.id,
    required this.name,
    required this.currencyName,
    required this.tariffs,
    required this.inheritanceTaxRate,
    Map<String, bool>? exportBans,
    Map<String, bool>? targetedExportBans, // ★追加
    this.foodDomesticPriority = false,
    this.ubiPayoutRatio = 1.0,
    this.useProgressiveUbi = false,
    Map<String, double>? reserves,
    required this.residents,
    required this.resources,
    this.currencyIndex = 1.0,
    Map<String, double>? exportLedger,
    Map<String, double>? importLedger,
    List<YearlyMetrics>? history,
  }) : exportBans = exportBans ?? {},
       targetedExportBans = targetedExportBans ?? {}, // ★追加
       reserves = reserves ?? {},
       exportLedger = exportLedger ?? {},
       importLedger = importLedger ?? {},
       history = history ?? [];
}

class Resident extends HiveObject {
  String id;
  String name;
  int age;
  double weight;
  double previousWeight;

  // 多通貨財布
  Map<String, double> wallet;

  double woodStock;
  double metalStock;
  double oilStock;
  List<String> lastYearActivities;

  Resident({
    required this.id,
    required this.name,
    required this.age,
    required this.weight,
    this.previousWeight = 65.0,
    Map<String, double>? wallet,
    this.woodStock = 0.0,
    this.metalStock = 0.0,
    this.oilStock = 0.0,
    List<String>? lastYearActivities,
  }) : wallet = wallet ?? {},
       lastYearActivities = lastYearActivities ?? [];

  int get civilizationLevel {
    var settings = Hive.box('settings');
    double metalThresh = settings.get('civMetalThreshold', defaultValue: 30.0);
    double woodThresh = settings.get('civWoodThreshold', defaultValue: 20.0);

    if (metalStock >= metalThresh) return 3;
    if (woodStock >= woodThresh) return 2;
    return 1;
  }
}

class ResourceInfo {
  String type;
  double availableAmount;
  double annualProduction;
  double lastMarketPrice;

  ResourceInfo({
    required this.type,
    required this.availableAmount,
    required this.annualProduction,
    this.lastMarketPrice = 10.0,
  });
}

class EventLog extends HiveObject {
  int year;
  String message;
  int timestamp;
  EventLog({
    required this.year,
    required this.message,
    required this.timestamp,
  });
}

class YearlyMetrics extends HiveObject {
  int year;
  double currencyIndex;
  double avgWeight;
  double avgCivLevel;

  Map<String, double> avgWallet;
  Map<String, double> governmentReserves;

  double foodPrice;
  double woodPrice;
  double metalPrice;
  double oilPrice;

  double ammLiquidity;
  double totalDomesticMoney;

  double netTradeBalance;
  double grossTradeVolume;

  // ジニ係数 (0.0=完全平等, 1.0=完全不平等)
  double giniIndex;

  // 総合幸福度指数 (Holistic Welfare Index) の平均値
  double avgHwi;

  // 各資源の市場在庫量（余剰量）
  double woodInventory;
  double metalInventory;
  double oilInventory;

  YearlyMetrics({
    required this.year,
    required this.currencyIndex,
    required this.avgWeight,
    required this.avgCivLevel,
    required this.avgWallet,
    required this.governmentReserves,
    required this.foodPrice,
    required this.woodPrice,
    required this.metalPrice,
    required this.oilPrice,
    required this.ammLiquidity,
    required this.totalDomesticMoney,
    this.netTradeBalance = 0.0,
    this.grossTradeVolume = 0.0,
    this.giniIndex = 0.0,
    this.avgHwi = 0.0,
    this.woodInventory = 0.0,
    this.metalInventory = 0.0,
    this.oilInventory = 0.0,
  });
}

// 地球共通両替所（AMM流動性プール）
class GlobalExchange extends HiveObject {
  Map<String, double> liquidityPool;

  GlobalExchange({Map<String, double>? liquidityPool})
    : liquidityPool = liquidityPool ?? {};
}

// --- Hive Adapters ---

class CountryAdapter extends TypeAdapter<Country> {
  @override
  final int typeId = 0;

  @override
  Country read(BinaryReader reader) {
    return Country(
      id: reader.readString(),
      name: reader.readString(),
      currencyName: reader.readString(),
      tariffs: Map<String, double>.from(reader.readMap()),
      inheritanceTaxRate: reader.readDouble(),
      reserves: Map<String, double>.from(reader.readMap()),
      residents: reader.readHiveList().castHiveList<Resident>(),
      resources: Map<String, ResourceInfo>.from(reader.readMap()),
      currencyIndex: reader.readDouble(),
      exportLedger: Map<String, double>.from(reader.readMap()),
      importLedger: Map<String, double>.from(reader.readMap()),
      history: List<YearlyMetrics>.from(reader.readList()),
      exportBans: Map<String, bool>.from(reader.readMap()),
      targetedExportBans: Map<String, bool>.from(reader.readMap()), // ★追加
      foodDomesticPriority: reader.readBool(),
      ubiPayoutRatio: reader.readDouble(),
      useProgressiveUbi: reader.readBool(),
    );
  }

  @override
  void write(BinaryWriter writer, Country obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.currencyName);
    writer.writeMap(obj.tariffs);
    writer.writeDouble(obj.inheritanceTaxRate);
    writer.writeMap(obj.reserves);
    writer.writeHiveList(obj.residents);
    writer.writeMap(obj.resources);
    writer.writeDouble(obj.currencyIndex);
    writer.writeMap(obj.exportLedger);
    writer.writeMap(obj.importLedger);
    writer.writeList(obj.history);
    writer.writeMap(obj.exportBans);
    writer.writeMap(obj.targetedExportBans); // ★追加
    writer.writeBool(obj.foodDomesticPriority);
    writer.writeDouble(obj.ubiPayoutRatio);
    writer.writeBool(obj.useProgressiveUbi);
  }
}

class ResidentAdapter extends TypeAdapter<Resident> {
  @override
  final int typeId = 1;
  @override
  Resident read(BinaryReader reader) => Resident(
    id: reader.readString(),
    name: reader.readString(),
    age: reader.readInt(),
    weight: reader.readDouble(),
    previousWeight: reader.readDouble(),
    wallet: Map<String, double>.from(reader.readMap()),
    woodStock: reader.readDouble(),
    metalStock: reader.readDouble(),
    oilStock: reader.readDouble(),
    lastYearActivities: List<String>.from(reader.readList()),
  );
  @override
  void write(BinaryWriter writer, Resident obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeInt(obj.age);
    writer.writeDouble(obj.weight);
    writer.writeDouble(obj.previousWeight);
    writer.writeMap(obj.wallet);
    writer.writeDouble(obj.woodStock);
    writer.writeDouble(obj.metalStock);
    writer.writeDouble(obj.oilStock);
    writer.writeList(obj.lastYearActivities);
  }
}

class ResourceInfoAdapter extends TypeAdapter<ResourceInfo> {
  @override
  final int typeId = 2;
  @override
  ResourceInfo read(BinaryReader reader) => ResourceInfo(
    type: reader.readString(),
    availableAmount: reader.readDouble(),
    annualProduction: reader.readDouble(),
    lastMarketPrice: reader.readDouble(),
  );
  @override
  void write(BinaryWriter writer, ResourceInfo obj) {
    writer.writeString(obj.type);
    writer.writeDouble(obj.availableAmount);
    writer.writeDouble(obj.annualProduction);
    writer.writeDouble(obj.lastMarketPrice);
  }
}

class EventLogAdapter extends TypeAdapter<EventLog> {
  @override
  final int typeId = 3;
  @override
  EventLog read(BinaryReader reader) => EventLog(
    year: reader.readInt(),
    message: reader.readString(),
    timestamp: reader.readInt(),
  );
  @override
  void write(BinaryWriter writer, EventLog obj) {
    writer.writeInt(obj.year);
    writer.writeString(obj.message);
    writer.writeInt(obj.timestamp);
  }
}

class YearlyMetricsAdapter extends TypeAdapter<YearlyMetrics> {
  @override
  final int typeId = 4;
  @override
  YearlyMetrics read(BinaryReader reader) => YearlyMetrics(
    year: reader.readInt(),
    currencyIndex: reader.readDouble(),
    avgWeight: reader.readDouble(),
    avgCivLevel: reader.readDouble(),
    avgWallet: Map<String, double>.from(reader.readMap()),
    governmentReserves: Map<String, double>.from(reader.readMap()),
    foodPrice: reader.readDouble(),
    woodPrice: reader.readDouble(),
    metalPrice: reader.readDouble(),
    oilPrice: reader.readDouble(),
    ammLiquidity: reader.readDouble(),
    totalDomesticMoney: reader.readDouble(),
    netTradeBalance: reader.readDouble(),
    grossTradeVolume: reader.readDouble(),
    giniIndex: reader.readDouble(),
    avgHwi: reader.readDouble(),
    woodInventory: reader.readDouble(),
    metalInventory: reader.readDouble(),
    oilInventory: reader.readDouble(),
  );
  @override
  void write(BinaryWriter writer, YearlyMetrics obj) {
    writer.writeInt(obj.year);
    writer.writeDouble(obj.currencyIndex);
    writer.writeDouble(obj.avgWeight);
    writer.writeDouble(obj.avgCivLevel);
    writer.writeMap(obj.avgWallet);
    writer.writeMap(obj.governmentReserves);
    writer.writeDouble(obj.foodPrice);
    writer.writeDouble(obj.woodPrice);
    writer.writeDouble(obj.metalPrice);
    writer.writeDouble(obj.oilPrice);
    writer.writeDouble(obj.ammLiquidity);
    writer.writeDouble(obj.totalDomesticMoney);
    writer.writeDouble(obj.netTradeBalance);
    writer.writeDouble(obj.grossTradeVolume);
    writer.writeDouble(obj.giniIndex);
    writer.writeDouble(obj.avgHwi);
    writer.writeDouble(obj.woodInventory);
    writer.writeDouble(obj.metalInventory);
    writer.writeDouble(obj.oilInventory);
  }
}

class GlobalExchangeAdapter extends TypeAdapter<GlobalExchange> {
  @override
  final int typeId = 5;
  @override
  GlobalExchange read(BinaryReader reader) =>
      GlobalExchange(liquidityPool: Map<String, double>.from(reader.readMap()));
  @override
  void write(BinaryWriter writer, GlobalExchange obj) {
    writer.writeMap(obj.liquidityPool);
  }
}

class SimulationSettingsAdapter extends TypeAdapter<SimulationSettings> {
  @override
  final int typeId = 6;
  @override
  SimulationSettings read(BinaryReader reader) {
    return SimulationSettings(
      annualConsumption: Map<String, double>.from(reader.readMap()),
      residentDepreciationRates: Map<String, double>.from(reader.readMap()),
      countryDepreciationRates: Map<String, double>.from(reader.readMap()),
    );
  }

  @override
  void write(BinaryWriter writer, SimulationSettings obj) {
    writer.writeMap(obj.annualConsumption);
    writer.writeMap(obj.residentDepreciationRates);
    writer.writeMap(obj.countryDepreciationRates);
  }
}
