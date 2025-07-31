import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/shift_schedule_screen.dart';
import 'services/storage_service.dart';
import 'package:flutter_background/flutter_background.dart';
import 'services/background_service.dart';

void main() async {
  print('main: App starting');
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase first
  await Firebase.initializeApp();
  print('main: Firebase initialized');
  
  await StorageService.init();
  print('main: StorageService initialized');
  
  // Initialize background execution differently for iOS vs Android
  if (Platform.isAndroid) {
    await _initializeAndroidBackground();
  } else if (Platform.isIOS) {
    await _initializeIOSBackground();
  }
  
  print('main: Running app');
  runApp(const MyApp());
}

Future<void> _initializeAndroidBackground() async {
  const androidConfig = FlutterBackgroundAndroidConfig(
    notificationTitle: 'VMI Driver App',
    notificationText: 'Tracking sensors in background',
    notificationImportance: AndroidNotificationImportance.normal,
    notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
  );

  bool hasPermissions = await FlutterBackground.hasPermissions;
  print('main: FlutterBackground.hasPermissions = $hasPermissions');
  if (!hasPermissions) {
    print('main: Requesting background permissions');
    await FlutterBackground.initialize(androidConfig: androidConfig);
    await FlutterBackground.enableBackgroundExecution();
    print('main: Background execution enabled');
  }
}

Future<void> _initializeIOSBackground() async {
  // iOS background handling is more restrictive
  // We'll rely on app lifecycle states instead of persistent background execution
  print('main: iOS detected - using app lifecycle for background handling');
  
  // Request permissions that we'll need
  await BackgroundService().requestPermissions();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    print('_MyAppState: initState called');
    WidgetsBinding.instance.addObserver(this);
    
    // Start the periodic check
    _startScheduleTimer();
  }

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      print('_MyAppState: scheduleTimer tick');
      BackgroundService().checkSchedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('_MyAppState: App lifecycle state changed to $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground
        _startScheduleTimer();
        BackgroundService().handleAppForeground();
        break;
      case AppLifecycleState.paused:
        // App went to background
        if (Platform.isIOS) {
          // On iOS, we have limited background time
          BackgroundService().handleAppBackground();
        }
        break;
      case AppLifecycleState.detached:
        // App is being terminated
        BackgroundService().handleAppTermination();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    print('_MyAppState: dispose called');
    WidgetsBinding.instance.removeObserver(this);
    _scheduleTimer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    print('_MyAppState: build called');
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StorageService()),
      ],
      child: MaterialApp(
        title: 'VMI Driver App',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          // Add iOS-specific styling
          platform: Platform.isIOS ? TargetPlatform.iOS : TargetPlatform.android,
        ),
        home: const ShiftScheduleScreen(),
      ),
    );
  }
}