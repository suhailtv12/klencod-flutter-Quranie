import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  runApp(QuraniMasterApp(prefs: prefs));
}

// ============================================================================
// 1. نماذج البيانات (Models)
// ============================================================================
class QuranSurahInfo {
  final int number;
  final String name;
  final String englishName;
  final String revelationType;
  final int ayahsCount;
  final int pageNumber;

  const QuranSurahInfo({
    required this.number,
    required this.name,
    required this.englishName,
    required this.revelationType,
    required this.ayahsCount,
    required this.pageNumber,
  });
}

class ReciterInfo {
  final String name;
  final String riwayah;
  final String serverUrl;

  const ReciterInfo({
    required this.name,
    required this.riwayah,
    required this.serverUrl,
  });
}

// ============================================================================
// 2. إدارة الحالة المركزية للتطبيق (App Controller)
// ============================================================================
class AppController extends ChangeNotifier {
  final SharedPreferences prefs;
  final AudioPlayer audioPlayer = AudioPlayer();

  bool isDarkMode = false;
  double quranFontSize = 24.0;

  // مشغل الصوتيات
  int selectedReciterIndex = 0;
  int currentSurahAudioIndex = 0;
  bool isAudioLoading = false;
  Duration audioDuration = Duration.zero;
  Duration audioPosition = Duration.zero;

  // مواقيت الصلاة
  PrayerTimes? prayerTimes;
  String nextPrayerName = "جاري الحساب...";
  Duration timeUntilNextPrayer = Duration.zero;
  Timer? prayerTimer;

  // السبحة الإلكترونية
  int tasbihCounter = 0;
  int tasbihTarget = 33;
  String currentZikr = "سُبْحَانَ اللَّهِ";
  List<String> customAzkar = [
    "سُبْحَانَ اللَّهِ",
    "الْحَمْدُ لِلَّهِ",
    "لَا إِلَهَ إِلَّا اللَّهُ",
    "اللَّهُ أَكْبَرُ",
    "أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْهِ",
    "اللَّهُمَّ صَلِّ عَلَى سَيِّدِنَا مُحَمَّدٍ",
  ];

  // خطة الحفظ
  int hifzTotalTarget = 604;
  int hifzCurrentPage = 1;
  int hifzDailyPages = 2;

  // المفضلة
  List<int> bookmarkedSurahs = [];

  AppController(this.prefs) {
    _loadSavedData();
    _initAudioStreams();
    _initPrayerTimes();
    _startPrayerCountdown();
  }

  void _loadSavedData() {
    isDarkMode = prefs.getBool('darkMode') ?? false;
    quranFontSize = prefs.getDouble('quranFontSize') ?? 24.0;
    tasbihCounter = prefs.getInt('tasbihCounter') ?? 0;
    hifzCurrentPage = prefs.getInt('hifzCurrentPage') ?? 1;
    hifzDailyPages = prefs.getInt('hifzDailyPages') ?? 2;
    final savedAzkar = prefs.getStringList('customAzkar');
    if (savedAzkar != null) customAzkar = savedAzkar;
    final savedBookmarks = prefs.getStringList('bookmarks');
    if (savedBookmarks != null) {
      bookmarkedSurahs = savedBookmarks.map((e) => int.parse(e)).toList();
    }
  }

  void _initAudioStreams() {
    audioPlayer.durationStream.listen((d) {
      if (d != null) {
        audioDuration = d;
        notifyListeners();
      }
    });
    audioPlayer.positionStream.listen((p) {
      audioPosition = p;
      notifyListeners();
    });
    audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        playNextSurah();
      }
      notifyListeners();
    });
  }

  Future<void> playSurah(int surahIndex, {int? reciterIdx}) async {
    if (reciterIdx != null) selectedReciterIndex = reciterIdx;
    currentSurahAudioIndex = surahIndex;
    isAudioLoading = true;
    notifyListeners();

    final reciter = recitersList[selectedReciterIndex];
    final surahNumberStr = (surahIndex + 1).toString().padLeft(3, '0');
    final audioUrl = "${reciter.serverUrl}/$surahNumberStr.mp3";

    try {
      await audioPlayer.setUrl(audioUrl);
      audioPlayer.play();
    } catch (e) {
      debugPrint("Audio Play Error: $e");
    } finally {
      isAudioLoading = false;
      notifyListeners();
    }
  }

  void togglePlayPause() {
    if (audioPlayer.playing) {
      audioPlayer.pause();
    } else {
      if (audioPlayer.duration == null || audioPlayer.duration == Duration.zero) {
        playSurah(currentSurahAudioIndex);
      } else {
        audioPlayer.play();
      }
    }
    notifyListeners();
  }

  void playNextSurah() {
    if (currentSurahAudioIndex < allQuranSurahs.length - 1) {
      playSurah(currentSurahAudioIndex + 1);
    }
  }

  void playPrevSurah() {
    if (currentSurahAudioIndex > 0) {
      playSurah(currentSurahAudioIndex - 1);
    }
  }

  Future<void> _initPrayerTimes() async {
    Coordinates coordinates = Coordinates(21.4225, 39.8262); // مكة المكرمة
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
        coordinates = Coordinates(pos.latitude, pos.longitude);
      }
    } catch (_) {}

    final params = CalculationMethod.muslim_world_league.getParameters();
    params.madhab = Madhab.shafi;
    prayerTimes = PrayerTimes.today(coordinates, params);
    _calculateNextPrayer();
    notifyListeners();
  }

  void _calculateNextPrayer() {
    if (prayerTimes == null) return;
    final next = prayerTimes!.nextPrayer();
    DateTime? nextTime;

    switch (next) {
      case Prayer.fajr:
        nextPrayerName = "الفجر";
        nextTime = prayerTimes!.fajr;
        break;
      case Prayer.sunrise:
        nextPrayerName = "الشروق";
        nextTime = prayerTimes!.sunrise;
        break;
      case Prayer.dhuhr:
        nextPrayerName = "الظهر";
        nextTime = prayerTimes!.dhuhr;
        break;
      case Prayer.asr:
        nextPrayerName = "العصر";
        nextTime = prayerTimes!.asr;
        break;
      case Prayer.maghrib:
        nextPrayerName = "المغرب";
        nextTime = prayerTimes!.maghrib;
        break;
      case Prayer.isha:
        nextPrayerName = "العشاء";
        nextTime = prayerTimes!.isha;
        break;
      case Prayer.none:
        nextPrayerName = "الفجر (غداً)";
        nextTime = prayerTimes!.fajr.add(const Duration(days: 1));
        break;
    }

    if (nextTime != null) {
      timeUntilNextPrayer = nextTime.difference(DateTime.now());
      if (timeUntilNextPrayer.isNegative) timeUntilNextPrayer = Duration.zero;
    }
  }

  void _startPrayerCountdown() {
    prayerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (prayerTimes != null) {
        _calculateNextPrayer();
        notifyListeners();
      }
    });
  }

  void incrementTasbih() {
    tasbihCounter++;
    prefs.setInt('tasbihCounter', tasbihCounter);
    notifyListeners();
  }

  void resetTasbih() {
    tasbihCounter = 0;
    prefs.setInt('tasbihCounter', 0);
    notifyListeners();
  }

  void addCustomZikr(String zikr) {
    if (zikr.trim().isNotEmpty && !customAzkar.contains(zikr.trim())) {
      customAzkar.add(zikr.trim());
      prefs.setStringList('customAzkar', customAzkar);
      currentZikr = zikr.trim();
      resetTasbih();
    }
  }

  void updateHifzProgress(int pages) {
    hifzCurrentPage = (hifzCurrentPage + pages).clamp(1, hifzTotalTarget);
    prefs.setInt('hifzCurrentPage', hifzCurrentPage);
    notifyListeners();
  }

  void setHifzDailyTarget(int pages) {
    hifzDailyPages = pages;
    prefs.setInt('hifzDailyPages', pages);
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    prefs.setBool('darkMode', isDarkMode);
    notifyListeners();
  }

  void setFontSize(double size) {
    quranFontSize = size;
    prefs.setDouble('quranFontSize', size);
    notifyListeners();
  }

  void toggleBookmark(int surahNumber) {
    if (bookmarkedSurahs.contains(surahNumber)) {
      bookmarkedSurahs.remove(surahNumber);
    } else {
      bookmarkedSurahs.add(surahNumber);
    }
    prefs.setStringList('bookmarks', bookmarkedSurahs.map((e) => e.toString()).toList());
    notifyListeners();
  }

  @override
  void dispose() {
    audioPlayer.dispose();
    prayerTimer?.cancel();
    super.dispose();
  }
}

late AppController globalController;

// ============================================================================
// 3. التطبيق والتنقل العام
// ============================================================================
class QuraniMasterApp extends StatelessWidget {
  final SharedPreferences prefs;
  const QuraniMasterApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    globalController = AppController(prefs);

    return AnimatedBuilder(
      animation: globalController,
      builder: (context, _) {
        const primaryGreen = Color(0xFF0A4D3C);
        const goldAccent = Color(0xFFC5A059);

        return MaterialApp(
          title: 'قرآني',
          debugShowCheckedModeBanner: false,
          themeMode: globalController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: primaryGreen,
            scaffoldBackgroundColor: const Color(0xFFFBF9F5),
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryGreen,
              primary: primaryGreen,
              secondary: goldAccent,
              surface: Colors.white,
            ),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.light().textTheme),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: goldAccent,
            scaffoldBackgroundColor: const Color(0xFF101915),
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryGreen,
              primary: goldAccent,
              secondary: primaryGreen,
              surface: const Color(0xFF172420),
              brightness: Brightness.dark,
            ),
            textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
          ),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MainNavigationHub(),
          ),
        );
      },
    );
  }
}

class MainNavigationHub extends StatefulWidget {
  const MainNavigationHub({super.key});

  @override
  State<MainNavigationHub> createState() => _MainNavigationHubState();
}

class _MainNavigationHubState extends State<MainNavigationHub> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    QuranHomeScreen(),
    AudioStudioScreen(),
    HifzTrackerScreen(),
    TasbihScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        elevation: 10,
        backgroundColor: theme.colorScheme.surface,
        indicatorColor: theme.colorScheme.primary.withOpacity(0.15),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_rounded), label: 'المصحف'),
          NavigationDestination(icon: Icon(Icons.headphones_rounded), label: 'التلاوات'),
          NavigationDestination(icon: Icon(Icons.auto_graph_rounded), label: 'الحفظ'),
          NavigationDestination(icon: Icon(Icons.fingerprint_rounded), label: 'السبحة'),
          NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. الشاشة الرئيسية: المصحف الشريف والعد التنازلي للصلاة
// ============================================================================
class QuranHomeScreen extends StatefulWidget {
  const QuranHomeScreen({super.key});

  @override
  State<QuranHomeScreen> createState() => _QuranHomeScreenState();
}

class _QuranHomeScreenState extends State<QuranHomeScreen> {
  String searchKeyword = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = allQuranSurahs.where((s) {
      return s.name.contains(searchKeyword) ||
          s.englishName.toLowerCase().contains(searchKeyword.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_stories, color: Color(0xFFC5A059)),
            SizedBox(width: 10),
            Text('قرآني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(globalController.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => globalController.toggleTheme(),
          ),
        ],
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildPrayerCountdownCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                onChanged: (v) => setState(() => searchKeyword = v),
                decoration: InputDecoration(
                  hintText: 'ابحث باسم السورة (مثال: البقرة، يوسف، الكهف)...',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A059)),
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final surah = filtered[index];
                  final isFav = globalController.bookmarkedSurahs.contains(surah.number);

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC5A059), width: 1.5),
                        ),
                        child: Text(
                          '${surah.number}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      title: Text(
                        surah.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      subtitle: Text(
                        '${surah.revelationType} • ${surah.ayahsCount} آية • صفحة ${surah.pageNumber}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.bookmark : Icons.bookmark_border,
                              color: isFav ? const Color(0xFFC5A059) : Colors.grey,
                            ),
                            onPressed: () => globalController.toggleBookmark(surah.number),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: SurahReaderScreen(surah: surah),
                            ),
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

  Widget _buildPrayerCountdownCard() {
    final d = globalController.timeUntilNextPrayer;
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A4D3C), Color(0xFF166852)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A4D3C).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_filled, color: Color(0xFFC5A059), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "الصلاة القادمة: صلاة ${globalController.nextPrayerName}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text("مواقيت دقيقة", style: TextStyle(color: Colors.white, fontSize: 11)),
              )
            ],
          ),
          const SizedBox(height: 16),
          Text(
            "$h:$m:$s",
            style: const TextStyle(
              fontSize: 36,
              color: Color(0xFFC5A059),
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "الوقت المتبقي حتى موعد الأذان",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. قارئ المصحف الشريف والتفسير الميسر
// ============================================================================
class SurahReaderScreen extends StatefulWidget {
  final QuranSurahInfo surah;
  const SurahReaderScreen({super.key, required this.surah});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  bool isLoading = true;
  List<dynamic> ayahs = [];

  @override
  void initState() {
    super.initState();
    _fetchSurahContent();
  }

  Future<void> _fetchSurahContent() async {
    final url = Uri.parse("https://api.alquran.cloud/v1/surah/${widget.surah.number}/editions/quran-uthmani,ar.muyassar");
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final uthmani = data['data'][0]['ayahs'];
        final tafseer = data['data'][1]['ayahs'];

        List<dynamic> list = [];
        for (int i = 0; i < uthmani.length; i++) {
          list.add({
            'number': uthmani[i]['numberInSurah'],
            'text': uthmani[i]['text'],
            'tafseer': tafseer[i]['text'],
          });
        }
        if (mounted) {
          setState(() {
            ayahs = list;
            isLoading = false;
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
            'text': "نص الآية الكريمة المباركة رقم ${i + 1} من ${widget.surah.name}",
            'tafseer': "تفسير ميسر يساعد المؤمن على تدبر وفهم كتاب ربه.",
          },
        );
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () => _showFontSlider(),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: Color(0xFFC5A059)),
            onPressed: () {
              globalController.playSurah(widget.surah.number - 1);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('بدأ تشغيل ${widget.surah.name}')),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0A4D3C)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.surah.name,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C)),
                      ),
                      const SizedBox(height: 6),
                      Text('${widget.surah.revelationType} • ${widget.surah.ayahsCount} آيات'),
                      const SizedBox(height: 12),
                      if (widget.surah.number != 9)
                        Text(
                          "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
                          style: GoogleFonts.amiri(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: ayahs.map((a) {
                      return InkWell(
                        onTap: () => _showAyahSheet(a),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          child: RichText(
                            textAlign: TextAlign.justify,
                            text: TextSpan(
                              style: GoogleFonts.amiri(
                                fontSize: globalController.quranFontSize,
                                height: 2.3,
                                color: theme.textTheme.bodyLarge?.color,
                              ),
                              children: [
                                TextSpan(text: a['text']),
                                TextSpan(
                                  text: " ﴿${a['number']}﴾ ",
                                  style: const TextStyle(
                                    color: Color(0xFFC5A059),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  void _showAyahSheet(dynamic a) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الآية (${a['number']}) من ${widget.surah.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Divider(),
              const Text('التفسير الميسر:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C))),
              const SizedBox(height: 8),
              Text(a['tafseer'] ?? 'التفسير غير متوفر حالياً.', style: const TextStyle(fontSize: 15, height: 1.6)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Share.share("${a['text']} [${widget.surah.name}: ${a['number']}]\nتطبيق قرآني");
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A4D3C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.share),
                label: const Text('مشاركة الآية الكريمة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFontSlider() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('حجم خط الآيات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Slider(
                value: globalController.quranFontSize,
                min: 18,
                max: 38,
                activeColor: const Color(0xFF0A4D3C),
                onChanged: (v) {
                  setS(() => globalController.setFontSize(v));
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 6. استوديو التلاوات: أكثر من 30 قارئ بروايات متعددة
// ============================================================================
class AudioStudioScreen extends StatefulWidget {
  const AudioStudioScreen({super.key});

  @override
  State<AudioStudioScreen> createState() => _AudioStudioScreenState();
}

class _AudioStudioScreenState extends State<AudioStudioScreen> {
  String reciterSearch = "";

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final activeSurah = allQuranSurahs[globalController.currentSurahAudioIndex];
    final activeReciter = recitersList[globalController.selectedReciterIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصحف الصوتي المرتل', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A4D3C), Color(0xFF135B47)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: const Color(0xFF0A4D3C).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              children: [
                Text(
                  activeSurah.name,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "${activeReciter.name} (${activeReciter.riwayah})",
                  style: const TextStyle(color: Color(0xFFC5A059), fontSize: 14),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: globalController.audioPosition.inSeconds.toDouble().clamp(
                        0.0,
                        (globalController.audioDuration.inSeconds > 0)
                            ? globalController.audioDuration.inSeconds.toDouble()
                            : 1.0,
                      ),
                  max: (globalController.audioDuration.inSeconds > 0)
                      ? globalController.audioDuration.inSeconds.toDouble()
                      : 1.0,
                  activeColor: const Color(0xFFC5A059),
                  inactiveColor: Colors.white24,
                  onChanged: (val) {
                    globalController.audioPlayer.seek(Duration(seconds: val.toInt()));
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_format(globalController.audioPosition), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(_format(globalController.audioDuration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      icon: const Icon(Icons.skip_previous),
                      onPressed: () => globalController.playPrevSurah(),
                    ),
                    const SizedBox(width: 20),
                    InkWell(
                      onTap: () => globalController.togglePlayPause(),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFC5A059)),
                        child: globalController.isAudioLoading
                            ? const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Icon(
                                globalController.audioPlayer.playing ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      icon: const Icon(Icons.skip_next),
                      onPressed: () => globalController.playNextSurah(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('قائمة القراء:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(
                  onPressed: () => _showRecitersSheet(),
                  icon: const Icon(Icons.swap_horiz, color: Color(0xFFC5A059)),
                  label: const Text('تغيير القارئ',
                      style: TextStyle(color: Color(0xFFC5A059), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allQuranSurahs.length,
              itemBuilder: (context, index) {
                final s = allQuranSurahs[index];
                final isCurrent = index == globalController.currentSurahAudioIndex;

                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: isCurrent ? const Color(0xFF0A4D3C).withOpacity(0.1) : null,
                  leading: Icon(
                    isCurrent && globalController.audioPlayer.playing ? Icons.graphic_eq : Icons.play_circle_outline,
                    color: isCurrent ? const Color(0xFF0A4D3C) : Colors.grey,
                  ),
                  title: Text(s.name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${s.revelationType} • ${s.ayahsCount} آية'),
                  trailing: Text('${s.number}', style: const TextStyle(color: Colors.grey)),
                  onTap: () => globalController.playSurah(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRecitersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) {
          final filtered = recitersList.where((r) {
            return r.name.contains(reciterSearch) || r.riwayah.contains(reciterSearch);
          }).toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('اختر القارئ (32 قارئاً متاحاً)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setM(() => reciterSearch = v),
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم القارئ أو الرواية (ورش، حفص)...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A059)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final r = filtered[idx];
                        final originalIndex = recitersList.indexOf(r);
                        final isSel = originalIndex == globalController.selectedReciterIndex;

                        return ListTile(
                          leading: Icon(Icons.person, color: isSel ? const Color(0xFF0A4D3C) : Colors.grey),
                          title: Text(r.name, style: TextStyle(fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(r.riwayah, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFFC5A059)) : null,
                          onTap: () {
                            globalController.playSurah(globalController.currentSurahAudioIndex, reciterIdx: originalIndex);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 7. خطة حفظ القرآن الكريم وتتبع التقدم
// ============================================================================
class HifzTrackerScreen extends StatelessWidget {
  const HifzTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = globalController.hifzCurrentPage;
    final total = globalController.hifzTotalTarget;
    final progress = (cur / total).clamp(0.0, 1.0);
    final remainingDays = ((total - cur) / globalController.hifzDailyPages).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text('خطة حفظ القرآن', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))
              ],
            ),
            child: Column(
              children: [
                const Text('نسبة الإنجاز الإجمالية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF0A4D3C),
                  backgroundColor: Colors.grey.shade200,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('تم حفظ: $cur صفحة', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C))),
                    Text('${(progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC5A059))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard('المتبقي', '${total - cur} صفحة', Icons.menu_book, const Color(0xFF0A4D3C)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInfoCard('الختم المتوقع', 'خلال $remainingDays يوم', Icons.calendar_today, const Color(0xFFC5A059)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('تسجيل إنجاز اليوم:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => globalController.updateHifzProgress(1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A4D3C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('+1 صفحة'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => globalController.updateHifzProgress(2),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC5A059),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_circle),
                  label: const Text('+2 صفحة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String val, IconData icon, Color col) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: col),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: col)),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. السبحة الإلكترونية التفاعلية وإضافة أذكار مخصصة
// ============================================================================
class TasbihScreen extends StatefulWidget {
  const TasbihScreen({super.key});

  @override
  State<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends State<TasbihScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final TextEditingController _newZikrController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _newZikrController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('السبحة الذكية', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'إضافة ذكر جديد',
            onPressed: () => _showAddZikrDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: globalController.customAzkar.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final z = globalController.customAzkar[idx];
                final isSelected = globalController.currentZikr == z;
                return ChoiceChip(
                  label: Text(z),
                  selected: isSelected,
                  selectedColor: const Color(0xFF0A4D3C),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) {
                    setState(() {
                      globalController.currentZikr = z;
                      globalController.resetTasbih();
                    });
                  },
                );
              },
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTapDown: (_) => _animController.reverse(),
            onTapUp: (_) {
              _animController.forward();
              HapticFeedback.lightImpact();
              globalController.incrementTasbih();
            },
            child: ScaleTransition(
              scale: _animController,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0A4D3C).withOpacity(0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(color: const Color(0xFFC5A059), width: 3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      globalController.currentZikr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0A4D3C)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${globalController.tasbihCounter}',
                      style: const TextStyle(fontSize: 54, fontWeight: FontWeight.bold),
                    ),
                    const Text('المس للشاشة للتسبيح', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => globalController.resetTasbih(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة البدء'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showAddZikrDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة ذكر مخصص'),
          content: TextField(
            controller: _newZikrController,
            decoration: const InputDecoration(hintText: 'اكتب الذكر هنا...'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                globalController.addCustomZikr(_newZikrController.text);
                _newZikrController.clear();
                Navigator.pop(ctx);
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 9. شاشة الإعدادات العامة للتحكم بالتطبيق
// ============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('الوضع الليلي (Dark Mode)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('تبديل المظهر العام للتطبيق لتوفير طاقة الشاشة'),
            value: globalController.isDarkMode,
            activeColor: const Color(0xFFC5A059),
            onChanged: (_) => globalController.toggleTheme(),
          ),
          const Divider(),
          ListTile(
            title: const Text('حجم خط المصحف الشريف', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Slider(
              value: globalController.quranFontSize,
              min: 18,
              max: 38,
              activeColor: const Color(0xFF0A4D3C),
              onChanged: (v) => globalController.setFontSize(v),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bookmark, color: Color(0xFFC5A059)),
            title: const Text('المحفوظات والمفضلة', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text('${globalController.bookmarkedSurahs.length} سور'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF0A4D3C)),
            title: const Text('عن تطبيق قرآني'),
            subtitle: const Text('الإصدار 1.0.0 - وقف لله تعالى صدقة جارية'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 10. قاعدة بيانات القراء (32 قارئاً بروايات مختلفة عبر خوادم MP3Quran)
// ============================================================================
final List<ReciterInfo> recitersList = [
  const ReciterInfo(name: "مشاري راشد العفاسي", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/afs"),
  const ReciterInfo(name: "عبد الباسط عبد الصمد", riwayah: "المصحف المجود", serverUrl: "https://server7.mp3quran.net/basit/Almusshaf-Al-Mojawwad"),
  const ReciterInfo(name: "عبد الباسط عبد الصمد", riwayah: "حفص عن عاصم (مرتل)", serverUrl: "https://server7.mp3quran.net/basit"),
  const ReciterInfo(name: "محمود خليل الحصري", riwayah: "حفص عن عاصم", serverUrl: "https://server13.mp3quran.net/husr"),
  const ReciterInfo(name: "محمود خليل الحصري", riwayah: "ورش عن نافع", serverUrl: "https://server13.mp3quran.net/husr/warsh"),
  const ReciterInfo(name: "محمود علي البنا", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/bna"),
  const ReciterInfo(name: "محمد صديق المنشاوي", riwayah: "حفص عن عاصم (مرتل)", serverUrl: "https://server10.mp3quran.net/minsh"),
  const ReciterInfo(name: "محمد صديق المنشاوي", riwayah: "المصحف المجود", serverUrl: "https://server10.mp3quran.net/minsh/Almusshaf-Al-Mojawwad"),
  const ReciterInfo(name: "ماهر المعيقلي", riwayah: "حفص عن عاصم", serverUrl: "https://server12.mp3quran.net/maher"),
  const ReciterInfo(name: "سعد الغامدي", riwayah: "حفص عن عاصم", serverUrl: "https://server7.mp3quran.net/s_gmd"),
  const ReciterInfo(name: "أبو بكر الشاطري", riwayah: "حفص عن عاصم", serverUrl: "https://server11.mp3quran.net/shatri"),
  const ReciterInfo(name: "أحمد بن علي العجمي", riwayah: "حفص عن عاصم", serverUrl: "https://server10.mp3quran.net/ajm"),
  const ReciterInfo(name: "سعود الشريم", riwayah: "حفص عن عاصم", serverUrl: "https://server7.mp3quran.net/shur"),
  const ReciterInfo(name: "عبد الرحمن السديس", riwayah: "حفص عن عاصم", serverUrl: "https://server11.mp3quran.net/sds"),
  const ReciterInfo(name: "علي بن عبد الرحمن الحذيفي", riwayah: "حفص عن عاصم", serverUrl: "https://server9.mp3quran.net/hthfi"),
  const ReciterInfo(name: "علي بن عبد الرحمن الحذيفي", riwayah: "قالون عن نافع", serverUrl: "https://server9.mp3quran.net/hthfi/qalon"),
  const ReciterInfo(name: "ياسر الدوسري", riwayah: "حفص عن عاصم", serverUrl: "https://server11.mp3quran.net/yasser"),
  const ReciterInfo(name: "ناصر القطامي", riwayah: "حفص عن عاصم", serverUrl: "https://server6.mp3quran.net/qtm"),
  const ReciterInfo(name: "فارس عباد", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/frs_a"),
  const ReciterInfo(name: "إدريس أبكر", riwayah: "حفص عن عاصم", serverUrl: "https://server6.mp3quran.net/abkr"),
  const ReciterInfo(name: "خالد الجليل", riwayah: "حفص عن عاصم", serverUrl: "https://server10.mp3quran.net/jleel"),
  const ReciterInfo(name: "محمد أيوب", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/ayyoub"),
  const ReciterInfo(name: "عبد الله خياط", riwayah: "حفص عن عاصم", serverUrl: "https://server12.mp3quran.net/kyat"),
  const ReciterInfo(name: "عبد الله جهني", riwayah: "حفص عن عاصم", serverUrl: "https://server13.mp3quran.net/jhn"),
  const ReciterInfo(name: "محمد اللحيدان", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/lhdan"),
  const ReciterInfo(name: "صلاح بو خاطر", riwayah: "حفص عن عاصم", serverUrl: "https://server8.mp3quran.net/bu_khtr"),
  const ReciterInfo(name: "عبد الرشيد صوفي", riwayah: "السوسي عن أبي عمرو", serverUrl: "https://server16.mp3quran.net/soufi/soosi"),
  const ReciterInfo(name: "عبد الرشيد صوفي", riwayah: "خلف عن حمزة", serverUrl: "https://server16.mp3quran.net/soufi/khalaf"),
  const ReciterInfo(name: "عمر القزابري", riwayah: "ورش عن نافع", serverUrl: "https://server9.mp3quran.net/kzbr"),
  const ReciterInfo(name: "العيون الكوشي", riwayah: "ورش عن نافع", serverUrl: "https://server11.mp3quran.net/koshi"),
  const ReciterInfo(name: "ياسين الجزائري", riwayah: "ورش عن نافع", serverUrl: "https://server11.mp3quran.net/jaza"),
  const ReciterInfo(name: "مفتاح السلطني", riwayah: "الدوري عن أبي عمرو", serverUrl: "https://server10.mp3quran.net/sultany/doori"),
];

// ============================================================================
// 11. فهرس سور القرآن الكريم كاملاً (114 سورة)
// ============================================================================
final List<QuranSurahInfo> allQuranSurahs = [
  const QuranSurahInfo(number: 1, name: "الفاتحة", englishName: "Al-Fatiha", revelationType: "مكية", ayahsCount: 7, pageNumber: 1),
  const QuranSurahInfo(number: 2, name: "البقرة", englishName: "Al-Baqarah", revelationType: "مدنية", ayahsCount: 286, pageNumber: 2),
  const QuranSurahInfo(number: 3, name: "آل عمران", englishName: "Aal-E-Imran", revelationType: "مدنية", ayahsCount: 200, pageNumber: 50),
  const QuranSurahInfo(number: 4, name: "النساء", englishName: "An-Nisa", revelationType: "مدنية", ayahsCount: 176, pageNumber: 77),
  const QuranSurahInfo(number: 5, name: "المائدة", englishName: "Al-Ma'idah", revelationType: "مدنية", ayahsCount: 120, pageNumber: 106),
  const QuranSurahInfo(number: 6, name: "الأنعام", englishName: "Al-An'am", revelationType: "مكية", ayahsCount: 165, pageNumber: 128),
  const QuranSurahInfo(number: 7, name: "الأعراف", englishName: "Al-A'raf", revelationType: "مكية", ayahsCount: 206, pageNumber: 151),
  const QuranSurahInfo(number: 8, name: "الأنفال", englishName: "Al-Anfal", revelationType: "مدنية", ayahsCount: 75, pageNumber: 177),
  const QuranSurahInfo(number: 9, name: "التوبة", englishName: "At-Tawbah", revelationType: "مدنية", ayahsCount: 129, pageNumber: 187),
  const QuranSurahInfo(number: 10, name: "يونس", englishName: "Yunus", revelationType: "مكية", ayahsCount: 109, pageNumber: 208),
  const QuranSurahInfo(number: 11, name: "هود", englishName: "Hud", revelationType: "مكية", ayahsCount: 123, pageNumber: 221),
  const QuranSurahInfo(number: 12, name: "يوسف", englishName: "Yusuf", revelationType: "مكية", ayahsCount: 111, pageNumber: 235),
  const QuranSurahInfo(number: 13, name: "الرعد", englishName: "Ar-Ra'd", revelationType: "مدنية", ayahsCount: 43, pageNumber: 249),
  const QuranSurahInfo(number: 14, name: "إبراهيم", englishName: "Ibrahim", revelationType: "مكية", ayahsCount: 52, pageNumber: 255),
  const QuranSurahInfo(number: 15, name: "الحجر", englishName: "Al-Hijr", revelationType: "مكية", ayahsCount: 99, pageNumber: 262),
  const QuranSurahInfo(number: 16, name: "النحل", englishName: "An-Nahl", revelationType: "مكية", ayahsCount: 128, pageNumber: 267),
  const QuranSurahInfo(number: 17, name: "الإسراء", englishName: "Al-Isra", revelationType: "مكية", ayahsCount: 111, pageNumber: 282),
  const QuranSurahInfo(number: 18, name: "الكهف", englishName: "Al-Kahf", revelationType: "مكية", ayahsCount: 110, pageNumber: 293),
  const QuranSurahInfo(number: 19, name: "مريم", englishName: "Maryam", revelationType: "مكية", ayahsCount: 98, pageNumber: 305),
  const QuranSurahInfo(number: 20, name: "طه", englishName: "Ta-Ha", revelationType: "مكية", ayahsCount: 135, pageNumber: 312),
  const QuranSurahInfo(number: 21, name: "الأنبياء", englishName: "Al-Anbiya", revelationType: "مكية", ayahsCount: 112, pageNumber: 322),
  const QuranSurahInfo(number: 22, name: "الحج", englishName: "Al-Hajj", revelationType: "مدنية", ayahsCount: 78, pageNumber: 332),
  const QuranSurahInfo(number: 23, name: "المؤمنون", englishName: "Al-Mu'minun", revelationType: "مكية", ayahsCount: 118, pageNumber: 342),
  const QuranSurahInfo(number: 24, name: "النور", englishName: "An-Nur", revelationType: "مدنية", ayahsCount: 64, pageNumber: 350),
  const QuranSurahInfo(number: 25, name: "الفرقان", englishName: "Al-Furqan", revelationType: "مكية", ayahsCount: 77, pageNumber: 359),
  const QuranSurahInfo(number: 26, name: "الشعراء", englishName: "Ash-Shu'ara", revelationType: "مكية", ayahsCount: 227, pageNumber: 367),
  const QuranSurahInfo(number: 27, name: "النمل", englishName: "An-Naml", revelationType: "مكية", ayahsCount: 93, pageNumber: 377),
  const QuranSurahInfo(number: 28, name: "القصص", englishName: "Al-Qasas", revelationType: "مكية", ayahsCount: 88, pageNumber: 385),
  const QuranSurahInfo(number: 29, name: "العنكبوت", englishName: "Al-Ankabut", revelationType: "مكية", ayahsCount: 69, pageNumber: 396),
  const QuranSurahInfo(number: 30, name: "الروم", englishName: "Ar-Rum", revelationType: "مكية", ayahsCount: 60, pageNumber: 404),
  const QuranSurahInfo(number: 31, name: "لقمان", englishName: "Luqman", revelationType: "مكية", ayahsCount: 34, pageNumber: 411),
  const QuranSurahInfo(number: 32, name: "السجدة", englishName: "As-Sajdah", revelationType: "مكية", ayahsCount: 30, pageNumber: 415),
  const QuranSurahInfo(number: 33, name: "الأحزاب", englishName: "Al-Ahzab", revelationType: "مدنية", ayahsCount: 73, pageNumber: 418),
  const QuranSurahInfo(number: 34, name: "سبأ", englishName: "Saba", revelationType: "مكية", ayahsCount: 54, pageNumber: 428),
  const QuranSurahInfo(number: 35, name: "فاطر", englishName: "Fatir", revelationType: "مكية", ayahsCount: 45, pageNumber: 434),
  const QuranSurahInfo(number: 36, name: "يس", englishName: "Ya-Sin", revelationType: "مكية", ayahsCount: 83, pageNumber: 440),
  const QuranSurahInfo(number: 37, name: "الصافات", englishName: "As-Saffat", revelationType: "مكية", ayahsCount: 182, pageNumber: 446),
  const QuranSurahInfo(number: 38, name: "ص", englishName: "Sad", revelationType: "مكية", ayahsCount: 88, pageNumber: 453),
  const QuranSurahInfo(number: 39, name: "الزمر", englishName: "Az-Zumar", revelationType: "مكية", ayahsCount: 75, pageNumber: 458),
  const QuranSurahInfo(number: 40, name: "غافر", englishName: "Ghafir", revelationType: "مكية", ayahsCount: 85, pageNumber: 467),
  const QuranSurahInfo(number: 41, name: "فصلت", englishName: "Fussilat", revelationType: "مكية", ayahsCount: 54, pageNumber: 477),
  const QuranSurahInfo(number: 42, name: "الشورى", englishName: "Ash-Shura", revelationType: "مكية", ayahsCount: 53, pageNumber: 483),
  const QuranSurahInfo(number: 43, name: "الزخرف", englishName: "Az-Zukhruf", revelationType: "مكية", ayahsCount: 89, pageNumber: 489),
  const QuranSurahInfo(number: 44, name: "الدخان", englishName: "Ad-Dukhan", revelationType: "مكية", ayahsCount: 59, pageNumber: 496),
  const QuranSurahInfo(number: 45, name: "الجاثية", englishName: "Al-Jathiyah", revelationType: "مكية", ayahsCount: 37, pageNumber: 499),
  const QuranSurahInfo(number: 46, name: "الأحقاف", englishName: "Al-Ahqaf", revelationType: "مكية", ayahsCount: 35, pageNumber: 502),
  const QuranSurahInfo(number: 47, name: "محمد", englishName: "Muhammad", revelationType: "مدنية", ayahsCount: 38, pageNumber: 507),
  const QuranSurahInfo(number: 48, name: "الفتح", englishName: "Al-Fath", revelationType: "مدنية", ayahsCount: 29, pageNumber: 511),
  const QuranSurahInfo(number: 49, name: "الحجرات", englishName: "Al-Hujurat", revelationType: "مدنية", ayahsCount: 18, pageNumber: 515),
  const QuranSurahInfo(number: 50, name: "ق", englishName: "Qaf", revelationType: "مكية", ayahsCount: 45, pageNumber: 518),
  const QuranSurahInfo(number: 51, name: "الذاريات", englishName: "Adh-Dhariyat", revelationType: "مكية", ayahsCount: 60, pageNumber: 520),
  const QuranSurahInfo(number: 52, name: "الطور", englishName: "At-Tur", revelationType: "مكية", ayahsCount: 49, pageNumber: 523),
  const QuranSurahInfo(number: 53, name: "النجم", englishName: "An-Najm", revelationType: "مكية", ayahsCount: 62, pageNumber: 526),
  const QuranSurahInfo(number: 54, name: "القمر", englishName: "Al-Qamar", revelationType: "مكية", ayahsCount: 55, pageNumber: 528),
  const QuranSurahInfo(number: 55, name: "الرحمن", englishName: "Ar-Rahman", revelationType: "مدنية", ayahsCount: 78, pageNumber: 531),
  const QuranSurahInfo(number: 56, name: "الواقعة", englishName: "Al-Waqi'ah", revelationType: "مكية", ayahsCount: 96, pageNumber: 534),
  const QuranSurahInfo(number: 57, name: "الحديد", englishName: "Al-Hadid", revelationType: "مدنية", ayahsCount: 29, pageNumber: 537),
  const QuranSurahInfo(number: 58, name: "المجادلة", englishName: "Al-Mujadila", revelationType: "مدنية", ayahsCount: 22, pageNumber: 542),
  const QuranSurahInfo(number: 59, name: "الحشر", englishName: "Al-Hashr", revelationType: "مدنية", ayahsCount: 24, pageNumber: 545),
  const QuranSurahInfo(number: 60, name: "الممتحنة", englishName: "Al-Mumtahanah", revelationType: "مدنية", ayahsCount: 13, pageNumber: 549),
  const QuranSurahInfo(number: 61, name: "الصف", englishName: "As-Saff", revelationType: "مدنية", ayahsCount: 14, pageNumber: 551),
  const QuranSurahInfo(number: 62, name: "الجمعة", englishName: "Al-Jumu'ah", revelationType: "مدنية", ayahsCount: 11, pageNumber: 553),
  const QuranSurahInfo(number: 63, name: "المنافقون", englishName: "Al-Munafiqun", revelationType: "مدنية", ayahsCount: 11, pageNumber: 554),
  const QuranSurahInfo(number: 64, name: "التغابن", englishName: "At-Taghabun", revelationType: "مدنية", ayahsCount: 18, pageNumber: 556),
  const QuranSurahInfo(number: 65, name: "الطلاق", englishName: "At-Talaq", revelationType: "مدنية", ayahsCount: 12, pageNumber: 558),
  const QuranSurahInfo(number: 66, name: "التحريم", englishName: "At-Tahrim", revelationType: "مدنية", ayahsCount: 12, pageNumber: 560),
  const QuranSurahInfo(number: 67, name: "الملك", englishName: "Al-Mulk", revelationType: "مكية", ayahsCount: 30, pageNumber: 562),
  const QuranSurahInfo(number: 68, name: "القلم", englishName: "Al-Qalam", revelationType: "مكية", ayahsCount: 52, pageNumber: 564),
  const QuranSurahInfo(number: 69, name: "الحاقة", englishName: "Al-Haqqah", revelationType: "مكية", ayahsCount: 52, pageNumber: 566),
  const QuranSurahInfo(number: 70, name: "المعارج", englishName: "Al-Ma'arij", revelationType: "مكية", ayahsCount: 44, pageNumber: 568),
  const QuranSurahInfo(number: 71, name: "نوح", englishName: "Nuh", revelationType: "مكية", ayahsCount: 28, pageNumber: 570),
  const QuranSurahInfo(number: 72, name: "الجن", englishName: "Al-Jinn", revelationType: "مكية", ayahsCount: 28, pageNumber: 572),
  const QuranSurahInfo(number: 73, name: "المزمل", englishName: "Al-Muzzammil", revelationType: "مكية", ayahsCount: 20, pageNumber: 574),
  const QuranSurahInfo(number: 74, name: "المدثر", englishName: "Al-Muddathir", revelationType: "مكية", ayahsCount: 56, pageNumber: 575),
  const QuranSurahInfo(number: 75, name: "القيامة", englishName: "Al-Qiyamah", revelationType: "مكية", ayahsCount: 40, pageNumber: 577),
  const QuranSurahInfo(number: 76, name: "الإنسان", englishName: "Al-Insan", revelationType: "مدنية", ayahsCount: 31, pageNumber: 578),
  const QuranSurahInfo(number: 77, name: "المرسلات", englishName: "Al-Mursalat", revelationType: "مكية", ayahsCount: 50, pageNumber: 580),
  const QuranSurahInfo(number: 78, name: "النبأ", englishName: "An-Naba", revelationType: "مكية", ayahsCount: 40, pageNumber: 582),
  const QuranSurahInfo(number: 79, name: "النازعات", englishName: "An-Nazi'at", revelationType: "مكية", ayahsCount: 46, pageNumber: 583),
  const QuranSurahInfo(number: 80, name: "عبس", englishName: "Abasa", revelationType: "مكية", ayahsCount: 42, pageNumber: 585),
  const QuranSurahInfo(number: 81, name: "التكوير", englishName: "At-Takwir", revelationType: "مكية", ayahsCount: 29, pageNumber: 586),
  const QuranSurahInfo(number: 82, name: "الانفطار", englishName: "Al-Infitar", revelationType: "مكية", ayahsCount: 19, pageNumber: 587),
  const QuranSurahInfo(number: 83, name: "المطففين", englishName: "Al-Mutaffifin", revelationType: "مكية", ayahsCount: 36, pageNumber: 587),
  const QuranSurahInfo(number: 84, name: "الانشقاق", englishName: "Al-Inshiqaq", revelationType: "مكية", ayahsCount: 25, pageNumber: 589),
  const QuranSurahInfo(number: 85, name: "البروج", englishName: "Al-Buruj", revelationType: "مكية", ayahsCount: 22, pageNumber: 590),
  const QuranSurahInfo(number: 86, name: "الطارق", englishName: "At-Tariq", revelationType: "مكية", ayahsCount: 17, pageNumber: 591),
  const QuranSurahInfo(number: 87, name: "الأعلى", englishName: "Al-A'la", revelationType: "مكية", ayahsCount: 19, pageNumber: 591),
  const QuranSurahInfo(number: 88, name: "الغاشية", englishName: "Al-Ghashiyah", revelationType: "مكية", ayahsCount: 26, pageNumber: 592),
  const QuranSurahInfo(number: 89, name: "الفجر", englishName: "Al-Fajr", revelationType: "مكية", ayahsCount: 30, pageNumber: 593),
  const QuranSurahInfo(number: 90, name: "البلد", englishName: "Al-Balad", revelationType: "مكية", ayahsCount: 20, pageNumber: 594),
  const QuranSurahInfo(number: 91, name: "الشمس", englishName: "Ash-Shams", revelationType: "مكية", ayahsCount: 15, pageNumber: 595),
  const QuranSurahInfo(number: 92, name: "الليل", englishName: "Al-Layl", revelationType: "مكية", ayahsCount: 21, pageNumber: 595),
  const QuranSurahInfo(number: 93, name: "الضحى", englishName: "Ad-Duha", revelationType: "مكية", ayahsCount: 11, pageNumber: 596),
  const QuranSurahInfo(number: 94, name: "الشرح", englishName: "Ash-Sharh", revelationType: "مكية", ayahsCount: 8, pageNumber: 596),
  const QuranSurahInfo(number: 95, name: "التين", englishName: "At-Tin", revelationType: "مكية", ayahsCount: 8, pageNumber: 597),
  const QuranSurahInfo(number: 96, name: "العلق", englishName: "Al-Alaq", revelationType: "مكية", ayahsCount: 19, pageNumber: 597),
  const QuranSurahInfo(number: 97, name: "القدر", englishName: "Al-Qadr", revelationType: "مكية", ayahsCount: 5, pageNumber: 598),
  const QuranSurahInfo(number: 98, name: "البينة", englishName: "Al-Bayyinah", revelationType: "مدنية", ayahsCount: 8, pageNumber: 598),
  const QuranSurahInfo(number: 99, name: "الزلزلة", englishName: "Az-Zalzalah", revelationType: "مدنية", ayahsCount: 8, pageNumber: 599),
  const QuranSurahInfo(number: 100, name: "العاديات", englishName: "Al-Adiyat", revelationType: "مكية", ayahsCount: 11, pageNumber: 599),
  const QuranSurahInfo(number: 101, name: "القارعة", englishName: "Al-Qari'ah", revelationType: "مكية", ayahsCount: 11, pageNumber: 600),
  const QuranSurahInfo(number: 102, name: "التكاثر", englishName: "At-Takathur", revelationType: "مكية", ayahsCount: 8, pageNumber: 600),
  const QuranSurahInfo(number: 103, name: "العصر", englishName: "Al-Asr", revelationType: "مكية", ayahsCount: 3, pageNumber: 601),
  const QuranSurahInfo(number: 104, name: "الهمزة", englishName: "Al-Humazah", revelationType: "مكية", ayahsCount: 9, pageNumber: 601),
  const QuranSurahInfo(number: 105, name: "الفيل", englishName: "Al-Fil", revelationType: "مكية", ayahsCount: 5, pageNumber: 601),
  const QuranSurahInfo(number: 106, name: "قريش", englishName: "Quraysh", revelationType: "مكية", ayahsCount: 4, pageNumber: 602),
  const QuranSurahInfo(number: 107, name: "الماعون", englishName: "Al-Ma'un", revelationType: "مكية", ayahsCount: 7, pageNumber: 602),
  const QuranSurahInfo(number: 108, name: "الكوثر", englishName: "Al-Kawthar", revelationType: "مكية", ayahsCount: 3, pageNumber: 602),
  const QuranSurahInfo(number: 109, name: "الكافرون", englishName: "Al-Kafirun", revelationType: "مكية", ayahsCount: 6, pageNumber: 603),
  const QuranSurahInfo(number: 110, name: "النصر", englishName: "An-Nasr", revelationType: "مدنية", ayahsCount: 3, pageNumber: 603),
  const QuranSurahInfo(number: 111, name: "المسد", englishName: "Al-Masad", revelationType: "مكية", ayahsCount: 5, pageNumber: 603),
  const QuranSurahInfo(number: 112, name: "الإخلاص", englishName: "Al-Ikhlas", revelationType: "مكية", ayahsCount: 4, pageNumber: 604),
  const QuranSurahInfo(number: 113, name: "الفلق", englishName: "Al-Falaq", revelationType: "مكية", ayahsCount: 5, pageNumber: 604),
  const QuranSurahInfo(number: 114, name: "الناس", englishName: "An-Nas", revelationType: "مكية", ayahsCount: 6, pageNumber: 604),
];