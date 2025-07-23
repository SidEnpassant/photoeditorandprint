import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photoeditor2/presentation/screens/splash_screen.dart';
import 'package:photoeditor2/presentation/screens/permission_screen.dart';
import 'package:photoeditor2/presentation/screens/camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const PhotoEditorApp());
}

class PhotoEditorApp extends StatelessWidget {
  const PhotoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
      routes: {
        '/permission': (context) => const PermissionScreen(),
        '/camera': (context) => const CameraScreen(),
      },
    );
  }
}
