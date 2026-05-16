import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'engine.dart';
import 'models.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({Key? key}) : super(key: key);

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  int _selectedPeriod = 10;
  int _selectedEndYear = 0;

  Set<String> _visibleCountries = {};
  bool _isInitialized = false;

  Color _getCountryColor(String id) {
    switch (id) {
      case 'USA':
        return Colors.blueAccent;
      case 'CHN':
        return Colors.redAccent;
      case 'JPN':
        return Colors.greenAccent;
      default:
        return Colors.primaries[id.hashCode % Colors.primaries.length];
    }
  }

  Widget _buildSettingsPanel(List<Country> allCountries, int currentMaxYear) {
    int effectiveEndYear =
        _selectedEndYear == 0 || _selectedEndYear > currentMaxYear
        ? currentMaxYear
        : _selectedEndYear;

    return Container(
      color: Colors.blueGrey[900],
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter by Country:',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: allCountries.map((c) {
              final isSelected = _visibleCountries.contains(c.id);
              return FilterChip(
                label: Text(c.id),
                selected: isSelected,
                selectedColor: _getCountryColor(c.id).withOpacity(0.6),
                backgroundColor: Colors.blueGrey[800],
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                onSelected: (bool selected) {
                  setState(() {
                    if (selected) {
                      _visibleCountries.add(c.id);
                    } else {
                      if (_visibleCountries.length > 1) {
                        _visibleCountries.remove(c.id);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'At least one country must be visible.',
                            ),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),

          const Text(
            'Time Range (Duration):',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: [
              _buildChip('10 Yrs', 10),
              _buildChip('20 Yrs', 20),
              _buildChip('50 Yrs', 50),
              // ★修正: All Time の代わりに 100 Yrs を最大表示期間に設定
              _buildChip('100 Yrs', 100),
            ],
          ),

          if (_selectedPeriod != 0 && currentMaxYear > 1) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Viewing up to Year: $effectiveEndYear',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (effectiveEndYear < currentMaxYear)
                  TextButton.icon(
                    icon: const Icon(Icons.fast_forward, size: 16),
                    label: const Text('Go to Latest'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () {
                      setState(() {
                        _selectedEndYear = 0;
                      });
                    },
                  ),
              ],
            ),
            Slider(
              value: effectiveEndYear.toDouble().clamp(
                1.0,
                currentMaxYear.toDouble(),
              ),
              min: 1.0,
              max: currentMaxYear.toDouble(),
              divisions: max(1, currentMaxYear - 1),
              activeColor: Colors.cyanAccent,
              inactiveColor: Colors.white24,
              label: 'Year $effectiveEndYear',
              onChanged: (val) {
                setState(() {
                  _selectedEndYear = val.toInt();
                });
              },
            ),
            Text(
              'Showing Year ${max(1, effectiveEndYear - _selectedPeriod + 1)} to $effectiveEndYear',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label, int period) {
    return ChoiceChip(
      label: Text(label),
      selected: _selectedPeriod == period,
      selectedColor: Colors.deepOrange,
      backgroundColor: Colors.blueGrey[800],
      labelStyle: TextStyle(
        color: _selectedPeriod == period ? Colors.white : Colors.white70,
        fontWeight: FontWeight.bold,
      ),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedPeriod = period;
          });
        }
      },
    );
  }

  Widget _emptyCard(String title) {
    return Card(
      color: Colors.black45,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: AspectRatio(
          aspectRatio: 1.5,
          child: Center(
            child: Text(
              '$title\n(Not enough data in this period)',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLineChart(
    String title,
    List<Country> countries,
    double Function(YearlyMetrics, Country) dataExtractor, {
    int currentMaxYear = 1,
  }) {
    if (countries.isEmpty || countries.first.history.isEmpty) {
      return _emptyCard(title);
    }

    int targetMaxYear =
        _selectedEndYear == 0 || _selectedEndYear > currentMaxYear
        ? currentMaxYear
        : _selectedEndYear;

    int minYearFilter = _selectedPeriod == 0
        ? 1
        : max(1, targetMaxYear - _selectedPeriod + 1);

    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    int actualMinX = targetMaxYear;
    int actualMaxX = minYearFilter;

    List<LineChartBarData> lineBars = [];
    bool hasData = false;

    for (var country in countries) {
      List<FlSpot> spots = [];
      var filteredHistory = country.history
          .where(
            (h) =>
                (h.year + 1) >= minYearFilter && (h.year + 1) <= targetMaxYear,
          )
          .toList();

      for (var h in filteredHistory) {
        hasData = true;
        int displayYear = h.year + 1;
        double val = dataExtractor(h, country);

        if (val < minY) minY = val;
        if (val > maxY) maxY = val;
        if (displayYear < actualMinX) actualMinX = displayYear;
        if (displayYear > actualMaxX) actualMaxX = displayYear;

        spots.add(FlSpot(displayYear.toDouble(), val));
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _getCountryColor(country.id),
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    if (!hasData) {
      return _emptyCard(title);
    }

    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    } else {
      double padding = (maxY - minY) * 0.1;
      minY -= padding;
      maxY += padding;
    }

    if (actualMinX >= actualMaxX) {
      actualMinX = max(1, actualMinX - 1);
      actualMaxX += 1;
    }

    double xRange = (actualMaxX - actualMinX).toDouble();
    double xInterval = max(1.0, (xRange / 5).floorToDouble());

    return Card(
      color: const Color(0xFF1E1E2C),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            AspectRatio(
              aspectRatio: 1.5,
              child: LineChart(
                LineChartData(
                  lineBarsData: lineBars,
                  minY: minY,
                  maxY: maxY,
                  minX: actualMinX.toDouble(),
                  maxX: actualMaxX.toDouble(),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        interval: xInterval,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Yr ${value.toInt()}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 45,
                        getTitlesWidget: (value, meta) {
                          String text;
                          if (value >= 1000000000000 ||
                              value <= -1000000000000) {
                            text =
                                '${(value / 1000000000000).toStringAsFixed(1)}T';
                          } else if (value >= 1000000000 ||
                              value <= -1000000000) {
                            text =
                                '${(value / 1000000000).toStringAsFixed(1)}B';
                          } else if (value >= 1000000 || value <= -1000000) {
                            text = '${(value / 1000000).toStringAsFixed(1)}M';
                          } else if (value >= 1000 || value <= -1000) {
                            text = '${(value / 1000).toStringAsFixed(1)}k';
                          } else if (value < 0.01 &&
                              value > -0.01 &&
                              value != 0) {
                            text = value.toStringAsExponential(1);
                          } else {
                            text = value.toStringAsFixed(1);
                          }
                          return Text(
                            text,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: (maxY - minY) / 4 > 0
                        ? (maxY - minY) / 4
                        : 1,
                    verticalInterval: xInterval,
                    getDrawingHorizontalLine: (value) {
                      if (value == 0) {
                        return const FlLine(
                          color: Colors.white54,
                          strokeWidth: 1.5,
                        );
                      }
                      return const FlLine(
                        color: Colors.white10,
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) =>
                        const FlLine(color: Colors.white10, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.white24),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            'Yr ${spot.x.toInt()}\n${spot.y.toStringAsFixed(2)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16.0,
              runSpacing: 4.0,
              children: countries.map((c) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      color: _getCountryColor(c.id),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      c.id,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SimulationEngine>();
    final allCountries = engine.countries;

    if (!_isInitialized && allCountries.isNotEmpty) {
      _visibleCountries = allCountries.map((c) => c.id).toSet();
      _isInitialized = true;
    }

    final visibleCountriesList = allCountries
        .where((c) => _visibleCountries.contains(c.id))
        .toList();

    int currentMaxYear = 1;
    if (allCountries.isNotEmpty && allCountries.first.history.isNotEmpty) {
      currentMaxYear = allCountries.first.history.last.year + 1;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Macroeconomic Indicators'),
        backgroundColor: Colors.indigo[900],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _buildSettingsPanel(allCountries, currentMaxYear),
          const SizedBox(height: 8),

          _buildLineChart(
            'Currency Strength Index (Calculated Base)',
            visibleCountriesList,
            (m, c) => m.currencyIndex,
            currentMaxYear: currentMaxYear,
          ),

          _buildLineChart(
            'Net Trade Balance (Local Currency)',
            visibleCountriesList,
            (m, c) => m.netTradeBalance,
            currentMaxYear: currentMaxYear,
          ),

          _buildLineChart(
            'AMM Liquidity Pool (Local Currency)',
            visibleCountriesList,
            (m, c) => m.ammLiquidity,
            currentMaxYear: currentMaxYear,
          ),

          _buildLineChart(
            'Total Domestic Money (Local Currency)',
            visibleCountriesList,
            (m, c) => m.totalDomesticMoney,
            currentMaxYear: currentMaxYear,
          ),

          _buildLineChart(
            'Average Weight (Health / Hunger Proxy)',
            visibleCountriesList,
            (m, c) => m.avgWeight,
            currentMaxYear: currentMaxYear,
          ),
          _buildLineChart(
            'Average Civilization Level',
            visibleCountriesList,
            (m, c) => m.avgCivLevel,
            currentMaxYear: currentMaxYear,
          ),

          _buildLineChart(
            'Food Market Price (Local Currency)',
            visibleCountriesList,
            (m, c) => m.foodPrice,
            currentMaxYear: currentMaxYear,
          ),
          _buildLineChart(
            'Wood Market Price (Local Currency)',
            visibleCountriesList,
            (m, c) => m.woodPrice,
            currentMaxYear: currentMaxYear,
          ),
          _buildLineChart(
            'Metal Market Price (Local Currency)',
            visibleCountriesList,
            (m, c) => m.metalPrice,
            currentMaxYear: currentMaxYear,
          ),
          _buildLineChart(
            'Oil Market Price (Local Currency)',
            visibleCountriesList,
            (m, c) => m.oilPrice,
            currentMaxYear: currentMaxYear,
          ),
        ],
      ),
    );
  }
}
