import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BluetoothScreen(),
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  FlutterBlue flutterBlue = FlutterBlue.instance;
  StreamSubscription<BluetoothDeviceState>? deviceConnection;
  BluetoothDevice? device;
  List<int> receivedData = [];
  final double threshold = 80;

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _requestNotificationPermission();
    // Start scanning for Bluetooth devices
    //_startScanning();
  }

  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isGranted) {
      // Notification permission is already granted
      return;
    }
    // Request notification permission
    final permissionStatus = await Permission.notification.request();
    if (permissionStatus != PermissionStatus.granted) {
      // Permission not granted, show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Notification permission is required to receive alerts.'),
        ),
      );
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _startScanning() async {
    try {
      // Check if location permission is granted
      if (await Permission.location.isGranted) {
        // Location permission is granted, proceed with Bluetooth scanning
        bool isBluetoothOn = await FlutterBlue.instance.isOn;
        if (!isBluetoothOn) {
          // Bluetooth is not enabled, prompt the user to enable it
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please enable Bluetooth to start scanning.'),
            ),
          );
          return;
        }

        // Indicate to the user that scanning has started
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanning for devices...'),
          ),
        );

        // Start scanning for Bluetooth devices
        flutterBlue.startScan(timeout: Duration(seconds: 4));
        flutterBlue.scanResults.listen((results) {
          // Look for your ESP32 device here
          for (ScanResult r in results) {
            if (r.device.name == 'Helmet') {
              // Connect to the device
              deviceConnection = r.device.state.listen((state) {
                if (state == BluetoothDeviceState.connected) {
                  // Device connected, start reading data
                  device = r.device;
                  _startReading();
                }
              });
              flutterBlue.stopScan();
              break;
            }
          }
        });
      } else {
        // Location permission is not granted, request it
        await Permission.location.request();
      }
    } catch (e) {
      print('Error starting scan: $e');
      // Show an error message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start scanning: $e'),
        ),
      );
    }
  }

  void _startReading() async {
    List<BluetoothService> services = await device!.discoverServices();
    services.forEach((service) {
      service.characteristics.forEach((characteristic) {
        if (characteristic.properties.read) {
          characteristic.value.listen((value) {
            setState(() {
              receivedData.addAll(value);
              if (receivedData.length >= 5) {
                processReceivedData(receivedData);
                receivedData.clear();
              }
            });
          });
        }
      });
    });
  }

  void processReceivedData(List<int> data) {
    // Deserialize the received bytes into your struct
    // This assumes the struct fields are uint8_t
    int bezo1 = data[0];
    int bezo2 = data[1];
    int bezo3 = data[2];
    int bezo4 = data[3];
    int alcohol = data[4];
    // Do something with the received data, e.g., update UI
    print('Received Data: $bezo1, $bezo2, $bezo3, $bezo4, $alcohol');
    checkThreshold(bezo1);
    checkThreshold(bezo2);
    checkThreshold(bezo3);
    checkThreshold(bezo4);
    checkThreshold(alcohol);
  }

  void checkThreshold(int value) async {
    if (value > threshold) {
      await _showNotification();
    }
  }

  Future<void> _showNotification() async {
    // Check if notification permission is granted
    if (!(await Permission.notification.isGranted)) {
      // Notification permission not granted, show a message to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Notification permission is required to receive alerts.'),
        ),
      );
      return;
    }
    // Notification permission is granted, proceed with showing the notification
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your channel id',
      'your channel name',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Threshold Exceeded',
      'One of the values has exceeded 80%',
      platformChannelSpecifics,
    );
  }

  @override
  void dispose() {
    deviceConnection?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Bluetooth'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _startScanning,
              child: Text('Start Scanning'),
            ),
          ],
        ),
      ),
    );
  }
}
