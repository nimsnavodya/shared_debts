import 'package:cloud_firestore/cloud_firestore.dart';

class Debt {
  const Debt({
    required this.id,
    required this.groupId,
    required this.debtorId,
    required this.creditorId,
    required this.amount,
    this.note,
    required this.creatorId,
    this.createdAt,
    this.status = 'open',
  });

  final String id;
  final String groupId;
  final String debtorId;
  final String creditorId;
  final double amount;
  final String? note;
  final String creatorId;
  final DateTime? createdAt;
  final String status;

  bool get isOpen => status == 'open';

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'debtorId': debtorId,
      'creditorId': creditorId,
      'amount': amount,
      'note': ?(note != null && note!.trim().isNotEmpty ? note!.trim() : null),
      'creatorId': creatorId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'status': status,
    };
  }

  factory Debt.fromMap(String id, Map<String, dynamic> map) {
    DateTime? createdAt;
    final createdRaw = map['createdAt'];
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    }

    final amountRaw = map['amount'];
    final double amount = (amountRaw is num) ? amountRaw.toDouble() : 0.0;

    return Debt(
      id: id,
      groupId: map['groupId'] as String? ?? '',
      debtorId: map['debtorId'] as String? ?? '',
      creditorId: map['creditorId'] as String? ?? '',
      amount: amount,
      note: map['note'] as String?,
      creatorId: map['creatorId'] as String? ?? '',
      createdAt: createdAt,
      status: map['status'] as String? ?? 'open',
    );
  }

  /// Calculates the net balance for each member in [memberIds] from [debts].
  ///
  /// For open debts:
  /// - The debtor owes money, so their net balance decreases by [amount] (-amount).
  /// - The creditor is owed money, so their net balance increases by [amount] (+amount).
  /// - Closed/settled debts are excluded.
  static Map<String, double> calculateBalances(
    List<String> memberIds,
    List<Debt> debts,
  ) {
    final Map<String, double> balances = {
      for (final id in memberIds) id: 0.0,
    };

    for (final debt in debts) {
      if (!debt.isOpen) continue;
      balances[debt.debtorId] =
          (balances[debt.debtorId] ?? 0.0) - debt.amount;
      balances[debt.creditorId] =
          (balances[debt.creditorId] ?? 0.0) + debt.amount;
    }

    // Clean up negative zero and round to 2 decimal places
    balances.updateAll((key, val) {
      if (val.abs() < 0.00001) return 0.0;
      return double.parse(val.toStringAsFixed(2));
    });

    return balances;
  }
}
