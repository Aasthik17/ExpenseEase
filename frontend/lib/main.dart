// main.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';  // Add this import
//import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:http/http.dart' as http;  // For HTTP requests
import 'dart:convert';  // For JSON handling
import 'dart:io';  // For SocketException
import 'dart:async';  // For TimeoutException
import 'dart:developer';
import 'package:flutter/services.dart'; // For FilteringTextInputFormatter

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CurrencyProvider()),

      ],
      child: const ExpenseTrackerApp(),
    ),
  );
}

// Models
class User {
  final int id;
  final String name;
  final String email;
  final String pin;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.pin,
  });
}

// Providers
class AuthProvider with ChangeNotifier {
  User? _currentUser;
  List<Expense> _userExpenses = [];
  final String _baseUrl = 'const String API_BASE_URL = String.fromEnvironment("API_BASE_URL");';
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  List<Expense> get userExpenses => _userExpenses;
  bool get isLoading => _isLoading;

  Future<void> signUp(String name, String email, String pin, String confirmPin) async {
    if (pin != confirmPin) throw Exception("PINs don't match");
    if (pin.length != 4) throw Exception("PIN must be 4 digits");

    try {
      _setLoading(true);
      final response = await http.post(
        Uri.parse('$_baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'pin': pin,
        }),
      ).timeout(const Duration(seconds: 10));

      final responseData = _handleResponse(response);
      _currentUser = User(
        id: responseData['user_id'],
        name: responseData['name'],
        email: responseData['email'],
        pin: pin, // Add the missing 'pin' parameter
      );
      notifyListeners();
    } catch (e) {
      _handleError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> login(String email, String pin) async {
    try {
      _setLoading(true);
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'pin': pin}),
      ).timeout(const Duration(seconds: 10));

      final responseData = _handleResponse(response);
      _currentUser = User(
        id: responseData['user_id'], // Make sure this matches the server response
        name: responseData['name'],
        email: responseData['email'],
        pin: pin, // Store the pin if needed
      );

      await _fetchUserData(_currentUser!.id);
      return true;
    } catch (e) {
      _handleError(e);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _fetchUserData(int userId) async {
    try {
      _setLoading(true);
      final response = await http.get(
        Uri.parse('$_baseUrl/user-data/$userId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      final responseData = _handleResponse(response);
      _userExpenses = (responseData['expenses'] as List)
          .map((e) => Expense.fromJson(e))
          .toList();
      notifyListeners();
    } catch (e) {
      _handleError(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addExpense(Expense expense) async {
  try {
    _setLoading(true);
    log('Sending expense to server: ${expense.toJson()}');
    
    final response = await http.post(
      Uri.parse('$_baseUrl/expenses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(expense.toJson()),
    ).timeout(const Duration(seconds: 10));

    final responseData = _handleResponse(response);
    log('Server response: $responseData');
    
    final newExpense = Expense.fromJson(responseData);
    _userExpenses.add(newExpense);
    notifyListeners();
    
    log('Expense successfully added to database');
    } catch (e) {
      log('Error adding expense: $e', level: 1000);
      _handleError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removeExpense(int expenseId) async {
    try {
      _setLoading(true);
      final response = await http.delete(
        Uri.parse('$_baseUrl/expenses/$expenseId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      _handleResponse(response);
      _userExpenses.removeWhere((e) => e.id == expenseId);
      notifyListeners();
    } catch (e) {
      _handleError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  dynamic _handleResponse(http.Response response) {
    log('Response status: ${response.statusCode}'); // Replace print with log
    log('Response body: ${response.body}'); // Replace print with log
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body)?['error'] ?? 'Request failed with status ${response.statusCode}';
      throw Exception(error);
    }
  }

  void _handleError(dynamic error) {
    debugPrint('AuthProvider Error: $error');
    if (error is SocketException) {
      throw Exception('No internet connection');
    } else if (error is TimeoutException) {
      throw Exception('Request timed out');
    } else {
      throw error; // Replace rethrow with throw
    }
  }
}

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

class CurrencyProvider with ChangeNotifier {
  // Supported currencies with symbol and code
  final Map<String, String> _supportedCurrencies = {
    'INR': '₹',  // Indian Rupee (default)
    'USD': '\$', // US Dollar
    'EUR': '€',  // Euro
    'GBP': '£',  // British Pound
    'JPY': '¥',  // Japanese Yen
    'AUD': 'A\$' // Australian Dollar
  };

  String _currentCurrencyCode = 'INR'; // Default to INR
  
  String get currencySymbol => _supportedCurrencies[_currentCurrencyCode]!;
  String get currencyCode => _currentCurrencyCode;
  Map<String, String> get availableCurrencies => _supportedCurrencies;
  
  void setCurrency(String currencyCode) {
    if (_supportedCurrencies.containsKey(currencyCode)) {
      _currentCurrencyCode = currencyCode;
      notifyListeners();
    }
  }

  static String format(BuildContext context, double amount) {
    final currency = Provider.of<CurrencyProvider>(context, listen: false);
    return '${currency.currencySymbol}${amount.toStringAsFixed(2)}';
  }
  
  // Or with intl package:
  static String formatWithSymbol(BuildContext context, double amount) {
    final currency = Provider.of<CurrencyProvider>(context, listen: false);
    final format = NumberFormat.currency(
      symbol: currency.currencySymbol,
      decimalDigits: 2,
    );
    return format.format(amount);
  }
}


class ExpenseTrackerApp extends StatelessWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return MaterialApp(
      title: 'ExpenseEase',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode, // Use provider's theme mode
      home: authProvider.currentUser == null ? const AuthWrapper() : const HomePage(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SignUpPage(pageController: _pageController),
          LoginPage(pageController: _pageController),
        ],
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  final PageController pageController;

  const SignUpPage({super.key, required this.pageController});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await Provider.of<AuthProvider>(context, listen: false).signUp(
        _nameController.text,
        _emailController.text,
        _pinController.text,
        _confirmPinController.text,
      );

      if (!mounted) return; // Ensure the widget is still mounted
      if (widget.pageController.hasClients) {
        widget.pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      if (!mounted) return; // Ensure the widget is still mounted
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Sign Up')),
    body: LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 
                         MediaQuery.of(context).viewInsets.bottom,
            ),
            child: IntrinsicHeight(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // Center vertically
                  children: [
                    // Form fields (keep your existing fields)
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pinController,
                      decoration: const InputDecoration(
                        labelText: '4-digit PIN',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      maxLength: 4,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPinController,
                      decoration: const InputDecoration(
                        labelText: 'Confirm PIN',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      maxLength: 4,
                    ),
                    const SizedBox(height: 32), // Increased spacing

                    // Centered Sign Up Button
                    Center(
                      child: SizedBox(
                        width: double.infinity, // Full width
                        child: ElevatedButton(
                          onPressed: () => _handleSignUp(context),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Sign Up', style: TextStyle(fontSize: 18)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Centered "Already have an account?" text
                    Center(
                      child: TextButton(
                        onPressed: () {
                          widget.pageController.animateToPage(
                            1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text(
                          'Already have an account? Log in',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
}

class LoginPage extends StatefulWidget {
  final PageController pageController;
  
  const LoginPage({super.key, required this.pageController});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin(BuildContext context) async {
    if (_emailController.text.isEmpty || !_emailController.text.contains('@')) {
      setState(() => _errorMessage = 'Enter valid email');
      return;
    }
    if (_pinController.text.length != 4) {
      setState(() => _errorMessage = 'Enter 4-digit PIN');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await Provider.of<AuthProvider>(
        context,
        listen: false,
      ).login(_emailController.text, _pinController.text);

      if (!mounted) return; // Ensure the widget is still mounted
      if (!success) {
        setState(() => _errorMessage = 'Invalid email or PIN');
      }
    } catch (e) {
      if (!mounted) return; // Ensure the widget is still mounted
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) => 
                !value!.contains('@') ? 'Enter valid email' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinController,
              decoration: const InputDecoration(labelText: '4-digit PIN'),
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: () => _handleLogin(context),
                    child: const Text('Login'),
                  ),
            TextButton(
              onPressed: () {
                if (widget.pageController.hasClients) {
                  widget.pageController.animateToPage(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: const Text('Don\'t have an account? Sign up'),
            )
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final List<Expense> expenses = [];
  int _selectedIndex = 0;
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userName = authProvider.currentUser?.name.split(' ').first ?? 'User';
    // Removed unused variable 'expenses'

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ExpenseEase'),
            Text(
              'Hey $userName!',
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
          ],
        ),
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Expenses',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Statistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddExpenseOptions(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildExpensesList();
      case 1:
        return _buildStatistics();
      case 2:
        return _buildSettings();
      default:
        return _buildExpensesList();
    }
  }

  Widget _buildExpensesList() {
    final authProvider = Provider.of<AuthProvider>(context, listen: true);
    final expenses = authProvider.userExpenses;

    if (expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No expenses yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add an expense to get started',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                _showAddExpenseOptions(context);
              },
              child: const Text('Add Expense'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final expense = expenses[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(_getCategoryIcon(expense.category)),
            ),
            title: Text(expense.title),
            subtitle: Text(expense.category),
            trailing: Text(
              CurrencyProvider.format(context, expense.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            onTap: () {
              _showExpenseDetails(expense);
            },
          ),
        );
      },
    );
  }
  
  Widget _buildStatistics() {
    final authProvider = Provider.of<AuthProvider>(context, listen: true);
    final expenses = authProvider.userExpenses;
    
    if (expenses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No expenses yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Add expenses to see statistics',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    double totalExpenses = expenses.fold(0, (sum, expense) => sum + expense.amount);
    
    // Create a map of category totals
    Map<String, double> categoryTotals = {};
    for (var expense in expenses) {
      categoryTotals[expense.category] = 
          (categoryTotals[expense.category] ?? 0) + expense.amount;
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Expenses',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    CurrencyProvider.format(context, totalExpenses),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Expenses by Category',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: categoryTotals.length,
              itemBuilder: (context, index) {
                String category = categoryTotals.keys.elementAt(index);
                double amount = categoryTotals[category]!;
                double percentage = amount / totalExpenses * 100;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Row(
                                children: [
                                  Icon(_getCategoryIcon(category)),
                                  const SizedBox(width: 8),
                                  Text(category),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            '${CurrencyProvider.format(context, amount)} '
                            '(${percentage.toStringAsFixed(1)}%)',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.grey[300],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView( // <-- Added this
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildSettingsCard(
              'Data Sources',
              [
                SettingsItem(
                  'Bank Messages',
                  'Link your bank SMS messages',
                  Icons.sms,
                  () => _requestSmsPermission(),
                ),
                SettingsItem(
                  'OCR Settings',
                  'Configure bill scanning preferences',
                  Icons.document_scanner,
                  () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsCard(
              'Account',
              [
                SettingsItem(
                  'Export Data',
                  'Export your expense data',
                  Icons.download,
                  () {},
                ),
                SettingsItem(
                  'Categories',
                  'Manage expense categories',
                  Icons.category,
                  () => _showCategoriesManagement(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSettingsCard(
              'Appearance',
              [
                SettingsItem(
                  'Theme',
                  'Change app theme',
                  Icons.color_lens,
                  () {
                    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Select Theme'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('System Default'),
                                onTap: () {
                                  themeProvider.setThemeMode(ThemeMode.system);
                                  if (mounted) {
                                    if (mounted) {
                                      Navigator.pop(context);
                                    }
                                  }
                                },
                              ),
                              ListTile(
                                title: const Text('Light Mode'),
                                onTap: () {
                                  themeProvider.setThemeMode(ThemeMode.light);
                                  Navigator.pop(context);
                                },
                              ),
                              ListTile(
                                title: const Text('Dark Mode'),
                                onTap: () {
                                  themeProvider.setThemeMode(ThemeMode.dark);
                                  Navigator.pop(context);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                SettingsItem(
                  'Currency',
                  'Set your preferred currency',
                  Icons.attach_money,
                  () {
                    final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('Select Currency'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: currencyProvider.availableCurrencies.entries.map((entry) {
                                return ListTile(
                                  title: Text('${entry.value} - ${entry.key}'),
                                  onTap: () {
                                    currencyProvider.setCurrency(entry.key);
                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSettingsCard(String title, List<SettingsItem> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...items.map((item) => _buildSettingsItem(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(SettingsItem item) {
    return ListTile(
      leading: Icon(item.icon),
      title: Text(item.title),
      subtitle: Text(item.subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: item.onTap,
    );
  }

  void _showAddExpenseOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Expense',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              _buildAddExpenseOption(
                context,
                'Manual Entry',
                Icons.edit,
                () {
                  Navigator.pop(context);
                  _showManualEntryForm();
                },
              ),
              const SizedBox(height: 16),
              _buildAddExpenseOption(
                context,
                'Scan Bill',
                Icons.document_scanner,
                () {
                  Navigator.pop(context);
                  _scanBill();
                },
              ),
              const SizedBox(height: 16),
              _buildAddExpenseOption(
                context,
                'From Bank Messages',
                Icons.sms,
                () {
                  Navigator.pop(context);
                  _showBankMessages();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddExpenseOption(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 16),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  void _showManualEntryForm() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Food';
    final dateController = TextEditingController(
      text: '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}',
    );
    String? notes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add Expense',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          border: OutlineInputBorder(),
                          prefixText: '₹ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          'Food',
                          'Transportation',
                          'Entertainment',
                          'Shopping',
                          'Bills',
                          'Health',
                          'Other',
                        ].map((String category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Row(
                              children: [
                                Icon(_getCategoryIcon(category)),
                                const SizedBox(width: 8),
                                Text(category),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              selectedCategory = newValue;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: dateController,
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        readOnly: true,
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (pickedDate != null) {
                            setState(() {
                              dateController.text =
                                  '${pickedDate.month}/${pickedDate.day}/${pickedDate.year}';
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) {
                          notes = value;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (titleController.text.isNotEmpty && amountController.text.isNotEmpty) {
                              try {
                                final amount = double.tryParse(amountController.text) ?? 0.0;
                                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                final navigator = Navigator.of(context);
                                final newExpense = Expense(
                                  id: 0,
                                  title: titleController.text,
                                  amount: amount, // Use the parsed double value
                                  category: selectedCategory,
                                  date: DateTime.now(),
                                  userId: authProvider.currentUser!.id,
                                  notes: notes,
                                );
                                
                                await authProvider.addExpense(newExpense);
                                
                                if (mounted) {
                                  navigator.pop(); // Close the modal
                                  _showSnackBar('Expense added successfully');
                                }
                              } catch (e) {
                                if (mounted) {
                                  _showSnackBar('Error: ${e.toString()}');
                                }
                              }
                            } else {
                              _showSnackBar('Please fill in all required fields');
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Text('Save'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              },
            );

          },
        );
      },
    );
  }

  Future<void> _scanBill() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      
      if (image == null) return;
      
      _showLoadingDialog('Scanning bill...');
      
      // Create multipart request
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('const String OCR_SERVICE_URL = String.fromEnvironment("OCR_SERVICE_URL");')
      );
      
      // Add image file
      request.files.add(await http.MultipartFile.fromPath(
        'image', 
        image.path
      ));
      
      // Send request
      var response = await request.send();
      
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var extractedData = json.decode(responseData);
        
        if (!mounted) return;
        Navigator.pop(context);
        
        String titleGuess = extractedData['category'] ?? 'Scanned Expense';
          _showOcrResultForm({
            'title': titleGuess,
            'amount': extractedData['amount']?.toString() ?? '',
            'category': extractedData['category'] ?? 'Other',
            'date': extractedData['date'] != null
                ? _formatDateForInput(extractedData['date'])
                : '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}',
          });
      } else {
        throw Exception('Failed to process bill');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar('Error scanning bill: $e');
    }
  }

  void _showOcrResultForm(Map<String, dynamic> extractedData) {
    //print("🧾 Extracted Data from OCR: $extractedData");

    final titleController = TextEditingController(text: extractedData['title'] ?? '');
    final amountController = TextEditingController(text: extractedData['amount']?.toString() ?? '');
    String selectedCategory = extractedData['category'] ?? 'Food';
    final dateString = extractedData['date']?.toString() ?? '';
    final dateController = TextEditingController(text: dateString);
    String? notes;

    DateTime parsedDate = DateTime.tryParse(dateString) ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      items: [
                        'Food', 'Transportation', 'Entertainment', 'Shopping', 'Bills', 'Health', 'Other'
                      ].map((category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => selectedCategory = val);
                      },
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: parsedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            parsedDate = picked;
                            dateController.text = '${picked.month}/${picked.day}/${picked.year}';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 3,
                      controller: TextEditingController(text: notes),
                      onChanged: (val) => notes = val,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (titleController.text.isNotEmpty && amountController.text.isNotEmpty) {
                                final newExpense = Expense(
                                  id: DateTime.now().millisecondsSinceEpoch, // Example unique ID
                                  userId: Provider.of<AuthProvider>(context, listen: false).currentUser!.id, // Fetch user ID from AuthProvider
                                  title: titleController.text,
                                  amount: double.tryParse(amountController.text) ?? 0.0,
                                  category: selectedCategory,
                                  date: parsedDate,
                                  notes: notes,
                                  source: 'OCR',
                                );
                                setState(() {
                                  expenses.add(newExpense);
                                });
                                Navigator.pop(context);
                                _showSnackBar('Expense added');
                              } else {
                                _showSnackBar('Failed to add expense');
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }



  Future<void> _requestSmsPermission() async {
    var status = await Permission.sms.request();
    if (status.isGranted) {
      _showSnackBar('SMS permission granted');
      _showBankMessages();
    } else {
      _showSnackBar('SMS permission denied. Cannot access bank messages.');
    }
  }

  void _showBankMessages() async {
    // Simulate fetching bank messages
    await Future.delayed(const Duration(seconds: 1));
    
    // Sample bank messages
    final messages = [
      BankMessage(
        'Your account was debited with ₹45.30 for Amazon.com on 04/05/2025',
        DateTime.now().subtract(const Duration(days: 2)),
        'Amazon.com',
        45.30,
      ),
      BankMessage(
        'Your account was debited with ₹12.99 for Netflix Subscription on 04/01/2025',
        DateTime.now().subtract(const Duration(days: 6)),
        'Netflix',
        12.99,
      ),
      BankMessage(
        'Your account was debited with ₹35.75 for Uber on 03/29/2025',
        DateTime.now().subtract(const Duration(days: 9)),
        'Uber',
        35.75,
      ),
    ];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bank Messages',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select messages to add as expenses',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(message.merchant),
                        subtitle: Text(
                          message.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                               '\$${message.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${message.date.month}/${message.date.day}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showBankMessageConfirmation(message);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBankMessageConfirmation(BankMessage message) {
    final titleController = TextEditingController(text: message.merchant);
    final amountController = TextEditingController(text: message.amount.toString());
    String selectedCategory = _guessCategory(message.merchant);
    final dateController = TextEditingController(
      text: '${message.date.month}/${message.date.day}/${message.date.year}',
    );
    String? notes = message.content;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirm Bank Message Expense',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please review and edit the information',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      'Food',
                      'Transportation',
                      'Entertainment',
                      'Shopping',
                      'Bills',
                      'Health',
                      'Other',
                    ].map((String category) {
                      return DropdownMenuItem<String>(
                        value: category,
                        child: Row(
                          children: [
                            Icon(_getCategoryIcon(category)),
                            const SizedBox(width: 8),
                            Text(category),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedCategory = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dateController,
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    readOnly: true,
                    onTap: () async {final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: message.date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          dateController.text =
                              '${pickedDate.month}/${pickedDate.day}/${pickedDate.year}';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    controller: TextEditingController(text: notes),
                    onChanged: (value) {
                      notes = value;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Text('Cancel'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            if (titleController.text.isNotEmpty &&
                                amountController.text.isNotEmpty) {
                              final navigator = Navigator.of(context);
                              final newExpense = Expense(
                                id: DateTime.now().millisecondsSinceEpoch, // Example unique ID
                                userId: Provider.of<AuthProvider>(context, listen: false).currentUser!.id, // Fetch user ID from AuthProvider
                                title: titleController.text,
                                amount: double.parse(amountController.text),
                                category: selectedCategory,
                                date: DateTime.parse(
                                    _parseDate(dateController.text)),
                                notes: notes,
                                source: 'Bank Message',
                              );
                              await Provider.of<AuthProvider>(context, listen: false).addExpense(newExpense);
                              
                              if (!mounted) return;
                              navigator.pop();
                              _showSnackBar('Expense added successfully');
                            } else {
                              _showSnackBar('Please fill in all required fields');
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.0),
                            child: Text('Save'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showExpenseDetails(Expense expense) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.title,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(_getCategoryIcon(expense.category),
                                color: Colors.grey, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              expense.category,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyProvider.format(context, expense.amount),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildDetailItem('Date', 
                '${expense.date.month}/${expense.date.day}/${expense.date.year}'),
              if (expense.source != null)
                _buildDetailItem('Source', expense.source!),
              if (expense.notes != null && expense.notes!.isNotEmpty)
                _buildDetailItem('Notes', expense.notes!),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Show edit form here
                    },
                    child: const Text('Edit'),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    onPressed: () {
                      Provider.of<AuthProvider>(context, listen: false).removeExpense(expense.id);
                      Navigator.pop(context);
                      _showSnackBar('Expense deleted');
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  void _showCategoriesManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Manage Categories',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    final category = [
                      'Food',
                      'Transportation',
                      'Entertainment',
                      'Shopping',
                      'Bills',
                      'Health',
                      'Other',
                    ][index];
                    return ListTile(
                      leading: Icon(_getCategoryIcon(category)),
                      title: Text(category),
                      trailing: index < 6
                          ? const Icon(Icons.drag_handle)
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Add new category
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.0),
                    child: Text('Add New Category'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(message),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant;
      case 'Transportation':
        return Icons.directions_car;
      case 'Entertainment':
        return Icons.movie;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Bills':
        return Icons.receipt;
      case 'Health':
        return Icons.medical_services;
      default:
        return Icons.category;
    }
  }

  String _guessCategory(String merchant) {
    merchant = merchant.toLowerCase();
    if (merchant.contains('amazon') ||
        merchant.contains('walmart') ||
        merchant.contains('target')) {
      return 'Shopping';
    } else if (merchant.contains('uber') ||
        merchant.contains('lyft') ||
        merchant.contains('transit')) {
      return 'Transportation';
    } else if (merchant.contains('netflix') ||
        merchant.contains('hulu') ||
        merchant.contains('cinema') ||
        merchant.contains('theater')) {
      return 'Entertainment';
    } else if (merchant.contains('restaurant') ||
        merchant.contains('cafe') ||
        merchant.contains('doordash') ||
        merchant.contains('uber eats')) {
      return 'Food';
    } else if (merchant.contains('doctor') ||
        merchant.contains('pharmacy') ||
        merchant.contains('hospital')) {
      return 'Health';
    } else if (merchant.contains('utility') ||
        merchant.contains('electric') ||
        merchant.contains('water') ||
        merchant.contains('phone') ||
        merchant.contains('bill')) {
      return 'Bills';
    }
    return 'Other';
  }

  String _parseDate(String dateStr) {
    // Convert MM/DD/YYYY to YYYY-MM-DD for DateTime.parse
    final parts = dateStr.split('/');
    if (parts.length == 3) {
      return '${parts[2]}-${parts[0].padLeft(2, '0')}-${parts[1].padLeft(2, '0')}';
    }
    return DateTime.now().toIso8601String().split('T')[0];
  }

  String _formatDateForInput(String isoDate) {
    try {
      final parsed = DateTime.parse(isoDate);
      return '${parsed.month}/${parsed.day}/${parsed.year}';
    } catch (e) {
      return '${DateTime.now().month}/${DateTime.now().day}/${DateTime.now().year}';
    }
  }
}

class Expense {
  final int id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final String? notes;
  final String? source;
  final int userId;

  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.userId,
    this.notes,
    this.source,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['expense_id'] ?? 0,
      title: json['title'],
      amount: json['amount'] is String 
          ? double.parse(json['amount'])
          : json['amount'].toDouble(),
      category: json['category'],
      date: DateTime.parse(json['date']),
      userId: json['user_id'],
      notes: json['notes'],
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String().split('T')[0],
      'user_id': userId,
      'notes': notes,
      'source': source,
    };
  }
}

class BankMessage {
  final String content;
  final DateTime date;
  final String merchant;
  final double amount;

  BankMessage(this.content, this.date, this.merchant, this.amount);
}

class SettingsItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  SettingsItem(this.title, this.subtitle, this.icon, this.onTap);
}