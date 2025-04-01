import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  late Stream<DatabaseEvent> _sensorStream;

  @override
  void initState() {
    super.initState();
    // Escucha en tiempo real los cambios en el nodo 'sensors'
    _sensorStream = _databaseRef.child('sensors').onValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Temperatura'),
        backgroundColor: Colors.blueAccent, // Color de la barra superior
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade700,
              Colors.blue.shade300
            ], // Gradiente de azul oscuro a azul claro
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: StreamBuilder<DatabaseEvent>(
          stream: _sensorStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (snapshot.hasData) {
              final data =
                  snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              final humidity = data['humidity'] ?? 'No data';
              final temperature = data['temperature'] ?? 'No data';

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Tarjeta para la temperatura
                      Card(
                        color: Colors.white.withOpacity(0.8),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.thermostat,
                                color: Colors.orange,
                                size: 50,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Temperature',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '$temperature °C',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Tarjeta para la humedad
                      Card(
                        color: Colors.white.withOpacity(0.8),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.water_drop,
                                color: Colors.blue,
                                size: 50,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Humidity',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '$humidity %',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return const Center(child: Text('No data available'));
          },
        ),
      ),
    );
  }
}
