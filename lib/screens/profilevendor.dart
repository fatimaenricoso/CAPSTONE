import 'package:flutter/material.dart';

class ProfileVendorScreen extends StatelessWidget {
  const ProfileVendorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: const Center(child: Text("Profile Screen")),
    );
  }
}
