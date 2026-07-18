import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:temperature_app/data/database_helper.dart';

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
  
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _detailedHistory = [];
  int _selectedIndex = 0;
  
  // Period filter: 'Semana' (last 7 entries) or 'Mes' (last 30 entries)
  String _selectedPeriod = 'Semana';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    
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
    final historyData = await DatabaseHelper.instance.getDailyAverages();
    final detailedData = await DatabaseHelper.instance.getDetailedMeasurements();
    setState(() {
      _history = historyData;
      _detailedHistory = detailedData;
    });
  }

  Future<void> _triggerMeasurement() async {
    setState(() {
      _isMeasuring = true;
      _manualMeasurementRequested = true;
    });
    // Set trigger to 1 in Firebase RTDB so Arduino runs the measurement
    await _databaseRef.child('commands').update({
      'trigger_measurement': 1,
    });
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_history.isEmpty) return [];
    int limit = _selectedPeriod == 'Semana' ? 7 : 30;
    if (_history.length <= limit) {
      return _history;
    }
    return _history.sublist(_history.length - limit);
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
            const SizedBox(height: 50),
            // Measure Button
            _buildMeasureButton(),
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

  Widget _buildMeasureButton() {
    return InkWell(
      onTap: _isMeasuring ? null : _triggerMeasurement,
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          gradient: _isMeasuring
              ? const LinearGradient(colors: [Colors.grey, Colors.black26])
              : const LinearGradient(
                  colors: [Colors.cyan, Colors.blueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            if (!_isMeasuring)
              BoxShadow(
                color: Colors.cyan.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isMeasuring) ...[
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Midiendo...',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ] else ...[
              const Icon(Icons.refresh_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Text(
                'Medir Ahora',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ]
          ],
        ),
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
    if (_history.isEmpty) {
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
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _triggerMeasurement,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tomar Medida'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.white,
                ),
              )
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
          
          // Period Selector (Semana / Mes)
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
                  _buildPeriodButton('Semana'),
                  _buildPeriodButton('Mes'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Section 1: Temperature Chart
          _buildChartSection(
            title: 'Temperatura (Mín / Máx / Med)',
            chart: _buildTripleLineChart(isTemp: true, dataList: filteredData),
            legend: _buildChartLegend(0),
          ),
          const SizedBox(height: 24),
          
          // Section 2: Humidity Chart
          _buildChartSection(
            title: 'Humedad (Mín / Máx / Med)',
            chart: _buildTripleLineChart(isTemp: false, dataList: filteredData),
            legend: _buildChartLegend(1),
          ),
          const SizedBox(height: 24),
          
          // Section 3: Thermal Amplitude Chart
          _buildChartSection(
            title: 'Amplitud Térmica Diaria (Máx - Mín)',
            chart: _buildThermalAmplitudeChart(dataList: filteredData),
            legend: _buildChartLegend(2),
          ),
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

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index >= 0 && index < dataList.length) {
                  final String dateStr = dataList[index]['date'] ?? '';
                  final parts = dateStr.split('-');
                  if (parts.length == 3) {
                    return Text(
                      '${parts[2]}/${parts[1]}',
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
          // Max Line
          LineChartBarData(
            spots: maxSpots,
            isCurved: true,
            color: Colors.redAccent,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
          ),
          // Average Line
          LineChartBarData(
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
          ),
          // Min Line
          LineChartBarData(
            spots: minSpots,
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
          ),
        ],
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

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index >= 0 && index < dataList.length) {
                  final String dateStr = dataList[index]['date'] ?? '';
                  final parts = dateStr.split('-');
                  if (parts.length == 3) {
                    return Text(
                      '${parts[2]}/${parts[1]}',
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
          LineChartBarData(
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
          ),
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
