import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set transparent status bar for a premium edge-to-edge look
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // Initialize global database connection
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
  String priority; // Low, Medium, High
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

/* =============================================================================
   2. DATABASE & STATE MANAGEMENT (Singleton Pattern)
============================================================================= */

class LocalDatabase {
  static late SharedPreferences _prefs;
  static AppUser? currentUser;
  
  static final ValueNotifier<bool> isDarkMode = ValueNotifier(true);
  static final ValueNotifier<List<TaskItem>> currentTasks = ValueNotifier([]);
  static final ValueNotifier<List<TaskCategory>> currentCategories = ValueNotifier([]);

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

  // --- Auth Methods ---
  
  static Future<bool> registerUser(String name, String email, String password) async {
    final existing = _prefs.getString('user_$email');
    if (existing != null) return false; // User exists

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
    await _prefs.remove('active_user_id');
  }

  // --- OTP Methods ---

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

  // --- Data Methods ---

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
      // Seed default categories
      final defaultCats = [
        TaskCategory(id: 'c1', name: 'Work', colorValue: Colors.blue.value),
        TaskCategory(id: 'c2', name: 'Personal', colorValue: Colors.purple.value),
        TaskCategory(id: 'c3', name: 'Health', colorValue: Colors.green.value),
      ];
      currentCategories.value = defaultCats;
      saveCategories();
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
}

/* =============================================================================
   3. APP WRAPPER & THEME DEFINITIONS
============================================================================= */

class TaskBuddyMaxApp extends StatelessWidget {
  const TaskBuddyMaxApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Globally enable animations on hot reload
    Animate.restartOnHotReload = true;

    return ValueListenableBuilder<bool>(
      valueListenable: LocalDatabase.isDarkMode,
      builder: (context, isDark, child) {
        final baseTextTheme = GoogleFonts.outfitTextTheme();
        
        return MaterialApp(
          title: 'Task Buddy Max',
          debugShowCheckedModeBanner: false,
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          
          // --- LIGHT THEME ---
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF4F46E5), // Indigo
            scaffoldBackgroundColor: const Color(0xFFF3F4F6), // Cool gray
            textTheme: baseTextTheme.apply(
              bodyColor: const Color(0xFF1F2937),
              displayColor: const Color(0xFF111827),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
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

          // --- DARK THEME ---
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF6366F1), // Light Indigo
            scaffoldBackgroundColor: const Color(0xFF0B0F19), // Deep Black/Blue
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
    // Hold splash for 2.5 seconds to show off animations
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

    // Simulate network delay for realism
    await Future.delayed(const Duration(seconds: 1));

    if (_isLogin) {
      // Handle Login
      final user = await LocalDatabase.loginUser(email, pass);
      if (user != null) {
        if (!user.isVerified) {
          // Generate OTP and route to verification
          await LocalDatabase.generateOTP(user.email);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => OtpScreen(email: user.email)),
          );
        } else {
          // Login success
          await LocalDatabase.setActiveSession(user);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        }
      } else {
        _showError('Invalid email or password.');
      }
    } else {
      // Handle Sign Up
      final success = await LocalDatabase.registerUser(name, email, pass);
      if (success) {
        await LocalDatabase.generateOTP(email);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OtpScreen(email: email)),
        );
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
                // Animated Icon
                Icon(
                  _isLogin ? Icons.lock_person_rounded : Icons.person_add_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                )
                .animate(target: _isLogin ? 1 : 0)
                .flipH(duration: 400.ms),
                
                const SizedBox(height: 32),
                
                // Dynamic Header
                Text(
                  _isLogin ? 'Welcome\nBack.' : 'Create\nAccount.',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
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

                // Form Fields
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: _isLogin ? 0 : 80,
                  curve: Curves.easeInOut,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                    ),
                  ),
                ),

                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
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
                      onPressed: () {
                        setState(() => _obscurePass = !_obscurePass);
                      },
                    ),
                  ),
                )
                .animate()
                .fadeIn(delay: 300.ms)
                .slideY(begin: 0.1, end: 0),

                const SizedBox(height: 48),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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

                // Toggle Button
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: _isLogin ? "Don't have an account? " : "Already have an account? ",
                        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                        children: [
                          TextSpan(
                            text: _isLogin ? 'Sign Up' : 'Sign In',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
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
    // Helper to see the OTP without actually sending an email
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
      SnackBar(
        content: Text('New OTP sent: $newOtp'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code.')),
      );
      return;
    }

    setState(() => _isVerifying = true);
    HapticFeedback.mediumImpact();

    await Future.delayed(const Duration(seconds: 1)); // Network simulation

    final success = await LocalDatabase.verifyOTP(widget.email, code);

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      setState(() => _isVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid verification code.')),
      );
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
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.mark_email_read_rounded, size: 48, color: Colors.green),
              )
              .animate()
              .scale(curve: Curves.easeOutBack, duration: 600.ms),
              
              const SizedBox(height: 32),
              
              const Text(
                'Check your\nemail.',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              )
              .animate()
              .fadeIn(delay: 200.ms)
              .slideX(begin: -0.1),
              
              const SizedBox(height: 16),
              
              Text(
                'We sent a 6-digit verification code to:\n${widget.email}',
                style: const TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
              )
              .animate()
              .fadeIn(delay: 300.ms),

              const SizedBox(height: 48),

              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 16,
                ),
                decoration: InputDecoration(
                  hintText: '000000',
                  counterText: "",
                  filled: true,
                  fillColor: Theme.of(context).cardTheme.color,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
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
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
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
                    _timerSeconds > 0 
                        ? 'Resend code in $_timerSeconds seconds'
                        : 'Resend Verification Code',
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
   7. MAIN DASHBOARD SCREEN
============================================================================= */

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _currentFilter = 'All'; // All, Pending, Done, Priority
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      
      // Left Drawer Navigation
      drawer: const CustomAppDrawer(),
      
      body: ValueListenableBuilder<List<TaskItem>>(
        valueListenable: LocalDatabase.currentTasks,
        builder: (context, tasks, child) {
          
          // Compute Metrics
          int doneCount = tasks.where((t) => t.isCompleted).length;
          double progress = tasks.isEmpty ? 0 : doneCount / tasks.length;
          
          // Apply Filters
          List<TaskItem> filteredList = tasks.where((t) {
            if (_currentFilter == 'Pending') return !t.isCompleted;
            if (_currentFilter == 'Done') return t.isCompleted;
            if (_currentFilter == 'Priority') return t.priority == 'High' && !t.isCompleted;
            return true;
          }).toList();

          // Sort: Pending first, then by closest deadline
          filteredList.sort((a, b) {
            if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
            return a.deadline.compareTo(b.deadline);
          });

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Dynamic Header
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

              // Bento Grid Stats
              SliverToBoxAdapter(
                child: _buildDashboardBento(context, progress, tasks.length - doneCount)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1),
              ),

              // Filter Chips
              SliverToBoxAdapter(
                child: _buildFilterSection()
                    .animate()
                    .fadeIn(delay: 200.ms),
              ),

              // Task List or Empty State
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
                        return TaskListTile(
                          task: filteredList[index],
                          index: index,
                        );
                      },
                      childCount: filteredList.length,
                    ),
                  ),
                ),

              // Padding for FAB
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
      
      // Floating Action Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TaskEditorScreen()),
        ),
        elevation: 4,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('New Objective', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      )
      .animate()
      .scale(delay: 600.ms, curve: Curves.easeOutBack, duration: 400.ms),
    );
  }

  Widget _buildDashboardBento(BuildContext context, double progress, int pendingCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.tertiary, // Usually a pink/purple variant in M3
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Completion',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$pendingCount pending tasks',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            
            // Progress Ring
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
                      progress >= 1.0 && pendingCount == 0 
                          ? Icons.emoji_events_rounded 
                          : Icons.trending_up_rounded,
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
                    color: isSelected 
                        ? Theme.of(context).colorScheme.primary 
                        : Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected 
                          ? Colors.transparent 
                          : Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    filterName,
                    style: TextStyle(
                      color: isSelected 
                          ? Colors.white 
                          : Theme.of(context).textTheme.bodyLarge?.color,
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
    // Find category details safely
    final categories = LocalDatabase.currentCategories.value;
    TaskCategory? cat;
    try {
      cat = categories.firstWhere((c) => c.id == task.categoryId);
    } catch (_) {
      cat = TaskCategory(id: 'err', name: 'General', colorValue: Colors.grey.value);
    }

    final isOverdue = !task.isCompleted && task.deadline.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(task.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 32),
        ),
        onDismissed: (_) {
          HapticFeedback.mediumImpact();
          LocalDatabase.deleteTask(task.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task removed'), duration: Duration(seconds: 2)),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]
          ),
          child: Material(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TaskEditorScreen(task: task)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Custom Checkbox
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        task.isCompleted = !task.isCompleted;
                        LocalDatabase.updateTask(task);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        height: 32,
                        width: 32,
                        decoration: BoxDecoration(
                          color: task.isCompleted 
                              ? Colors.greenAccent 
                              : Colors.transparent,
                          border: Border.all(
                            color: task.isCompleted 
                                ? Colors.greenAccent 
                                : Colors.grey.withOpacity(0.5),
                            width: 2,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: task.isCompleted 
                            ? const Icon(Icons.check_rounded, size: 20, color: Colors.black)
                            : null,
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Task Details
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
                              color: task.isCompleted 
                                  ? Colors.grey 
                                  : Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Category Tag
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Color(cat.colorValue).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  cat.name,
                                  style: TextStyle(
                                    color: Color(cat.colorValue),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Deadline
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: isOverdue ? Colors.redAccent : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd, hh:mm a').format(task.deadline),
                                style: TextStyle(
                                  color: isOverdue ? Colors.redAccent : Colors.grey,
                                  fontSize: 12,
                                  fontWeight: isOverdue ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                              
                              // Focus indicator if time spent
                              if (task.focusMinutesSpent > 0) ...[
                                const Spacer(),
                                const Icon(Icons.local_fire_department_rounded, size: 14, color: Colors.orangeAccent),
                                const SizedBox(width: 2),
                                Text(
                                  '${task.focusMinutesSpent}m',
                                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                )
                              ]
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Priority Dot indicator
                    if (!task.isCompleted)
                      Container(
                        margin: const EdgeInsets.only(left: 12),
                        height: 12,
                        width: 12,
                        decoration: BoxDecoration(
                          color: _getPriorityColor(),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      )
      .animate()
      .fadeIn(delay: Duration(milliseconds: 100 * index), duration: 400.ms)
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
      
      // Ensure category still exists
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task title cannot be empty')),
      );
      return;
    }

    final deadline = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedTime.hour, _selectedTime.minute,
    );

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
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time == null) return;

    setState(() {
      _selectedDate = date;
      _selectedTime = time;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? 'New Objective' : 'Edit Objective', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Input
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'What needs to be done?',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ).animate().fadeIn().slideX(begin: -0.05),
            
            const SizedBox(height: 24),
            
            // Description Input
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

            // Settings Grid
            Row(
              children: [
                // Deadline Picker
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

                // Category Picker
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

            // Priority Picker
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
      
      // Save Button
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
  
  // Timer States
  static const int WORK_MINUTES = 25;
  static const int BREAK_MINUTES = 5;
  
  int _secondsRemaining = WORK_MINUTES * 60;
  bool _isRunning = false;
  bool _isWorkPhase = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Default select first pending task
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
    SystemSound.play(SystemSoundType.alert); // Native ping
    
    setState(() {
      _isRunning = false;
      
      // Add time to task if it was a work phase
      if (_isWorkPhase && _selectedTask != null) {
        _selectedTask!.focusMinutesSpent += WORK_MINUTES;
        LocalDatabase.updateTask(_selectedTask!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('+${WORK_MINUTES}m added to ${_selectedTask!.title}')),
        );
      }
      
      // Swap phase
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

    // Get pending tasks for dropdown
    final pendingTasks = LocalDatabase.currentTasks.value.where((t) => !t.isCompleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Engine', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            children: [
              // Task Selector
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

              // Timer Display (Stack with Circular Progress)
              SizedBox(
                height: 320,
                width: 320,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background Track
                    CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 20,
                      color: Theme.of(context).cardTheme.color,
                    ),
                    // Animated Progress Track
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 20,
                      backgroundColor: Colors.transparent,
                      color: _isWorkPhase ? Theme.of(context).colorScheme.primary : Colors.greenAccent,
                      strokeCap: StrokeCap.round,
                    ),
                    // Text Overlay
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
                            style: const TextStyle(
                              fontSize: 80,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),

              const Spacer(),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.grey,
                    onPressed: _isRunning ? null : _resetTimer,
                  ).animate().fadeIn(delay: 200.ms),
                  
                  const SizedBox(width: 32),
                  
                  FloatingActionButton.large(
                    onPressed: _toggleTimer,
                    elevation: _isRunning ? 0 : 8,
                    backgroundColor: _isRunning ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                    child: Icon(
                      _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ).animate().scale(delay: 300.ms, curve: Curves.elasticOut),
                  
                  const SizedBox(width: 32),
                  
                  IconButton(
                    iconSize: 32,
                    icon: const Icon(Icons.skip_next_rounded),
                    color: Colors.grey,
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
   11. ANALYTICS & CUSTOM PAINTER DASHBOARD
============================================================================= */

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ValueListenableBuilder<List<TaskItem>>(
        valueListenable: LocalDatabase.currentTasks,
        builder: (context, tasks, _) {
          
          // Data Calculation
          final int total = tasks.length;
          final int done = tasks.where((t) => t.isCompleted).length;
          final int focusMinutes = tasks.fold(0, (sum, t) => sum + t.focusMinutesSpent);
          
          // Mock data points based on completion ratio for the chart
          final double baseRatio = total == 0 ? 0.0 : done / total;
          final List<double> chartData = [
            math.max(0.1, baseRatio * 0.3),
            math.max(0.2, baseRatio * 0.5),
            math.max(0.1, baseRatio * 0.8),
            math.max(0.4, baseRatio * 0.6),
            math.max(0.3, baseRatio * 0.9),
            math.max(0.6, baseRatio * 1.1),
            math.max(0.2, baseRatio), // Current Day
          ];

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Metrics Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        context, 'Completed', '$done / $total', Colors.blueAccent, Icons.task_alt,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        context, 'Focus Time', '${(focusMinutes / 60).toStringAsFixed(1)}h', Colors.orangeAccent, Icons.local_fire_department,
                      ),
                    ),
                  ],
                ).animate().fadeIn().slideY(begin: 0.1),
                
                const SizedBox(height: 40),
                const Text('Activity Heatmap (7 Days)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                // Custom Painter Chart
                Container(
                  height: 280,
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 20, offset: const Offset(0, 10),
                      )
                    ]
                  ),
                  child: CustomPaint(
                    painter: _SmoothLineChartPainter(
                      color: Theme.of(context).colorScheme.primary,
                      dataPoints: chartData,
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).scale(curve: Curves.easeOutQuart),

                const SizedBox(height: 40),
                const Text('System Log', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                // Log List
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.greenAccent, child: Icon(Icons.check, color: Colors.black)),
                        title: const Text('System Operational'),
                        subtitle: Text('Database loaded with $total records.'),
                      ),
                      const Divider(height: 1, indent: 70),
                      ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.purpleAccent, child: Icon(Icons.category, color: Colors.white)),
                        title: const Text('Categories Synced'),
                        subtitle: Text('${LocalDatabase.currentCategories.value.length} active tags available.'),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String val, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

// THE CUSTOM PAINTER (For rendering actual paths)
class _SmoothLineChartPainter extends CustomPainter {
  final Color color;
  final List<double> dataPoints;

  _SmoothLineChartPainter({required this.color, required this.dataPoints});

  @override
  void paint(Canvas canvas, Size size) {
    if (dataPoints.isEmpty) return;

    final maxVal = dataPoints.reduce(math.max) <= 0 ? 1.0 : dataPoints.reduce(math.max) * 1.2;
    final dx = size.width / (dataPoints.length - 1);
    
    final path = Path();
    final fillPath = Path();
    
    // Start paths
    path.moveTo(0, size.height * (1 - (dataPoints[0] / maxVal)));
    fillPath.moveTo(0, size.height);
    fillPath.lineTo(0, size.height * (1 - (dataPoints[0] / maxVal)));

    // Generate coordinates
    List<Offset> points = [];
    for (int i = 0; i < dataPoints.length; i++) {
      points.add(Offset(i * dx, size.height * (1 - (dataPoints[i] / maxVal))));
    }

    // Draw smooth bezier curves
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlPointX = p0.dx + ((p1.dx - p0.dx) / 2);
      
      path.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);
      fillPath.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    // 1. Draw Fill Gradient
    final paintFill = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.4), color.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, paintFill);

    // 2. Draw Stroke Line
    final paintLine = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paintLine);

    // 3. Draw Points
    final pointPaint = Paint()..color = Colors.white;
    final pointBorderPaint = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke;
    
    for (final point in points) {
      canvas.drawCircle(point, 6, pointPaint);
      canvas.drawCircle(point, 6, pointBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/* =============================================================================
   12. CATEGORY MANAGER & DRAWER NAVIGATION
============================================================================= */

class CustomAppDrawer extends StatelessWidget {
  const CustomAppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            width: double.infinity,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: Colors.indigo),
                ),
                const SizedBox(height: 16),
                Text(
                  LocalDatabase.currentUser?.name ?? 'Guest User',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  LocalDatabase.currentUser?.email ?? 'No email associated',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // Navigation Links
          ListTile(
            leading: const Icon(Icons.folder_special_rounded),
            title: const Text('Manage Categories'),
            onTap: () {
              Navigator.pop(context); // Close drawer
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagerScreen()));
            },
          ),
          
          ValueListenableBuilder<bool>(
            valueListenable: LocalDatabase.isDarkMode,
            builder: (context, isDark, _) {
              return ListTile(
                leading: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
                title: Text(isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  LocalDatabase.toggleTheme();
                },
              );
            }
          ),

          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('System Settings'),
            onTap: () {}, // Placeholder for expansion
          ),

          const Spacer(),
          const Divider(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

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
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter category name...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.isEmpty) return;
              // Generate a random bright color for the category
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

