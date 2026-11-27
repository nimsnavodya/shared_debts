import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/debt.dart';
import '../models/group.dart';
import '../models/payment.dart';
import '../models/reminder_settings.dart';
import 'group_service.dart';

/// Abstraction over local notifications to allow clean unit and widget testing.
abstract class NotificationScheduler {
  Future<void> initialize();
  Future<bool> requestPermission();
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  });
  Future<void> cancelReminder(int id);
  Future<void> cancelAll();
}

/// Production implementation backed by [FlutterLocalNotificationsPlugin].
class FlutterNotificationScheduler implements NotificationScheduler {
  FlutterNotificationScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  @override
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    await initialize();
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'payment_reminders',
      'Payment Reminders',
      channelDescription:
          'Personal reminders for your remaining unpaid group balances',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelReminder(int id) async {
    await initialize();
    if (kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }
}

class _ScheduledSignature {
  const _ScheduledSignature({
    required this.owedAmount,
    required this.intervalDays,
  });

  final double owedAmount;
  final int intervalDays;

  @override
  bool operator ==(Object other) =>
      other is _ScheduledSignature &&
      (other.owedAmount - owedAmount).abs() < 0.005 &&
      other.intervalDays == intervalDays;

  @override
  int get hashCode => Object.hash(owedAmount.toStringAsFixed(2), intervalDays);
}

/// Manages personal payment reminders for the signed-in member.
class ReminderService {
  ReminderService({
    NotificationScheduler? scheduler,
    DateTime Function()? now,
  })  : _scheduler = scheduler ?? FlutterNotificationScheduler(),
        _now = now ?? DateTime.now;

  final NotificationScheduler _scheduler;
  final DateTime Function() _now;
  final Map<String, _ScheduledSignature> _scheduledSignatures = {};

  bool _permissionCheckedThisSession = false;
  bool _hasPermission = true;

  bool get hasPermission => _hasPermission;

  static int notificationIdForGroup(String groupId) {
    return groupId.hashCode & 0x7FFFFFFF;
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2);
  }

  Future<bool> requestPermission() async {
    try {
      _hasPermission = await _scheduler.requestPermission();
      _permissionCheckedThisSession = true;
      return _hasPermission;
    } catch (e) {
      debugPrint('ReminderService: Permission request error: $e');
      return false;
    }
  }

  /// Refreshes the reminder for a single [group] for [userId].
  ///
  /// - Cancels the reminder if reminders are turned off or [userId] has no
  ///   remaining unpaid balance (settled or only owed money).
  /// - Avoids duplicate scheduling when the outstanding balance and interval
  ///   have not changed.
  Future<bool> refreshForGroup({
    required Group group,
    required String userId,
    required List<Debt> debts,
    required List<Payment> payments,
    required ReminderSettings settings,
    bool requestPermissionIfNeeded = false,
  }) async {
    if (userId.trim().isEmpty || userId == 'guest_user') {
      return true;
    }

    final notifId = notificationIdForGroup(group.id);
    final balances = Debt.calculateBalances(
      group.memberIds,
      debts,
      payments: payments,
    );
    final balance = balances[userId] ?? 0.0;
    final owedAmount = balance < -0.005 ? -balance : 0.0;

    if (!settings.enabled || owedAmount <= 0.005) {
      _scheduledSignatures.remove(group.id);
      try {
        await _scheduler.cancelReminder(notifId);
      } catch (e) {
        debugPrint('ReminderService: Error cancelling reminder: $e');
      }
      return true;
    }

    final signature = _ScheduledSignature(
      owedAmount: owedAmount,
      intervalDays: settings.intervalDays,
    );

    if (_scheduledSignatures[group.id] == signature) {
      return _hasPermission;
    }

    if (requestPermissionIfNeeded && !_permissionCheckedThisSession) {
      final granted = await requestPermission();
      if (!granted) {
        return false;
      }
    }

    final scheduledAt = _now().add(Duration(days: settings.intervalDays));
    try {
      await _scheduler.cancelReminder(notifId);
      await _scheduler.scheduleReminder(
        id: notifId,
        title: 'Payment reminder: ${group.name}',
        body:
            'You have a remaining unpaid balance of ${_formatAmount(owedAmount)}.',
        scheduledAt: scheduledAt,
      );
      _scheduledSignatures[group.id] = signature;
    } catch (e) {
      debugPrint('ReminderService: Error scheduling reminder: $e');
    }

    return _hasPermission;
  }

  /// Refreshes all group reminders for [userId] using their saved settings.
  Future<bool> refreshAllGroups({
    required String userId,
    required GroupService groupService,
    bool requestPermissionIfNeeded = false,
  }) async {
    if (userId.trim().isEmpty || userId == 'guest_user') {
      return true;
    }

    try {
      final settings = await groupService.getReminderSettings(userId);
      if (!settings.enabled) {
        _scheduledSignatures.clear();
        await _scheduler.cancelAll();
        return true;
      }

      final groups = await groupService.fetchGroupsOnce(userId);
      var permissionOk = true;
      for (final group in groups) {
        final debts = await groupService.fetchDebtsOnce(group.id);
        final payments = await groupService.fetchPaymentsOnce(group.id);
        final ok = await refreshForGroup(
          group: group,
          userId: userId,
          debts: debts,
          payments: payments,
          settings: settings,
          requestPermissionIfNeeded: requestPermissionIfNeeded,
        );
        if (!ok) permissionOk = false;
      }
      return permissionOk;
    } catch (e) {
      debugPrint('ReminderService: Error refreshing all groups: $e');
      return _hasPermission;
    }
  }

  Future<void> clearOnSignOut() async {
    _scheduledSignatures.clear();
    _permissionCheckedThisSession = false;
    try {
      await _scheduler.cancelAll();
    } catch (e) {
      debugPrint('ReminderService: Error clearing reminders on sign-out: $e');
    }
  }
}
