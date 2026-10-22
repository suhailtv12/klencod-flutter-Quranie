import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const QuraniApp());
}

// -------------------------------------------------------------
// إدارة الحالة العامة (State Management مبسط وخفيف داخل الملف)
// -------------------------------------------------------------
class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.light;
  double quranFontSize = 22.0;
  List<int> bookmarkedSurahs = [1, 18, 36, 67]; // افتراضي
  int tasbihCount = 0;
  String currentZikr = "سُبْحَانَ اللَّهِ";

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setFontSize(double size) {
    quranFontSize = size;
    notifyListeners();
  }

  void toggleBookmark(int surahNumber) {
    if (bookmarkedSurahs.contains(surahNumber)) {
      bookmarkedSurahs.remove(surahNumber);
    } else {
      bookmarkedSurahs.add(surahNumber);
    }
    notifyListeners();
  }

  void incrementTasbih() {
    tasbihCount++;
    notifyListeners();
  }

  void resetTasbih() {
    tasbihCount = 0;
    notifyListeners();
  }

  void changeZikr(String newZikr) {
    currentZikr = newZikr;
    tasbihCount = 0;
    notifyListeners();
  }
}

final appState = AppState();

// -------------------------------------------------------------
// التطبيق الرئيسي
// -------------------------------------------------------------
class QuraniApp extends StatefulWidget {
  const QuraniApp({super.key});

  @override
  State<QuraniApp> createState() => _QuraniAppState();
}

class _QuraniAppState extends State<QuraniApp> {
  @override
  void initState() {
    super.initState();
    appState.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    // الألوان الإسلامية الراقية
    const primaryEmerald = Color(0xFF0E5A47);
    const accentGold = Color(0xFFC5A059);

    return MaterialApp(
      title: 'قرآني',
      debugShowCheckedModeBanner: false,
      themeMode: appState.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: primaryEmerald,
        scaffoldBackgroundColor: const Color(0xFFFBF9F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryEmerald,
          primary: primaryEmerald,
          secondary: accentGold,
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        fontFamily: 'Cairo',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: accentGold,
        scaffoldBackgroundColor: const Color(0xFF101915),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryEmerald,
          primary: accentGold,
          secondary: primaryEmerald,
          surface: const Color(0xFF192621),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Cairo',
      ),
      // إجبار الواجهة بالكامل على العمل بنظام من اليمين لليسار RTL
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MainNavigationScreen(),
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة التنقل الرئيسية (Bottom Navigation Bar)
// -------------------------------------------------------------
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    QuranHomeScreen(),
    AudioPlayerScreen(),
    TasbihScreen(),
    BookmarksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          elevation: 0,
          backgroundColor: theme.colorScheme.surface,
          indicatorColor: theme.colorScheme.primary.withOpacity(0.15),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book, color: Color(0xFF0E5A47)),
              label: 'المصحف',
            ),
            NavigationDestination(
              icon: Icon(Icons.headphones_outlined),
              selectedIcon: Icon(Icons.headphones, color: Color(0xFF0E5A47)),
              label: 'التلاوات',
            ),
            NavigationDestination(
              icon: Icon(Icons.touch_app_outlined),
              selectedIcon: Icon(Icons.touch_app, color: Color(0xFF0E5A47)),
              label: 'السبحة',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_outline),
              selectedIcon: Icon(Icons.bookmark, color: Color(0xFF0E5A47)),
              label: 'المفضلة',
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// الشاشة الرئيسية - فهرس السور والبحث
// -------------------------------------------------------------
class QuranHomeScreen extends StatefulWidget {
  const QuranHomeScreen({super.key});

  @override
  State<QuranHomeScreen> createState() => _QuranHomeScreenState();
}

class _QuranHomeScreenState extends State<QuranHomeScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredSurahs = quranSurahsList
        .where((s) => s.name.contains(searchQuery) || s.englishName.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

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
            icon: Icon(appState.themeMode == ThemeMode.light ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
            onPressed: () => appState.toggleTheme(),
            tooltip: 'تغيير المظهر',
          ),
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: CustomScrollView(
        slivers: [
          // آية اليوم وبطاقة القراءة السريعة
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _buildDailyAyahCard(theme),
                  const SizedBox(height: 16),
                  _buildSearchBar(theme),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // قائمة السور
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final surah = filteredSurahs[index];
                  return _buildSurahCard(context, surah);
                },
                childCount: filteredSurahs.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildDailyAyahCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E5A47), Color(0xFF1B8268)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E5A47).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.wb_sunny_outlined, color: Color(0xFFC5A059), size: 20),
                  SizedBox(width: 6),
                  Text("آية وتأمل", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text("سورة إبراهيم", style: TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "﴿ رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِن ذُرِّيَّتِي ۚ رَبَّنَا وَتَقَبَّلْ دُعَاءِ ﴾",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                // فتح آخر سورة تمت قراءتها
                final fatiha = quranSurahsList.first;
                Navigator.push(context, MaterialPageRoute(builder: (_) => SurahDetailScreen(surah: fatiha)));
              },
              icon: const Icon(Icons.arrow_back, color: Color(0xFFC5A059), size: 18),
              label: const Text("متابعة القراءة", style: TextStyle(color: Color(0xFFC5A059), fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return TextField(
      onChanged: (val) => setState(() => searchQuery = val),
      decoration: InputDecoration(
        hintText: 'ابحث عن اسم السورة...',
        prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A059)),
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSurahCard(BuildContext context, SurahModel surah) {
    final theme = Theme.of(context);
    final isBookmarked = appState.bookmarkedSurahs.contains(surah.number);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Directionality(
                textDirection: TextDirection.rtl,
                child: SurahDetailScreen(surah: surah),
              ),
            ),
          );
        },
        leading: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.brightness_5_outlined, size: 42, color: Color(0xFFC5A059)),
            Text(
              '${surah.number}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        title: Text(
          surah.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: Text(
          '${surah.type} • ${surah.ayahsCount} آيات',
          style: TextStyle(fontSize: 13, color: theme.textTheme.bodySmall?.color?.withOpacity(0.7)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: isBookmarked ? const Color(0xFFC5A059) : Colors.grey,
              ),
              onPressed: () => appState.toggleBookmark(surah.number),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة عرض السورة وقراءة المصحف والتحكم بحجم الخط
// -------------------------------------------------------------
class SurahDetailScreen extends StatefulWidget {
  final SurahModel surah;
  const SurahDetailScreen({super.key, required this.surah});

  @override
  State<SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends State<SurahDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.surah.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'تعديل حجم الخط',
            onPressed: () => _showFontSizeBottomSheet(context),
          ),
          IconButton(
            icon: Icon(
              appState.bookmarkedSurahs.contains(widget.surah.number) ? Icons.bookmark : Icons.bookmark_border,
              color: const Color(0xFFC5A059),
            ),
            onPressed: () => appState.toggleBookmark(widget.surah.number),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة معلومات السورة والبسملة
          _buildSurahHeader(),
          const SizedBox(height: 24),

          // الآيات
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: widget.surah.ayahs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        "يتم جلب نص السورة كاملاً... متوفر تجريبياً سورة الفاتحة والإخلاص وباقي السور تضاف عبر API.",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Column(
                    children: widget.surah.ayahs.map((ayah) {
                      return InkWell(
                        onTap: () => _showAyahOptions(context, ayah),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
                          ),
                          child: RichText(
                            textAlign: TextAlign.justify,
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: appState.quranFontSize,
                                height: 2.2,
                                color: theme.textTheme.bodyLarge?.color,
                                fontFamily: 'Cairo',
                              ),
                              children: [
                                TextSpan(text: ayah.text),
                                TextSpan(
                                  text: ' ﴿${ayah.numberInSurah}﴾ ',
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSurahHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E5A47),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            widget.surah.name,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.surah.type} • آياتها: ${widget.surah.ayahsCount}',
            style: const TextStyle(color: Color(0xFFC5A059), fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (widget.surah.number != 9) // التوبة لا تبدأ بالبسملة
            const Text(
              "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  void _showFontSizeBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('حجم خط الآيات القرآنية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.text_fields, size: 20),
                      Expanded(
                        child: Slider(
                          value: appState.quranFontSize,
                          min: 16.0,
                          max: 36.0,
                          divisions: 10,
                          activeColor: const Color(0xFF0E5A47),
                          inactiveColor: Colors.grey.shade300,
                          label: appState.quranFontSize.round().toString(),
                          onChanged: (val) {
                            setSheetState(() => appState.setFontSize(val));
                            setState(() {});
                          },
                        ),
                      ),
                      const Icon(Icons.text_fields, size: 30),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
                      style: TextStyle(fontSize: appState.quranFontSize, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _showAyahOptions(BuildContext context, AyahModel ayah) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الآية رقم (${ayah.numberInSurah})', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.menu_book, color: Color(0xFF0E5A47)),
                  title: const Text('التفسير الميسر'),
                  subtitle: Text(ayah.tafseer ?? 'التفسير: من أسرار هذه الآيات المباركة الهداية إلى صراط الله العزيز الحميد.'),
                  onTap: () => Navigator.pop(ctx),
                ),
                ListTile(
                  leading: const Icon(Icons.copy, color: Color(0xFFC5A059)),
                  title: const Text('نسخ الآية الكريمة'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ayah.text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ الآية بنجاح')));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// شاشة السبحة الإلكترونية التفاعلية
// -------------------------------------------------------------
class TasbihScreen extends StatelessWidget {
  const TasbihScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final azkar = [
      "سُبْحَانَ اللَّهِ",
      "الْحَمْدُ لِلَّهِ",
      "لَا إِلَهَ إِلَّا اللَّهُ",
      "اللَّهُ أَكْبَرُ",
      "أَسْتَغْفِرُ اللَّهَ",
      "لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ",
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('السبحة الذكية', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            const SizedBox(height: 20),
            // قائمة اختيار الذكر
            SizedBox(
              height: 45,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: azkar.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final z = azkar[idx];
                  final isSelected = appState.currentZikr == z;
                  return ChoiceChip(
                    label: Text(z),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0E5A47),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) => appState.changeZikr(z),
                  );
                },
              ),
            ),
            const Spacer(),

            // الدائرة التفاعلية للتسبيح
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                appState.incrementTasbih();
              },
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0E5A47).withOpacity(0.15),
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
                      appState.currentZikr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0E5A47)),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      '${appState.tasbihCount}',
                      style: const TextStyle(fontSize: 55, fontWeight: FontWeight.bold),
                    ),
                    const Text('انقر للتسبيح', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // زر إعادة التصفير
            ElevatedButton.icon(
              onPressed: () => appState.resetTasbih(),
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
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة التلاوات والمشغل الصوتي المتقدم
// -------------------------------------------------------------
class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  bool isPlaying = false;
  double progress = 0.35;
  String selectedReciter = "الشيخ مشاري راشد العفاسي";

  final reciters = [
    "الشيخ مشاري راشد العفاسي",
    "الشيخ عبد الباسط عبد الصمد",
    "الشيخ ماهر المعيقلي",
    "الشيخ سعد الغامدي",
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المستمع القرآني', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // اختيار القارئ
              DropdownButtonFormField<String>(
                value: selectedReciter,
                decoration: InputDecoration(
                  labelText: 'اختر القارئ',
                  prefixIcon: const Icon(Icons.person, color: Color(0xFFC5A059)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
                items: reciters.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (val) => setState(() => selectedReciter = val!),
              ),
              const Spacer(),

              // واجهة القرص التفاعلي
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E5A47), Color(0xFF1B8268)],
                  ),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF0E5A47).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.graphic_eq, size: 80, color: Color(0xFFC5A059)),
                ),
              ),
              const SizedBox(height: 30),

              const Text("سورة الكهف", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(selectedReciter, style: const TextStyle(color: Colors.grey, fontSize: 14)),

              const SizedBox(height: 20),

              // شريط تقدم التلاوة
              Slider(
                value: progress,
                activeColor: const Color(0xFF0E5A47),
                inactiveColor: Colors.grey.shade300,
                onChanged: (val) => setState(() => progress = val),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("12:45", style: TextStyle(fontSize: 12)),
                    Text("28:10", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // أزرار التحكم
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 15),
                  InkWell(
                    onTap: () => setState(() => isPlaying = !isPlaying),
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0E5A47)),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () {},
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// شاشة المفضلة والعلامات المرجعية
// -------------------------------------------------------------
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookmarked = quranSurahsList.where((s) => appState.bookmarkedSurahs.contains(s.number)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('المفضلة والمحفوظات', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: bookmarked.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_border, size: 70, color: Colors.grey),
                    SizedBox(height: 10),
                    Text('لا توجد سور محفوظة في المفضلة بعد.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: bookmarked.length,
                itemBuilder: (context, index) {
                  final surah = bookmarked[index];
                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.bookmark, color: Color(0xFFC5A059)),
                      title: Text(surah.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${surah.type} • ${surah.ayahsCount} آيات'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => appState.toggleBookmark(surah.number),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => SurahDetailScreen(surah: surah)),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// -------------------------------------------------------------
// نماذج البيانات وقاعدة البيانات المحلية الافتراضية
// -------------------------------------------------------------
class AyahModel {
  final int numberInSurah;
  final String text;
  final String? tafseer;

  AyahModel({required this.numberInSurah, required this.text, this.tafseer});
}

class SurahModel {
  final int number;
  final String name;
  final String englishName;
  final String type;
  final int ayahsCount;
  final List<AyahModel> ayahs;

  SurahModel({
    required this.number,
    required this.name,
    required this.englishName,
    required this.type,
    required this.ayahsCount,
    required this.ayahs,
  });
}

// عينة متكاملة جاهزة للعرض الفوري
final List<SurahModel> quranSurahsList = [
  SurahModel(
    number: 1,
    name: "سُورَةُ الفَاتِحَةِ",
    englishName: "Al-Fatiha",
    type: "مكية",
    ayahsCount: 7,
    ayahs: [
      AyahModel(numberInSurah: 1, text: "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", tafseer: "أبتدئ قراءتي مستعيناً باسم الله."),
      AyahModel(numberInSurah: 2, text: "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ", tafseer: "الثناء الكامل لله خالق الخلق ورازقهم."),
      AyahModel(numberInSurah: 3, text: "الرَّحْمَٰنِ الرَّحِيمِ", tafseer: "ذو الرحمة الواسعة بجميع خلقه."),
      AyahModel(numberInSurah: 4, text: "مَالِكِ يَوْمِ الدِّينِ", tafseer: "المتصرف وحده في يوم الجزاء والحساب."),
      AyahModel(numberInSurah: 5, text: "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ", tafseer: "نخصك وحدك بالعبادة وبالاستعانة."),
      AyahModel(numberInSurah: 6, text: "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ", tafseer: "وفقنا وسددنا إلى الطريق الواضح وهو الإسلام."),
      AyahModel(numberInSurah: 7, text: "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ", tafseer: "طريق النبيين والصديقين غير المغضوب عليهم وهم اليهود ومن تبعهم، ولا الضالين وهم النصارى."),
    ],
  ),
  SurahModel(
    number: 112,
    name: "سُورَةُ الإِخْلَاصِ",
    englishName: "Al-Ikhlas",
    type: "مكية",
    ayahsCount: 4,
    ayahs: [
      AyahModel(numberInSurah: 1, text: "قُلْ هُوَ اللَّهُ أَحَدٌ", tafseer: "قل أيها الرسول: هو الله المتفرد بالألوهية لا شريك له."),
      AyahModel(numberInSurah: 2, text: "اللَّهُ الصَّمَدُ", tafseer: "الذي يقصده جميع خلقه في قضاء حوائجهم."),
      AyahModel(numberInSurah: 3, text: "لَمْ يَلِدْ وَلَمْ يُولَدْ", tafseer: "تنزه عن الولد والوالد والكفء."),
      AyahModel(numberInSurah: 4, text: "وَلَمْ يَكُن لَّهُ كُفُوًا أَحَدٌ", tafseer: "وليس له مماثل ولا نظير سبحانه وتعالى."),
    ],
  ),
  SurahModel(
    number: 113,
    name: "سُورَةُ الفَلَقِ",
    englishName: "Al-Falaq",
    type: "مدنية",
    ayahsCount: 5,
    ayahs: [
      AyahModel(numberInSurah: 1, text: "قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ"),
      AyahModel(numberInSurah: 2, text: "مِن شَرِّ مَا خَلَقَ"),
      AyahModel(numberInSurah: 3, text: "وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ"),
      AyahModel(numberInSurah: 4, text: "وَمِن شَرِّ النَّفَّاثَاتِ فِي الْعُقَدِ"),
      AyahModel(numberInSurah: 5, text: "وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ"),
    ],
  ),
  SurahModel(
    number: 114,
    name: "سُورَةُ النَّاسِ",
    englishName: "An-Nas",
    type: "مدنية",
    ayahsCount: 6,
    ayahs: [
      AyahModel(numberInSurah: 1, text: "قُلْ أَعُوذُ بِرَبِّ النَّاسِ"),
      AyahModel(numberInSurah: 2, text: "مَلِكِ النَّاسِ"),
      AyahModel(numberInSurah: 3, text: "إِلَٰهِ النَّاسِ"),
      AyahModel(numberInSurah: 4, text: "مِن شَرِّ الْوَسْوَاسِ الْخَنَّاسِ"),
      AyahModel(numberInSurah: 5, text: "الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ"),
      AyahModel(numberInSurah: 6, text: "مِنَ الْجِنَّةِ وَالنَّاسِ"),
    ],
  ),
  SurahModel(number: 2, name: "سُورَةُ البَقَرَةِ", englishName: "Al-Baqarah", type: "مدنية", ayahsCount: 286, ayahs: []),
  SurahModel(number: 3, name: "سُورَةُ آلِ عِمْرَانَ", englishName: "Ali 'Imran", type: "مدنية", ayahsCount: 200, ayahs: []),
  SurahModel(number: 18, name: "سُورَةُ الكَهْفِ", englishName: "Al-Kahf", type: "مكية", ayahsCount: 110, ayahs: []),
  SurahModel(number: 36, name: "سُورَةُ يس", englishName: "Ya-Sin", type: "مكية", ayahsCount: 83, ayahs: []),
  SurahModel(number: 55, name: "سُورَةُ الرَّحْمَٰن", englishName: "Ar-Rahman", type: "مدنية", ayahsCount: 78, ayahs: []),
  SurahModel(number: 67, name: "سُورَةُ المُلْكِ", englishName: "Al-Mulk", type: "مكية", ayahsCount: 30, ayahs: []),
];