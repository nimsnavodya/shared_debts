import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_debts/app.dart';
import 'package:shared_debts/models/group.dart';
import 'package:shared_debts/screens/groups_screen.dart';
import 'package:shared_debts/screens/sign_in_screen.dart';
import 'package:shared_debts/services/auth_service.dart';
import 'package:shared_debts/services/group_service.dart';

class _TestAuthService extends AuthService {
  _TestAuthService({this.testUser, this.onSignIn, this.onSignOut});

  final User? testUser;
  final Future<UserCredential?> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  @override
  User? get currentUser => testUser;

  @override
  Stream<User?> get authStateChanges => Stream.value(testUser);

  @override
  Future<UserCredential?> signInWithGoogle() async {
    if (onSignIn != null) return onSignIn!();
    return null;
  }

  @override
  Future<void> signOut() async {
    if (onSignOut != null) await onSignOut!();
  }
}

void main() {
  testWidgets('SignInScreen displays branding and Google sign-in button', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Shared Debts'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(
      find.text(
        'Keep track of shared debts and group expenses fairly with friends.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Tapping Sign in with Google triggers signInWithGoogle', (
    tester,
  ) async {
    bool signInCalled = false;
    final testAuth = _TestAuthService(
      onSignIn: () async {
        signInCalled = true;
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authService: testAuth)),
    );

    await tester.tap(find.text('Sign in with Google'));
    await tester.pump();

    expect(signInCalled, isTrue);
  });

  testWidgets('Validation error when group name is empty', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp(home: GroupsScreen()));
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    // Tap Create with empty input
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a group name'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  testWidgets('Create a Shared group', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp(home: GroupsScreen()));
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Apartment Expenses');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Dialog should be closed
    expect(find.text('Create a group'), findsNothing);
    // Group should be visible on page
    expect(find.text('Apartment Expenses'), findsOneWidget);
    expect(find.text('Shared group · 1 member'), findsOneWidget);
  });

  testWidgets('Create a Trip group', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp(home: GroupsScreen()));
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ella Trip');
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Dialog should be closed
    expect(find.text('Create a group'), findsNothing);
    // Group should be visible on page
    expect(find.text('Ella Trip'), findsOneWidget);
    expect(find.text('Trip · 1 member'), findsOneWidget);
  });

  testWidgets('Account button shows Sign out option and triggers signOut', (
    tester,
  ) async {
    bool signOutCalled = false;
    final testAuth = _TestAuthService(
      onSignOut: () async {
        signOutCalled = true;
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: GroupsScreen(authService: testAuth)),
    );

    // Find and tap the account popup menu button
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(signOutCalled, isTrue);
  });

  testWidgets('GroupsScreen shows loading indicator when waiting for stream', (
    tester,
  ) async {
    final completer = Completer<List<Group>>();
    final mockService = _MockGroupService(
      stream: completer.future.asStream(),
      initialGroups: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupsScreen(groupService: mockService),
      ),
    );

    // Initial frame should show loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete([
      const Group(
        id: 'g1',
        name: 'Weekend Getaway',
        kind: GroupKind.trip,
        memberCount: 1,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Weekend Getaway'), findsOneWidget);
  });

  testWidgets('GroupsScreen shows error state when stream has error', (
    tester,
  ) async {
    final mockService = _MockGroupService(
      stream: Stream.error('Permission denied or network failure'),
      initialGroups: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupsScreen(groupService: mockService),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load groups'), findsOneWidget);
    expect(
      find.textContaining('Permission denied or network failure'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  test('Group model converts to and from map with correct fields', () {
    final now = DateTime.now();
    final group = Group(
      id: 'group_123',
      name: 'Summer Trip',
      kind: GroupKind.trip,
      memberCount: 2,
      creatorId: 'user_abc',
      memberIds: const ['user_abc', 'user_xyz'],
      createdAt: now,
    );

    final map = group.toMap();
    expect(map['name'], 'Summer Trip');
    expect(map['kind'], 'trip');
    expect(map['creatorId'], 'user_abc');
    expect(map['memberIds'], ['user_abc', 'user_xyz']);

    final reconstructed = Group.fromMap('group_123', {
      'name': 'Summer Trip',
      'kind': 'trip',
      'creatorId': 'user_abc',
      'memberIds': ['user_abc', 'user_xyz'],
      'createdAt': now,
    });

    expect(reconstructed.id, 'group_123');
    expect(reconstructed.name, 'Summer Trip');
    expect(reconstructed.kind, GroupKind.trip);
    expect(reconstructed.memberCount, 2);
    expect(reconstructed.creatorId, 'user_abc');
    expect(reconstructed.memberIds, ['user_abc', 'user_xyz']);
    expect(reconstructed.createdAt, now);
  });

  test('GroupService stores creator as first member and saves fields', () async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'Office Lunch',
      kind: GroupKind.shared,
      creatorId: 'test_creator_123',
    );

    expect(group.name, 'Office Lunch');
    expect(group.kind, GroupKind.shared);
    expect(group.creatorId, 'test_creator_123');
    expect(group.memberIds, ['test_creator_123']);
    expect(group.memberCount, 1);
    expect(group.createdAt, isNotNull);

    final streamFuture = service.streamGroups('test_creator_123').first;
    final groups = await streamFuture;
    expect(groups.length, 1);
    expect(groups.first.id, group.id);
  });
}

class _MockGroupService extends GroupService {
  _MockGroupService({this.stream, this.initialGroups});

  final Stream<List<Group>>? stream;
  final List<Group>? initialGroups;

  @override
  List<Group>? getInitialGroups(String userId) => initialGroups;

  @override
  Stream<List<Group>> streamGroups(String userId) {
    if (stream != null) return stream!;
    return super.streamGroups(userId);
  }
}
