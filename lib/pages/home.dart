import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:temperature_app/data/database_helper.dart';
import 'package:temperature_app/data/sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  
  double? _temp;
  double? _humidity;
  bool _isMeasuring = false;
  bool _manualMeasurementRequested = false;
  int? _lastTimestamp;
  
  List<Map<String, dynamic>> _hourlyAverages = [];
  List<Map<String, dynamic>> _dailyAverages = [];
  List<Map<String, dynamic>> _weeklyAverages = [];
  List<Map<String, dynamic>> _monthlyAverages = [];
  List<Map<String, dynamic>> _detailedHistory = [];
  int _selectedIndex = 0;
  
  // Period filter: 'Horas', 'Diaria', 'Semana' or 'Mes'
  String _selectedPeriod = 'Diaria';
  int? _showingTempTooltipIndex;
  int? _showingHumTooltipIndex;
  int? _showingAmpTooltipIndex;

  @override
  void initState() {
    super.initState();
    // Initialize local history, then seed from Firestore if needed & schedule daily sync
    _loadHistory().then((_) => SyncService.initialize());
    
    // Listen for database changes to update real-time and save to local SQLite
    _databaseRef.child('sensors').onValue.listen((DatabaseEvent event) async {
      debugPrint('Firebase sensors event received: ${event.snapshot.value}');
      if (event.snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        
        final double? newTemp = (data['temperature'] as num?)?.toDouble();
        final double? newHum = (data['humidity'] as num?)?.toDouble();
        final double? newHumExtra = (data['humidityExtra'] as num?)?.toDouble();
        final int? timestamp = data['timestamp'] as int?;

        debugPrint('Parsed sensors data: temp=$newTemp, hum=$newHum, humExtra=$newHumExtra, timestamp=$timestamp (lastTimestamp=$_lastTimestamp)');

        setState(() {
          _temp = newTemp;
          _humidity = newHum;
        });

        // Save to SQLite only if the timestamp changed (new reading)
        if (timestamp != null && newTemp != null && newHum != null) {
          if (_lastTimestamp == null) {
            debugPrint('Initializing _lastTimestamp to $timestamp on startup, skipping insert.');
            _lastTimestamp = timestamp;
            return;
          }

          if (timestamp != _lastTimestamp) {
            debugPrint('New timestamp detected ($timestamp != $_lastTimestamp). Inserting measurement...');
            _lastTimestamp = timestamp;
            
            final bool wasManual = _manualMeasurementRequested || _isMeasuring;
            _manualMeasurementRequested = false;
            
            if (wasManual) {
              debugPrint('Clearing manual measurement state.');
              setState(() {
                _isMeasuring = false;
              });
            }
            
            final row = {
              'temperature': newTemp,
              'humidity': newHum,
              'humidityExtra': newHumExtra ?? 0.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'is_manual': wasManual ? 1 : 0,
            };
            
            final id = await DatabaseHelper.instance.insertMeasurement(row);
            debugPrint('Inserted measurement successfully with ID: $id');
            
            _loadHistory();
            // Trigger daily sync check after a new measurement is recorded
            SyncService.syncNowIfNeeded();
          } else {
            debugPrint('Timestamp $timestamp matches _lastTimestamp $_lastTimestamp. Skipping insert.');
          }
        } else {
          debugPrint('Skipping insert: missing required fields (timestamp=$timestamp, temp=$newTemp, hum=$newHum)');
        }
      }
    });

    // Monitor the command trigger status to show measuring state
    _databaseRef.child('commands/trigger_measurement').onValue.listen((DatabaseEvent event) {
      final triggerVal = event.snapshot.value;
      final isMeasuringNow = (triggerVal == 1 || triggerVal == true);
      
      setState(() {
        _isMeasuring = isMeasuringNow;
      });

      if (isMeasuringNow) {
        // Fail-safe: reset measuring state and clear trigger in Firebase if stuck for 15s
        Future.delayed(const Duration(seconds: 15), () async {
          if (mounted && _isMeasuring) {
            final snapshot = await _databaseRef.child('commands/trigger_measurement').get();
            final currentVal = snapshot.value;
            if (currentVal == 1 || currentVal == true) {
              await _databaseRef.child('commands').update({
                'trigger_measurement': 0,
              });
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final hourlyData = await DatabaseHelper.instance.getHourlyAverages();
    final dailyData = await DatabaseHelper.instance.getDailyAverages();
    final weeklyData = await DatabaseHelper.instance.getWeeklyAverages();
    final monthlyData = await DatabaseHelper.instance.getMonthlyAverages();
    final detailedData = await DatabaseHelper.instance.getDetailedMeasurements();
    setState(() {
      _hourlyAverages = hourlyData;
      _dailyAverages = dailyData;
      _weeklyAverages = weeklyData;
      _monthlyAverages = monthlyData;
      _detailedHistory = detailedData;
    });
  }



  List<Map<String, dynamic>> get _filteredHistory {
    if (_selectedPeriod == 'Horas') {
      return _hourlyAverages;
    } else if (_selectedPeriod == 'Diaria') {
      return _dailyAverages;
    } else if (_selectedPeriod == 'Semana') {
      return _weeklyAverages;
    } else if (_selectedPeriod == 'Mes') {
      return _monthlyAverages;
    }
    return [];
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    return '$hour:$minute:$second - $day/$month/$year';
  }

  /// Formats a weekly label as the full calendar week range, e.g. "13-19 Jul"
  /// or "28 Jul-3 Ago" for cross-month weeks.
  /// Uses min_date (any day in the week) to compute the Monday and Sunday
  /// of that calendar week.
  String _formatWeekLabel(Map<String, dynamic> item) {
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
    ];
    final minDateStr = item['min_date'] as String?;
    if (minDateStr == null) return item['date'] ?? '';
    try {
      final dateInWeek = DateTime.parse(minDateStr);
      // weekday: 1 = Monday … 7 = Sunday
      final monday = dateInWeek.subtract(Duration(days: dateInWeek.weekday - 1));
      final sunday = monday.add(const Duration(days: 6));
      final startMonth = months[monday.month - 1];
      final endMonth   = months[sunday.month - 1];
      if (monday.month == sunday.month) {
        return '${monday.day}-${sunday.day} $endMonth';
      } else {
        return '${monday.day} $startMonth-${sunday.day} $endMonth';
      }
    } catch (_) {
      return item['date'] ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B), // Slate 800
        elevation: 0,
        title: const Text(
          'Smart Climate Station',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildRealtimeTab(),
          _buildHistoryListTab(),
          _buildStatsTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: const Color(0xFF1E293B), // Slate 800
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Tiempo Real',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_rounded),
            label: 'Estadísticas',
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeTab() {
    final hasData = _temp != null && _humidity != null;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)], // Slate 900 to Indigo 950
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!hasData) ...[
              const CircularProgressIndicator(color: Colors.cyanAccent),
              const SizedBox(height: 16),
              const Text(
                'Esperando conexión con la estación...',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ] else ...[
              // Temperature Card
              _buildSensorCard(
                title: 'Temperatura Interior',
                value: '${_temp!.toStringAsFixed(1)} °C',
                icon: Icons.thermostat_rounded,
                iconColor: Colors.orangeAccent,
                gradientColors: [Colors.orange.shade800.withOpacity(0.15), Colors.orange.shade500.withOpacity(0.05)],
              ),
              const SizedBox(height: 30),
              // Humidity Card
              _buildSensorCard(
                title: 'Humedad Ambiente',
                value: '${_humidity!.toStringAsFixed(1)} %',
                icon: Icons.water_drop_rounded,
                iconColor: Colors.cyanAccent,
                gradientColors: [Colors.cyan.shade800.withOpacity(0.15), Colors.cyan.shade500.withOpacity(0.05)],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required List<Color> gradientColors,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: iconColor.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: iconColor.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 40),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildHistoryListTab() {
    if (_detailedHistory.isEmpty) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.history_rounded, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No hay mediciones registradas.',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Toma una medida o espera a una automática.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0F172A),
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _detailedHistory.length,
        itemBuilder: (context, index) {
          final item = _detailedHistory[index];
          final double? temp = (item['temperature'] as num?)?.toDouble();
          final double? hum = (item['humidity'] as num?)?.toDouble();
          final int timestamp = item['timestamp'] as int? ?? 0;
          final bool isManual = (item['is_manual'] as int? ?? 0) == 1;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // Slate 800
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isManual ? Colors.tealAccent.withOpacity(0.15) : Colors.indigoAccent.withOpacity(0.15),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Icon indicator based on type
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isManual ? Colors.teal.withOpacity(0.15) : Colors.indigo.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isManual ? Icons.touch_app_rounded : Icons.autorenew_rounded,
                    color: isManual ? Colors.tealAccent : Colors.indigoAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Details (Values & Timestamp)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            temp != null ? '${temp.toStringAsFixed(1)} °C' : '-- °C',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            hum != null ? '${hum.toStringAsFixed(1)} %' : '-- %',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(timestamp),
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Type badge label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isManual ? Colors.teal.withOpacity(0.1) : Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isManual ? Colors.tealAccent.withOpacity(0.3) : Colors.indigoAccent.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isManual ? 'Manual' : 'Automática',
                    style: TextStyle(
                      color: isManual ? Colors.tealAccent : Colors.indigoAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsTab() {
    if (_detailedHistory.isEmpty) {
      return Container(
        color: const Color(0xFF0F172A),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.analytics_outlined, color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              const Text(
                'No hay datos históricos registrados.',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Las mediciones periódicas se guardarán aquí.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final filteredData = _filteredHistory;

    return Container(
      color: const Color(0xFF0F172A),
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Histórico y Análisis',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          // Period Selector (Horas / Diaria / Semana / Mes)
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPeriodButton('Horas'),
                  _buildPeriodButton('Diaria'),
                  _buildPeriodButton('Semana'),
                  _buildPeriodButton('Mes'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Section 1: Temperature Chart
          _buildChartSection(
            title: _selectedPeriod == 'Horas'
                ? 'Temperatura (Media por hora)'
                : 'Temperatura (Mín / Máx / Med)',
            chart: _buildTripleLineChart(isTemp: true, dataList: filteredData),
            legend: _buildChartLegend(0),
          ),
          const SizedBox(height: 24),
          
          // Section 2: Humidity Chart
          _buildChartSection(
            title: _selectedPeriod == 'Horas'
                ? 'Humedad (Media por hora)'
                : 'Humedad (Mín / Máx / Med)',
            chart: _buildTripleLineChart(isTemp: false, dataList: filteredData),
            legend: _buildChartLegend(1),
          ),
          const SizedBox(height: 24),
          
          if (_selectedPeriod != 'Horas') ...[
            const SizedBox(height: 24),
            // Section 3: Thermal Amplitude Chart
            _buildChartSection(
              title: 'Amplitud Térmica Diaria (Máx - Mín)',
              chart: _buildThermalAmplitudeChart(dataList: filteredData),
              legend: _buildChartLegend(2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String period) {
    bool isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
          _showingTempTooltipIndex = null;
          _showingHumTooltipIndex = null;
          _showingAmpTooltipIndex = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          period,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection({
    required String title,
    required Widget chart,
    required Widget legend,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Horizontal scrolling wrapper for the chart
          LayoutBuilder(
            builder: (context, constraints) {
              // Calculate custom width based on data count to allow horizontal scrolling
              final dataCount = _filteredHistory.length;
              final double minWidth = constraints.maxWidth;
              final double calculatedWidth = dataCount * 65.0; // 65px per day point
              final double finalWidth = calculatedWidth < minWidth ? minWidth : calculatedWidth;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: finalWidth,
                  height: 150,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0), // Padding to make the last label readable
                    child: chart,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          legend,
        ],
      ),
    );
  }

  Widget _buildTripleLineChart({required bool isTemp, required List<Map<String, dynamic>> dataList}) {
    List<FlSpot> avgSpots = [];
    List<FlSpot> minSpots = [];
    List<FlSpot> maxSpots = [];

    for (int i = 0; i < dataList.length; i++) {
      final item = dataList[i];
      if (isTemp) {
        avgSpots.add(FlSpot(i.toDouble(), (item['avg_temp'] as num).toDouble()));
        minSpots.add(FlSpot(i.toDouble(), (item['min_temp'] as num).toDouble()));
        maxSpots.add(FlSpot(i.toDouble(), (item['max_temp'] as num).toDouble()));
      } else {
        avgSpots.add(FlSpot(i.toDouble(), (item['avg_hum'] as num).toDouble()));
        minSpots.add(FlSpot(i.toDouble(), (item['min_hum'] as num).toDouble()));
        maxSpots.add(FlSpot(i.toDouble(), (item['max_hum'] as num).toDouble()));
      }
    }

    Color mainColor = isTemp ? Colors.orangeAccent : Colors.cyanAccent;

    double minY = 0.0;
    double maxY = 100.0;
    if (dataList.isNotEmpty) {
      double minYVal = double.infinity;
      double maxYVal = double.negativeInfinity;
      for (var item in dataList) {
        double min = isTemp ? (item['min_temp'] as num).toDouble() : (item['min_hum'] as num).toDouble();
        double max = isTemp ? (item['max_temp'] as num).toDouble() : (item['max_hum'] as num).toDouble();
        if (min < minYVal) minYVal = min;
        if (max > maxYVal) maxYVal = max;
      }
      minY = (minYVal - 1.5).floorToDouble();
      maxY = (maxYVal + 1.5).ceilToDouble();
      if (!isTemp) {
        if (minY < 0.0) minY = 0.0;
        if (maxY > 100.0) maxY = 100.0;
      }
    }

    final maxBar = LineChartBarData(
      spots: maxSpots,
      isCurved: true,
      color: Colors.redAccent,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
    );
    final avgBar = LineChartBarData(
      spots: avgSpots,
      isCurved: true,
      color: mainColor,
      barWidth: 3.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(
        show: true,
        color: mainColor.withOpacity(0.08),
      ),
    );
    final minBar = LineChartBarData(
      spots: minSpots,
      isCurved: true,
      color: Colors.blueAccent,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
    );

    List<ShowingTooltipIndicators> showingTooltips = [];
    final activeIndex = isTemp ? _showingTempTooltipIndex : _showingHumTooltipIndex;
    if (activeIndex != null && activeIndex < dataList.length) {
      if (_selectedPeriod == 'Horas') {
        showingTooltips = [
          ShowingTooltipIndicators([
            LineBarSpot(avgBar, 0, avgSpots[activeIndex]),
          ])
        ];
      } else {
        showingTooltips = [
          ShowingTooltipIndicators([
            LineBarSpot(maxBar, 0, maxSpots[activeIndex]),
            LineBarSpot(avgBar, 1, avgSpots[activeIndex]),
            LineBarSpot(minBar, 2, minSpots[activeIndex]),
          ])
        ];
      }
    }

    return LineChart(
      LineChartData(
        minX: -0.5,
        maxX: dataList.isEmpty ? 0.0 : dataList.length.toDouble() - 0.5,
        minY: minY,
        maxY: maxY,
        showingTooltipIndicators: showingTooltips,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent) {
              if (response != null && response.lineBarSpots != null && response.lineBarSpots!.isNotEmpty) {
                final index = response.lineBarSpots!.first.spotIndex;
                setState(() {
                  if (isTemp) {
                    _showingTempTooltipIndex = (_showingTempTooltipIndex == index) ? null : index;
                  } else {
                    _showingHumTooltipIndex = (_showingHumTooltipIndex == index) ? null : index;
                  }
                });
              } else {
                setState(() {
                  if (isTemp) {
                    _showingTempTooltipIndex = null;
                  } else {
                    _showingHumTooltipIndex = null;
                  }
                });
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              final String unit = isTemp ? ' º' : ' %';
              return touchedSpots.map((touchedSpot) {
                if (_selectedPeriod == 'Horas') {
                  if (touchedSpot.barIndex != 0) return null;
                  final textStyle = TextStyle(
                    color: touchedSpot.bar.color ?? Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  );
                  return LineTooltipItem(
                    '${touchedSpot.y.toStringAsFixed(1)}$unit',
                    textStyle,
                  );
                }
                
                String labelPrefix = '';
                if (touchedSpot.barIndex == 0) {
                  labelPrefix = 'Max: ';
                } else if (touchedSpot.barIndex == 1) {
                  labelPrefix = 'Med: ';
                } else if (touchedSpot.barIndex == 2) {
                  labelPrefix = 'Min: ';
                }

                final textStyle = TextStyle(
                  color: touchedSpot.bar.color ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                );
                return LineTooltipItem(
                  '$labelPrefix${touchedSpot.y.toStringAsFixed(1)}$unit',
                  textStyle,
                );
              }).toList();
            },
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                // Only draw label at exact integer positions (one per data point)
                if (value != value.roundToDouble()) return const Text('');
                int index = value.toInt();
                if (index >= 0 && index < dataList.length) {
                  final item = dataList[index];
                  final String dateStr = item['date'] ?? '';
                  if (dateStr.contains('-')) {
                    final parts = dateStr.split('-');
                    if (parts.length == 3) {
                      return Text(
                        '${parts[2]}/${parts[1]}',
                        style: const TextStyle(color: Colors.white54, fontSize: 9),
                      );
                    } else if (parts.length == 2) {
                      if (parts[1].startsWith('W')) {
                        return Text(
                          _formatWeekLabel(item),
                          style: const TextStyle(color: Colors.white54, fontSize: 9),
                        );
                      } else {
                        final yearShort = parts[0].substring(2);
                        return Text(
                          '${parts[1]}/$yearShort',
                          style: const TextStyle(color: Colors.white54, fontSize: 9),
                        );
                      }
                    }
                  } else {
                    return Text(
                      dateStr,
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    );
                  }
                }
                return const Text('');
              },
              reservedSize: 20,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        // Explicit X and Y axis border lines
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5),
            bottom: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
        ),
        lineBarsData: _selectedPeriod == 'Horas'
            ? [avgBar]
            : [maxBar, avgBar, minBar],
      ),
    );
  }

  Widget _buildThermalAmplitudeChart({required List<Map<String, dynamic>> dataList}) {
    List<FlSpot> amplitudeSpots = [];

    for (int i = 0; i < dataList.length; i++) {
      final item = dataList[i];
      double max = (item['max_temp'] as num).toDouble();
      double min = (item['min_temp'] as num).toDouble();
      double amplitude = max - min;
      amplitudeSpots.add(FlSpot(i.toDouble(), amplitude));
    }

    double minY = 0.0;
    double maxY = 20.0;
    if (dataList.isNotEmpty) {
      double minYVal = double.infinity;
      double maxYVal = double.negativeInfinity;
      for (var item in dataList) {
        double max = (item['max_temp'] as num).toDouble();
        double min = (item['min_temp'] as num).toDouble();
        double amplitude = max - min;
        if (amplitude < minYVal) minYVal = amplitude;
        if (amplitude > maxYVal) maxYVal = amplitude;
      }
      minY = (minYVal - 1.0).floorToDouble();
      if (minY < 0.0) minY = 0.0;
      maxY = (maxYVal + 1.0).ceilToDouble();
    }

    final ampBar = LineChartBarData(
      spots: amplitudeSpots,
      isCurved: true,
      color: Colors.purpleAccent,
      barWidth: 3.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(
        show: true,
        color: Colors.purpleAccent.withOpacity(0.08),
      ),
    );

    List<ShowingTooltipIndicators> showingTooltips = [];
    if (_showingAmpTooltipIndex != null && _showingAmpTooltipIndex! < amplitudeSpots.length) {
      showingTooltips = [
        ShowingTooltipIndicators([
          LineBarSpot(ampBar, 0, amplitudeSpots[_showingAmpTooltipIndex!]),
        ])
      ];
    }

    return LineChart(
      LineChartData(
        minX: -0.5,
        maxX: dataList.isEmpty ? 0.0 : dataList.length.toDouble() - 0.5,
        minY: minY,
        maxY: maxY,
        showingTooltipIndicators: showingTooltips,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent) {
              if (response != null && response.lineBarSpots != null && response.lineBarSpots!.isNotEmpty) {
                final index = response.lineBarSpots!.first.spotIndex;
                setState(() {
                  _showingAmpTooltipIndex = (_showingAmpTooltipIndex == index) ? null : index;
                });
              } else {
                setState(() {
                  _showingAmpTooltipIndex = null;
                });
              }
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                final textStyle = TextStyle(
                  color: touchedSpot.bar.color ?? Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                );
                return LineTooltipItem(
                  'Amp: ${touchedSpot.y.toStringAsFixed(1)} º',
                  textStyle,
                );
              }).toList();
            },
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                // Only draw label at exact integer positions (one per data point)
                if (value != value.roundToDouble()) return const Text('');
                int index = value.toInt();
                if (index >= 0 && index < dataList.length) {
                  final item = dataList[index];
                  final String dateStr = item['date'] ?? '';
                  if (dateStr.contains('-')) {
                    final parts = dateStr.split('-');
                    if (parts.length == 3) {
                      return Text(
                        '${parts[2]}/${parts[1]}',
                        style: const TextStyle(color: Colors.white54, fontSize: 9),
                      );
                    } else if (parts.length == 2) {
                      if (parts[1].startsWith('W')) {
                        return Text(
                          _formatWeekLabel(item),
                          style: const TextStyle(color: Colors.white54, fontSize: 9),
                        );
                      } else {
                        final yearShort = parts[0].substring(2);
                        return Text(
                          '${parts[1]}/$yearShort',
                          style: const TextStyle(color: Colors.white54, fontSize: 9),
                        );
                      }
                    }
                  } else {
                    return Text(
                      dateStr,
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    );
                  }
                }
                return const Text('');
              },
              reservedSize: 20,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        // Explicit X and Y axis border lines
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5),
            bottom: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5),
          ),
        ),
        lineBarsData: [
          ampBar,
        ],
      ),
    );
  }

  Widget _buildChartLegend(int index) {
    if (index == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(color: Colors.purpleAccent, text: 'Amplitud (Máx - Mín)'),
        ],
      );
    }

    // For 'Horas' period only show the average
    if (_selectedPeriod == 'Horas') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(
            color: index == 0 ? Colors.orangeAccent : Colors.cyanAccent,
            text: 'Media por hora',
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem(color: Colors.redAccent, text: 'Máx'),
        const SizedBox(width: 16),
        _buildLegendItem(
          color: index == 0 ? Colors.orangeAccent : Colors.cyanAccent,
          text: 'Med',
        ),
        const SizedBox(width: 16),
        _buildLegendItem(color: Colors.blueAccent, text: 'Mín'),
      ],
    );
  }

  Widget _buildLegendItem({required Color color, required String text}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
