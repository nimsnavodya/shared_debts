import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/debt.dart';
import '../models/group.dart';
import '../models/payment.dart';
import '../models/reminder_settings.dart';

class GroupService {
  GroupService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  // In-memory fallback for testing or when Firebase is not initialized
  final List<Group> _inMemoryGroups = [];
  StreamController<List<Group>>? _inMemoryController;

  // In-memory storage for invitations used in tests / fallback mode
  final Map<String, Map<String, String>> _inMemoryInvitations = {};

  // In-memory storage for debts used in tests / fallback mode
  final Map<String, List<Debt>> _inMemoryDebts = {};
  final Map<String, StreamController<List<Debt>>> _inMemoryDebtControllers = {};

  // In-memory storage for payments used in tests / fallback mode
  final Map<String, List<Payment>> _inMemoryPayments = {};
  final Map<String, StreamController<List<Payment>>>
      _inMemoryPaymentControllers = {};

  // In-memory storage for personal reminder settings
  final Map<String, ReminderSettings> _inMemoryReminderSettings = {};
  final Map<String, StreamController<ReminderSettings>>
      _inMemoryReminderControllers = {};

  FirebaseFirestore? get _firestore {
    if (_customFirestore != null) return _customFirestore;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {
      // Firebase not initialized
    }
    return null;
  }

  StreamController<List<Group>> _getInMemoryController() {
    return _inMemoryController ??= StreamController<List<Group>>.broadcast(
      onListen: () {
        _inMemoryController?.add(List.unmodifiable(_inMemoryGroups));
      },
    );
  }

  StreamController<List<Debt>> _getInMemoryDebtController(String groupId) {
    return _inMemoryDebtControllers.putIfAbsent(
      groupId,
      () => StreamController<List<Debt>>.broadcast(
        onListen: () {
          final list = _inMemoryDebts[groupId] ?? const [];
          _inMemoryDebtControllers[groupId]?.add(List.unmodifiable(list));
        },
      ),
    );
  }

  StreamController<List<Payment>> _getInMemoryPaymentController(
    String groupId,
  ) {
    return _inMemoryPaymentControllers.putIfAbsent(
      groupId,
      () => StreamController<List<Payment>>.broadcast(
        onListen: () {
          final list = _inMemoryPayments[groupId] ?? const [];
          _inMemoryPaymentControllers[groupId]?.add(List.unmodifiable(list));
        },
      ),
    );
  }

  List<Group>? getInitialGroups(String userId) {
    if (_firestore == null) {
      if (userId.isEmpty || userId == 'guest_user') {
        return List.unmodifiable(_inMemoryGroups);
      }
      return List.unmodifiable(
        _inMemoryGroups.where((g) => g.memberIds.contains(userId)).toList(),
      );
    }
    return null;
  }

  Stream<List<Group>> streamGroups(String userId) {
    final firestore = _firestore;
    if (firestore != null) {
      if (userId.isEmpty) {
        return Stream.value(const []);
      }
      return firestore
          .collection('groups')
          .where('memberIds', arrayContains: userId)
          .snapshots()
          .map((snapshot) {
            final groups = snapshot.docs.map((doc) {
              return Group.fromMap(doc.id, doc.data());
            }).toList();

            // Sort in memory by createdAt descending
            groups.sort((a, b) {
              final aTime =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });
            return groups;
          });
    }

    // In-memory fallback (e.g. unit/widget tests)
    final controller = _getInMemoryController();
    return controller.stream.map((groups) {
      if (userId.isEmpty) return groups;
      return groups.where((g) => g.memberIds.contains(userId)).toList();
    });
  }

  // ---------------------------------------------------------------
  //  Group creation
  // ---------------------------------------------------------------

  Future<Group> createGroup({
    required String name,
    required GroupKind kind,
    required String creatorId,
  }) async {
    final firestore = _firestore;
    final now = DateTime.now();

    if (firestore != null) {
      try {
        final docRef = firestore.collection('groups').doc();
        await docRef.set({
          'name': name,
          'kind': kind.name,
          'creatorId': creatorId,
          'memberIds': [creatorId],
          'createdAt': FieldValue.serverTimestamp(),
        });

        debugPrint(
          'GroupService: Successfully saved group ${docRef.id} to Firestore.',
        );
        return Group(
          id: docRef.id,
          name: name,
          kind: kind,
          memberCount: 1,
          creatorId: creatorId,
          memberIds: [creatorId],
          createdAt: now,
        );
      } catch (e) {
        debugPrint('GroupService: Error saving group to Firestore: $e');
        rethrow;
      }
    }

    // In-memory creation
    final group = Group(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      kind: kind,
      memberCount: 1,
      creatorId: creatorId,
      memberIds: [creatorId],
      createdAt: now,
    );
    _inMemoryGroups.insert(0, group);
    _getInMemoryController().add(List.unmodifiable(_inMemoryGroups));
    return group;
  }

  // ---------------------------------------------------------------
  //  Invitations
  // ---------------------------------------------------------------

  Future<String> createInvitation({
    required String groupId,
    required String creatorId,
  }) async {
    if (groupId.trim().isEmpty || creatorId.trim().isEmpty) {
      throw Exception('Invalid group or creator ID');
    }
    final firestore = _firestore;
    final token = _generateToken();
    if (firestore != null) {
      await firestore.collection('invitations').doc(token).set({
        'groupId': groupId,
        'creatorId': creatorId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      final idx = _inMemoryGroups.indexWhere((g) => g.id == groupId);
      if (idx == -1) {
        throw Exception('Group not found');
      }
      if (!_inMemoryGroups[idx].memberIds.contains(creatorId)) {
        throw Exception('User is not a member of this group');
      }
      _inMemoryInvitations[token] = {
        'groupId': groupId,
        'creatorId': creatorId,
      };
    }
    return token;
  }

  Future<void> joinGroupWithToken(String token, String userId) async {
    if (token.trim().isEmpty) throw Exception('Invalid invitation');
    if (userId.trim().isEmpty) throw Exception('User must be signed in');

    final firestore = _firestore;
    if (firestore != null) {
      final invDoc = await firestore.collection('invitations').doc(token).get();
      if (!invDoc.exists) throw Exception('Invalid invitation');
      final groupId = invDoc.data()?['groupId'] as String?;
      if (groupId == null) throw Exception('Malformed invitation');
      final groupRef = firestore.collection('groups').doc(groupId);
      await groupRef.update({
        'memberIds': FieldValue.arrayUnion([userId]),
        'inviteToken': token,
      });
      // Delete invitation after use
      try {
        await firestore.collection('invitations').doc(token).delete();
      } catch (e) {
        debugPrint('GroupService: Note, could not delete used invitation: $e');
      }
    } else {
      final inv = _inMemoryInvitations[token];
      if (inv == null) throw Exception('Invalid invitation');
      final groupId = inv['groupId'] as String;
      final idx = _inMemoryGroups.indexWhere((g) => g.id == groupId);
      if (idx == -1) throw Exception('Group not found');
      final group = _inMemoryGroups[idx];
      if (group.memberIds.contains(userId)) {
        throw Exception('User is already a member of this group');
      }
      final updated = Group(
        id: group.id,
        name: group.name,
        kind: group.kind,
        memberCount: group.memberCount + 1,
        creatorId: group.creatorId,
        memberIds: [...group.memberIds, userId],
        createdAt: group.createdAt,
      );
      _inMemoryGroups[idx] = updated;
      _getInMemoryController().add(List.unmodifiable(_inMemoryGroups));
      _inMemoryInvitations.remove(token);
    }
  }

  Future<void> revokeInvitation({
    required String token,
    required String userId,
  }) async {
    if (token.trim().isEmpty || userId.trim().isEmpty) {
      throw Exception('Token and user ID are required');
    }
    final firestore = _firestore;
    if (firestore != null) {
      await firestore.collection('invitations').doc(token).delete();
    } else {
      final inv = _inMemoryInvitations[token];
      if (inv == null) throw Exception('Invalid invitation');
      final groupId = inv['groupId']!;
      final group = _inMemoryGroups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => throw Exception('Group not found'),
      );
      if (inv['creatorId'] != userId && !group.memberIds.contains(userId)) {
        throw Exception('Unauthorized to delete invitation');
      }
      _inMemoryInvitations.remove(token);
    }
  }

  // ---------------------------------------------------------------
  //  Debts Management
  // ---------------------------------------------------------------

  List<Debt>? getInitialDebts(String groupId) {
    if (_firestore == null) {
      return List.unmodifiable(_inMemoryDebts[groupId] ?? const []);
    }
    return null;
  }

  Stream<List<Debt>> streamDebts(String groupId) {
    final firestore = _firestore;
    if (firestore != null) {
      if (groupId.isEmpty) return Stream.value(const []);
      return firestore
          .collection('groups')
          .doc(groupId)
          .collection('debts')
          .snapshots()
          .map((snapshot) {
            final debts = snapshot.docs.map((doc) {
              return Debt.fromMap(doc.id, doc.data());
            }).toList();

            // Sort in memory by createdAt descending
            debts.sort((a, b) {
              final aTime =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });
            return debts;
          });
    }

    // In-memory fallback
    final controller = _getInMemoryDebtController(groupId);
    return controller.stream;
  }

  Future<Debt> addDebt({
    required String groupId,
    required String debtorId,
    required String creditorId,
    required double amount,
    String? note,
    required String creatorId,
  }) async {
    if (amount <= 0) {
      throw Exception('Amount must be positive');
    }
    if (debtorId == creditorId) {
      throw Exception('Debtor and creditor must be different members');
    }
    if (groupId.trim().isEmpty || debtorId.trim().isEmpty || creditorId.trim().isEmpty) {
      throw Exception('Group ID, debtor, and creditor cannot be empty');
    }

    final firestore = _firestore;
    final now = DateTime.now();
    final cleanNote = (note != null && note.trim().isNotEmpty) ? note.trim() : null;

    if (firestore != null) {
      final docRef = firestore
          .collection('groups')
          .doc(groupId)
          .collection('debts')
          .doc();

      final data = {
        'groupId': groupId,
        'debtorId': debtorId,
        'creditorId': creditorId,
        'amount': amount,
        'note': ?cleanNote,
        'creatorId': creatorId,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'open',
      };

      await docRef.set(data);

      return Debt(
        id: docRef.id,
        groupId: groupId,
        debtorId: debtorId,
        creditorId: creditorId,
        amount: amount,
        note: cleanNote,
        creatorId: creatorId,
        createdAt: now,
        status: 'open',
      );
    }

    // In-memory fallback
    final debt = Debt(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      groupId: groupId,
      debtorId: debtorId,
      creditorId: creditorId,
      amount: amount,
      note: cleanNote,
      creatorId: creatorId,
      createdAt: now,
      status: 'open',
    );

    final list = _inMemoryDebts.putIfAbsent(groupId, () => []);
    list.insert(0, debt);
    _getInMemoryDebtController(groupId).add(List.unmodifiable(list));

    return debt;
  }

  // ---------------------------------------------------------------
  //  Payments Management
  // ---------------------------------------------------------------

  List<Payment>? getInitialPayments(String groupId) {
    if (_firestore == null) {
      return List.unmodifiable(_inMemoryPayments[groupId] ?? const []);
    }
    return null;
  }

  Stream<List<Payment>> streamPayments(String groupId) {
    final firestore = _firestore;
    if (firestore != null) {
      if (groupId.isEmpty) return Stream.value(const []);
      return firestore
          .collection('groups')
          .doc(groupId)
          .collection('payments')
          .snapshots()
          .map((snapshot) {
            final payments = snapshot.docs.map((doc) {
              return Payment.fromMap(doc.id, doc.data());
            }).toList();

            payments.sort((a, b) {
              final aTime =
                  a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });
            return payments;
          });
    }

    final controller = _getInMemoryPaymentController(groupId);
    return controller.stream;
  }

  Future<Payment> requestPayment({
    required String groupId,
    required String payerId,
    required String recipientId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) {
      throw Exception('Payment amount must be positive');
    }
    if (payerId == recipientId) {
      throw Exception('Payer and recipient must be different members');
    }
    if (groupId.trim().isEmpty ||
        payerId.trim().isEmpty ||
        recipientId.trim().isEmpty) {
      throw Exception('Group ID, payer, and recipient cannot be empty');
    }

    final firestore = _firestore;
    final now = DateTime.now();
    final cleanNote =
        (note != null && note.trim().isNotEmpty) ? note.trim() : null;

    if (firestore != null) {
      final docRef = firestore
          .collection('groups')
          .doc(groupId)
          .collection('payments')
          .doc();

      await docRef.set({
        'groupId': groupId,
        'payerId': payerId,
        'recipientId': recipientId,
        'amount': amount,
        'status': 'pending',
        'createdBy': payerId,
        'createdAt': FieldValue.serverTimestamp(),
        'note': ?cleanNote,
      });

      return Payment(
        id: docRef.id,
        groupId: groupId,
        payerId: payerId,
        recipientId: recipientId,
        amount: amount,
        status: 'pending',
        createdBy: payerId,
        createdAt: now,
        note: cleanNote,
      );
    }

    final payment = Payment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      groupId: groupId,
      payerId: payerId,
      recipientId: recipientId,
      amount: amount,
      status: 'pending',
      createdBy: payerId,
      createdAt: now,
      note: cleanNote,
    );

    final list = _inMemoryPayments.putIfAbsent(groupId, () => []);
    list.insert(0, payment);
    _getInMemoryPaymentController(groupId).add(List.unmodifiable(list));
    return payment;
  }

  Future<void> confirmPayment({
    required String groupId,
    required String paymentId,
    required String userId,
  }) async {
    if (groupId.trim().isEmpty ||
        paymentId.trim().isEmpty ||
        userId.trim().isEmpty) {
      throw Exception('Group ID, payment ID, and user ID are required');
    }

    final firestore = _firestore;
    if (firestore != null) {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('payments')
          .doc(paymentId)
          .update({
        'status': 'confirmed',
        'confirmedBy': userId,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final list = _inMemoryPayments[groupId];
    if (list == null) throw Exception('Payment not found');
    final idx = list.indexWhere((p) => p.id == paymentId);
    if (idx == -1) throw Exception('Payment not found');

    final existing = list[idx];
    if (!existing.isPending) {
      throw Exception('Only pending payments can be confirmed');
    }
    if (existing.recipientId != userId) {
      throw Exception('Only the named recipient can confirm this payment');
    }

    list[idx] = Payment(
      id: existing.id,
      groupId: existing.groupId,
      payerId: existing.payerId,
      recipientId: existing.recipientId,
      amount: existing.amount,
      status: 'confirmed',
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
      confirmedBy: userId,
      confirmedAt: DateTime.now(),
      note: existing.note,
    );
    _getInMemoryPaymentController(groupId).add(List.unmodifiable(list));
  }

  Future<void> cancelPayment({
    required String groupId,
    required String paymentId,
    required String userId,
  }) async {
    if (groupId.trim().isEmpty ||
        paymentId.trim().isEmpty ||
        userId.trim().isEmpty) {
      throw Exception('Group ID, payment ID, and user ID are required');
    }

    final firestore = _firestore;
    if (firestore != null) {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('payments')
          .doc(paymentId)
          .update({
        'status': 'cancelled',
        'cancelledBy': userId,
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    final list = _inMemoryPayments[groupId];
    if (list == null) throw Exception('Payment not found');
    final idx = list.indexWhere((p) => p.id == paymentId);
    if (idx == -1) throw Exception('Payment not found');

    final existing = list[idx];
    if (!existing.isPending) {
      throw Exception('Only pending payments can be cancelled');
    }
    if (existing.payerId != userId) {
      throw Exception('Only the named payer can cancel this payment');
    }

    list[idx] = Payment(
      id: existing.id,
      groupId: existing.groupId,
      payerId: existing.payerId,
      recipientId: existing.recipientId,
      amount: existing.amount,
      status: 'cancelled',
      createdBy: existing.createdBy,
      createdAt: existing.createdAt,
      cancelledBy: userId,
      cancelledAt: DateTime.now(),
      note: existing.note,
    );
    _getInMemoryPaymentController(groupId).add(List.unmodifiable(list));
  }

  // Simple token generator - 12 alphanumeric characters
  String _generateToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  void dispose() {
    _inMemoryController?.close();
    for (final c in _inMemoryDebtControllers.values) {
      c.close();
    }
    for (final c in _inMemoryPaymentControllers.values) {
      c.close();
    }
    for (final c in _inMemoryReminderControllers.values) {
      c.close();
    }
  }

  // ---------------------------------------------------------------
  //  Personal Reminder Settings & One-Shot Sync Helpers
  // ---------------------------------------------------------------

  StreamController<ReminderSettings> _getInMemoryReminderController(
    String userId,
  ) {
    return _inMemoryReminderControllers.putIfAbsent(
      userId,
      () => StreamController<ReminderSettings>.broadcast(
        onListen: () {
          final current =
              _inMemoryReminderSettings[userId] ?? const ReminderSettings();
          _inMemoryReminderControllers[userId]?.add(current);
        },
      ),
    );
  }

  Future<ReminderSettings> getReminderSettings(String userId) async {
    if (userId.trim().isEmpty) return const ReminderSettings();
    final firestore = _firestore;
    if (firestore != null) {
      final doc = await firestore.collection('users').doc(userId).get();
      if (!doc.exists) return const ReminderSettings();
      return ReminderSettings.fromMap(doc.data());
    }
    return _inMemoryReminderSettings[userId] ?? const ReminderSettings();
  }

  Stream<ReminderSettings> streamReminderSettings(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value(const ReminderSettings());
    }
    final firestore = _firestore;
    if (firestore != null) {
      return firestore.collection('users').doc(userId).snapshots().map((doc) {
        if (!doc.exists) return const ReminderSettings();
        return ReminderSettings.fromMap(doc.data());
      });
    }
    return _getInMemoryReminderController(userId).stream;
  }

  Future<void> saveReminderSettings({
    required String userId,
    required ReminderSettings settings,
  }) async {
    if (userId.trim().isEmpty) {
      throw Exception('User must be signed in');
    }
    if (settings.intervalDays < ReminderSettings.minIntervalDays ||
        settings.intervalDays > ReminderSettings.maxIntervalDays) {
      throw Exception(
        'Reminder interval must be between '
        '${ReminderSettings.minIntervalDays} and '
        '${ReminderSettings.maxIntervalDays} days',
      );
    }

    final firestore = _firestore;
    if (firestore != null) {
      await firestore.collection('users').doc(userId).set(
            settings.toMap(),
            SetOptions(merge: true),
          );
      return;
    }

    final updated = settings.copyWith(updatedAt: DateTime.now());
    _inMemoryReminderSettings[userId] = updated;
    _getInMemoryReminderController(userId).add(updated);
  }

  Future<List<Group>> fetchGroupsOnce(String userId) async {
    if (userId.trim().isEmpty) return const [];
    final firestore = _firestore;
    if (firestore != null) {
      final snapshot = await firestore
          .collection('groups')
          .where('memberIds', arrayContains: userId)
          .get();
      return snapshot.docs
          .map((doc) => Group.fromMap(doc.id, doc.data()))
          .toList();
    }
    return _inMemoryGroups
        .where((g) => g.memberIds.contains(userId))
        .toList();
  }

  Future<List<Debt>> fetchDebtsOnce(String groupId) async {
    if (groupId.trim().isEmpty) return const [];
    final firestore = _firestore;
    if (firestore != null) {
      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('debts')
          .get();
      return snapshot.docs
          .map((doc) => Debt.fromMap(doc.id, doc.data()))
          .toList();
    }
    return List.unmodifiable(_inMemoryDebts[groupId] ?? const []);
  }

  Future<List<Payment>> fetchPaymentsOnce(String groupId) async {
    if (groupId.trim().isEmpty) return const [];
    final firestore = _firestore;
    if (firestore != null) {
      final snapshot = await firestore
          .collection('groups')
          .doc(groupId)
          .collection('payments')
          .get();
      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    }
    return List.unmodifiable(_inMemoryPayments[groupId] ?? const []);
  }
}
