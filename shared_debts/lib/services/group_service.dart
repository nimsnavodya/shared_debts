import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/group.dart';

class GroupService {
  GroupService({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  // In-memory fallback for testing or when Firebase is not initialized
  final List<Group> _inMemoryGroups = [];
  StreamController<List<Group>>? _inMemoryController;

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
              final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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

        debugPrint('GroupService: Successfully saved group ${docRef.id} to Firestore.');
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

  void dispose() {
    _inMemoryController?.close();
  }
}

