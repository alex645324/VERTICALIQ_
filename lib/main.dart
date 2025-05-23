import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/shift_schedule_screen.dart';
import 'services/storage_service.dart';
import 'package:flutter_background/flutter_background.dart';
import 'services/background_service.dart';

void main() async {
  print('main: App starting');
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();  // prepare SharedPreferences
  print('main: StorageService initialized');
  // request and enable background execution 
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
  
  print('main: Running app');
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    print('_MyAppState: initState called');
    // Start the periodic check after the app has initialized
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      print('_MyAppState: scheduleTimer tick');
      BackgroundService().checkSchedule();
    });
  }

  @override
  void dispose() {
    print('_MyAppState: dispose called');
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
        ),
        home: const ShiftScheduleScreen(),
      ),
    );
  }
}