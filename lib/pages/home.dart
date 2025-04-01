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
        title: const Text('Home'),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _sensorStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.hasData) {
            final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            final humidity = data['humidity'] ?? 'No data';
            final temperature = data['temperature'] ?? 'No data';

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Humidity: $humidity'),
                  Text('Temperature: $temperature'),
                ],
              ),
            );
          }

          return const Center(child: Text('No data available'));
        },
      ),
    );
  }
}
