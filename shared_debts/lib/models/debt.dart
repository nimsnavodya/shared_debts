import 'package:cloud_firestore/cloud_firestore.dart';

import 'payment.dart';

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

  /// Calculates the net balance for each member in [memberIds] from [debts]
  /// and confirmed [payments].
  ///
  /// For open debts:
  /// - The debtor owes money, so their net balance decreases by [amount] (-amount).
  /// - The creditor is owed money, so their net balance increases by [amount] (+amount).
  ///
  /// For confirmed payments:
  /// - The payer paid money, so their net balance increases by [amount] (+amount).
  /// - The recipient received money, so their net balance decreases by [amount] (-amount).
  ///
  /// Pending or cancelled payments do not affect balances.
  static Map<String, double> calculateBalances(
    List<String> memberIds,
    List<Debt> debts, {
    List<Payment> payments = const [],
  }) {
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

    for (final payment in payments) {
      if (!payment.isConfirmed) continue;
      balances[payment.payerId] =
          (balances[payment.payerId] ?? 0.0) + payment.amount;
      balances[payment.recipientId] =
          (balances[payment.recipientId] ?? 0.0) - payment.amount;
    }

    // Clean up negative zero and round to 2 decimal places
    balances.updateAll((key, val) {
      if (val.abs() < 0.00001) return 0.0;
      return double.parse(val.toStringAsFixed(2));
    });

    return balances;
  }

  /// Minimizes the number of transfers required to settle all [balances].
  ///
  /// Returns an empty list when everyone's balance is effectively zero.
  static List<SuggestedPayment> calculateSuggestedPayments(
    Map<String, double> balances,
  ) {
    final debtors = <_BalanceEntry>[];
    final creditors = <_BalanceEntry>[];

    for (final entry in balances.entries) {
      final rounded = double.parse(entry.value.toStringAsFixed(2));
      if (rounded < -0.005) {
        debtors.add(_BalanceEntry(entry.key, -rounded));
      } else if (rounded > 0.005) {
        creditors.add(_BalanceEntry(entry.key, rounded));
      }
    }

    // Sort descending by amount, then by ID for deterministic ordering
    debtors.sort((a, b) {
      final cmp = b.amount.compareTo(a.amount);
      return cmp != 0 ? cmp : a.memberId.compareTo(b.memberId);
    });
    creditors.sort((a, b) {
      final cmp = b.amount.compareTo(a.amount);
      return cmp != 0 ? cmp : a.memberId.compareTo(b.memberId);
    });

    final suggestions = <SuggestedPayment>[];
    int i = 0;
    int j = 0;

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];
      final transfer = debtor.amount < creditor.amount
          ? debtor.amount
          : creditor.amount;
      final roundedTransfer = double.parse(transfer.toStringAsFixed(2));

      if (roundedTransfer >= 0.01) {
        suggestions.add(
          SuggestedPayment(
            payerId: debtor.memberId,
            recipientId: creditor.memberId,
            amount: roundedTransfer,
          ),
        );
      }

      debtor.amount -= transfer;
      creditor.amount -= transfer;

      if (debtor.amount < 0.005) i++;
      if (creditor.amount < 0.005) j++;
    }

    return suggestions;
  }

  /// Calculates remaining unpaid amounts per debt ID by allocating confirmed
  /// payments from the same payer to the same recipient (oldest debts first).
  static Map<String, double> calculateRemainingDebtAmounts(
    List<Debt> debts,
    List<Payment> payments,
  ) {
    final remainingByDebtId = <String, double>{};
    final poolByPair = <String, double>{};

    for (final payment in payments) {
      if (!payment.isConfirmed) continue;
      final key = '${payment.payerId}->${payment.recipientId}';
      poolByPair[key] = (poolByPair[key] ?? 0.0) + payment.amount;
    }

    // Sort open debts oldest-first so earlier debts are settled first
    final sortedDebts = debts.where((d) => d.isOpen).toList()
      ..sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });

    for (final debt in sortedDebts) {
      final key = '${debt.debtorId}->${debt.creditorId}';
      final available = poolByPair[key] ?? 0.0;
      if (available >= debt.amount - 0.005) {
        remainingByDebtId[debt.id] = 0.0;
        poolByPair[key] = available - debt.amount;
      } else if (available > 0.005) {
        final left = double.parse((debt.amount - available).toStringAsFixed(2));
        remainingByDebtId[debt.id] = left;
        poolByPair[key] = 0.0;
      } else {
        remainingByDebtId[debt.id] = debt.amount;
      }
    }

    return remainingByDebtId;
  }
}

class _BalanceEntry {
  _BalanceEntry(this.memberId, this.amount);
  final String memberId;
  double amount;
}
