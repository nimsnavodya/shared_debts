import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/groups_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/auth_service.dart';

class SharedDebtsApp extends StatelessWidget {
  const SharedDebtsApp({
    super.key,
    this.authService,
    this.home,
  });

  final AuthService? authService;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shared Debts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167D68)),
        useMaterial3: true,
      ),
      home: home ?? _AuthGate(authService: authService ?? AuthService()),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return SignInScreen(authService: authService);
        }

        return GroupsScreen(authService: authService);
      },
    );
  }
}
