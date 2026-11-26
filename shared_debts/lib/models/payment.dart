import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a suggested transfer to settle group balances with minimal payments.
class SuggestedPayment {
  const SuggestedPayment({
    required this.payerId,
    required this.recipientId,
    required this.amount,
  });

  final String payerId;
  final String recipientId;
  final double amount;
}

/// Represents a payment request and its lifecycle (pending, confirmed, cancelled).
class Payment {
  const Payment({
    required this.id,
    required this.groupId,
    required this.payerId,
    required this.recipientId,
    required this.amount,
    required this.status,
    required this.createdBy,
    this.createdAt,
    this.confirmedBy,
    this.confirmedAt,
    this.cancelledBy,
    this.cancelledAt,
    this.note,
  });

  final String id;
  final String groupId;
  final String payerId;
  final String recipientId;
  final double amount;
  final String status; // 'pending', 'confirmed', 'cancelled'
  final String createdBy;
  final DateTime? createdAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? note;

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'payerId': payerId,
      'recipientId': recipientId,
      'amount': amount,
      'status': status,
      'createdBy': createdBy,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      if (confirmedBy != null) 'confirmedBy': confirmedBy,
      if (confirmedAt != null) 'confirmedAt': Timestamp.fromDate(confirmedAt!),
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
      if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    };
  }

  factory Payment.fromMap(String id, Map<String, dynamic> map) {
    final amountRaw = map['amount'];
    final double amount = (amountRaw is num) ? amountRaw.toDouble() : 0.0;

    return Payment(
      id: id,
      groupId: map['groupId'] as String? ?? '',
      payerId: map['payerId'] as String? ?? '',
      recipientId: map['recipientId'] as String? ?? '',
      amount: amount,
      status: map['status'] as String? ?? 'pending',
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: _parseTimestamp(map['createdAt']),
      confirmedBy: map['confirmedBy'] as String?,
      confirmedAt: _parseTimestamp(map['confirmedAt']),
      cancelledBy: map['cancelledBy'] as String?,
      cancelledAt: _parseTimestamp(map['cancelledAt']),
      note: map['note'] as String?,
    );
  }
}
