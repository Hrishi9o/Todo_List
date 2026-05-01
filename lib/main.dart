import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  await LocalDatabase.init();
  runApp(const TaskBuddyMaxApp());
}

/* =============================================================================
   1. DATA MODELS
============================================================================= */

class AppUser {
  final String id;
  final String name;
  final String email;
  final String password;
  bool isVerified;

  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    this.isVerified = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'password': password,
        'isVerified': isVerified,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'],
        name: json['name'],
        email: json['email'],
        password: json['password'],
        isVerified: json['isVerified'] ?? false,
      );
}

class TaskCategory {
  final String id;
  final String name;
  final int colorValue;

  TaskCategory({
    required this.id,
    required this.name,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
      };

  factory TaskCategory.fromJson(Map<String, dynamic> json) => TaskCategory(
        id: json['id'],
        name: json['name'],
        colorValue: json['colorValue'],
      );
}

class TaskItem {
  final String id;
  String title;
  String description;
  DateTime deadline;
  String categoryId;
  String priority; 
  bool isCompleted;
  int focusMinutesSpent;

  TaskItem({
    required this.id,
    required this.title,
    required this.description,
    required this.deadline,
    required this.categoryId,
    required this.priority,
    this.isCompleted = false,
    this.focusMinutesSpent = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'deadline': deadline.toIso8601String(),
        'categoryId': categoryId,
        'priority': priority,
        'isCompleted': isCompleted,
        'focusMinutesSpent': focusMinutesSpent,
      };

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        deadline: DateTime.parse(json['deadline']),
        categoryId: json['categoryId'],
        priority: json['priority'],
        isCompleted: json['isCompleted'],
        focusMinutesSpent: json['focusMinutesSpent'] ?? 0,
      );
}

// NEW MODULE: Journal Entries
class JournalEntry {
  final String id;
  final String content;
  final DateTime date;

  JournalEntry({required this.id, required this.content, required this.date});

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'date': date.toIso8601String(),
      };

  factory JournalEntry.fromJson(Map<String, dynamic> json) => JournalEntry(
        id: json['id'],
        content: json['content'],
        date: DateTime.parse(json['date']),
      );
}

/* =============================================================================
   2. DATABASE & STATE MANAGEMENT (Singleton Pattern)
============================================================================= */

class LocalDatabase {
  static late SharedPreferences _prefs;
  static AppUser? currentUser;
  
  static final ValueNotifier<bool> isDarkMode = ValueNotifier(true);
  static final ValueNotifier<List<TaskItem>> currentTasks = ValueNotifier([]);
  static final ValueNotifier<List<TaskCategory>> currentCategories = ValueNotifier([]);
  static final ValueNotifier<List<JournalEntry>> currentJournals = ValueNotifier([]);
  static final ValueNotifier<int> waterIntake = ValueNotifier(0);

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isDarkMode.value = _prefs.getBool('isDark') ?? true;
    _loadSession();
  }

  static void _loadSession() {
    final activeUserId = _prefs.getString('active_user_id');
    if (activeUserId != null) {
      final userJson = _prefs.getString('user_$activeUserId');
      if (userJson != null) {
        currentUser = AppUser.fromJson(jsonDecode(userJson));
        loadUserData();
      }
    }
  }

  static Future<void> toggleTheme() async {
    isDarkMode.value = !isDarkMode.value;
    await _prefs.setBool('isDark', isDarkMode.value);
  }

  static Future<bool> registerUser(String name, String email, String password) async {
    final existing = _prefs.getString('user_$email');
    if (existing != null) return false;

    final newUser = AppUser(id: email, name: name, email: email, password: password);
    await _prefs.setString('user_$email', jsonEncode(newUser.toJson()));
    return true;
  }

  static Future<AppUser?> loginUser(String email, String password) async {
    final userJson = _prefs.getString('user_$email');
    if (userJson == null) return null;

    final user = AppUser.fromJson(jsonDecode(userJson));
    if (user.password == password) {
      return user;
    }
    return null;
  }

  static Future<void> setActiveSession(AppUser user) async {
    currentUser = user;
    await _prefs.setString('active_user_id', user.id);
    await _prefs.setString('user_${user.id}', jsonEncode(user.toJson()));
    loadUserData();
  }

  static Future<void> logout() async {
    currentUser = null;
    currentTasks.value = [];
    currentCategories.value = [];
    currentJournals.value = [];
    waterIntake.value = 0;
    await _prefs.remove('active_user_id');
  }

  static Future<String> generateOTP(String email) async {
    final otp = (100000 + math.Random().nextInt(900000)).toString();
    await _prefs.setString('otp_$email', otp);
    return otp;
  }

  static Future<bool> verifyOTP(String email, String inputOtp) async {
    final storedOtp = _prefs.getString('otp_$email');
    if (storedOtp == inputOtp) {
      final userJson = _prefs.getString('user_$email');
      if (userJson != null) {
        final user = AppUser.fromJson(jsonDecode(userJson));
        user.isVerified = true;
        await _prefs.setString('user_$email', jsonEncode(user.toJson()));
        await setActiveSession(user);
        return true;
      }
    }
    return false;
  }

  static void loadUserData() {
    if (currentUser == null) return;

    // Load Tasks
    final tasksJson = _prefs.getString('tasks_${currentUser!.id}');
    if (tasksJson != null) {
      final List decoded = jsonDecode(tasksJson);
      currentTasks.value = decoded.map((e) => TaskItem.fromJson(e)).toList();
    } else {
      currentTasks.value = [];
    }

    // Load Categories
    final catsJson = _prefs.getString('cats_${currentUser!.id}');
    if (catsJson != null) {
      final List decoded = jsonDecode(catsJson);
      currentCategories.value = decoded.map((e) => TaskCategory.fromJson(e)).toList();
    } else {
      final defaultCats = [
        TaskCategory(id: 'c1', name: 'Work', colorValue: Colors.blue.value),
        TaskCategory(id: 'c2', name: 'Personal', colorValue: Colors.purple.value),
        TaskCategory(id: 'c3', name: 'Health', colorValue: Colors.green.value),
      ];
      currentCategories.value = defaultCats;
      saveCategories();
    }

    // Load Journals
    final journalsJson = _prefs.getString('journals_${currentUser!.id}');
    if (journalsJson != null) {
      final List decoded = jsonDecode(journalsJson);
      currentJournals.value = decoded.map((e) => JournalEntry.fromJson(e)).toList();
    } else {
      currentJournals.value = [];
    }

    // Load Water Tracker
    final lastWaterDate = _prefs.getString('water_date_${currentUser!.id}');
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (lastWaterDate == todayStr) {
      waterIntake.value = _prefs.getInt('water_count_${currentUser!.id}') ?? 0;
    } else {
      waterIntake.value = 0;
      saveWaterIntake();
    }
  }

  static Future<void> saveTasks() async {
    if (currentUser == null) return;
    final encoded = jsonEncode(currentTasks.value.map((e) => e.toJson()).toList());
    await _prefs.setString('tasks_${currentUser!.id}', encoded);
  }

  static Future<void> saveCategories() async {
    if (currentUser == null) return;
    final encoded = jsonEncode(currentCategories.value.map((e) => e.toJson()).toList());
    await _prefs.setString('cats_${currentUser!.id}', encoded);
  }

  static Future<void> saveJournals() async {
    if (currentUser == null) return;
    final encoded = jsonEncode(currentJournals.value.map((e) => e.toJson()).toList());
    await _prefs.setString('journals_${currentUser!.id}', encoded);
  }

  static Future<void> saveWaterIntake() async {
    if (currentUser == null) return;
    await _prefs.setInt('water_count_${currentUser!.id}', waterIntake.value);
    await _prefs.setString('water_date_${currentUser!.id}', DateFormat('yyyy-MM-dd').format(DateTime.now()));
  }

  static void addTask(TaskItem task) {
    final newList = List<TaskItem>.from(currentTasks.value);
    newList.insert(0, task);
    currentTasks.value = newList;
    saveTasks();
  }

  static void updateTask(TaskItem task) {
    final newList = List<TaskItem>.from(currentTasks.value);
    final index = newList.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      newList[index] = task;
      currentTasks.value = newList;
      saveTasks();
    }
  }

  static void deleteTask(String id) {
    final newList = List<TaskItem>.from(currentTasks.value);
    newList.removeWhere((t) => t.id == id);
    currentTasks.value = newList;
    saveTasks();
  }

  static void addJournal(JournalEntry entry) {
    final newList = List<JournalEntry>.from(currentJournals.value);
    newList.insert(0, entry);
    currentJournals.value = newList;
    saveJournals();
  }

  static void incrementWater() {
    waterIntake.value++;
    saveWaterIntake();
  }
}

/* =============================================================================
   3. APP WRAPPER & THEME DEFINITIONS
============================================================================= */

class TaskBuddyMaxApp extends StatelessWidget {
  const TaskBuddyMaxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Animate.restartOnHotReload = true;

    return ValueListenableBuilder<bool>(
      valueListenable: LocalDatabase.isDarkMode,
      builder: (context, isDark, child) {
        final baseTextTheme = GoogleFonts.outfitTextTheme();
        
        return MaterialApp(
          title: 'Task Buddy Max',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF4F46E5),
            scaffoldBackgroundColor: const Color(0xFFF3F4F6),
            textTheme: baseTextTheme.apply(
              bodyColor: const Color(0xFF1F2937),
              displayColor: const Color(0xFF111827),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
              ),
            ),
          ),

          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF6366F1),
            scaffoldBackgroundColor: const Color(0xFF0B0F19),
            textTheme: baseTextTheme.apply(
              bodyColor: const Color(0xFFF9FAFB),
              displayColor: Colors.white,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: const Color(0xFF151B2B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1C2333),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
              ),
            ),
          ),
          
          home: const SplashScreen(),
        );
      },
    );
  }
}

/* =============================================================================
   4. SPLASH & ROUTING CONTROLLER
============================================================================= */

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeLogic();
  }

  void _routeLogic() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    if (LocalDatabase.currentUser != null) {
      if (LocalDatabase.currentUser!.isVerified) {
        _navigateReplace(const DashboardScreen());
      } else {
        _navigateReplace(OtpScreen(email: LocalDatabase.currentUser!.email));
      }
    } else {
      _navigateReplace(const AuthGateScreen());
    }
  }

  void _navigateReplace(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    blurRadius: 40,
                    spreadRadius: 10,
                  )
                ]
              ),
              child: Icon(
                Icons.task_alt_rounded,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
            .animate()
            .scale(duration: 800.ms, curve: Curves.easeOutBack)
            .then()
            .shimmer(duration: 1200.ms),
            
            const SizedBox(height: 32),
            
            const Text(
              'TASK BUDDY',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            )
            .animate()
            .fadeIn(delay: 400.ms, duration: 600.ms)
            .slideY(begin: 0.2, end: 0.0),
            
            const SizedBox(height: 8),
            
            const Text(
              'MAXIMUM PRODUCTIVITY',
              style: TextStyle(
                color: Colors.grey,
                letterSpacing: 3,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
            .animate()
            .fadeIn(delay: 700.ms, duration: 600.ms),
          ],
        ),
      ),
    );
  }
}

/* =============================================================================
   5. AUTHENTICATION FLOW (LOGIN & SIGNUP)
============================================================================= */

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({Key? key}) : super(key: key);
  @override State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  bool _isLogin = true;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError('Please fill in all required fields.');
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    await Future.delayed(const Duration(seconds: 1));

    if (_isLogin) {
      final user = await LocalDatabase.loginUser(email, pass);
      if (user != null) {
        if (!user.isVerified) {
          await LocalDatabase.generateOTP(user.email);
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OtpScreen(email: user.email)));
        } else {
          await LocalDatabase.setActiveSession(user);
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        }
      } else {
        _showError('Invalid email or password.');
      }
    } else {
      final success = await LocalDatabase.registerUser(name, email, pass);
      if (success) {
        await LocalDatabase.generateOTP(email);
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OtpScreen(email: email)));
      } else {
        _showError('An account with this email already exists.');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _isLogin = !_isLogin;
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isLogin ? Icons.lock_person_rounded : Icons.person_add_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                )
                .animate(target: _isLogin ? 1 : 0)
                .flipH(duration: 400.ms),
                
                const SizedBox(height: 32),
                
                Text(
                  _isLogin ? 'Welcome\nBack.' : 'Create\nAccount.',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1.1),
                )
                .animate(key: ValueKey(_isLogin))
                .fadeIn(duration: 400.ms)
                .slideX(begin: -0.1, end: 0),
                
                const SizedBox(height: 16),
                
                Text(
                  _isLogin 
                    ? 'Enter your credentials to access your workspace.' 
                    : 'Join the platform and supercharge your productivity.',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                )
                .animate(key: ValueKey('sub_$_isLogin'))
                .fadeIn(duration: 500.ms),

                const SizedBox(height: 48),

                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: _isLogin ? 0 : 80,
                  curve: Curves.easeInOut,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)),
                      ),
                    ),
                  ),
                ),

                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.alternate_email)),
                )
                .animate()
                .fadeIn(delay: 200.ms)
                .slideY(begin: 0.1, end: 0),
                
                const SizedBox(height: 16),
                
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: 300.ms)
                .slideY(begin: 0.1, end: 0),

                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isLoading 
                        ? const SizedBox(
                            height: 24, width: 24, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          )
                        : Text(
                            _isLogin ? 'Sign In' : 'Register',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                  ),
                )
                .animate()
                .fadeIn(delay: 400.ms)
                .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),

                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                    child: RichText(
                      text: TextSpan(
                        text: _isLogin ? "Don't have an account? " : "Already have an account? ",
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        children: [
                          TextSpan(
                            text: _isLogin ? 'Sign Up' : 'Sign In',
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: 500.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* =============================================================================
   6. OTP VERIFICATION SCREEN
============================================================================= */

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpCtrl = TextEditingController();
  int _timerSeconds = 30;
  Timer? _countdownTimer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _showDevHint();
  }

  void _showDevHint() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final prefs = await SharedPreferences.getInstance();
    final otp = prefs.getString('otp_${widget.email}');
    if (mounted && otp != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Developer Hint: OTP is $otp'),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _timerSeconds = 30);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  Future<void> _resendOtp() async {
    HapticFeedback.lightImpact();
    final newOtp = await LocalDatabase.generateOTP(widget.email);
    _startTimer();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('New OTP sent: $newOtp'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid 6-digit code.')));
      return;
    }

    setState(() => _isVerifying = true);
    HapticFeedback.mediumImpact();

    await Future.delayed(const Duration(seconds: 1)); 

    final success = await LocalDatabase.verifyOTP(widget.email, code);

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
    } else {
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid verification code.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthGateScreen())),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: const Icon(Icons.mark_email_read_rounded, size: 48, color: Colors.green),
              )
              .animate()
              .scale(curve: Curves.easeOutBack, duration: 600.ms),
              
              const SizedBox(height: 32),
              
              const Text('Check your\nemail.', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1.1))
              .animate()
              .fadeIn(delay: 200.ms)
              .slideX(begin: -0.1),
              
              const SizedBox(height: 16),
              
              Text('We sent a 6-digit verification code to:\n${widget.email}', style: const TextStyle(color: Colors.grey, fontSize: 16, height: 1.5))
              .animate()
              .fadeIn(delay: 300.ms),

              const SizedBox(height: 48),

              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 16),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: "",
                  filled: true,
                  fillColor: Theme.of(context).cardTheme.color,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              )
              .animate()
              .fadeIn(delay: 400.ms)
              .slideY(begin: 0.2),

              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: _isVerifying ? null : _verify,
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                  child: _isVerifying
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text('Verify Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              )
              .animate()
              .fadeIn(delay: 500.ms),

              const SizedBox(height: 24),

              Center(
                child: TextButton(
                  onPressed: _timerSeconds == 0 && !_isVerifying ? _resendOtp : null,
                  child: Text(
                    _timerSeconds > 0 ? 'Resend code in $_timerSeconds seconds' : 'Resend Verification Code',
                    style: TextStyle(
                      color: _timerSeconds > 0 ? Colors.grey : Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}

/* =============================================================================
   7. MAIN DASHBOARD SCREEN (Now with Quote & Hydration Engine)
============================================================================= */

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _currentFilter = 'All'; 
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<String> dailyQuotes = [
    "Discipline equals freedom.",
    "Do the hard work, especially when you don't feel like it.",
    "Amateurs sit and wait for inspiration, the rest of us just get up and go to work.",
    "Focus on being productive instead of busy.",
    "Great things are not done by impulse, but by a series of small things brought together."
  ];

  late String todayQuote;

  @override
  void initState() {
    super.initState();
    todayQuote = dailyQuotes[DateTime.now().day % dailyQuotes.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const CustomAppDrawer(),
      
      body: ValueListenableBuilder<List<TaskItem>>(
        valueListenable: LocalDatabase.currentTasks,
        builder: (context, tasks, child) {
          
          int doneCount = tasks.where((t) => t.isCompleted).length;
          double progress = tasks.isEmpty ? 0 : doneCount / tasks.length;
          
          List<TaskItem> filteredList = tasks.where((t) {
            if (_currentFilter == 'Pending') return !t.isCompleted;
            if (_currentFilter == 'Done') return t.isCompleted;
            if (_currentFilter == 'Priority') return t.priority == 'High' && !t.isCompleted;
            return true;
          }).toList();

          filteredList.sort((a, b) {
            if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
            return a.deadline.compareTo(b.deadline);
          });

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 140,
                pinned: true,
                floating: false,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                leading: IconButton(
                  icon: const Icon(Icons.sort_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.timer_outlined),
                    tooltip: 'Focus Engine',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PomodoroScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bar_chart_rounded),
                    tooltip: 'Analytics',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen())),
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                  title: Text(
                    'Hey, ${LocalDatabase.currentUser?.name.split(' ')[0] ?? 'User'}',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.displayLarge?.color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.format_quote_rounded, color: Colors.orangeAccent, size: 28),
                        const SizedBox(width: 12),
                        Expanded(child: Text('"$todayQuote"', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: -0.1),
              ),

              SliverToBoxAdapter(
                child: _buildDashboardBento(context, progress, tasks.length - doneCount)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1),
              ),

              SliverToBoxAdapter(
                child: _buildFilterSection()
                    .animate()
                    .fadeIn(delay: 200.ms),
              ),

              if (filteredList.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_rounded, size: 80, color: Colors.grey.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          'No tasks in this view.',
                          style: TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 400.ms),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return TaskListTile(task: filteredList[index], index: index);
                      },
                      childCount: filteredList.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskEditorScreen())),
        elevation: 4,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('New Objective', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      )
      .animate()
      .scale(delay: 600.ms, curve: Curves.easeOutBack, duration: 400.ms)
      .then().shimmer(duration: 1.seconds),
    );
  }

  Widget _buildDashboardBento(BuildContext context, double progress, int pendingCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily Completion', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text('${(progress * 100).toInt()}%', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text('$pendingCount pending tasks', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(
                  height: 90,
                  width: 90,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                        strokeCap: StrokeCap.round,
                      ),
                      Center(
                        child: Icon(
                          progress >= 1.0 && pendingCount == 0 ? Icons.emoji_events_rounded : Icons.trending_up_rounded,
                          color: Colors.white,
                          size: 36,
                        )
                        .animate(target: progress >= 1.0 ? 1 : 0)
                        .scale(curve: Curves.elasticOut),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Water Tracker Bento Module
          ValueListenableBuilder<int>(
            valueListenable: LocalDatabase.waterIntake,
            builder: (context, waterCount, _) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.2), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.lightBlueAccent.withOpacity(0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.water_drop_rounded, color: Colors.lightBlueAccent),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hydration Engine', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('$waterCount / 8 Glasses', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_rounded, color: Colors.lightBlueAccent, size: 32),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        LocalDatabase.incrementWater();
                      },
                    ).animate(key: ValueKey(waterCount)).scale(duration: 200.ms, curve: Curves.easeOutBack),
                  ],
                ),
              );
            }
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    final filters = ['All', 'Pending', 'Priority', 'Done'];
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: filters.map((filterName) {
            final isSelected = _currentFilter == filterName;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _currentFilter = filterName);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.2)),
                  ),
                  child: Text(
                    filterName,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/* =============================================================================
   8. TASK TILE WIDGET
============================================================================= */

class TaskListTile extends StatelessWidget {
  final TaskItem task;
  final int index;
  
  const TaskListTile({Key? key, required this.task, required this.index}) : super(key: key);

  Color _getPriorityColor() {
    switch(task.priority) {
      case 'High': return Colors.redAccent;
      case 'Medium': return Colors.orangeAccent;
      case 'Low': return Colors.greenAccent;
      default: return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = LocalDatabase.currentCategories.value;
    TaskCategory? cat;
    try {
      cat = categories.firstWhere((c) => c.id == task.categoryId);
    } catch (_) {
      cat = TaskCategory(id: 'err', name: 'General', colorValue: Colors.grey.value);
    }

    final isOverdue = !task.isCompleted && task.deadline.isBefore(DateTime.now());

    Widget tileContent = Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Material(
        color: task.isCompleted ? Theme.of(context).cardTheme.color!.withOpacity(0.6) : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskEditorScreen(task: task))),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    task.isCompleted = !task.isCompleted;
                    LocalDatabase.updateTask(task);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    height: 32, width: 32,
                    decoration: BoxDecoration(
                      color: task.isCompleted ? Colors.greenAccent : Colors.transparent,
                      border: Border.all(color: task.isCompleted ? Colors.greenAccent : Colors.grey.withOpacity(0.5), width: 2),
                      shape: BoxShape.circle,
                    ),
                    child: task.isCompleted ? const Icon(Icons.check_rounded, size: 20, color: Colors.black) : null,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? Colors.grey : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(cat.colorValue).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(cat.name, style: TextStyle(color: Color(cat.colorValue), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          
                          Icon(Icons.access_time_rounded, size: 14, color: isOverdue ? Colors.redAccent : Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM dd, hh:mm a').format(task.deadline),
                            style: TextStyle(color: isOverdue ? Colors.redAccent : Colors.grey, fontSize: 12, fontWeight: isOverdue ? FontWeight.bold : FontWeight.w500),
                          ),
                          
                          if (task.focusMinutesSpent > 0) ...[
                            const Spacer(),
                            const Icon(Icons.local_fire_department_rounded, size: 14, color: Colors.orangeAccent),
                            const SizedBox(width: 2),
                            Text('${task.focusMinutesSpent}m', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold))
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                
                if (!task.isCompleted)
                  Container(
                    margin: const EdgeInsets.only(left: 12),
                    height: 12, width: 12,
                    decoration: BoxDecoration(color: _getPriorityColor(), shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (task.isCompleted) {
      tileContent = tileContent.animate(onPlay: (controller) => controller.repeat(reverse: true)).shimmer(duration: 3.seconds, color: Colors.white24);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(task.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(24)),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 32),
        ),
        onDismissed: (_) {
          HapticFeedback.mediumImpact();
          LocalDatabase.deleteTask(task.id);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task removed'), duration: Duration(seconds: 2)));
        },
        child: tileContent,
      )
      .animate()
      .fadeIn(delay: Duration(milliseconds: 50 * index), duration: 400.ms)
      .slideX(begin: 0.05, curve: Curves.easeOutCubic),
    );
  }
}

/* =============================================================================
   9. TASK EDITOR & CREATOR
============================================================================= */

class TaskEditorScreen extends StatefulWidget {
  final TaskItem? task;
  const TaskEditorScreen({Key? key, this.task}) : super(key: key);
  @override State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late String _priority;
  late String _categoryId;

  @override
  void initState() {
    super.initState();
    final cats = LocalDatabase.currentCategories.value;
    final defaultCatId = cats.isNotEmpty ? cats.first.id : '';

    if (widget.task != null) {
      _titleCtrl.text = widget.task!.title;
      _descCtrl.text = widget.task!.description;
      _selectedDate = widget.task!.deadline;
      _selectedTime = TimeOfDay.fromDateTime(widget.task!.deadline);
      _priority = widget.task!.priority;
      
      if (cats.any((c) => c.id == widget.task!.categoryId)) {
        _categoryId = widget.task!.categoryId;
      } else {
        _categoryId = defaultCatId;
      }
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now().replacing(hour: TimeOfDay.now().hour + 1);
      _priority = 'Medium';
      _categoryId = defaultCatId;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task title cannot be empty')));
      return;
    }

    final deadline = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);

    final task = TaskItem(
      id: widget.task?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      deadline: deadline,
      categoryId: _categoryId,
      priority: _priority,
      isCompleted: widget.task?.isCompleted ?? false,
      focusMinutesSpent: widget.task?.focusMinutesSpent ?? 0,
    );

    if (widget.task == null) {
      LocalDatabase.addTask(task);
    } else {
      LocalDatabase.updateTask(task);
    }

    Navigator.pop(context);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: _selectedTime);
    if (time == null) return;

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.task == null ? 'New Objective' : 'Edit Objective', style: const TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(hintText: 'What needs to be done?', border: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.zero),
            ).animate().fadeIn().slideX(begin: -0.05),
            
            const SizedBox(height: 24),
            
            TextField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Add details, context, or links...',
                filled: true,
                fillColor: Theme.of(context).cardTheme.color,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
            ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),

            const SizedBox(height: 32),
            const Text('Attributes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDateTime,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.calendar_month_rounded, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 12),
                          const Text('Deadline', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, hh:mm a').format(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute)),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).scale(),

                const SizedBox(width: 16),

                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.folder_open_rounded, color: Colors.orangeAccent),
                        const SizedBox(height: 12),
                        const Text('Category', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        DropdownButtonHideUnderline(
                          child: ValueListenableBuilder<List<TaskCategory>>(
                            valueListenable: LocalDatabase.currentCategories,
                            builder: (context, cats, _) {
                              return DropdownButton<String>(
                                value: _categoryId,
                                isDense: true,
                                isExpanded: true,
                                items: cats.map((c) => DropdownMenuItem(
                                  value: c.id, 
                                  child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                )).toList(),
                                onChanged: (v) { if (v != null) setState(() => _categoryId = v); },
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: 300.ms).scale(),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_rounded, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  const Text('Priority Level', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _priority,
                      isDense: true,
                      isExpanded: true,
                      items: ['Low', 'Medium', 'High'].map((p) => DropdownMenuItem(
                        value: p, 
                        child: Text('$p Priority', style: const TextStyle(fontWeight: FontWeight.bold)),
                      )).toList(),
                      onChanged: (v) { if (v != null) setState(() => _priority = v); },
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).scale(),

            const SizedBox(height: 80),
          ],
        ),
      ),
      
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - 48,
        height: 60,
        child: FloatingActionButton.extended(
          onPressed: _save,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          label: const Text('Save Objective', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          icon: const Icon(Icons.save_rounded),
        ),
      ).animate().slideY(begin: 1.0, curve: Curves.easeOutQuart, duration: 600.ms),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/* =============================================================================
   10. POMODORO / FOCUS ENGINE
============================================================================= */

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({Key? key}) : super(key: key);
  @override State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  TaskItem? _selectedTask;
  
  static const int WORK_MINUTES = 25;
  static const int BREAK_MINUTES = 5;
  
  int _secondsRemaining = WORK_MINUTES * 60;
  bool _isRunning = false;
  bool _isWorkPhase = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final pending = LocalDatabase.currentTasks.value.where((t) => !t.isCompleted).toList();
    if (pending.isNotEmpty) {
      _selectedTask = pending.first;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    HapticFeedback.mediumImpact();
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining > 0) {
          setState(() => _secondsRemaining--);
        } else {
          _handlePhaseComplete();
        }
      });
    }
  }

  void _handlePhaseComplete() {
    _timer?.cancel();
    SystemSound.play(SystemSoundType.alert);
    
    setState(() {
      _isRunning = false;
      
      if (_isWorkPhase && _selectedTask != null) {
        _selectedTask!.focusMinutesSpent += WORK_MINUTES;
        LocalDatabase.updateTask(_selectedTask!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('+${WORK_MINUTES}m added to ${_selectedTask!.title}')),
        );
      }
      
      _isWorkPhase = !_isWorkPhase;
      _secondsRemaining = (_isWorkPhase ? WORK_MINUTES : BREAK_MINUTES) * 60;
    });
  }

  void _resetTimer() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _secondsRemaining = (_isWorkPhase ? WORK_MINUTES : BREAK_MINUTES) * 60;
    });
  }

  void _skipPhase() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isWorkPhase = !_isWorkPhase;
      _secondsRemaining = (_isWorkPhase ? WORK_MINUTES : BREAK_MINUTES) * 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    int minutes = _secondsRemaining ~/ 60;
    int seconds = _secondsRemaining % 60;
    double progress = 1.0 - (_secondsRemaining / ((_isWorkPhase ? WORK_MINUTES : BREAK_MINUTES) * 60));

    final pendingTasks = LocalDatabase.currentTasks.value.where((t) => !t.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Focus Engine', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TaskItem>(
                    value: _selectedTask,
                    isExpanded: true,
                    hint: const Text('Select task to focus on...'),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: pendingTasks.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: _isRunning ? null : (v) {
                      if (v != null) setState(() => _selectedTask = v);
                    },
                  ),
                ),
              ).animate().fadeIn().slideY(begin: -0.2),

              const Spacer(),

              SizedBox(
                height: 320, width: 320,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(value: 1.0, strokeWidth: 20, color: Theme.of(context).cardTheme.color),
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 20,
                      backgroundColor: Colors.transparent,
                      color: _isWorkPhase ? Theme.of(context).colorScheme.primary : Colors.greenAccent,
                      strokeCap: StrokeCap.round,
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: (_isWorkPhase ? Theme.of(context).colorScheme.primary : Colors.greenAccent).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _isWorkPhase ? 'FOCUS PHASE' : 'BREAK PHASE',
                              style: TextStyle(
                                color: _isWorkPhase ? Theme.of(context).colorScheme.primary : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w900, height: 1.0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),

              const Spacer(),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32, icon: const Icon(Icons.refresh_rounded), color: Colors.grey,
                    onPressed: _isRunning ? null : _resetTimer,
                  ).animate().fadeIn(delay: 200.ms),
                  
                  const SizedBox(width: 32),
                  
                  FloatingActionButton.large(
                    onPressed: _toggleTimer,
                    elevation: _isRunning ? 0 : 8,
                    backgroundColor: _isRunning ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                    child: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 48, color: Colors.white),
                  ).animate().scale(delay: 300.ms, curve: Curves.elasticOut),
                  
                  const SizedBox(width: 32),
                  
                  IconButton(
                    iconSize: 32, icon: const Icon(Icons.skip_next_rounded), color: Colors.grey,
                    onPressed: _skipPhase,
                  ).animate().fadeIn(delay: 400.ms),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/* =============================================================================
   11. ADVANCED ANALYTICS (DEEP WORK & ALGORITHMIC STREAKS)
============================================================================= */

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  int _calculateCurrentStreak(List<TaskItem> tasks) {
    if (tasks.isEmpty) return 0;
    
    final completedDates = tasks
        .where((t) => t.isCompleted)
        .map((t) => DateTime(t.deadline.year, t.deadline.month, t.deadline.day))
        .toSet()
        .toList();
        
    completedDates.sort((a, b) => b.compareTo(a)); 

    if (completedDates.isEmpty) return 0;

    int streak = 0;
    DateTime currentDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    if (completedDates.first.isBefore(currentDate.subtract(const Duration(days: 1)))) {
      return 0; 
    }

    DateTime expectedDate = completedDates.first;
    for (var date in completedDates) {
      if (date.isAtSameMomentAs(expectedDate)) {
        streak++;
        expectedDate = expectedDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deep Insights', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ValueListenableBuilder<List<TaskItem>>(
        valueListenable: LocalDatabase.currentTasks,
        builder: (context, tasks, _) {
          final int total = tasks.length;
          final int done = tasks.where((t) => t.isCompleted).length;
          final int focusMinutes = tasks.fold(0, (sum, t) => sum + t.focusMinutesSpent);
          final int currentStreak = _calculateCurrentStreak(tasks);
          
          final double completionRate = total == 0 ? 0.0 : done / total;
          
          int highPriorityDone = tasks.where((t) => t.isCompleted && t.priority == 'High').length;
          int medPriorityDone = tasks.where((t) => t.isCompleted && t.priority == 'Medium').length;
          int lowPriorityDone = tasks.where((t) => t.isCompleted && t.priority == 'Low').length;

          return ListView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            children: [
              Row(
                children: [
                  Expanded(child: _buildMetricCard(context, 'Current Streak', '$currentStreak Days', Colors.deepPurpleAccent, Icons.local_fire_department_rounded)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard(context, 'Deep Focus', '${(focusMinutes / 60).toStringAsFixed(1)}h', Colors.orangeAccent, Icons.headphones_rounded)),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  children: [
                    const Text('Task Velocity', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size(200, 200),
                            painter: _DonutChartPainter(
                              high: highPriorityDone.toDouble(),
                              medium: medPriorityDone.toDouble(),
                              low: lowPriorityDone.toDouble(),
                              empty: (total - done).toDouble(),
                            ),
                          ).animate().scale(curve: Curves.easeOutBack, duration: 800.ms),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${(completionRate * 100).toInt()}%', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                              const Text('Completed', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ).animate().fadeIn(delay: 400.ms),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildChartLegend('High', Colors.redAccent),
                        _buildChartLegend('Medium', Colors.orangeAccent),
                        _buildChartLegend('Low', Colors.greenAccent),
                      ],
                    ).animate().fadeIn(delay: 600.ms),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

              const SizedBox(height: 32),

              const Text('Activity Matrix (Last 28 Days)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7, crossAxisSpacing: 8, mainAxisSpacing: 8,
                      ),
                      itemCount: 28,
                      itemBuilder: (context, index) {
                        final intensity = math.Random().nextDouble();
                        Color boxColor;
                        if (intensity < 0.3) {
                          boxColor = Theme.of(context).cardTheme.color == Colors.white ? Colors.grey.shade200 : Colors.white10;
                        } else if (intensity < 0.6) {
                          boxColor = Theme.of(context).colorScheme.primary.withOpacity(0.4);
                        } else if (intensity < 0.8) {
                          boxColor = Theme.of(context).colorScheme.primary.withOpacity(0.7);
                        } else {
                          boxColor = Theme.of(context).colorScheme.primary;
                        }

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(8)),
                        ).animate().scale(delay: Duration(milliseconds: 20 * index), curve: Curves.easeOutBack);
                      },
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
              
              const SizedBox(height: 60),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChartLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String val, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 24),
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900, height: 1.0)),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final double high;
  final double medium;
  final double low;
  final double empty;

  _DonutChartPainter({required this.high, required this.medium, required this.low, required this.empty});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = high + medium + low + empty;
    if (total == 0) return;

    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const double strokeWidth = 20.0;
    
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;

    void drawSegment(double value, Color color) {
      if (value == 0) return;
      final sweepAngle = (value / total) * 2 * math.pi;
      paint.color = color;
      canvas.drawArc(rect, startAngle, sweepAngle - 0.05, false, paint);
      startAngle += sweepAngle;
    }

    drawSegment(high, Colors.redAccent);
    drawSegment(medium, Colors.orangeAccent);
    drawSegment(low, Colors.greenAccent);
    drawSegment(empty, Colors.grey.withOpacity(0.2));
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return high != oldDelegate.high || medium != oldDelegate.medium || low != oldDelegate.low || empty != oldDelegate.empty;
  }
}

/* =============================================================================
   12. CATEGORY MANAGER & ENHANCED DRAWER NAVIGATION
============================================================================= */

class CategoryManagerScreen extends StatefulWidget {
  const CategoryManagerScreen({Key? key}) : super(key: key);
  @override State<CategoryManagerScreen> createState() => _CategoryManagerScreenState();
}

class _CategoryManagerScreenState extends State<CategoryManagerScreen> {
  void _addCategory() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter category name...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isEmpty) return;
              final randColor = Colors.primaries[math.Random().nextInt(Colors.primaries.length)].value;
              final newCat = TaskCategory(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: ctrl.text.trim(),
                colorValue: randColor,
              );
              
              final list = List<TaskCategory>.from(LocalDatabase.currentCategories.value);
              list.add(newCat);
              LocalDatabase.currentCategories.value = list;
              LocalDatabase.saveCategories();
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ValueListenableBuilder<List<TaskCategory>>(
        valueListenable: LocalDatabase.currentCategories,
        builder: (context, cats, _) {
          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: cats.length,
            itemBuilder: (context, index) {
              final cat = cats[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(cat.colorValue),
                    child: Text(cat.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () {
                      final list = List<TaskCategory>.from(LocalDatabase.currentCategories.value);
                      list.removeAt(index);
                      LocalDatabase.currentCategories.value = list;
                      LocalDatabase.saveCategories();
                    },
                  ),
                ),
              ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX();
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addCategory,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CustomAppDrawer extends StatelessWidget {
  const CustomAppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Colors.deepPurpleAccent],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              )
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.indigo,
                        child: Icon(Icons.api_rounded, size: 40, color: Colors.white),
                      ),
                    ).animate().scaleXY(curve: Curves.easeOutBack, duration: 600.ms),
                    
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumUpgradeScreen()));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amberAccent.withOpacity(0.5))),
                        child: const Text('UPGRADE TO PRO', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  LocalDatabase.currentUser?.name ?? 'Guest User',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ).animate().slideX(begin: -0.1).fadeIn(),
                const SizedBox(height: 4),
                Text(
                  LocalDatabase.currentUser?.email ?? 'No email associated',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ).animate().slideX(begin: -0.1, delay: 100.ms).fadeIn(),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerTile(
                  context, 
                  icon: Icons.dashboard_rounded, 
                  title: 'Dashboard', 
                  onTap: () => Navigator.pop(context),
                  delay: 100,
                ),
                _buildDrawerTile(
                  context, 
                  icon: Icons.workspace_premium_rounded, 
                  title: 'Achievements', 
                  color: Colors.amber,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementBoardScreen()));
                  },
                  delay: 150,
                ),
                _buildDrawerTile(
                  context, icon: Icons.videogame_asset_rounded, title: 'Focus Arcade', color: Colors.greenAccent,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const FocusArcadeScreen()));
                  }, delay: 175,
                ),
                _buildDrawerTile(
                  context, icon: Icons.book_rounded, title: 'Reflections Journal', color: Colors.purpleAccent,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalScreen()));
                  }, delay: 185,
                ),
                _buildDrawerTile(
                  context, 
                  icon: Icons.folder_special_rounded, 
                  title: 'Manage Categories', 
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen()));
                  },
                  delay: 200,
                ),
                _buildDrawerTile(
                  context, 
                  icon: Icons.settings_system_daydream_rounded, 
                  title: 'System Config', 
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemSettingsScreen()));
                  },
                  delay: 250,
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Divider(height: 1),
                ),
                
                ValueListenableBuilder<bool>(
                  valueListenable: LocalDatabase.isDarkMode,
                  builder: (context, isDark, _) {
                    return _buildDrawerTile(
                      context,
                      icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      title: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        LocalDatabase.toggleTheme();
                      },
                      delay: 300,
                    );
                  }
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              tileColor: Colors.redAccent.withOpacity(0.1),
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Terminate Session', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                HapticFeedback.heavyImpact();
                await LocalDatabase.logout();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthGateScreen()),
                  (route) => false,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDrawerTile(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap, required int delay, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: color ?? Theme.of(context).iconTheme.color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        onTap: onTap,
        hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ).animate().fadeIn(delay: Duration(milliseconds: delay)).slideX(begin: -0.1),
    );
  }
}

/* =============================================================================
   12b. NEW FEATURE: REFLECTIONS JOURNAL
============================================================================= */

class JournalScreen extends StatefulWidget {
  const JournalScreen({Key? key}) : super(key: key);
  @override State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _textController = TextEditingController();

  void _addJournal() {
    if (_textController.text.trim().isEmpty) return;
    HapticFeedback.mediumImpact();
    final newEntry = JournalEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: _textController.text.trim(),
      date: DateTime.now(),
    );
    LocalDatabase.addJournal(newEntry);
    _textController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daily Reflections', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'What is on your mind today?',
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.purpleAccent),
                    onPressed: _addJournal,
                  ),
                ],
              ),
            ).animate().slideY(begin: -0.2).fadeIn(),
          ),
          
          Expanded(
            child: ValueListenableBuilder<List<JournalEntry>>(
              valueListenable: LocalDatabase.currentJournals,
              builder: (context, journals, _) {
                if (journals.isEmpty) {
                  return const Center(child: Text('Your journal is empty.', style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: journals.length,
                  itemBuilder: (context, index) {
                    final j = journals[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.purpleAccent.withOpacity(0.1)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('EEEE, MMM dd • hh:mm a').format(j.date), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Text(j.content, style: const TextStyle(fontSize: 16, height: 1.4)),
                        ],
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX();
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

/* =============================================================================
   13. GAMIFICATION & ACHIEVEMENT ENGINE
============================================================================= */

class AchievementBoardScreen extends StatelessWidget {
  const AchievementBoardScreen({Key? key}) : super(key: key);

  List<Map<String, dynamic>> _calculateAchievements(List<TaskItem> tasks) {
    final int doneCount = tasks.where((t) => t.isCompleted).length;
    final int focusTime = tasks.fold(0, (sum, t) => sum + t.focusMinutesSpent);
    final bool hasHighPriorityDone = tasks.any((t) => t.isCompleted && t.priority == 'High');

    return [
      {
        'title': 'First Blood', 'desc': 'Complete your first task.',
        'icon': Icons.star_rounded, 'color': Colors.amber,
        'unlocked': doneCount >= 1, 'progress': doneCount >= 1 ? 1.0 : 0.0,
      },
      {
        'title': 'Task Master', 'desc': 'Complete 10 tasks total.',
        'icon': Icons.military_tech_rounded, 'color': Colors.indigoAccent,
        'unlocked': doneCount >= 10, 'progress': math.min(1.0, doneCount / 10),
      },
      {
        'title': 'Deep Focus', 'desc': 'Log 120 minutes of focus time.',
        'icon': Icons.local_fire_department_rounded, 'color': Colors.deepOrangeAccent,
        'unlocked': focusTime >= 120, 'progress': math.min(1.0, focusTime / 120),
      },
      {
        'title': 'Dragon Slayer', 'desc': 'Complete a High Priority task.',
        'icon': Icons.shield_rounded, 'color': Colors.redAccent,
        'unlocked': hasHighPriorityDone, 'progress': hasHighPriorityDone ? 1.0 : 0.0,
      },
      {
        'title': 'Zen Master', 'desc': 'Log 500 minutes of focus time.',
        'icon': Icons.self_improvement_rounded, 'color': Colors.tealAccent,
        'unlocked': focusTime >= 500, 'progress': math.min(1.0, focusTime / 500),
      },
      {
        'title': 'Unstoppable', 'desc': 'Complete 50 tasks total.',
        'icon': Icons.diamond_rounded, 'color': Colors.cyanAccent,
        'unlocked': doneCount >= 50, 'progress': math.min(1.0, doneCount / 50),
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Achievement Board', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)), elevation: 0, backgroundColor: Colors.transparent),
      body: ValueListenableBuilder<List<TaskItem>>(
        valueListenable: LocalDatabase.currentTasks,
        builder: (context, tasks, _) {
          final achievements = _calculateAchievements(tasks);
          final unlockedCount = achievements.where((a) => a['unlocked'] as bool).length;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Theme.of(context).colorScheme.primary, Colors.purpleAccent],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), blurRadius: 30, offset: const Offset(0, 15))],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.workspace_premium_rounded, size: 80, color: Colors.white)
                                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                                .scaleXY(end: 1.1, duration: 2.seconds)
                                .shimmer(duration: 2.seconds, color: Colors.white54),
                            const SizedBox(height: 16),
                            const Text('YOUR RANKING', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 4)),
                            const SizedBox(height: 8),
                            Text(
                              unlockedCount == achievements.length ? 'GOD TIER' : 'ELITE OPERATOR',
                              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 24),
                            LinearProgressIndicator(
                              value: unlockedCount / achievements.length,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 12, borderRadius: BorderRadius.circular(12),
                            ),
                            const SizedBox(height: 8),
                            Text('$unlockedCount / ${achievements.length} Unlocked', style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ).animate().fadeIn(duration: 800.ms).slideY(begin: -0.2, curve: Curves.easeOutCirc),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final badge = achievements[index];
                      final isUnlocked = badge['unlocked'] as bool;
                      final progress = badge['progress'] as double;

                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isUnlocked ? (badge['color'] as Color).withOpacity(0.5) : Colors.grey.withOpacity(0.1),
                            width: 2,
                          ),
                          boxShadow: isUnlocked ? [BoxShadow(color: (badge['color'] as Color).withOpacity(0.2), blurRadius: 20, spreadRadius: -5)] : [],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    height: 70, width: 70,
                                    child: CircularProgressIndicator(
                                      value: progress, strokeWidth: 6,
                                      backgroundColor: Colors.grey.withOpacity(0.1),
                                      valueColor: AlwaysStoppedAnimation<Color>(isUnlocked ? badge['color'] as Color : Colors.grey),
                                      strokeCap: StrokeCap.round,
                                    ),
                                  ),
                                  Icon(badge['icon'] as IconData, size: 36, color: isUnlocked ? badge['color'] as Color : Colors.grey.withOpacity(0.3))
                                  .animate(target: isUnlocked ? 1 : 0)
                                  .scaleXY(end: 1.2, duration: 400.ms, curve: Curves.easeOutBack),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                badge['title'] as String, textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isUnlocked ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Text(badge['desc'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3)),
                            ],
                          ),
                        ),
                      ).animate()
                       .fadeIn(delay: Duration(milliseconds: 100 * index), duration: 600.ms)
                       .scaleXY(begin: 0.8, end: 1.0, curve: Curves.easeOutBack);
                    },
                    childCount: achievements.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          );
        },
      ),
    );
  }
}

/* =============================================================================
   14. SYSTEM SETTINGS & SECURE CLOUD SYNC SIMULATOR
============================================================================= */

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({Key? key}) : super(key: key);
  @override State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  bool _syncing = false;
  List<String> _syncLogs = [];
  final ScrollController _logScrollController = ScrollController();

  Future<void> _runCloudSyncSimulation() async {
    setState(() {
      _syncing = true;
      _syncLogs = ['[SYSTEM] Initializing Secure WebSocket Connection...'];
    });

    final logsToGenerate = [
      '[AUTH] Validating active session token via AES-256...',
      '[AUTH] Token verified. User: ${LocalDatabase.currentUser?.id}',
      '[DATABASE] Compressing local SQLite nodes...',
      '[DATABASE] Payload size: ${(LocalDatabase.currentTasks.value.length + LocalDatabase.currentJournals.value.length) * 1.4} KB',
      '[NETWORK] Establishing TLS 1.3 Handshake with ap-south-1...',
      '[NETWORK] Uplink secured. Transmitting encrypted chunks...',
      '[SYNC] Resolving entity collisions...',
      '[SYNC] No conflicts detected in Category logic.',
      '[DATABASE] Updating local checksums...',
      '[SYSTEM] Sync process completed with exit code 0.'
    ];

    for (String log in logsToGenerate) {
      await Future.delayed(Duration(milliseconds: 400 + math.Random().nextInt(600)));
      if (!mounted) return;
      setState(() { _syncLogs.add(log); });
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent + 50,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
        );
      }
      HapticFeedback.lightImpact();
    }

    setState(() => _syncing = false);
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Configuration', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 2),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    child: Icon(Icons.admin_panel_settings_rounded, size: 40, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(LocalDatabase.currentUser?.name ?? 'Admin', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(LocalDatabase.currentUser?.email ?? 'sysadmin@local', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                          child: const Text('Verified Origin', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ).animate().fadeIn().slideY(begin: -0.1),

            const SizedBox(height: 40),
            const Text('Database Synchronization', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black87, borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 10))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('SERVER TERMINAL', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 2)),
                      if (_syncing) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2))
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 200, width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                    child: ListView.builder(
                      controller: _logScrollController,
                      itemCount: _syncLogs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('> ${_syncLogs[index]}', style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12))
                          .animate().fadeIn(duration: 200.ms),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _runCloudSyncSimulation,
                      icon: const Icon(Icons.cloud_sync_rounded),
                      label: Text(_syncing ? 'SYNCING DATA...' : 'FORCE MANUAL SYNC'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.indigoAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  )
                ],
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
            
            const SizedBox(height: 40),
            
            const Text('Danger Zone', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.redAccent)),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 2)),
              tileColor: Colors.redAccent.withOpacity(0.05),
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text('Wipe All Local Data', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text('This action cannot be undone.', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                LocalDatabase.currentTasks.value = [];
                LocalDatabase.currentJournals.value = [];
                LocalDatabase.saveTasks();
                LocalDatabase.saveJournals();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All local data wiped.')));
              },
            ).animate().fadeIn(delay: 400.ms)
          ],
        ),
      ),
    );
  }
}

/* =============================================================================
   15. FOCUS ARCADE (MINI-GAMES FOR BREAKS) - NOW WITH NEURO MATH
============================================================================= */

class FocusArcadeScreen extends StatelessWidget {
  const FocusArcadeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Arcade', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        children: [
          const Text('Take a productive break.', style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          
          _buildGameCard(
            context,
            title: 'Reaction Strike',
            desc: 'Test your reflexes and wake up your brain. Tap the target as fast as possible.',
            icon: Icons.bolt_rounded,
            color: Colors.orangeAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReactionGameScreen())),
          ),
          const SizedBox(height: 24),
          _buildGameCard(
            context,
            title: 'Neuro-Math Sprint',
            desc: 'Fire up your prefrontal cortex with rapid calculations before deep work.',
            icon: Icons.calculate_rounded,
            color: Colors.pinkAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MathSprintScreen())),
          ),
          const SizedBox(height: 24),
          _buildGameCard(
            context,
            title: 'Zen Breather',
            desc: 'Lower your heart rate before deep work. Synchronize your breathing.',
            icon: Icons.air_rounded,
            color: Colors.cyanAccent,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ZenBreatherScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard(BuildContext context, {required String title, required String desc, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(radius: 32, backgroundColor: color.withOpacity(0.2), child: Icon(icon, size: 32, color: color)),
            const SizedBox(height: 24),
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(desc, style: const TextStyle(color: Colors.grey, height: 1.5)),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('PLAY NOW', style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: color, size: 16),
              ],
            )
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1);
  }
}

// Mini Game 1: Reaction Strike
class ReactionGameScreen extends StatefulWidget {
  const ReactionGameScreen({Key? key}) : super(key: key);
  @override State<ReactionGameScreen> createState() => _ReactionGameScreenState();
}

class _ReactionGameScreenState extends State<ReactionGameScreen> {
  bool _isPlaying = false;
  bool _targetVisible = false;
  DateTime? _showTime;
  int _score = 0;
  String _message = 'Tap Start to Begin';
  Timer? _gameTimer;

  void _startGame() {
    setState(() { _isPlaying = true; _score = 0; _message = 'Wait for it...'; _targetVisible = false; });
    _queueTarget();
  }

  void _queueTarget() {
    final delay = Duration(milliseconds: 1000 + math.Random().nextInt(3000));
    _gameTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() { _targetVisible = true; _showTime = DateTime.now(); _message = 'TAP!'; });
      HapticFeedback.heavyImpact();
    });
  }

  void _targetTapped() {
    if (!_targetVisible) {
      _gameTimer?.cancel();
      setState(() { _isPlaying = false; _message = 'Too early! You lose.'; _targetVisible = false; });
      HapticFeedback.vibrate();
      return;
    }
    
    final reactionTime = DateTime.now().difference(_showTime!).inMilliseconds;
    setState(() {
      _score++;
      _targetVisible = false;
      _message = '${reactionTime}ms! Keep going!';
    });
    HapticFeedback.lightImpact();
    
    if (_score < 5) {
      _queueTarget();
    } else {
      setState(() { _isPlaying = false; _message = 'You survived 5 rounds! Great reflexes.'; });
    }
  }

  @override
  void dispose() { _gameTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reaction Strike')),
      body: GestureDetector(
        onTap: _isPlaying ? _targetTapped : null,
        child: Container(
          color: _targetVisible ? Colors.orangeAccent.withOpacity(0.2) : Colors.transparent,
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_message, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              Text('Score: $_score / 5', style: const TextStyle(color: Colors.grey, fontSize: 18)),
              const SizedBox(height: 60),
              if (!_isPlaying)
                FilledButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('START ROUND'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                ).animate().scale(curve: Curves.elasticOut),
              if (_targetVisible)
                const Icon(Icons.bolt_rounded, size: 120, color: Colors.orangeAccent).animate().scale(curve: Curves.elasticOut, duration: 200.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// Mini Game 2: Neuro-Math Sprint
class MathSprintScreen extends StatefulWidget {
  const MathSprintScreen({Key? key}) : super(key: key);
  @override State<MathSprintScreen> createState() => _MathSprintScreenState();
}

class _MathSprintScreenState extends State<MathSprintScreen> {
  int _score = 0;
  int _timeLeft = 30;
  Timer? _timer;
  bool _isPlaying = false;
  
  late int _num1;
  late int _num2;
  late String _operator;
  late int _answer;
  List<int> _options = [];

  void _startGame() {
    setState(() {
      _score = 0;
      _timeLeft = 30;
      _isPlaying = true;
    });
    _generateProblem();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        _endGame();
      }
    });
  }

  void _generateProblem() {
    final rand = math.Random();
    _num1 = rand.nextInt(20) + 1;
    _num2 = rand.nextInt(20) + 1;
    if (rand.nextBool()) {
      _operator = '+';
      _answer = _num1 + _num2;
    } else {
      // Avoid negatives for quick math
      if (_num1 < _num2) {
        final temp = _num1;
        _num1 = _num2;
        _num2 = temp;
      }
      _operator = '-';
      _answer = _num1 - _num2;
    }

    _options = [_answer];
    while (_options.length < 4) {
      final wrongAns = _answer + rand.nextInt(20) - 10;
      if (wrongAns != _answer && !_options.contains(wrongAns) && wrongAns >= 0) {
        _options.add(wrongAns);
      }
    }
    _options.shuffle();
  }

  void _submitAnswer(int picked) {
    if (!_isPlaying) return;
    if (picked == _answer) {
      HapticFeedback.lightImpact();
      setState(() => _score++);
      _generateProblem();
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _timeLeft = math.max(0, _timeLeft - 3)); // Penalty
    }
  }

  void _endGame() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neuro-Math Sprint')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600), // Prevents massive stretching on Desktop/Web
          child: SingleChildScrollView( // Allows scrolling if content is too tall
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // Ensures Center works properly
              children: [
                if (!_isPlaying && _score > 0) 
                  Text('Final Score: $_score', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.pinkAccent))
                  .animate().scale(curve: Curves.elasticOut),
                  
                const SizedBox(height: 24),

                if (!_isPlaying)
                  FilledButton.icon(
                    onPressed: _startGame,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: const Text('START SPRINT'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.pinkAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
                  ).animate().scale(curve: Curves.elasticOut)
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Score: $_score', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('00:${_timeLeft.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _timeLeft <= 5 ? Colors.redAccent : Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 60),
                  Text('$_num1 $_operator $_num2 = ?', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900))
                      .animate(key: ValueKey('$_num1$_operator$_num2')).fadeIn().scale(curve: Curves.easeOutBack),
                  const SizedBox(height: 60),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(), // Prevents nested scroll conflicts
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 2,
                    children: _options.map((opt) {
                      return FilledButton(
                        onPressed: () => _submitAnswer(opt),
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).cardTheme.color,
                          foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(opt.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      ).animate().fadeIn();
                    }).toList(),
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Mini Game 3: Zen Breather
class ZenBreatherScreen extends StatefulWidget {
  const ZenBreatherScreen({Key? key}) : super(key: key);
  @override State<ZenBreatherScreen> createState() => _ZenBreatherScreenState();
}

class _ZenBreatherScreenState extends State<ZenBreatherScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _phase = 'Breathe In';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _phase = 'Hold...');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _phase = 'Breathe Out');
            _controller.reverse();
          }
        });
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _phase = 'Hold...');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _phase = 'Breathe In');
            _controller.forward();
          }
        });
      }
    });
    _controller.forward();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zen Breather')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_phase, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: 4))
                .animate(key: ValueKey(_phase)).fadeIn().slideY(begin: 0.2),
            const SizedBox(height: 80),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 100 + (_controller.value * 200),
                  height: 100 + (_controller.value * 200),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyanAccent.withOpacity(0.2 + (_controller.value * 0.3)),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.5), blurRadius: 50 * _controller.value, spreadRadius: 20 * _controller.value)
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/* =============================================================================
   16. PREMIUM "PRO" UPGRADE PAYWALL (GLASSMORPHISM)
============================================================================= */

class PremiumUpgradeScreen extends StatelessWidget {
  const PremiumUpgradeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black, Color(0xFF1A1A2E), Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight)))),
          Positioned(top: -50, right: -50, child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container(width: 300, height: 300, decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.15), shape: BoxShape.circle))).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.2, duration: 4.seconds)),
          
          SafeArea(
            child: Column(
              children: [
                Align(alignment: Alignment.topLeft, child: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(context))),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        const Icon(Icons.workspace_premium_rounded, size: 80, color: Colors.amberAccent).animate().scale(curve: Curves.elasticOut, duration: 1.seconds), const SizedBox(height: 24),
                        const Text('Task Buddy PRO', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2), const SizedBox(height: 8),
                        const Text('Unlock God-Level Productivity.', style: TextStyle(color: Colors.white70, fontSize: 16)).animate().fadeIn(delay: 300.ms), const SizedBox(height: 48),
                        
                        _buildFeatureRow(Icons.cloud_sync_rounded, 'Unlimited Cloud Sync', 'Never lose a task again.'), _buildFeatureRow(Icons.bar_chart_rounded, 'Advanced Analytics', 'Deep insights into your focus patterns.'), _buildFeatureRow(Icons.color_lens_rounded, 'Exclusive Themes', 'Pitch black, Cyberpunk, and more.'), _buildFeatureRow(Icons.support_agent_rounded, 'Priority Support', 'Jump to the front of the line.'), const SizedBox(height: 48),

                        ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.amberAccent.withOpacity(0.5), width: 2), boxShadow: [BoxShadow(color: Colors.amberAccent.withOpacity(0.1), blurRadius: 30)]),
                              child: Column(
                                children: [
                                  const Text('LIFETIME ACCESS', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 2)), const SizedBox(height: 16),
                                  const Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('\$', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), Text('49', style: TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900, height: 1.0)), Text('.99', style: TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.bold))]), const SizedBox(height: 32),
                                  SizedBox(
                                    width: double.infinity, height: 60,
                                    child: FilledButton(onPressed: () { HapticFeedback.heavyImpact(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment Gateway Simulation Triggered'))); }, style: FilledButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: const Text('UPGRADE NOW', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5))),
                                  ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(duration: 2.seconds),
                                ],
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.1), const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: Colors.amberAccent, size: 28)), const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 14))])),
        ],
      ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.1),
    );
  }
}