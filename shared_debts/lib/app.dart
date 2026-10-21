import 'package:flutter/material.dart';
import 'screens/groups_screen.dart';

class SharedDebtsApp extends StatelessWidget {
  const SharedDebtsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shared Debts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167D68)),
        useMaterial3: true,
      ),
      home: const GroupsScreen(),
    );
  }
}
