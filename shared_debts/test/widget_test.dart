import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_debts/app.dart';
import 'package:shared_debts/models/debt.dart';
import 'package:shared_debts/models/group.dart';
import 'package:shared_debts/models/reminder_settings.dart';
import 'package:shared_debts/screens/group_details_screen.dart';
import 'package:shared_debts/screens/groups_screen.dart';
import 'package:shared_debts/screens/sign_in_screen.dart';
import 'package:shared_debts/services/auth_service.dart';
import 'package:shared_debts/services/group_service.dart';
import 'package:shared_debts/services/reminder_service.dart';

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
      MaterialApp(home: GroupsScreen(groupService: mockService)),
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
      MaterialApp(home: GroupsScreen(groupService: mockService)),
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

  test(
    'GroupService stores creator as first member and saves fields',
    () async {
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
    },
  );

  test('Valid invitation creation and joining flow', () async {
    final service = GroupService();
    // User 1 creates group
    final group = await service.createGroup(
      name: 'Road Trip',
      kind: GroupKind.trip,
      creatorId: 'user_1',
    );

    // User 1 creates invitation token
    final token = await service.createInvitation(
      groupId: group.id,
      creatorId: 'user_1',
    );
    expect(token, isNotEmpty);
    expect(token.length, 12);

    // User 2 joins using the token
    await service.joinGroupWithToken(token, 'user_2');

    // Verify User 2 now sees the group
    final user2Groups = await service.streamGroups('user_2').first;
    expect(user2Groups.length, 1);
    expect(user2Groups.first.name, 'Road Trip');
    expect(user2Groups.first.memberCount, 2);
    expect(user2Groups.first.memberIds, containsAll(['user_1', 'user_2']));

    // Verify token was consumed and cannot be reused
    expect(
      () => service.joinGroupWithToken(token, 'user_3'),
      throwsA(isA<Exception>()),
    );
  });

  test('Joining with an invalid token fails', () async {
    final service = GroupService();
    expect(
      () => service.joinGroupWithToken('NON_EXISTENT_TOKEN_123', 'user_2'),
      throwsA(predicate((e) => e.toString().contains('Invalid invitation'))),
    );
  });

  test('Unauthorized invitation attempts are rejected', () async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'Secret Project',
      kind: GroupKind.shared,
      creatorId: 'user_1',
    );

    // Non-member (user_intruder) tries to create an invitation for user_1's group
    expect(
      () => service.createInvitation(
        groupId: group.id,
        creatorId: 'user_intruder',
      ),
      throwsA(predicate((e) => e.toString().contains('not a member'))),
    );

    // Joining without signed-in user ID fails
    final validToken = await service.createInvitation(
      groupId: group.id,
      creatorId: 'user_1',
    );
    expect(
      () => service.joinGroupWithToken(validToken, ''),
      throwsA(predicate((e) => e.toString().contains('User must be signed in'))),
    );

    // Member already in group cannot join again
    expect(
      () => service.joinGroupWithToken(validToken, 'user_1'),
      throwsA(predicate((e) => e.toString().contains('already a member'))),
    );

    // Unrelated user cannot revoke another group's invitation
    final token2 = await service.createInvitation(
      groupId: group.id,
      creatorId: 'user_1',
    );
    expect(
      () => service.revokeInvitation(token: token2, userId: 'unrelated_user'),
      throwsA(predicate((e) => e.toString().contains('Unauthorized'))),
    );

    // Creator can revoke the invitation
    await service.revokeInvitation(token: token2, userId: 'user_1');
    expect(
      () => service.joinGroupWithToken(token2, 'new_user'),
      throwsA(predicate((e) => e.toString().contains('Invalid invitation'))),
    );
  });

  test('Debt model converts to and from map with correct fields', () {
    final now = DateTime.now();
    final debt = Debt(
      id: 'd1',
      groupId: 'g1',
      debtorId: 'u1',
      creditorId: 'u2',
      amount: 45.50,
      note: 'Dinner',
      creatorId: 'u1',
      createdAt: now,
      status: 'open',
    );

    final map = debt.toMap();
    expect(map['groupId'], 'g1');
    expect(map['debtorId'], 'u1');
    expect(map['creditorId'], 'u2');
    expect(map['amount'], 45.50);
    expect(map['note'], 'Dinner');
    expect(map['creatorId'], 'u1');
    expect(map['status'], 'open');

    final reconstructed = Debt.fromMap('d1', {
      'groupId': 'g1',
      'debtorId': 'u1',
      'creditorId': 'u2',
      'amount': 45.50,
      'note': 'Dinner',
      'creatorId': 'u1',
      'createdAt': now,
      'status': 'open',
    });

    expect(reconstructed.id, 'd1');
    expect(reconstructed.groupId, 'g1');
    expect(reconstructed.debtorId, 'u1');
    expect(reconstructed.creditorId, 'u2');
    expect(reconstructed.amount, 45.50);
    expect(reconstructed.note, 'Dinner');
    expect(reconstructed.status, 'open');
  });

  test('Simple debt balance calculation: A owes B 50', () {
    final members = ['A', 'B'];
    final debts = [
      const Debt(
        id: 'd1',
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'B',
        amount: 50.0,
        creatorId: 'A',
      ),
    ];

    final balances = Debt.calculateBalances(members, debts);

    expect(balances['A'], -50.0);
    expect(balances['B'], 50.0);
  });

  test('Cycle debt balance calculation: A owes B 50, B owes C 50, C owes A 50 (net balance zero for everyone)', () {
    final members = ['A', 'B', 'C'];
    final debts = [
      const Debt(
        id: 'd1',
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'B',
        amount: 50.0,
        creatorId: 'A',
      ),
      const Debt(
        id: 'd2',
        groupId: 'g1',
        debtorId: 'B',
        creditorId: 'C',
        amount: 50.0,
        creatorId: 'B',
      ),
      const Debt(
        id: 'd3',
        groupId: 'g1',
        debtorId: 'C',
        creditorId: 'A',
        amount: 50.0,
        creatorId: 'C',
      ),
    ];

    final balances = Debt.calculateBalances(members, debts);

    // Everyone's net balance should be zero
    expect(balances['A'], 0.0);
    expect(balances['B'], 0.0);
    expect(balances['C'], 0.0);
  });

  test('GroupService addDebt and streamDebts with validation', () async {
    final service = GroupService();

    // Rejects non-positive amounts
    expect(
      () => service.addDebt(
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'B',
        amount: 0,
        creatorId: 'A',
      ),
      throwsA(predicate((e) => e.toString().contains('positive'))),
    );

    // Rejects same debtor and creditor
    expect(
      () => service.addDebt(
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'A',
        amount: 50,
        creatorId: 'A',
      ),
      throwsA(predicate((e) => e.toString().contains('different'))),
    );

    // Adds valid debt
    final debt = await service.addDebt(
      groupId: 'g1',
      debtorId: 'A',
      creditorId: 'B',
      amount: 75.0,
      note: 'Groceries',
      creatorId: 'A',
    );

    expect(debt.id, isNotEmpty);
    expect(debt.amount, 75.0);
    expect(debt.note, 'Groceries');
    expect(debt.status, 'open');

    final debts = await service.streamDebts('g1').first;
    expect(debts.length, 1);
    expect(debts.first.id, debt.id);
  });

  testWidgets('Tapping a group opens its details page and shows debts and balances', (tester) async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'Weekend Trip',
      kind: GroupKind.trip,
      creatorId: 'guest_user',
    );
    // Add another member via invitation
    final token = await service.createInvitation(groupId: group.id, creatorId: 'guest_user');
    await service.joinGroupWithToken(token, 'friend_456');

    // Add a debt
    await service.addDebt(
      groupId: group.id,
      debtorId: 'guest_user',
      creditorId: 'friend_456',
      amount: 40.0,
      note: 'Gas',
      creatorId: 'guest_user',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupsScreen(groupService: service),
      ),
    );
    await tester.pumpAndSettle();

    // Tap on the group
    await tester.tap(find.text('Weekend Trip'));
    await tester.pumpAndSettle();

    // Details screen is shown
    expect(find.text('Member Balances'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget);
    expect(find.text('Gas'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Add debt'), findsWidgets);

    // Verify raw UID is NOT shown; formatted readable name is shown instead
    expect(find.textContaining('guest_user'), findsNothing);
    expect(find.textContaining('friend_456'), findsNothing);
    expect(find.textContaining('Creator'), findsWidgets);
    expect(find.textContaining('Member 2'), findsWidgets);
    expect(find.text('Suggested payments'), findsOneWidget);
    expect(find.text('Creator pays Member 2 — 40'), findsOneWidget);
  });

  test('Suggested payments minimize transfers for chain debts', () {
    final members = ['A', 'B', 'C'];
    final debts = [
      Debt(
        id: 'd1',
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'B',
        amount: 50,
        creatorId: 'A',
      ),
      Debt(
        id: 'd2',
        groupId: 'g1',
        debtorId: 'B',
        creditorId: 'C',
        amount: 50,
        creatorId: 'B',
      ),
    ];

    final balances = Debt.calculateBalances(members, debts);
    final suggestions = Debt.calculateSuggestedPayments(balances);

    expect(suggestions.length, 1);
    expect(suggestions.first.payerId, 'A');
    expect(suggestions.first.recipientId, 'C');
    expect(suggestions.first.amount, 50);
  });

  test('Cycle debt results in zero balances and no suggested payments', () {
    final members = ['A', 'B', 'C'];
    final debts = [
      Debt(
        id: 'd1',
        groupId: 'g1',
        debtorId: 'A',
        creditorId: 'B',
        amount: 50,
        creatorId: 'A',
      ),
      Debt(
        id: 'd2',
        groupId: 'g1',
        debtorId: 'B',
        creditorId: 'C',
        amount: 50,
        creatorId: 'B',
      ),
      Debt(
        id: 'd3',
        groupId: 'g1',
        debtorId: 'C',
        creditorId: 'A',
        amount: 50,
        creatorId: 'C',
      ),
    ];

    final balances = Debt.calculateBalances(members, debts);
    final suggestions = Debt.calculateSuggestedPayments(balances);

    expect(balances['A'], 0.0);
    expect(balances['B'], 0.0);
    expect(balances['C'], 0.0);
    expect(suggestions, isEmpty);
  });

  test('Pending payment does not change balances; only recipient can confirm',
      () async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'Trip',
      kind: GroupKind.trip,
      creatorId: 'user_a',
    );
    final token =
        await service.createInvitation(groupId: group.id, creatorId: 'user_a');
    await service.joinGroupWithToken(token, 'user_b');

    final debt = await service.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 100.0,
      creatorId: 'user_a',
    );

    final payment = await service.requestPayment(
      groupId: group.id,
      payerId: 'user_a',
      recipientId: 'user_b',
      amount: 100.0,
    );

    // Pending payment must NOT change balances
    var payments = service.getInitialPayments(group.id)!;
    var balances = Debt.calculateBalances(
      ['user_a', 'user_b'],
      [debt],
      payments: payments,
    );
    expect(balances['user_a'], -100.0);
    expect(balances['user_b'], 100.0);

    // Payer cannot confirm their own payment
    await expectLater(
      () => service.confirmPayment(
        groupId: group.id,
        paymentId: payment.id,
        userId: 'user_a',
      ),
      throwsException,
    );

    // Unrelated user cannot confirm
    await expectLater(
      () => service.confirmPayment(
        groupId: group.id,
        paymentId: payment.id,
        userId: 'user_c',
      ),
      throwsException,
    );

    // Recipient cannot cancel payer's request
    await expectLater(
      () => service.cancelPayment(
        groupId: group.id,
        paymentId: payment.id,
        userId: 'user_b',
      ),
      throwsException,
    );

    // Recipient confirms -> balances update to 0
    await service.confirmPayment(
      groupId: group.id,
      paymentId: payment.id,
      userId: 'user_b',
    );

    payments = service.getInitialPayments(group.id)!;
    balances = Debt.calculateBalances(
      ['user_a', 'user_b'],
      [debt],
      payments: payments,
    );
    expect(balances['user_a'], 0.0);
    expect(balances['user_b'], 0.0);
    expect(Debt.calculateSuggestedPayments(balances), isEmpty);
  });

  test('Partial payment leaves remaining amount open', () async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'House',
      kind: GroupKind.shared,
      creatorId: 'user_a',
    );
    final token =
        await service.createInvitation(groupId: group.id, creatorId: 'user_a');
    await service.joinGroupWithToken(token, 'user_b');

    final debt = await service.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 100.0,
      creatorId: 'user_a',
    );

    // Pay 40 out of 100
    final payment = await service.requestPayment(
      groupId: group.id,
      payerId: 'user_a',
      recipientId: 'user_b',
      amount: 40.0,
    );
    await service.confirmPayment(
      groupId: group.id,
      paymentId: payment.id,
      userId: 'user_b',
    );

    final payments = service.getInitialPayments(group.id)!;
    final balances = Debt.calculateBalances(
      ['user_a', 'user_b'],
      [debt],
      payments: payments,
    );
    expect(balances['user_a'], -60.0);
    expect(balances['user_b'], 60.0);

    final remaining = Debt.calculateRemainingDebtAmounts([debt], payments);
    expect(remaining[debt.id], 60.0);

    final suggestions = Debt.calculateSuggestedPayments(balances);
    expect(suggestions.length, 1);
    expect(suggestions.first.amount, 60.0);
  });

  testWidgets(
      'Payer sends I paid request and Recipient confirms on GroupDetailsScreen',
      (tester) async {
    final service = GroupService();
    final group = await service.createGroup(
      name: 'Dinner',
      kind: GroupKind.shared,
      creatorId: 'user_a',
    );
    final token =
        await service.createInvitation(groupId: group.id, creatorId: 'user_a');
    await service.joinGroupWithToken(token, 'user_b');

    final updatedGroup = Group(
      id: group.id,
      name: group.name,
      kind: group.kind,
      memberCount: 2,
      creatorId: 'user_a',
      memberIds: const ['user_a', 'user_b'],
    );

    await service.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 400.0,
      creatorId: 'user_a',
    );

    // 1. Payer ('user_a', named 'Nimsara') views GroupDetailsScreen
    final payerAuth = _TestAuthService(
      testUser: _FakeUser(uid: 'user_a', displayName: 'Nimsara'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailsScreen(
          group: updatedGroup,
          groupService: service,
          authService: payerAuth,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggested payments'), findsOneWidget);
    expect(find.text('Nimsara (You) pays Member 2 — 400'), findsOneWidget);
    expect(find.text('I paid'), findsOneWidget);

    // Tap "I paid" and send partial payment of 150
    await tester.tap(find.text('I paid'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '150');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    // Pending request shown; balance unchanged (still owes 400)
    expect(find.text('Pending requests'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('-400'), findsOneWidget);

    // 2. Recipient ('user_b') views GroupDetailsScreen and confirms
    final recipientAuth = _TestAuthService(
      testUser: _FakeUser(uid: 'user_b', displayName: 'Friend'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailsScreen(
          group: updatedGroup,
          groupService: service,
          authService: recipientAuth,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Balance updated to 250 remaining, partial status shown, history recorded
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('-250'), findsOneWidget);
    expect(find.text('+250'), findsOneWidget);
    expect(find.text('Partial (250 left)'), findsOneWidget);
  });

  test('ReminderService uses 14-day default and avoids duplicates', () async {
    final fixedNow = DateTime(2026, 11, 27, 10, 0);
    final scheduler = _FakeNotificationScheduler();
    final reminderService = ReminderService(
      scheduler: scheduler,
      now: () => fixedNow,
    );
    final groupService = GroupService();

    final group = await groupService.createGroup(
      name: 'Trip',
      kind: GroupKind.trip,
      creatorId: 'user_a',
    );
    final token = await groupService.createInvitation(
      groupId: group.id,
      creatorId: 'user_a',
    );
    await groupService.joinGroupWithToken(token, 'user_b');

    // user_a owes user_b 100
    await groupService.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 100,
      creatorId: 'user_a',
    );

    final settings = await groupService.getReminderSettings('user_a');
    expect(settings.enabled, isTrue);
    expect(settings.intervalDays, 14);

    // Refresh for debtor (user_a) -> schedules 14 days from fixedNow
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled.length, 1);
    final entry = scheduler.scheduled.values.first;
    expect(entry.scheduledAt, fixedNow.add(const Duration(days: 14)));
    expect(entry.body, contains('100'));

    // Refresh again with same balance -> no duplicate schedule call
    final countBefore = scheduler.scheduleCalls;
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduleCalls, countBefore);

    // Creditor (user_b) is owed money, so user_b must NOT get a payment reminder
    await reminderService.refreshAllGroups(
      userId: 'user_b',
      groupService: groupService,
    );
    expect(scheduler.scheduleCalls, countBefore);
  });

  test('ReminderService supports custom interval, off, and cancels when settled',
      () async {
    final fixedNow = DateTime(2026, 11, 27, 10, 0);
    final scheduler = _FakeNotificationScheduler();
    final reminderService = ReminderService(
      scheduler: scheduler,
      now: () => fixedNow,
    );
    final groupService = GroupService();

    final group = await groupService.createGroup(
      name: 'Roommates',
      kind: GroupKind.shared,
      creatorId: 'user_a',
    );
    final token = await groupService.createInvitation(
      groupId: group.id,
      creatorId: 'user_a',
    );
    await groupService.joinGroupWithToken(token, 'user_b');

    await groupService.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 200,
      creatorId: 'user_a',
    );

    // Custom 5-day interval
    await groupService.saveReminderSettings(
      userId: 'user_a',
      settings: const ReminderSettings(enabled: true, intervalDays: 5),
    );
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled.length, 1);
    expect(
      scheduler.scheduled.values.first.scheduledAt,
      fixedNow.add(const Duration(days: 5)),
    );

    // Pending payment does NOT cancel the reminder
    final payment = await groupService.requestPayment(
      groupId: group.id,
      payerId: 'user_a',
      recipientId: 'user_b',
      amount: 200,
    );
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled.length, 1);

    // Confirmed payment settles balance -> reminder is cancelled
    await groupService.confirmPayment(
      groupId: group.id,
      paymentId: payment.id,
      userId: 'user_b',
    );
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled, isEmpty);

    // Add another debt, then turn reminders OFF -> cancels all
    await groupService.addDebt(
      groupId: group.id,
      debtorId: 'user_a',
      creditorId: 'user_b',
      amount: 50,
      creatorId: 'user_a',
    );
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled.length, 1);

    await groupService.saveReminderSettings(
      userId: 'user_a',
      settings: const ReminderSettings(enabled: false, intervalDays: 5),
    );
    await reminderService.refreshAllGroups(
      userId: 'user_a',
      groupService: groupService,
    );
    expect(scheduler.scheduled, isEmpty);
  });

  testWidgets('Member can open reminder settings and save custom interval',
      (tester) async {
    final groupService = GroupService();
    final scheduler = _FakeNotificationScheduler();
    final reminderService = ReminderService(scheduler: scheduler);
    final auth = _TestAuthService(
      testUser: _FakeUser(uid: 'user_a', displayName: 'Nimsara'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: GroupsScreen(
          authService: auth,
          groupService: groupService,
          reminderService: reminderService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open Payment reminders dialog
    await tester.tap(find.byTooltip('Payment reminders'));
    await tester.pumpAndSettle();

    expect(find.text('Payment reminders'), findsOneWidget);
    expect(find.text('Every 14 days'), findsOneWidget);

    // Choose Custom and enter 10 days
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '10');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await groupService.getReminderSettings('user_a');
    expect(saved.enabled, isTrue);
    expect(saved.intervalDays, 10);
  });
}

class _ScheduledEntry {
  _ScheduledEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledAt,
  });

  final int id;
  final String title;
  final String body;
  final DateTime scheduledAt;
}

class _FakeNotificationScheduler implements NotificationScheduler {
  final Map<int, _ScheduledEntry> scheduled = {};
  int scheduleCalls = 0;
  bool permissionGranted = true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    scheduleCalls++;
    scheduled[id] = _ScheduledEntry(
      id: id,
      title: title,
      body: body,
      scheduledAt: scheduledAt,
    );
  }

  @override
  Future<void> cancelReminder(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }
}

class _FakeUser implements User {
  _FakeUser({required this.uid, this.displayName});

  @override
  final String uid;

  @override
  final String? displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
