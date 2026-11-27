import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores a member's personal payment reminder preferences.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.intervalDays = defaultIntervalDays,
    this.updatedAt,
  });

  static const int defaultIntervalDays = 14;
  static const int minIntervalDays = 1;
  static const int maxIntervalDays = 365;

  final bool enabled;
  final int intervalDays;
  final DateTime? updatedAt;

  ReminderSettings copyWith({
    bool? enabled,
    int? intervalDays,
    DateTime? updatedAt,
  }) {
    return ReminderSettings(
      enabled: enabled ?? this.enabled,
      intervalDays: intervalDays ?? this.intervalDays,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reminderEnabled': enabled,
      'reminderIntervalDays': intervalDays,
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory ReminderSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ReminderSettings();

    final enabledRaw = map['reminderEnabled'];
    final bool enabled = enabledRaw is bool ? enabledRaw : true;

    final intervalRaw = map['reminderIntervalDays'];
    int intervalDays = defaultIntervalDays;
    if (intervalRaw is int &&
        intervalRaw >= minIntervalDays &&
        intervalRaw <= maxIntervalDays) {
      intervalDays = intervalRaw;
    }

    DateTime? updatedAt;
    final updatedRaw = map['updatedAt'];
    if (updatedRaw is Timestamp) {
      updatedAt = updatedRaw.toDate();
    } else if (updatedRaw is DateTime) {
      updatedAt = updatedRaw;
    }

    return ReminderSettings(
      enabled: enabled,
      intervalDays: intervalDays,
      updatedAt: updatedAt,
    );
  }
}
