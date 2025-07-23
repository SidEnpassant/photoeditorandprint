import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'dart:async';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Navigate to permission screen after 1.5 seconds
    Timer(const Duration(milliseconds: 1500), () {
      Navigator.of(context).pushReplacementNamed('/permission');
    });
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text(
              'Photo Editor',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            const SpinKitFadingCircle(color: Colors.blueAccent, size: 48.0),
          ],
        ),
      ),
    );
  }
}
