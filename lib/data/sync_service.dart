import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temperature_app/data/database_helper.dart';

class SyncService {
  static const _collectionName = 'measurements';
  static const _lastSyncKey = 'last_firestore_sync_ms';
  static const _syncIntervalHours = 23; // sync at most once every 23h

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────

  /// Call once on app startup (after SQLite is ready).
  /// • If SQLite is empty → restore from Firestore.
  /// • Then check if a daily sync upload is due.
  static Future<void> initialize() async {
    try {
      final localCount = await DatabaseHelper.instance.countMeasurements();
      if (localCount == 0) {
        await _downloadFromFirestore();
      }
      await syncNowIfNeeded();
    } catch (e) {
      // Never crash the app because of sync issues
      debugPrint('[SyncService] initialize error: $e');
    }
  }

  /// Uploads to Firestore if more than [_syncIntervalHours] have passed
  /// since the last successful sync.
  static Future<void> syncNowIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastSyncMs = prefs.getInt(_lastSyncKey) ?? 0;
      final hoursSinceLastSync = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastSyncMs))
          .inHours;

      if (hoursSinceLastSync >= _syncIntervalHours) {
        await _uploadToFirestore();
        await prefs.setInt(
          _lastSyncKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        debugPrint('[SyncService] Upload completed.');
      } else {
        debugPrint(
            '[SyncService] Skipping upload — last sync was $hoursSinceLastSync h ago.');
      }
    } catch (e) {
      debugPrint('[SyncService] syncNowIfNeeded error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // PRIVATE
  // ─────────────────────────────────────────────────────────

  /// Upload all local SQLite measurements to Firestore.
  /// Uses the timestamp (ms) as document ID → idempotent, no duplicates.
  static Future<void> _uploadToFirestore() async {
    final rows = await DatabaseHelper.instance.getAllMeasurements();
    if (rows.isEmpty) return;

    // Firestore batch writes are limited to 500 operations each
    const batchSize = 400;
    for (int i = 0; i < rows.length; i += batchSize) {
      final batch = _db.batch();
      final end = (i + batchSize) > rows.length ? rows.length : i + batchSize;
      final chunk = rows.sublist(i, end);
      for (final row in chunk) {
        final ts = row['timestamp'] as int;
        final docRef = _db.collection(_collectionName).doc(ts.toString());
        batch.set(docRef, {
          'temperature': row['temperature'],
          'humidity': row['humidity'],
          'humidityExtra': row['humidityExtra'] ?? 0.0,
          'timestamp': ts,
          'is_manual': row['is_manual'] ?? 0,
        });
      }
      await batch.commit();
    }
  }

  /// Download all Firestore documents and insert them into local SQLite.
  /// Called only when the local DB is empty (e.g. after reinstall).
  static Future<void> _downloadFromFirestore() async {
    debugPrint('[SyncService] Local DB empty — restoring from Firestore...');
    final snapshot = await _db
        .collection(_collectionName)
        .orderBy('timestamp', descending: false)
        .get();

    if (snapshot.docs.isEmpty) {
      debugPrint('[SyncService] No data in Firestore yet.');
      return;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      await DatabaseHelper.instance.insertMeasurementIfNotExists({
        'temperature': (data['temperature'] as num?)?.toDouble() ?? 0.0,
        'humidity': (data['humidity'] as num?)?.toDouble() ?? 0.0,
        'humidityExtra': (data['humidityExtra'] as num?)?.toDouble() ?? 0.0,
        'timestamp': (data['timestamp'] as int?) ?? 0,
        'is_manual': (data['is_manual'] as int?) ?? 0,
      });
    }
    debugPrint(
        '[SyncService] Restored \${snapshot.docs.length} measurements from Firestore.');
  }
}
