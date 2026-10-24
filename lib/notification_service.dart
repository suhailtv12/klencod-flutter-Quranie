import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:adhan/adhan.dart';

// معالج إشعارات فايربيس في الخلفية عند إغلاق التطبيق
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. تهيئة المناطق الزمنية
    tz.initializeTimeZones();

    // 2. إعدادات الإشعارات المحلية للأندرويد
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await flutterLocalNotificationsPlugin.initialize(initSettings);

    // 3. تهيئة فايربيس بشكل آمن (لن يعلق التطبيق إذا لم تضف الملف بعد)
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // الاستماع للإشعارات والتطبيق مفتوح
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          showInstantNotification(
            title: message.notification!.title ?? 'قرآني',
            body: message.notification!.body ?? '',
          );
        }
      });
    } catch (e) {
      debugPrint("تنبيه فايربيس: لم يتم ربط google-services.json بعد، سيعمل التطبيق بدونه بسلاسة: $e");
    }
  }

  // إشعار فوري
  Future<void> showInstantNotification({required String title, required String body}) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'qurani_instant_channel',
      'إشعارات عامة',
      channelDescription: 'قناة الإشعارات الفورية لآيات وتذكيرات تطبيق قرآني',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(0, title, body, details);
  }

  // جدولة إشعارات الصلوات الخمس يومياً
  Future<void> schedulePrayerNotifications(PrayerTimes prayerTimes) async {
    // إلغاء الجدولة السابقة لتجديدها حسب المواقيت الجديدة
    await flutterLocalNotificationsPlugin.cancelAll();

    final prayers = {
      1: {'name': 'صلاة الفجر', 'time': prayerTimes.fajr},
      2: {'name': 'صلاة الظهر', 'time': prayerTimes.dhuhr},
      3: {'name': 'صلاة العصر', 'time': prayerTimes.asr},
      4: {'name': 'صلاة المغرب', 'time': prayerTimes.maghrib},
      5: {'name': 'صلاة العشاء', 'time': prayerTimes.isha},
    };

    prayers.forEach((id, data) async {
      final String prayerName = data['name'] as String;
      final DateTime time = data['time'] as DateTime;

      // تحويل وقت الصلاة إلى توقيت المنطقة الزمنية المحلي
      var scheduledDate = tz.TZDateTime.from(time, tz.local);

      // إذا كان وقت اليوم قد مضى، يتم الجدولة لليوم التالي
      if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'prayer_times_channel',
        'مواقيت الصلاة',
        channelDescription: 'تذكير بدخول أوقات الصلوات المفروضة',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        'حان الآن موعد $prayerName',
        'حي على الصلاة.. حي على الفلاح',
        scheduledDate,
        const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // تكرار يومي بنفس الساعة
      );
    });
  }
}