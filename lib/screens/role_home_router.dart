import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'home/home_screen.dart';

class RoleHomeRouter extends StatelessWidget {
  const RoleHomeRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    debugPrint("USER ROLE : ${auth.userRole}");
    debugPrint("USER TYPE : ${auth.userType}");

    if (!auth.isLoggedIn) {
      return const HomeScreen();
    }

    if (auth.userType == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const HomeScreen();
  }
}
