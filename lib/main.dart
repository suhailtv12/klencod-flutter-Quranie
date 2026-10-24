import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.qurani.audio.channel',
      androidNotificationChannelName: 'تلاوات قرآني',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_launcher',
    );
  } catch (e) {
    debugPrint("JustAudioBackground Note: $e");
  }

  await AppNotificationService.init();

  final prefs = await SharedPreferences.getInstance();
  runApp(QuraniUltimateMasterApp(prefs: prefs));
}

// ============================================================================
// 1. خدمة الإشعارات والجدولة
// ============================================================================
class AppNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    try {
      tz.initializeTimeZones();
      const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notifications.initialize(initSettings);
      await _scheduleDailyReminders();
    } catch (e) {
      debugPrint("Notifications init note: $e");
    }
  }

  static Future<void> _scheduleDailyReminders() async {
    await _scheduleDaily(101, 'أذكار الصباح المباركة ☀️', 'ابدأ يومك بنور الذكر: أصبحنا وأصبح الملك لله..', 7, 0);
    await _scheduleDaily(102, 'أذكار المساء وحصن المسلم 🌙', 'أمسينا وأمسى الملك لله.. حصّن نفسك بأذكار المساء.', 17, 0);
  }

  static Future<void> _scheduleDaily(int id, String title, String body, int hour, int minute) async {
    try {
      var now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

      const details = AndroidNotificationDetails(
        'qurani_reminders_channel',
        'تذكيرات الأذكار',
        importance: Importance.high,
        priority: Priority.high,
      );

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        const NotificationDetails(android: details),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  static Future<void> schedulePrayerTimes(PrayerTimes prayerTimes) async {
    try {
      final list = {
        1: {'name': 'صلاة الفجر', 'time': prayerTimes.fajr},
        2: {'name': 'صلاة الظهر', 'time': prayerTimes.dhuhr},
        3: {'name': 'صلاة العصر', 'time': prayerTimes.asr},
        4: {'name': 'صلاة المغرب', 'time': prayerTimes.maghrib},
        5: {'name': 'صلاة العشاء', 'time': prayerTimes.isha},
      };

      for (var entry in list.entries) {
        final name = entry.value['name'] as String;
        final time = entry.value['time'] as DateTime;
        var scheduled = tz.TZDateTime.from(time, tz.local);
        if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
          scheduled = scheduled.add(const Duration(days: 1));
        }

        const details = AndroidNotificationDetails(
          'prayer_channel',
          'مواقيت الأذان',
          importance: Importance.max,
          priority: Priority.high,
        );

        await _notifications.zonedSchedule(
          entry.key,
          'حان الآن موعد $name',
          'حي على الصلاة.. حي على الفلاح',
          scheduled,
          const NotificationDetails(android: details),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (_) {}
  }
}

// ============================================================================
// 2. نماذج البيانات (Models)
// ============================================================================
class SurahData {
  final int number;
  final String name;
  final String englishName;
  final String type;
  final int ayahsCount;
  final int startPage;

  const SurahData({
    required this.number,
    required this.name,
    required this.englishName,
    required this.type,
    required this.ayahsCount,
    required this.startPage,
  });
}

class ReciterData {
  final String id;
  final String name;
  final String riwayah;
  final String server;

  const ReciterData({required this.id, required this.name, required this.riwayah, required this.server});
}

class DownloadedAudio {
  final int surahNumber;
  final String surahName;
  final String reciterName;
  final String filePath;
  final int fileSize;

  DownloadedAudio({
    required this.surahNumber,
    required this.surahName,
    required this.reciterName,
    required this.filePath,
    this.fileSize = 0,
  });

  Map<String, dynamic> toMap() => {
    'surahNumber': surahNumber,
    'surahName': surahName,
    'reciterName': reciterName,
    'filePath': filePath,
    'fileSize': fileSize,
  };

  factory DownloadedAudio.fromMap(Map<String, dynamic> map) => DownloadedAudio(
    surahNumber: map['surahNumber'],
    surahName: map['surahName'],
    reciterName: map['reciterName'],
    filePath: map['filePath'],
    fileSize: map['fileSize'] ?? 0,
  );
}

class HifzPlan {
  final String id;
  final String title;
  final int targetPages;
  int completedPages;
  final int dailyPages;
  final String startDate;

  HifzPlan({
    required this.id,
    required this.title,
    required this.targetPages,
    required this.completedPages,
    required this.dailyPages,
    required this.startDate,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'targetPages': targetPages,
    'completedPages': completedPages,
    'dailyPages': dailyPages,
    'startDate': startDate,
  };

  factory HifzPlan.fromMap(Map<String, dynamic> map) => HifzPlan(
    id: map['id'],
    title: map['title'],
    targetPages: map['targetPages'],
    completedPages: map['completedPages'],
    dailyPages: map['dailyPages'],
    startDate: map['startDate'],
  );
}

class ZikrItem {
  final String text;
  final String count;
  final String reward;
  int current;

  ZikrItem({required this.text, required this.count, required this.reward, this.current = 0});
}

// ============================================================================
// 3. محرك التطبيق وإدارة الحالة العامة
// ============================================================================
class AppEngine extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences prefs;
  final AudioPlayer player = AudioPlayer();

  bool isDark = false;
  double fontSize = 24.0;

  // مشغل الصوتيات
  int currentReciterIndex = 0;
  int currentSurahIndex = 0;
  bool isAudioBuffering = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  String currentPlayingTitle = "";
  bool isPlayingOffline = false;

  // المؤقت ومواقيت الصلاة
  PrayerTimes? prayerTimes;
  String nextPrayer = "الفجر";
  Duration remainingTime = Duration.zero;
  Timer? ticker;

  // ميزة موضع التوقف
  int? stopPositionSurahNumber;
  String? stopPositionSurahName;
  int? stopPositionPage;

  List<DownloadedAudio> downloadedList = [];
  Map<int, double> downloadProgress = {};
  List<HifzPlan> hifzPlans = [];
  List<int> bookmarkedSurahs = [];

  AppEngine(this.prefs) {
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
    _setupAudio();
    _initPrayerTimesFast();
    _startLiveTimer();
  }

  void _loadPreferences() {
    isDark = prefs.getBool('isDark') ?? false;
    fontSize = prefs.getDouble('fontSize') ?? 24.0;

    // استرجاع موضع التوقف
    stopPositionSurahNumber = prefs.getInt('stop_surah_num');
    stopPositionSurahName = prefs.getString('stop_surah_name');
    stopPositionPage = prefs.getInt('stop_surah_page');

    final bList = prefs.getStringList('bookmarks');
    if (bList != null) bookmarkedSurahs = bList.map((e) => int.parse(e)).toList();

    final dStr = prefs.getString('downloaded_audios');
    if (dStr != null) {
      final List dec = jsonDecode(dStr);
      downloadedList = dec.map((e) => DownloadedAudio.fromMap(e)).toList();
    }

    final pStr = prefs.getString('hifz_plans_list');
    if (pStr != null) {
      final List dec = jsonDecode(pStr);
      hifzPlans = dec.map((e) => HifzPlan.fromMap(e)).toList();
    } else {
      hifzPlans.add(HifzPlan(
        id: '1',
        title: 'خطة حفظ جزء عمّ المبارك',
        targetPages: 23,
        completedPages: 5,
        dailyPages: 1,
        startDate: 'اليوم',
      ));
    }
  }

  void _setupAudio() {
    player.durationStream.listen((d) {
      duration = d ?? Duration.zero;
      notifyListeners();
    });
    player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    player.playerStateStream.listen((state) {
      isAudioBuffering = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;
      if (state.processingState == ProcessingState.completed) {
        playNextSurah();
      }
      notifyListeners();
    });
  }

  // --- تشغيل الصوتيات مع نظام الحماية من أخطاء الروابط ---
  Future<void> playSurah(int surahIdx, {int? reciterIdx, bool forceOnline = false}) async {
    if (reciterIdx != null) currentReciterIndex = reciterIdx;
    currentSurahIndex = surahIdx;
    final surah = surahsCatalog[surahIdx];
    final reciter = allReciters[currentReciterIndex];
    currentPlayingTitle = "${surah.name} - ${reciter.name}";
    isAudioBuffering = true;
    notifyListeners();

    final localMatch = downloadedList.firstWhere(
      (d) => d.surahNumber == surah.number && d.reciterName == reciter.name,
      orElse: () => DownloadedAudio(surahNumber: -1, surahName: "", reciterName: "", filePath: ""),
    );

    try {
      await player.stop();
      final numPad = surah.number.toString().padLeft(3, '0');
      final remoteUrl = "${reciter.server}/$numPad.mp3";

      final mediaItem = MediaItem(
        id: '${surah.number}_${reciter.id}',
        album: 'القرآن الكريم',
        title: surah.name,
        artist: reciter.name,
      );

      if (localMatch.surahNumber != -1 && File(localMatch.filePath).existsSync() && !forceOnline) {
        isPlayingOffline = true;
        try {
          await player.setAudioSource(AudioSource.file(localMatch.filePath, tag: mediaItem));
        } catch (_) {
          await player.setFilePath(localMatch.filePath);
        }
      } else {
        isPlayingOffline = false;
        try {
          await player.setAudioSource(AudioSource.uri(Uri.parse(remoteUrl), tag: mediaItem));
        } catch (_) {
          // خطة بديلة سريعة لتشغيل الرابط مباشرة بدون وسائط شاشة القفل إذا تعذر ذلك
          await player.setUrl(remoteUrl);
        }
      }
      await player.play();
    } catch (e) {
      debugPrint("Audio Play Error: $e");
    } finally {
      isAudioBuffering = false;
      notifyListeners();
    }
  }

  Future<void> playDownloadedFile(DownloadedAudio item) async {
    try {
      await player.stop();
      currentPlayingTitle = "${item.surahName} (${item.reciterName}) - بدون إنترنت";
      isPlayingOffline = true;
      notifyListeners();

      final mediaItem = MediaItem(
        id: 'local_${item.surahNumber}',
        album: 'القرآن الكريم (محلي)',
        title: item.surahName,
        artist: item.reciterName,
      );

      try {
        await player.setAudioSource(AudioSource.file(item.filePath, tag: mediaItem));
      } catch (_) {
        await player.setFilePath(item.filePath);
      }
      await player.play();
    } catch (e) {
      debugPrint("File playback error: $e");
    }
  }

  void togglePlay() {
    if (player.playing) {
      player.pause();
    } else {
      if (player.duration == null || player.duration == Duration.zero) {
        playSurah(currentSurahIndex);
      } else {
        player.play();
      }
    }
    notifyListeners();
  }

  void playNextSurah() {
    if (currentSurahIndex < surahsCatalog.length - 1) {
      playSurah(currentSurahIndex + 1);
    }
  }

  void playPrevSurah() {
    if (currentSurahIndex > 0) {
      playSurah(currentSurahIndex - 1);
    }
  }

  // --- تحميل السور الصوتية ---
  Future<void> downloadSurahAudio(SurahData surah, ReciterData reciter) async {
    final numPad = surah.number.toString().padLeft(3, '0');
    final remoteUrl = "${reciter.server}/$numPad.mp3";
    downloadProgress[surah.number] = 0.05;
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = "${dir.path}/surah_${reciter.id}_$numPad.mp3";
      final file = File(savePath);

      if (file.existsSync()) file.deleteSync();

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(remoteUrl));
      final response = await client.send(request);

      final total = response.contentLength ?? 1;
      int received = 0;
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        downloadProgress[surah.number] = (received / total).clamp(0.0, 1.0);
        notifyListeners();
      }).asFuture();

      await sink.close();

      final int bytes = await file.length();

      downloadedList.removeWhere((d) => d.surahNumber == surah.number && d.reciterName == reciter.name);
      downloadedList.add(DownloadedAudio(
        surahNumber: surah.number,
        surahName: surah.name,
        reciterName: reciter.name,
        filePath: savePath,
        fileSize: bytes,
      ));

      prefs.setString('downloaded_audios', jsonEncode(downloadedList.map((e) => e.toMap()).toList()));
    } catch (e) {
      debugPrint("Download error: $e");
    } finally {
      downloadProgress.remove(surah.number);
      notifyListeners();
    }
  }

  void deleteDownloadedAudio(DownloadedAudio item) {
    try {
      final f = File(item.filePath);
      if (f.existsSync()) f.deleteSync();
      downloadedList.remove(item);
      prefs.setString('downloaded_audios', jsonEncode(downloadedList.map((e) => e.toMap()).toList()));
      notifyListeners();
    } catch (_) {}
  }

  bool isSurahDownloaded(int surahNum, String reciterName) {
    return downloadedList.any((d) => d.surahNumber == surahNum && d.reciterName == reciterName);
  }

  // --- ميزة حفظ وإلغاء موضع التوقف ---
  void setStopPosition(SurahData surah) {
    stopPositionSurahNumber = surah.number;
    stopPositionSurahName = surah.name;
    stopPositionPage = surah.startPage;

    prefs.setInt('stop_surah_num', surah.number);
    prefs.setString('stop_surah_name', surah.name);
    prefs.setInt('stop_surah_page', surah.startPage);
    notifyListeners();
  }

  void clearStopPosition() {
    stopPositionSurahNumber = null;
    stopPositionSurahName = null;
    stopPositionPage = null;

    prefs.remove('stop_surah_num');
    prefs.remove('stop_surah_name');
    prefs.remove('stop_surah_page');
    notifyListeners();
  }

  bool isCurrentStopPosition(int surahNumber) {
    return stopPositionSurahNumber == surahNumber;
  }

  // --- خطط الحفظ ---
  void createNewHifzPlan(String title, int targetPages, int daily) {
    hifzPlans.add(HifzPlan(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      targetPages: targetPages,
      completedPages: 0,
      dailyPages: daily,
      startDate: "${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}",
    ));
    _saveHifz();
  }

  void incrementPlanProgress(String id, int pages) {
    final idx = hifzPlans.indexWhere((p) => p.id == id);
    if (idx != -1) {
      hifzPlans[idx].completedPages = (hifzPlans[idx].completedPages + pages).clamp(0, hifzPlans[idx].targetPages);
      _saveHifz();
    }
  }

  void deleteHifzPlan(String id) {
    hifzPlans.removeWhere((p) => p.id == id);
    _saveHifz();
  }

  void _saveHifz() {
    prefs.setString('hifz_plans_list', jsonEncode(hifzPlans.map((e) => e.toMap()).toList()));
    notifyListeners();
  }

  // --- مواقيت الصلاة والمؤقت الحي ---
  void _initPrayerTimesFast() {
    _calculatePrayer(Coordinates(21.4225, 39.8262));
  }

  Future<void> requestAppPermissions(BuildContext context) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        _calculatePrayer(Coordinates(pos.latitude, pos.longitude));
      }
    } catch (_) {}
  }

  void _calculatePrayer(Coordinates coords) {
    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi;
    prayerTimes = PrayerTimes.today(coords, params);
    _syncCountdown();
    if (prayerTimes != null) {
      AppNotificationService.schedulePrayerTimes(prayerTimes!);
    }
    notifyListeners();
  }

  void _syncCountdown() {
    if (prayerTimes == null) return;
    final next = prayerTimes!.nextPrayer();
    DateTime? nextTime;

    switch (next) {
      case Prayer.fajr:
        nextPrayer = "الفجر";
        nextTime = prayerTimes!.fajr;
        break;
      case Prayer.sunrise:
        nextPrayer = "الشروق";
        nextTime = prayerTimes!.sunrise;
        break;
      case Prayer.dhuhr:
        nextPrayer = "الظهر";
        nextTime = prayerTimes!.dhuhr;
        break;
      case Prayer.asr:
        nextPrayer = "العصر";
        nextTime = prayerTimes!.asr;
        break;
      case Prayer.maghrib:
        nextPrayer = "المغرب";
        nextTime = prayerTimes!.maghrib;
        break;
      case Prayer.isha:
        nextPrayer = "العشاء";
        nextTime = prayerTimes!.isha;
        break;
      case Prayer.none:
        nextPrayer = "الفجر (غداً)";
        nextTime = prayerTimes!.fajr.add(const Duration(days: 1));
        break;
    }

    if (nextTime != null) {
      remainingTime = nextTime.difference(DateTime.now());
      if (remainingTime.isNegative) remainingTime = Duration.zero;
    }
  }

  void _startLiveTimer() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (prayerTimes != null) {
        _syncCountdown();
        notifyListeners();
      }
    });
  }

  void toggleTheme() {
    isDark = !isDark;
    prefs.setBool('isDark', isDark);
    notifyListeners();
  }

  void updateFontSize(double size) {
    fontSize = size;
    prefs.setDouble('fontSize', size);
    notifyListeners();
  }

  void toggleBookmark(int num) {
    if (bookmarkedSurahs.contains(num)) {
      bookmarkedSurahs.remove(num);
    } else {
      bookmarkedSurahs.add(num);
    }
    prefs.setStringList('bookmarks', bookmarkedSurahs.map((e) => e.toString()).toList());
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCountdown();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.dispose();
    ticker?.cancel();
    super.dispose();
  }
}

late AppEngine appEngine;

// ============================================================================
// 4. التطبيق الرئيسي والهوية البصرية مع إصلاح شريط الحالة العلوي
// ============================================================================
class QuraniUltimateMasterApp extends StatelessWidget {
  final SharedPreferences prefs;
  const QuraniUltimateMasterApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    appEngine = AppEngine(prefs);

    return AnimatedBuilder(
      animation: appEngine,
      builder: (context, _) {
        const primaryColor = Color(0xFF0A4D3C);
        const goldColor = Color(0xFFC5A059);

        // ضبط ألوان شريط الحالة العلوي بدقة ليتغير فورياً مع المظهر وبدون أي خط أسود
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: appEngine.isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: appEngine.isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: appEngine.isDark ? const Color(0xFF0E1613) : Colors.white,
            systemNavigationBarIconBrightness: appEngine.isDark ? Brightness.light : Brightness.dark,
          ),
        );

        return MaterialApp(
          title: 'قرآني',
          debugShowCheckedModeBanner: false,
          themeMode: appEngine.isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: primaryColor,
            scaffoldBackgroundColor: const Color(0xFFF9F7F2),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: primaryColor, secondary: goldColor, surface: Colors.white),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.light().textTheme),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: goldColor,
            scaffoldBackgroundColor: const Color(0xFF0E1613),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
            ),
            colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: goldColor, secondary: primaryColor, surface: const Color(0xFF15221E), brightness: Brightness.dark),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
          ),
          home: const Directionality(textDirection: TextDirection.rtl, child: MainNavigationWrapper()),
        );
      },
    );
  }
}

class MainNavigationWrapper extends StatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _idx = 0;
  final List<Widget> _screens = const [
    HomeScreen(),
    AudioStudioScreen(),
    DownloadsScreen(),
    HifzPlansScreen(),
    AzkarScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primary.withOpacity(0.15),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_rounded), label: 'المصحف'),
          NavigationDestination(icon: Icon(Icons.headphones_rounded), label: 'التلاوات'),
          NavigationDestination(icon: Icon(Icons.download_done_rounded), label: 'التنزيلات'),
          NavigationDestination(icon: Icon(Icons.auto_graph_rounded), label: 'الحفظ'),
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), label: 'الأذكار'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. الشاشة الرئيسية: المصحف، موضع التوقف، والمؤقت الحي
// ============================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String search = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appEngine.requestAppPermissions(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = surahsCatalog.where((s) => s.name.contains(search) || s.englishName.toLowerCase().contains(search.toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Color(0xFFC5A059)),
            SizedBox(width: 8),
            Text('قرآني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'تحديث مواقيت الصلاة لموقعك',
            onPressed: () => appEngine.requestAppPermissions(context),
          ),
          IconButton(
            icon: Icon(appEngine.isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => appEngine.toggleTheme(),
          ),
        ],
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // المؤقت الحي بدون أي تجمد
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AnimatedBuilder(
                animation: appEngine,
                builder: (context, _) => _buildLiveCountdownBanner(),
              ),
            ),
          ),

          // بطاقة موضع التوقف المحفوظ مع إمكانية المتابعة أو الإلغاء فورياً
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: appEngine,
              builder: (context, _) {
                if (appEngine.stopPositionSurahNumber == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC5A059).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFC5A059), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark, color: Color(0xFFC5A059), size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("موضع التوقف الحالي:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(
                              "${appEngine.stopPositionSurahName} (صفحة ${appEngine.stopPositionPage})",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF0A4D3C)),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text("متابعة", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final surah = surahsCatalog.firstWhere((s) => s.number == appEngine.stopPositionSurahNumber);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SurahReaderView(surah: surah)),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                        tooltip: 'إلغاء موضع التوقف',
                        onPressed: () {
                          appEngine.clearStopPosition();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء موضع التوقف بنجاح')));
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // شريط البحث
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: InputDecoration(
                  hintText: 'ابحث عن أي سورة بالاسم...',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A059)),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),

          // قائمة الـ 114 سورة
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final s = filtered[i];
                  final isFav = appEngine.bookmarkedSurahs.contains(s.number);
                  final isStopPos = appEngine.isCurrentStopPosition(s.number);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isStopPos ? const Color(0xFFC5A059).withOpacity(0.1) : theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: isStopPos ? const BorderSide(color: Color(0xFFC5A059), width: 1.5) : BorderSide.none,
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC5A059), width: 1.5)),
                        child: Text('${s.number}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Row(
                        children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                          if (isStopPos) ...[
                            const SizedBox(width: 8),
                            const Chip(
                              label: Text("موضع التوقف", style: TextStyle(fontSize: 10, color: Colors.white)),
                              backgroundColor: Color(0xFF0A4D3C),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text('${s.type} • ${s.ayahsCount} آيات • صـ ${s.startPage}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : Colors.grey),
                            onPressed: () => appEngine.toggleBookmark(s.number),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SurahReaderView(surah: s)),
                          ),
                        );
                      },
                    ),
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCountdownBanner() {
    final d = appEngine.remainingTime;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0A4D3C), Color(0xFF186E58)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF0A4D3C).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("الصلاة القادمة: صلاة ${appEngine.nextPrayer}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const Icon(Icons.access_time_filled, color: Color(0xFFC5A059)),
            ],
          ),
          const SizedBox(height: 14),
          Text("$h:$m:$s", style: const TextStyle(fontSize: 38, color: Color(0xFFC5A059), fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          const Text("الوقت المتبقي حتى الأذان (محدث ثانية بثانية بدون توقف)", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================================
// 6. قارئ المصحف مع زر حفظ التوقف وزر الإلغاء
// ============================================================================
class SurahReaderView extends StatefulWidget {
  final SurahData surah;
  const SurahReaderView({super.key, required this.surah});

  @override
  State<SurahReaderView> createState() => _SurahReaderViewState();
}

class _SurahReaderViewState extends State<SurahReaderView> with SingleTickerProviderStateMixin {
  late TabController tabCtrl;
  bool loading = true;
  List<dynamic> ayahs = [];
  String? localImagePath;

  @override
  void initState() {
    super.initState();
    tabCtrl = TabController(length: 2, vsync: this);
    _checkOfflineImage();
    _fetchTextWithCache();
  }

  Future<void> _checkOfflineImage() async {
    final pageNumStr = widget.surah.startPage.toString().padLeft(3, '0');
    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/page_$pageNumStr.png";
    final file = File(filePath);

    if (file.existsSync()) {
      if (mounted) setState(() => localImagePath = filePath);
    } else {
      final remoteUrl = "https://raw.githubusercontent.com/Govar-Frman/Quran-Page-Images/main/pages/$pageNumStr.png";
      try {
        final res = await http.get(Uri.parse(remoteUrl)).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          await file.writeAsBytes(res.bodyBytes);
          if (mounted) setState(() => localImagePath = filePath);
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchTextWithCache() async {
    final cacheKey = "surah_text_${widget.surah.number}";
    final cached = appEngine.prefs.getString(cacheKey);

    if (cached != null) {
      if (mounted) {
        setState(() {
          ayahs = jsonDecode(cached);
          loading = false;
        });
      }
      return;
    }

    final url = Uri.parse("https://api.alquran.cloud/v1/surah/${widget.surah.number}/editions/quran-uthmani,ar.muyassar");
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final uth = d['data'][0]['ayahs'];
        final taf = d['data'][1]['ayahs'];
        List<dynamic> tmp = [];
        for (int i = 0; i < uth.length; i++) {
          tmp.add({
            'number': uth[i]['numberInSurah'],
            'text': uth[i]['text'],
            'tafseer': taf[i]['text'],
          });
        }
        await appEngine.prefs.setString(cacheKey, jsonEncode(tmp));
        if (mounted) {
          setState(() {
            ayahs = tmp;
            loading = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        ayahs = List.generate(
          widget.surah.ayahsCount,
          (i) => {
            'number': i + 1,
            'text': "آية رقم ${i + 1} من ${widget.surah.name}",
            'tafseer': "التفسير الميسر متاح بمجرد الاتصال بالإنترنت أول مرة ليتم حفظه تلقائياً.",
          },
        );
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageNumStr = widget.surah.startPage.toString().padLeft(3, '0');
    final remoteUrl = "https://raw.githubusercontent.com/Govar-Frman/Quran-Page-Images/main/pages/$pageNumStr.png";

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          AnimatedBuilder(
            animation: appEngine,
            builder: (context, _) {
              final isSaved = appEngine.isCurrentStopPosition(widget.surah.number);
              return IconButton(
                icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_add_outlined),
                color: isSaved ? const Color(0xFFC5A059) : null,
                tooltip: isSaved ? 'إلغاء التوقف هنا' : 'حفظ التوقف عند هذه السورة',
                onPressed: () {
                  if (isSaved) {
                    appEngine.clearStopPosition();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء موضع التوقف')));
                  } else {
                    appEngine.setStopPosition(widget.surah);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ ${widget.surah.name} كموضع توقف')));
                  }
                },
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: tabCtrl,
          indicatorColor: const Color(0xFFC5A059),
          tabs: const [
            Tab(icon: Icon(Icons.image), text: "صفحة المصحف"),
            Tab(icon: Icon(Icons.format_align_right), text: "النص والتفسير"),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabCtrl,
        children: [
          InteractiveViewer(
            panEnabled: true,
            minScale: 0.8,
            maxScale: 3.5,
            child: Center(
              child: localImagePath != null
                  ? Image.file(File(localImagePath!), fit: BoxFit.contain)
                  : Image.network(
                      remoteUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF0A4D3C)));
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text("تعذر تحميل صورة المصحف، تأكد من الاتصال بالإنترنت لحفظها."),
                      ),
                    ),
            ),
          ),
          loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF0A4D3C)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: ayahs.length,
                  itemBuilder: (ctx, idx) {
                    final a = ayahs[idx];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "${a['text']} ﴿${a['number']}﴾",
                              style: GoogleFonts.amiri(fontSize: appEngine.fontSize, height: 2.1),
                              textAlign: TextAlign.justify,
                            ),
                            const Divider(height: 20),
                            Text("التفسير الميسر: ${a['tafseer']}", style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}

// ============================================================================
// 7. استوديو التلاوات مع المشغل المطور
// ============================================================================
class AudioStudioScreen extends StatefulWidget {
  const AudioStudioScreen({super.key});

  @override
  State<AudioStudioScreen> createState() => _AudioStudioScreenState();
}

class _AudioStudioScreenState extends State<AudioStudioScreen> {
  String searchReciter = "";

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final curReciter = allReciters[appEngine.currentReciterIndex];

    return Scaffold(
      appBar: AppBar(title: const Text('المصحف الصوتي المرتل', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0A4D3C), Color(0xFF155C48)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  appEngine.currentPlayingTitle.isEmpty ? "اختر سورة للتلاوة" : appEngine.currentPlayingTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                if (appEngine.isPlayingOffline)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFC5A059), borderRadius: BorderRadius.circular(8)),
                    child: const Text("تشغيل بدون إنترنت (أوفلاين)", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                Slider(
                  value: appEngine.position.inSeconds.toDouble().clamp(0.0, (appEngine.duration.inSeconds > 0) ? appEngine.duration.inSeconds.toDouble() : 1.0),
                  max: (appEngine.duration.inSeconds > 0) ? appEngine.duration.inSeconds.toDouble() : 1.0,
                  activeColor: const Color(0xFFC5A059),
                  inactiveColor: Colors.white24,
                  onChanged: (v) => appEngine.player.seek(Duration(seconds: v.toInt())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_format(appEngine.position), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    Text(_format(appEngine.duration), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white, size: 30), onPressed: () => appEngine.playPrevSurah()),
                    const SizedBox(width: 20),
                    InkWell(
                      onTap: () => appEngine.togglePlay(),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC5A059)),
                        child: appEngine.isAudioBuffering
                            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Icon(appEngine.player.playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(icon: const Icon(Icons.skip_next, color: Colors.white, size: 30), onPressed: () => appEngine.playNextSurah()),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("القارئ: ${curReciter.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _showRecitersModal(),
                  icon: const Icon(Icons.person, color: Color(0xFFC5A059)),
                  label: const Text('تغيير (30+)', style: TextStyle(color: Color(0xFFC5A059))),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: surahsCatalog.length,
              itemBuilder: (ctx, i) {
                final s = surahsCatalog[i];
                final isCurrent = i == appEngine.currentSurahIndex;
                final isDownloaded = appEngine.isSurahDownloaded(s.number, curReciter.name);
                final prog = appEngine.downloadProgress[s.number];

                return ListTile(
                  leading: Icon(
                    isCurrent && appEngine.player.playing ? Icons.graphic_eq : Icons.play_circle_outline,
                    color: isCurrent ? const Color(0xFF0A4D3C) : Colors.grey,
                  ),
                  title: Text(s.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text("${s.type} • ${s.ayahsCount} آية"),
                  trailing: prog != null
                      ? SizedBox(width: 32, height: 32, child: CircularProgressIndicator(value: prog, color: const Color(0xFFC5A059)))
                      : IconButton(
                          icon: Icon(
                            isDownloaded ? Icons.download_done : Icons.download_for_offline_outlined,
                            color: isDownloaded ? const Color(0xFF0A4D3C) : const Color(0xFFC5A059),
                          ),
                          tooltip: isDownloaded ? 'محملة مسبقاً' : 'تحميل للاستماع بدون إنترنت',
                          onPressed: () {
                            if (!isDownloaded) {
                              appEngine.downloadSurahAudio(s, curReciter);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('بدأ تحميل سورة ${s.name} بصوت ${curReciter.name}...')));
                            }
                          },
                        ),
                  onTap: () => appEngine.playSurah(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRecitersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final fil = allReciters.where((r) => r.name.contains(searchReciter) || r.riwayah.contains(searchReciter)).toList();
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('اختر قارئك المفضل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (v) => setM(() => searchReciter = v),
                  decoration: InputDecoration(hintText: 'ابحث باسم الشيخ...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: fil.length,
                    itemBuilder: (ctx, idx) {
                      final r = fil[idx];
                      final orig = allReciters.indexOf(r);
                      return ListTile(
                        title: Text(r.name),
                        subtitle: Text(r.riwayah),
                        trailing: orig == appEngine.currentReciterIndex ? const Icon(Icons.check, color: Color(0xFFC5A059)) : null,
                        onTap: () {
                          appEngine.playSurah(appEngine.currentSurahIndex, reciterIdx: orig);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 8. قسم التنزيلات الصوتية الأوفلاين (شامل لحجم الملف وإدارته)
// ============================================================================
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التنزيلات الصوتية (بدون إنترنت)', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: AnimatedBuilder(
        animation: appEngine,
        builder: (context, _) {
          final list = appEngine.downloadedList;
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 70, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سور صوتية محملة بعد.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('توجه إلى قسم "التلاوات" واضغط على زر التنزيل بجانب أي سورة.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final item = list[i];
              final mb = (item.fileSize / (1024 * 1024)).toStringAsFixed(1);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF0A4D3C),
                    child: Icon(Icons.play_arrow, color: Colors.white),
                  ),
                  title: Text(item.surahName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${item.reciterName} • الحجم: $mb MB"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'حذف التنزيل',
                    onPressed: () => appEngine.deleteDownloadedAudio(item),
                  ),
                  onTap: () => appEngine.playDownloadedFile(item),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 9. قسم خطط حفظ القرآن الكريم التفاعلي
// ============================================================================
class HifzPlansScreen extends StatelessWidget {
  const HifzPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('خطط حفظ القرآن الكريم', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_task),
            tooltip: 'إنشاء خطة جديدة',
            onPressed: () => _showCreatePlanDialog(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: appEngine,
        builder: (context, _) {
          final plans = appEngine.hifzPlans;
          if (plans.isEmpty) {
            return const Center(child: Text('لا توجد خطط حالية، اضغط على + لإنشاء خطتك الأولى!'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plans.length,
            itemBuilder: (ctx, idx) {
              final p = plans[idx];
              final progress = (p.completedPages / p.targetPages).clamp(0.0, 1.0);
              final remainingPages = p.targetPages - p.completedPages;
              final remainingDays = (remainingPages / p.dailyPages).ceil();

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => appEngine.deleteHifzPlan(p.id),
                          )
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFF0A4D3C),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('تم إنجاز: ${p.completedPages} من ${p.targetPages} صفحة', style: const TextStyle(fontSize: 12)),
                          Text('${(progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('الورد اليومي: ${p.dailyPages} صفحة • الختم المتوقع خلال: $remainingDays يوم', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => appEngine.incrementPlanProgress(p.id, 1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A4D3C),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('حفظت +1 صفحة'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => appEngine.incrementPlanProgress(p.id, 2),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFC5A059),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.add_circle_outline, size: 18),
                              label: const Text('حفظت +2 صفحة'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreatePlanDialog(BuildContext context) {
    final titleCtrl = TextEditingController(text: "خطة حفظ سورة البقرة");
    final targetCtrl = TextEditingController(text: "48");
    final dailyCtrl = TextEditingController(text: "2");

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنشاء خطة حفظ جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم الخطة')),
                TextField(controller: targetCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إجمالي الصفحات المستهدفة')),
                TextField(controller: dailyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الورد اليومي (صفحة/يوم)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final t = titleCtrl.text.trim();
                final target = int.tryParse(targetCtrl.text) ?? 20;
                final daily = int.tryParse(dailyCtrl.text) ?? 1;
                if (t.isNotEmpty) {
                  appEngine.createNewHifzPlan(t, target, daily);
                }
                Navigator.pop(ctx);
              },
              child: const Text('إنشاء الخطة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 10. قسم الأذكار اليومية وحصن المسلم
// ============================================================================
class AzkarScreen extends StatefulWidget {
  const AzkarScreen({super.key});

  @override
  State<AzkarScreen> createState() => _AzkarScreenState();
}

class _AzkarScreenState extends State<AzkarScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<ZikrItem> sabahAzkar = [
    ZikrItem(text: "أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لاَ إِلَـهَ إِلاَّ اللهُ وَحْدَهُ لاَ شَرِيكَ لَهُ.", count: "1", reward: "حفظ وبركة في اليوم كله"),
    ZikrItem(text: "اللّهُـمَّ أَنْتَ رَبِّـي لا إِلَهَ إِلا أَنْتَ، خَلَقْتَنـي وَأَنا عَبْـدُك، وَأَنا عَلـى عَهْـدِكَ وَوَعْـدِكَ ما اسْتَطَـعْت..", count: "1", reward: "سيد الاستغفار: من قالها موقناً بها فمات دخل الجنة"),
    ZikrItem(text: "سُبْحَانَ اللهِ وَبِحَمْدِهِ: عَدَدَ خَلْقِهِ، وَرِضَا نَفْسِهِ، وَزِنَةَ عَرْشِهِ، وَمِدَادَ كَلِمَاتِهِ.", count: "3", reward: "تعدل ساعات طويلة من الذكر"),
    ZikrItem(text: "بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ.", count: "3", reward: "لم يضره شيء قط في يومه"),
  ];

  final List<ZikrItem> masaaAzkar = [
    ZikrItem(text: "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لاَ إِلَـهَ إِلاَّ اللهُ وَحْدَهُ لاَ شَرِيكَ لَهُ.", count: "1", reward: "حفظ وبركة طوال الليل"),
    ZikrItem(text: "أَعُوذُ بِكَلِمَاتِ اللهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ.", count: "3", reward: "لم يضره شيء في ليلته"),
    ZikrItem(text: "اللَّهُمَّ إِنِّي أَسْأَلُكَ الْعَفْوَ وَالْعَافِيَةَ فِي الدُّنْيَا وَالآخِرَةِ.", count: "1", reward: "الحفظ والعافية التامة"),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('أذكار المسلم اليومية', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFC5A059),
          tabs: const [
            Tab(text: "أذكار الصباح ☀️"),
            Tab(text: "أذكار المساء 🌙"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAzkarList(sabahAzkar),
          _buildAzkarList(masaaAzkar),
        ],
      ),
    );
  }

  Widget _buildAzkarList(List<ZikrItem> list) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, idx) {
        final item = list[idx];
        final maxCount = int.tryParse(item.count) ?? 1;

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.text, style: GoogleFonts.amiri(fontSize: 19, height: 1.9)),
                const SizedBox(height: 8),
                Text("الفضل: ${item.reward}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("التكرار المطلوب: ${item.count}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
                    ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          if (item.current < maxCount) item.current++;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: item.current >= maxCount ? Colors.grey : const Color(0xFF0A4D3C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(item.current >= maxCount ? 'تم الإنجاز ✔' : 'تم ${item.current} / $maxCount'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 11. شاشة الإعدادات
// ============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold))),
      body: AnimatedBuilder(
        animation: appEngine,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  title: const Text('الوضع الليلي (Dark Mode)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('تبديل مظهر التطبيق فورياً وتوفير البطارية'),
                  value: appEngine.isDark,
                  activeColor: const Color(0xFFC5A059),
                  onChanged: (_) => appEngine.toggleTheme(),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('حجم خط الآيات القرآنية', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('${appEngine.fontSize.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C))),
                        ],
                      ),
                      Slider(
                        value: appEngine.fontSize,
                        min: 18,
                        max: 38,
                        divisions: 10,
                        activeColor: const Color(0xFF0A4D3C),
                        onChanged: (v) => appEngine.updateFontSize(v),
                      ),
                      Center(
                        child: Text(
                          "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
                          style: GoogleFonts.amiri(fontSize: appEngine.fontSize),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.favorite, color: Colors.redAccent),
                  title: const Text('السور المحفوظة في المفضلة', style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text('${appEngine.bookmarkedSurahs.length} سورة'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: const ListTile(
                  leading: Icon(Icons.info_outline, color: Color(0xFF0A4D3C)),
                  title: Text('عن تطبيق قرآني'),
                  subtitle: Text('تطبيق إسلامي شامل صدقة جارية - الإصدار 3.0 المطور'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// 12. قاعدة بيانات كبار القراء (32 قارئاً بروايات مختلفة)
// ============================================================================
final List<ReciterData> allReciters = [
  const ReciterData(id: "afs", name: "مشاري راشد العفاسي", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/afs"),
  const ReciterData(id: "basit_mjw", name: "عبد الباسط عبد الصمد", riwayah: "المصحف المجود", server: "https://server7.mp3quran.net/basit/Almusshaf-Al-Mojawwad"),
  const ReciterData(id: "basit_mrt", name: "عبد الباسط عبد الصمد", riwayah: "حفص عن عاصم (مرتل)", server: "https://server7.mp3quran.net/basit"),
  const ReciterData(id: "husr", name: "محمود خليل الحصري", riwayah: "حفص عن عاصم", server: "https://server13.mp3quran.net/husr"),
  const ReciterData(id: "husr_w", name: "محمود خليل الحصري", riwayah: "ورش عن نافع", server: "https://server13.mp3quran.net/husr/warsh"),
  const ReciterData(id: "bna", name: "محمود علي البنا", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/bna"),
  const ReciterData(id: "minsh_mrt", name: "محمد صديق المنشاوي", riwayah: "حفص عن عاصم (مرتل)", server: "https://server10.mp3quran.net/minsh"),
  const ReciterData(id: "minsh_mjw", name: "محمد صديق المنشاوي", riwayah: "المصحف المجود", server: "https://server10.mp3quran.net/minsh/Almusshaf-Al-Mojawwad"),
  const ReciterData(id: "maher", name: "ماهر المعيقلي", riwayah: "حفص عن عاصم", server: "https://server12.mp3quran.net/maher"),
  const ReciterData(id: "s_gmd", name: "سعد الغامدي", riwayah: "حفص عن عاصم", server: "https://server7.mp3quran.net/s_gmd"),
  const ReciterData(id: "shatri", name: "أبو بكر الشاطري", riwayah: "حفص عن عاصم", server: "https://server11.mp3quran.net/shatri"),
  const ReciterData(id: "ajm", name: "أحمد بن علي العجمي", riwayah: "حفص عن عاصم", server: "https://server10.mp3quran.net/ajm"),
  const ReciterData(id: "shur", name: "سعود الشريم", riwayah: "حفص عن عاصم", server: "https://server7.mp3quran.net/shur"),
  const ReciterData(id: "sds", name: "عبد الرحمن السديس", riwayah: "حفص عن عاصم", server: "https://server11.mp3quran.net/sds"),
  const ReciterData(id: "hthfi", name: "علي بن عبد الرحمن الحذيفي", riwayah: "حفص عن عاصم", server: "https://server9.mp3quran.net/hthfi"),
  const ReciterData(id: "hthfi_q", name: "علي بن عبد الرحمن الحذيفي", riwayah: "قالون عن نافع", server: "https://server9.mp3quran.net/hthfi/qalon"),
  const ReciterData(id: "yasser", name: "ياسر الدوسري", riwayah: "حفص عن عاصم", server: "https://server11.mp3quran.net/yasser"),
  const ReciterData(id: "qtm", name: "ناصر القطامي", riwayah: "حفص عن عاصم", server: "https://server6.mp3quran.net/qtm"),
  const ReciterData(id: "frs_a", name: "فارس عباد", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/frs_a"),
  const ReciterData(id: "abkr", name: "إدريس أبكر", riwayah: "حفص عن عاصم", server: "https://server6.mp3quran.net/abkr"),
  const ReciterData(id: "jleel", name: "خالد الجليل", riwayah: "حفص عن عاصم", server: "https://server10.mp3quran.net/jleel"),
  const ReciterData(id: "ayyoub", name: "محمد أيوب", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/ayyoub"),
  const ReciterData(id: "kyat", name: "عبد الله خياط", riwayah: "حفص عن عاصم", server: "https://server12.mp3quran.net/kyat"),
  const ReciterData(id: "jhn", name: "عبد الله جهني", riwayah: "حفص عن عاصم", server: "https://server13.mp3quran.net/jhn"),
  const ReciterData(id: "lhdan", name: "محمد اللحيدان", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/lhdan"),
  const ReciterData(id: "bu_khtr", name: "صلاح بو خاطر", riwayah: "حفص عن عاصم", server: "https://server8.mp3quran.net/bu_khtr"),
  const ReciterData(id: "soufi_s", name: "عبد الرشيد صوفي", riwayah: "السوسي عن أبي عمرو", server: "https://server16.mp3quran.net/soufi/soosi"),
  const ReciterData(id: "soufi_k", name: "عبد الرشيد صوفي", riwayah: "خلف عن حمزة", server: "https://server16.mp3quran.net/soufi/khalaf"),
  const ReciterData(id: "kzbr", name: "عمر القزابري", riwayah: "ورش عن نافع", server: "https://server9.mp3quran.net/kzbr"),
  const ReciterData(id: "koshi", name: "العيون الكوشي", riwayah: "ورش عن نافع", server: "https://server11.mp3quran.net/koshi"),
  const ReciterData(id: "jaza", name: "ياسين الجزائري", riwayah: "ورش عن نافع", server: "https://server11.mp3quran.net/jaza"),
  const ReciterData(id: "sultany", name: "مفتاح السلطني", riwayah: "الدوري عن أبي عمرو", server: "https://server10.mp3quran.net/sultany/doori"),
];

// ============================================================================
// 13. فهرس الـ 114 سورة كاملاً
// ============================================================================
final List<SurahData> surahsCatalog = [
  const SurahData(number: 1, name: "الفاتحة", englishName: "Al-Fatiha", type: "مكية", ayahsCount: 7, startPage: 1),
  const SurahData(number: 2, name: "البقرة", englishName: "Al-Baqarah", type: "مدنية", ayahsCount: 286, startPage: 2),
  const SurahData(number: 3, name: "آل عمران", englishName: "Aal-E-Imran", type: "مدنية", ayahsCount: 200, startPage: 50),
  const SurahData(number: 4, name: "النساء", englishName: "An-Nisa", type: "مدنية", ayahsCount: 176, startPage: 77),
  const SurahData(number: 5, name: "المائدة", englishName: "Al-Ma'idah", type: "مدنية", ayahsCount: 120, startPage: 106),
  const SurahData(number: 6, name: "الأنعام", englishName: "Al-An'am", type: "مكية", ayahsCount: 165, startPage: 128),
  const SurahData(number: 7, name: "الأعراف", englishName: "Al-A'raf", type: "مكية", ayahsCount: 206, startPage: 151),
  const SurahData(number: 8, name: "الأنفال", englishName: "Al-Anfal", type: "مدنية", ayahsCount: 75, startPage: 177),
  const SurahData(number: 9, name: "التوبة", englishName: "At-Tawbah", type: "مدنية", ayahsCount: 129, startPage: 187),
  const SurahData(number: 10, name: "يونس", englishName: "Yunus", type: "مكية", ayahsCount: 109, startPage: 208),
  const SurahData(number: 11, name: "هود", englishName: "Hud", type: "مكية", ayahsCount: 123, startPage: 221),
  const SurahData(number: 12, name: "يوسف", englishName: "Yusuf", type: "مكية", ayahsCount: 111, startPage: 235),
  const SurahData(number: 13, name: "الرعد", englishName: "Ar-Ra'd", type: "مدنية", ayahsCount: 43, startPage: 249),
  const SurahData(number: 14, name: "إبراهيم", englishName: "Ibrahim", type: "مكية", ayahsCount: 52, startPage: 255),
  const SurahData(number: 15, name: "الحجر", englishName: "Al-Hijr", type: "مكية", ayahsCount: 99, startPage: 262),
  const SurahData(number: 16, name: "النحل", englishName: "An-Nahl", type: "مكية", ayahsCount: 128, startPage: 267),
  const SurahData(number: 17, name: "الإسراء", englishName: "Al-Isra", type: "مكية", ayahsCount: 111, startPage: 282),
  const SurahData(number: 18, name: "الكهف", englishName: "Al-Kahf", type: "مكية", ayahsCount: 110, startPage: 293),
  const SurahData(number: 19, name: "مريم", englishName: "Maryam", type: "مكية", ayahsCount: 98, startPage: 305),
  const SurahData(number: 20, name: "طه", englishName: "Ta-Ha", type: "مكية", ayahsCount: 135, startPage: 312),
  const SurahData(number: 21, name: "الأنبياء", englishName: "Al-Anbiya", type: "مكية", ayahsCount: 112, startPage: 322),
  const SurahData(number: 22, name: "الحج", englishName: "Al-Hajj", type: "مدنية", ayahsCount: 78, startPage: 332),
  const SurahData(number: 23, name: "المؤمنون", englishName: "Al-Mu'minun", type: "مكية", ayahsCount: 118, startPage: 342),
  const SurahData(number: 24, name: "النور", englishName: "An-Nur", type: "مدنية", ayahsCount: 64, startPage: 350),
  const SurahData(number: 25, name: "الفرقان", englishName: "Al-Furqan", type: "مكية", ayahsCount: 77, startPage: 359),
  const SurahData(number: 26, name: "الشعراء", englishName: "Ash-Shu'ara", type: "مكية", ayahsCount: 227, startPage: 367),
  const SurahData(number: 27, name: "النمل", englishName: "An-Naml", type: "مكية", ayahsCount: 93, startPage: 377),
  const SurahData(number: 28, name: "القصص", englishName: "Al-Qasas", type: "مكية", ayahsCount: 88, startPage: 385),
  const SurahData(number: 29, name: "العنكبوت", englishName: "Al-Ankabut", type: "مكية", ayahsCount: 69, startPage: 396),
  const SurahData(number: 30, name: "الروم", englishName: "Ar-Rum", type: "مكية", ayahsCount: 60, startPage: 404),
  const SurahData(number: 31, name: "لقمان", englishName: "Luqman", type: "مكية", ayahsCount: 34, startPage: 411),
  const SurahData(number: 32, name: "السجدة", englishName: "As-Sajdah", type: "مكية", ayahsCount: 30, startPage: 415),
  const SurahData(number: 33, name: "الأحزاب", englishName: "Al-Ahzab", type: "مدنية", ayahsCount: 73, startPage: 418),
  const SurahData(number: 34, name: "سبأ", englishName: "Saba", type: "مكية", ayahsCount: 54, startPage: 428),
  const SurahData(number: 35, name: "فاطر", englishName: "Fatir", type: "مكية", ayahsCount: 45, startPage: 434),
  const SurahData(number: 36, name: "يس", englishName: "Ya-Sin", type: "مكية", ayahsCount: 83, startPage: 440),
  const SurahData(number: 37, name: "الصافات", englishName: "As-Saffat", type: "مكية", ayahsCount: 182, startPage: 446),
  const SurahData(number: 38, name: "ص", englishName: "Sad", type: "مكية", ayahsCount: 88, startPage: 453),
  const SurahData(number: 39, name: "الزمر", englishName: "Az-Zumar", type: "مكية", ayahsCount: 75, startPage: 458),
  const SurahData(number: 40, name: "غافر", englishName: "Ghafir", type: "مكية", ayahsCount: 85, startPage: 467),
  const SurahData(number: 41, name: "فصلت", englishName: "Fussilat", type: "مكية", ayahsCount: 54, startPage: 477),
  const SurahData(number: 42, name: "الشورى", englishName: "Ash-Shura", type: "مكية", ayahsCount: 53, startPage: 483),
  const SurahData(number: 43, name: "الزخرف", englishName: "Az-Zukhruf", type: "مكية", ayahsCount: 89, startPage: 489),
  const SurahData(number: 44, name: "الدخان", englishName: "Ad-Dukhan", type: "مكية", ayahsCount: 59, startPage: 496),
  const SurahData(number: 45, name: "الجاثية", englishName: "Al-Jathiyah", type: "مكية", ayahsCount: 37, startPage: 499),
  const SurahData(number: 46, name: "الأحقاف", englishName: "Al-Ahqaf", type: "مكية", ayahsCount: 35, startPage: 502),
  const SurahData(number: 47, name: "محمد", englishName: "Muhammad", type: "مدنية", ayahsCount: 38, startPage: 507),
  const SurahData(number: 48, name: "الفتح", englishName: "Al-Fath", type: "مدنية", ayahsCount: 29, startPage: 511),
  const SurahData(number: 49, name: "الحجرات", englishName: "Al-Hujurat", type: "مدنية", ayahsCount: 18, startPage: 515),
  const SurahData(number: 50, name: "ق", englishName: "Qaf", type: "مكية", ayahsCount: 45, startPage: 518),
  const SurahData(number: 51, name: "الذاريات", englishName: "Adh-Dhariyat", type: "مكية", ayahsCount: 60, startPage: 520),
  const SurahData(number: 52, name: "الطور", englishName: "At-Tur", type: "مكية", ayahsCount: 49, startPage: 523),
  const SurahData(number: 53, name: "النجم", englishName: "An-Najm", type: "مكية", ayahsCount: 62, startPage: 526),
  const SurahData(number: 54, name: "القمر", englishName: "Al-Qamar", type: "مكية", ayahsCount: 55, startPage: 528),
  const SurahData(number: 55, name: "الرحمن", englishName: "Ar-Rahman", type: "مدنية", ayahsCount: 78, startPage: 531),
  const SurahData(number: 56, name: "الواقعة", englishName: "Al-Waqi'ah", type: "مكية", ayahsCount: 96, startPage: 534),
  const SurahData(number: 57, name: "الحديد", englishName: "Al-Hadid", type: "مدنية", ayahsCount: 29, startPage: 537),
  const SurahData(number: 58, name: "المجادلة", englishName: "Al-Mujadila", type: "مدنية", ayahsCount: 22, startPage: 542),
  const SurahData(number: 59, name: "الحشر", englishName: "Al-Hashr", type: "مدنية", ayahsCount: 24, startPage: 545),
  const SurahData(number: 60, name: "الممتحنة", englishName: "Al-Mumtahanah", type: "مدنية", ayahsCount: 13, startPage: 549),
  const SurahData(number: 61, name: "الصف", englishName: "As-Saff", type: "مدنية", ayahsCount: 14, startPage: 551),
  const SurahData(number: 62, name: "الجمعة", englishName: "Al-Jumu'ah", type: "مدنية", ayahsCount: 11, startPage: 553),
  const SurahData(number: 63, name: "المنافقون", englishName: "Al-Munafiqun", type: "مدنية", ayahsCount: 11, startPage: 554),
  const SurahData(number: 64, name: "التغابن", englishName: "At-Taghabun", type: "مدنية", ayahsCount: 18, startPage: 556),
  const SurahData(number: 65, name: "الطلاق", englishName: "At-Talaq", type: "مدنية", ayahsCount: 12, startPage: 558),
  const SurahData(number: 66, name: "التحريم", englishName: "At-Tahrim", type: "مدنية", ayahsCount: 12, startPage: 560),
  const SurahData(number: 67, name: "الملك", englishName: "Al-Mulk", type: "مكية", ayahsCount: 30, startPage: 562),
  const SurahData(number: 68, name: "القلم", englishName: "Al-Qalam", type: "مكية", ayahsCount: 52, startPage: 564),
  const SurahData(number: 69, name: "الحاقة", englishName: "Al-Haqqah", type: "مكية", ayahsCount: 52, startPage: 566),
  const SurahData(number: 70, name: "المعارج", englishName: "Al-Ma'arij", type: "مكية", ayahsCount: 44, startPage: 568),
  const SurahData(number: 71, name: "نوح", englishName: "Nuh", type: "مكية", ayahsCount: 28, startPage: 570),
  const SurahData(number: 72, name: "الجن", englishName: "Al-Jinn", type: "مكية", ayahsCount: 28, startPage: 572),
  const SurahData(number: 73, name: "المزمل", englishName: "Al-Muzzammil", type: "مكية", ayahsCount: 20, startPage: 574),
  const SurahData(number: 74, name: "المدثر", englishName: "Al-Muddathir", type: "مكية", ayahsCount: 56, startPage: 575),
  const SurahData(number: 75, name: "القيامة", englishName: "Al-Qiyamah", type: "مكية", ayahsCount: 40, startPage: 577),
  const SurahData(number: 76, name: "الإنسان", englishName: "Al-Insan", type: "مدنية", ayahsCount: 31, startPage: 578),
  const SurahData(number: 77, name: "المرسلات", englishName: "Al-Mursalat", type: "مكية", ayahsCount: 50, startPage: 580),
  const SurahData(number: 78, name: "النبأ", englishName: "An-Naba", type: "مكية", ayahsCount: 40, startPage: 582),
  const SurahData(number: 79, name: "النازعات", englishName: "An-Nazi'at", type: "مكية", ayahsCount: 46, startPage: 583),
  const SurahData(number: 80, name: "عبس", englishName: "Abasa", type: "مكية", ayahsCount: 42, startPage: 585),
  const SurahData(number: 81, name: "التكوير", englishName: "At-Takwir", type: "مكية", ayahsCount: 29, startPage: 586),
  const SurahData(number: 82, name: "الانفطار", englishName: "Al-Infitar", type: "مكية", ayahsCount: 19, startPage: 587),
  const SurahData(number: 83, name: "المطففين", englishName: "Al-Mutaffifin", type: "مكية", ayahsCount: 36, startPage: 587),
  const SurahData(number: 84, name: "الانشقاق", englishName: "Al-Inshiqaq", type: "مكية", ayahsCount: 25, startPage: 589),
  const SurahData(number: 85, name: "البروج", englishName: "Al-Buruj", type: "مكية", ayahsCount: 22, startPage: 590),
  const SurahData(number: 86, name: "الطارق", englishName: "At-Tariq", type: "مكية", ayahsCount: 17, startPage: 591),
  const SurahData(number: 87, name: "الأعلى", englishName: "Al-A'la", type: "مكية", ayahsCount: 19, startPage: 591),
  const SurahData(number: 88, name: "الغاشية", englishName: "Al-Ghashiyah", type: "مكية", ayahsCount: 26, startPage: 592),
  const SurahData(number: 89, name: "الفجر", englishName: "Al-Fajr", type: "مكية", ayahsCount: 30, startPage: 593),
  const SurahData(number: 90, name: "البلد", englishName: "Al-Balad", type: "مكية", ayahsCount: 20, startPage: 594),
  const SurahData(number: 91, name: "الشمس", englishName: "Ash-Shams", type: "مكية", ayahsCount: 15, startPage: 595),
  const SurahData(number: 92, name: "الليل", englishName: "Al-Layl", type: "مكية", ayahsCount: 21, startPage: 595),
  const SurahData(number: 93, name: "الضحى", englishName: "Ad-Duha", type: "مكية", ayahsCount: 11, startPage: 596),
  const SurahData(number: 94, name: "الشرح", englishName: "Ash-Sharh", type: "مكية", ayahsCount: 8, startPage: 596),
  const SurahData(number: 95, name: "التين", englishName: "At-Tin", type: "مكية", ayahsCount: 8, startPage: 597),
  const SurahData(number: 96, name: "العلق", englishName: "Al-Alaq", type: "مكية", ayahsCount: 19, startPage: 597),
  const SurahData(number: 97, name: "القدر", englishName: "Al-Qadr", type: "مكية", ayahsCount: 5, startPage: 598),
  const SurahData(number: 98, name: "البينة", englishName: "Al-Bayyinah", type: "مدنية", ayahsCount: 8, startPage: 598),
  const SurahData(number: 99, name: "الزلزلة", englishName: "Az-Zalzalah", type: "مدنية", ayahsCount: 8, startPage: 599),
  const SurahData(number: 100, name: "العاديات", englishName: "Al-Adiyat", type: "مكية", ayahsCount: 11, startPage: 599),
  const SurahData(number: 101, name: "القارعة", englishName: "Al-Qari'ah", type: "مكية", ayahsCount: 11, startPage: 600),
  const SurahData(number: 102, name: "التكاثر", englishName: "At-Takathur", type: "مكية", ayahsCount: 8, startPage: 600),
  const SurahData(number: 103, name: "العصر", englishName: "Al-Asr", type: "مكية", ayahsCount: 3, startPage: 601),
  const SurahData(number: 104, name: "الهمزة", englishName: "Al-Humazah", type: "مكية", ayahsCount: 9, startPage: 601),
  const SurahData(number: 105, name: "الفيل", englishName: "Al-Fil", type: "مكية", ayahsCount: 5, startPage: 601),
  const SurahData(number: 106, name: "قريش", englishName: "Quraysh", type: "مكية", ayahsCount: 4, startPage: 602),
  const SurahData(number: 107, name: "الماعون", englishName: "Al-Ma'un", type: "مكية", ayahsCount: 7, startPage: 602),
  const SurahData(number: 108, name: "الكوثر", englishName: "Al-Kawthar", type: "مكية", ayahsCount: 3, startPage: 602),
  const SurahData(number: 109, name: "الكافرون", englishName: "Al-Kafirun", type: "مكية", ayahsCount: 6, startPage: 603),
  const SurahData(number: 110, name: "النصر", englishName: "An-Nasr", type: "مدنية", ayahsCount: 3, startPage: 603),
  const SurahData(number: 111, name: "المسد", englishName: "Al-Masad", type: "مكية", ayahsCount: 5, startPage: 603),
  const SurahData(number: 112, name: "الإخلاص", englishName: "Al-Ikhlas", type: "مكية", ayahsCount: 4, startPage: 604),
  const SurahData(number: 113, name: "الفلق", englishName: "Al-Falaq", type: "مكية", ayahsCount: 5, startPage: 604),
  const SurahData(number: 114, name: "الناس", englishName: "An-Nas", type: "مكية", ayahsCount: 6, startPage: 604),
];