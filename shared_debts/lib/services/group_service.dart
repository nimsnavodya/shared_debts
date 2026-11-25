import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/group.dart';

class GroupService {
  GroupService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  final FirebaseFirestore? _customFirestore;

  // In-memory fallback for testing or when Firebase is not initialized
  final List<Group> _inMemoryGroups = [];
  StreamController<List<Group>>? _inMemoryController;

  // In-memory storage for invitations used in tests / fallback mode
  final Map<String, Map<String, String>> _inMemoryInvitations = {};

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

  // Simple token generator - 12 alphanumeric characters
  String _generateToken() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  void dispose() {
    _inMemoryController?.close();
  }
}
