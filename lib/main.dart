import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  runApp(QuraniUltimateApp(prefs: prefs));
}

// ============================================================================
// 1. نماذج البيانات (Models)
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

  DownloadedAudio({
    required this.surahNumber,
    required this.surahName,
    required this.reciterName,
    required this.filePath,
  });

  Map<String, dynamic> toMap() => {
    'surahNumber': surahNumber,
    'surahName': surahName,
    'reciterName': reciterName,
    'filePath': filePath,
  };

  factory DownloadedAudio.fromMap(Map<String, dynamic> map) => DownloadedAudio(
    surahNumber: map['surahNumber'],
    surahName: map['surahName'],
    reciterName: map['reciterName'],
    filePath: map['filePath'],
  );
}

// ============================================================================
// 2. محرك التطبيق وإدارة الحالة دون أي تعليق (Non-blocking Engine)
// ============================================================================
class AppEngine extends ChangeNotifier with WidgetsBindingObserver {
  final SharedPreferences prefs;
  final AudioPlayer player = AudioPlayer();

  bool isDark = false;
  double fontSize = 24.0;

  // مشغل الصوت
  int currentReciterIndex = 0;
  int currentSurahIndex = 0;
  bool isAudioBuffering = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  String currentPlayingTitle = "";
  bool isPlayingOffline = false;

  // مواقيت الصلاة والمؤقت
  PrayerTimes? prayerTimes;
  String nextPrayer = "الفجر";
  Duration remainingTime = Duration.zero;
  Timer? ticker;

  // السبحة
  int tasbihCount = 0;
  int tasbihTarget = 33;
  String selectedZikr = "سُبْحَانَ اللَّهِ";
  List<String> azkarList = [
    "سُبْحَانَ اللَّهِ",
    "الْحَمْدُ لِلَّهِ",
    "لَا إِلَهَ إِلَّا اللَّهُ",
    "اللَّهُ أَكْبَرُ",
    "أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ",
    "اللَّهُمَّ صَلِّ عَلَى سَيِّدِنَا مُحَمَّدٍ",
  ];

  // التحميلات والمفضلة
  List<DownloadedAudio> downloadedList = [];
  Map<int, double> downloadProgress = {};

  AppEngine(this.prefs) {
    WidgetsBinding.instance.addObserver(this);
    _loadLocalSettings();
    _setupAudioStreams();
    _initFastPrayerTimes();
    _startCountdown();
  }

  void _loadLocalSettings() {
    isDark = prefs.getBool('isDark') ?? false;
    fontSize = prefs.getDouble('fontSize') ?? 24.0;
    tasbihCount = prefs.getInt('tasbihCount') ?? 0;
    final custom = prefs.getStringList('azkarList');
    if (custom != null && custom.isNotEmpty) azkarList = custom;

    final dStr = prefs.getString('downloaded_audios');
    if (dStr != null) {
      final List dec = jsonDecode(dStr);
      downloadedList = dec.map((e) => DownloadedAudio.fromMap(e)).toList();
    }
  }

  void _setupAudioStreams() {
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

  // --- كود فحص وطلب إذن الموقع الجغرافي التفاعلي المدمج هنا ---
  Future<void> requestAppPermissions(BuildContext context) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى تفعيل الـ GPS لتحديد مواقيت الصلاة بدقة لموقعك الحالي'),
              backgroundColor: Color(0xFF0A4D3C),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفض الإذن، سيتم اعتماد توقيت مكة المكرمة كافتراضي.')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('تم رفض الإذن نهائياً، يرجى تفعيله من إعدادات الهاتف.'),
              action: SnackBarAction(
                label: 'الإعدادات',
                textColor: const Color(0xFFC5A059),
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        _calculateTimes(Coordinates(pos.latitude, pos.longitude));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحديد موقعك بنجاح وتحديث مواقيت الصلاة!'),
              backgroundColor: Color(0xFF0A4D3C),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("خطأ أثناء طلب الصلاحيات: $e");
    }
  }

  // --- تشغيل الصوت أوفلاين أو أونلاين ---
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
      if (localMatch.surahNumber != -1 && File(localMatch.filePath).existsSync() && !forceOnline) {
        isPlayingOffline = true;
        await player.setFilePath(localMatch.filePath);
      } else {
        isPlayingOffline = false;
        final numPad = surah.number.toString().padLeft(3, '0');
        final remoteUrl = "${reciter.server}/$numPad.mp3";
        await player.setUrl(remoteUrl);
      }
      player.play();
    } catch (e) {
      debugPrint("Audio Error: $e");
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
      await player.setFilePath(item.filePath);
      player.play();
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

  // --- تحميل السورة الصوتية إلى ذاكرة الهاتف أوفلاين ---
  Future<void> downloadSurahAudio(SurahData surah, ReciterData reciter) async {
    final numPad = surah.number.toString().padLeft(3, '0');
    final remoteUrl = "${reciter.server}/$numPad.mp3";

    downloadProgress[surah.number] = 0.05;
    notifyListeners();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = "${dir.path}/surah_${reciter.id}_$numPad.mp3";
      final file = File(savePath);

      if (file.existsSync()) {
        file.deleteSync();
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(remoteUrl));
      final response = await client.send(request);

      final totalBytes = response.contentLength ?? 1;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await response.stream.listen((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        downloadProgress[surah.number] = (receivedBytes / totalBytes).clamp(0.0, 1.0);
        notifyListeners();
      }).asFuture();

      await sink.close();

      downloadedList.removeWhere((d) => d.surahNumber == surah.number && d.reciterName == reciter.name);
      downloadedList.add(DownloadedAudio(
        surahNumber: surah.number,
        surahName: surah.name,
        reciterName: reciter.name,
        filePath: savePath,
      ));

      prefs.setString('downloaded_audios', jsonEncode(downloadedList.map((e) => e.toMap()).toList()));
    } catch (e) {
      debugPrint("Download failed: $e");
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

  // --- حساب المواقيت المبدئية ---
  void _initFastPrayerTimes() {
    _calculateTimes(Coordinates(21.4225, 39.8262));
  }

  void _calculateTimes(Coordinates coords) {
    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi;
    prayerTimes = PrayerTimes.today(coords, params);
    _syncNextPrayer();
    notifyListeners();
  }

  void _syncNextPrayer() {
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

  void _startCountdown() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (prayerTimes != null) {
        _syncNextPrayer();
        notifyListeners();
      }
    });
  }

  // --- السبحة ---
  void hitTasbih() {
    tasbihCount++;
    prefs.setInt('tasbihCount', tasbihCount);
    notifyListeners();
  }

  void resetTasbih() {
    tasbihCount = 0;
    prefs.setInt('tasbihCount', 0);
    notifyListeners();
  }

  void addNewZikr(String text) {
    if (text.trim().isNotEmpty && !azkarList.contains(text.trim())) {
      azkarList.add(text.trim());
      prefs.setStringList('azkarList', azkarList);
      selectedZikr = text.trim();
      resetTasbih();
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncNextPrayer();
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
// 3. الواجهة الرئيسية والتنقل
// ============================================================================
class QuraniUltimateApp extends StatelessWidget {
  final SharedPreferences prefs;
  const QuraniUltimateApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    appEngine = AppEngine(prefs);

    return AnimatedBuilder(
      animation: appEngine,
      builder: (context, _) {
        const primaryColor = Color(0xFF0A4D3C);
        const goldColor = Color(0xFFC5A059);

        return MaterialApp(
          title: 'قرآني',
          debugShowCheckedModeBanner: false,
          themeMode: appEngine.isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: primaryColor,
            scaffoldBackgroundColor: const Color(0xFFF9F7F2),
            colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: primaryColor, secondary: goldColor, surface: Colors.white),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.light().textTheme),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: goldColor,
            scaffoldBackgroundColor: const Color(0xFF0E1613),
            colorScheme: ColorScheme.fromSeed(seedColor: primaryColor, primary: goldColor, secondary: primaryColor, surface: const Color(0xFF15221E), brightness: Brightness.dark),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
          ),
          home: const Directionality(textDirection: TextDirection.rtl, child: RootNavScreen()),
        );
      },
    );
  }
}

class RootNavScreen extends StatefulWidget {
  const RootNavScreen({super.key});

  @override
  State<RootNavScreen> createState() => _RootNavScreenState();
}

class _RootNavScreenState extends State<RootNavScreen> {
  int _idx = 0;
  final List<Widget> _screens = const [
    HomeScreen(),
    AudioScreen(),
    DownloadsScreen(),
    TasbihScreen(),
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
          NavigationDestination(icon: Icon(Icons.download_done_rounded), label: 'التحميلات'),
          NavigationDestination(icon: Icon(Icons.fingerprint_rounded), label: 'السبحة'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. الشاشة الرئيسية: المصحف والمؤقت السريع
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
    // تظهر نافذة طلب الصلاحية على الشاشة تلقائياً بعد تشغيل التطبيق بثوانٍ قليلة وبدون تعليق
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
            tooltip: 'تحديث الموقع ومواقيت الصلاة',
            onPressed: () {
              appEngine.requestAppPermissions(context);
            },
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildCountdownBanner(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: InputDecoration(
                  hintText: 'ابحث عن سورة بالاسم (مثال: الكهف، مريم)...',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A059)),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final s = filtered[i];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC5A059), width: 1.5)),
                        child: Text('${s.number}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      subtitle: Text('${s.type} • ${s.ayahsCount} آيات • صـ ${s.startPage}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SurahViewer(surah: s)),
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

  Widget _buildCountdownBanner() {
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
              const Icon(Icons.alarm_on, color: Color(0xFFC5A059)),
            ],
          ),
          const SizedBox(height: 14),
          Text("$h:$m:$s", style: const TextStyle(fontSize: 38, color: Color(0xFFC5A059), fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 4),
          const Text("الوقت المتبقي حتى الأذان (محدث تلقائياً)", style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. قارئ المصحف الشريف
// ============================================================================
class SurahViewer extends StatefulWidget {
  final SurahData surah;
  const SurahViewer({super.key, required this.surah});

  @override
  State<SurahViewer> createState() => _SurahViewerState();
}

class _SurahViewerState extends State<SurahViewer> with SingleTickerProviderStateMixin {
  late TabController tabCtrl;
  bool loading = true;
  List<dynamic> ayahs = [];
  String? localImagePath;

  @override
  void initState() {
    super.initState();
    tabCtrl = TabController(length: 2, vsync: this);
    _checkLocalImage();
    _loadSurahTextWithCache();
  }

  Future<void> _checkLocalImage() async {
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

  Future<void> _loadSurahTextWithCache() async {
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
            'tafseer': "تفسير الآية متاح بعد الاتصال بالإنترنت لأول مرة ليتم حفظه تلقائياً.",
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
        bottom: TabBar(
          controller: tabCtrl,
          indicatorColor: const Color(0xFFC5A059),
          tabs: const [
            Tab(icon: Icon(Icons.image), text: "صفحة المصحف (أوفلاين)"),
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
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Color(0xFF0A4D3C)),
                              SizedBox(height: 10),
                              Text("جاري تنزيل وحفظ صفحة المصحف للأوفلاين..."),
                            ],
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Text("تعذر جلب صورة المصحف، يرجى تشغيل الإنترنت لمرة واحدة لحفظها."),
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
// 6. مشغل الصوتيات مع إمكانية التحميل أوفلاين
// ============================================================================
class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key});

  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> {
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
                    child: const Text("تشغيل بدون إنترنت (محلي)", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
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
                  onPressed: () => _chooseReciterDialog(),
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
                      ? SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(value: prog, color: const Color(0xFFC5A059)),
                        )
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

  void _chooseReciterDialog() {
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
                const Text('اختر القارئ المفضل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
// 7. قسم التحميلات الصوتية الأوفلاين
// ============================================================================
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final list = appEngine.downloadedList;

    return Scaffold(
      appBar: AppBar(
        title: const Text('السور الصوتية المحملة (أوفلاين)', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: list.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 70, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('لا توجد سور محملة بعد.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('يمكنك الذهاب لقسم "التلاوات" وتحميل أي سورة للاستماع بدون إنترنت.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final item = list[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF0A4D3C),
                      child: Icon(Icons.play_arrow, color: Colors.white),
                    ),
                    title: Text(item.surahName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${item.reciterName} • ملف محلي أوفلاين"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => appEngine.deleteDownloadedAudio(item),
                    ),
                    onTap: () => appEngine.playDownloadedFile(item),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================================
// 8. السبحة الإلكترونية التفاعلية
// ============================================================================
class TasbihScreen extends StatefulWidget {
  const TasbihScreen({super.key});

  @override
  State<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends State<TasbihScreen> with SingleTickerProviderStateMixin {
  late AnimationController animCtrl;
  final TextEditingController newZikr = TextEditingController();

  @override
  void initState() {
    super.initState();
    animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 90), lowerBound: 0.94, upperBound: 1.0, value: 1.0);
  }

  @override
  void dispose() {
    animCtrl.dispose();
    newZikr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('السبحة الذكية', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('إضافة ذكر جديد'),
                  content: TextField(controller: newZikr, decoration: const InputDecoration(hintText: 'اكتب الذكر...')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                    ElevatedButton(
                      onPressed: () {
                        appEngine.addNewZikr(newZikr.text);
                        newZikr.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text('حفظ'),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: appEngine.azkarList.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final z = appEngine.azkarList[i];
                final sel = appEngine.selectedZikr == z;
                return ChoiceChip(
                  label: Text(z),
                  selected: sel,
                  selectedColor: const Color(0xFF0A4D3C),
                  labelStyle: TextStyle(color: sel ? Colors.white : null, fontWeight: FontWeight.bold),
                  onSelected: (_) {
                    setState(() {
                      appEngine.selectedZikr = z;
                      appEngine.resetTasbih();
                    });
                  },
                );
              },
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTapDown: (_) => animCtrl.reverse(),
            onTapUp: (_) {
              animCtrl.forward();
              HapticFeedback.lightImpact();
              appEngine.hitTasbih();
            },
            child: ScaleTransition(
              scale: animCtrl,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF0A4D3C).withOpacity(0.18), blurRadius: 25, spreadRadius: 4),
                  ],
                  border: Border.all(color: const Color(0xFFC5A059), width: 4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(appEngine.selectedZikr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C))),
                    const SizedBox(height: 10),
                    Text('${appEngine.tasbihCount}', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold)),
                    const Text('المس للتسبيح', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => appEngine.resetTasbih(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400, foregroundColor: Colors.white),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة البدء'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ============================================================================
// 9. شاشة الإعدادات
// ============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('الوضع الليلي (Dark Mode)'),
            value: appEngine.isDark,
            activeColor: const Color(0xFFC5A059),
            onChanged: (_) => appEngine.toggleTheme(),
          ),
          const Divider(),
          ListTile(
            title: const Text('حجم خط الآيات القرآنية'),
            subtitle: Slider(
              value: appEngine.fontSize,
              min: 18,
              max: 38,
              activeColor: const Color(0xFF0A4D3C),
              onChanged: (v) => appEngine.updateFontSize(v),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF0A4D3C)),
            title: const Text('عن تطبيق قرآني'),
            subtitle: const Text('تطبيق إسلامي شامل ومجاني بدون إعلانات'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 10. قاعدة بيانات القراء (32 قارئاً بروايات مختلفة)
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
// 11. فهرس الـ 114 سورة كاملاً
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