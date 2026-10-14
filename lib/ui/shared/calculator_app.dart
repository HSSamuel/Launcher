import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../states/theme_state.dart';
import '../../states/apps_state.dart';
import '../../states/desktop_state.dart';
import '../../services/native_bridge.dart'; 

enum CalcMode { standard, scientific, date, currency }

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({Key? key}) : super(key: key);

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focusNode = FocusNode();
  
  CalcMode _currentMode = CalcMode.standard;
  bool _showHistory = false;
  final List<Map<String, String>> _history = [];
  
  // CRITICAL FIX: The memory stack for holding bracket states
  final List<Map<String, dynamic>> _parenStack = [];

  String _currentEntry = '0';
  String _operation = '';
  double _firstOperand = 0;
  bool _isResult = false;
  String _liveEquation = '';

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now().add(const Duration(days: 30));

  String _fromCurrency = 'NGN';
  String _toCurrency = 'USD';
  double _currencyAmount = 0;
  bool _isTopActive = true; 
  
  bool _isUpdatingRates = false;
  DateTime _lastRatesUpdate = DateTime.now().subtract(const Duration(days: 2));

  final Map<String, Map<String, dynamic>> _currencies = {
    'USD': {'name': 'United States - Dollar', 'symbol': '\$', 'rate': 1.0},
    'NGN': {'name': 'Nigeria - Naira', 'symbol': '₦', 'rate': 1550.0},
    'EUR': {'name': 'Europe - Euro', 'symbol': '€', 'rate': 0.92},
    'GBP': {'name': 'United Kingdom - Pound', 'symbol': '£', 'rate': 0.79},
    'JPY': {'name': 'Japan - Yen', 'symbol': '¥', 'rate': 150.0},
    'CAD': {'name': 'Canada - Dollar', 'symbol': 'C\$', 'rate': 1.35},
    'AUD': {'name': 'Australia - Dollar', 'symbol': 'A\$', 'rate': 1.53},
  };

  @override
  void initState() {
    super.initState();
    _loadCachedRates(); 
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _showToast(String message) {
  if (!mounted) return;
  
  final screenHeight = MediaQuery.of(context).size.height;
  
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13), textAlign: TextAlign.center), 
      duration: const Duration(seconds: 2), 
      behavior: SnackBarBehavior.floating, 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      margin: EdgeInsets.only(
        bottom: screenHeight / 2 - 24,
        left: 32,
        right: 32,
      ),
    )
  );
}

  Future<void> _loadCachedRates() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedStr = prefs.getString('cached_currency_rates');
    final lastUpdateStr = prefs.getString('last_currency_update');

    if (cachedStr != null) {
      try {
        final rates = jsonDecode(cachedStr) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            for (String key in _currencies.keys) {
              if (rates.containsKey(key)) {
                _currencies[key]!['rate'] = (rates[key] as num).toDouble();
              }
            }
            if (lastUpdateStr != null) _lastRatesUpdate = DateTime.parse(lastUpdateStr);
          });
        }
      } catch (_) {}
    }
    _fetchLiveRates(silent: true);
  }

  Future<void> _fetchLiveRates({bool silent = false}) async {
    if (!mounted) return;
    
    if (silent && DateTime.now().difference(_lastRatesUpdate).inHours < 12) {
       return;
    }
    
    setState(() => _isUpdatingRates = true);
    
    try {
      final res = await http.get(Uri.parse('https://open.er-api.com/v6/latest/USD')).timeout(const Duration(seconds: 8));
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rates = data['rates'] as Map<String, dynamic>;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_currency_rates', jsonEncode(rates));
        await prefs.setString('last_currency_update', DateTime.now().toIso8601String());

        if (mounted) {
          setState(() {
            for (String key in _currencies.keys) {
              if (rates.containsKey(key)) {
                _currencies[key]!['rate'] = (rates[key] as num).toDouble();
              }
            }
            _lastRatesUpdate = DateTime.now();
          });
          if (!silent) _showToast('Exchange rates synced successfully');
        }
      }
    } catch (_) {
      if (mounted && !silent) _showToast('Failed to update rates. Using cached data.');
    }
    if (mounted) setState(() => _isUpdatingRates = false);
  }

  void _vibrate() {
    if (context.read<DesktopState>().gestureHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  void _onKeyPress(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey.keyLabel;
      if (RegExp(r'^[0-9]$').hasMatch(key)) _onNumberPressed(key);
      else if (key == '+') _onOperatorPressed('+');
      else if (key == '-') _onOperatorPressed('-');
      else if (key == '*' || key == 'x') _onOperatorPressed('×');
      else if (key == '/') _onOperatorPressed('÷');
      else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter || key == '=') _calculate();
      else if (event.logicalKey == LogicalKeyboardKey.backspace) _backspace();
      else if (event.logicalKey == LogicalKeyboardKey.escape) _clear();
      else if (key == '.' || key == ',') _onNumberPressed('.');
    }
  }

  void _updateLiveEquation() {
    if (_operation.isNotEmpty && !_isResult) {
      _liveEquation = '${_formatWithCommas(_formatNumber(_firstOperand))} $_operation ${_formatWithCommas(_currentEntry)}';
    }
  }

  void _onNumberPressed(String num) {
    _vibrate();
    setState(() {
      if (_currentMode == CalcMode.currency) {
         if (_isResult) { 
           _currentEntry = num == '.' ? '0.' : num; 
           _isResult = false; 
         } else { 
           if (num == '.') {
             if (!_currentEntry.contains('.')) _currentEntry += '.';
           } else {
             _currentEntry = _currentEntry == '0' ? num : _currentEntry + num; 
           }
         }
         _currencyAmount = double.tryParse(_currentEntry) ?? 0;
         return;
      }

      if (_isResult) {
        _currentEntry = num == '.' ? '0.' : num;
        _isResult = false;
        if (_operation.isEmpty) _liveEquation = '';
      } else {
        if (num == '.') {
          if (!_currentEntry.contains('.')) _currentEntry += '.';
        } else {
          _currentEntry = _currentEntry == '0' ? num : _currentEntry + num;
        }
      }
      _updateLiveEquation();
    });
  }

  void _onOperatorPressed(String op) {
    _vibrate();
    setState(() {
      if (_operation.isNotEmpty && !_isResult) {
        _calculate(chainOperation: op);
      } else {
        _firstOperand = double.tryParse(_currentEntry) ?? 0;
      }
      _operation = op;
      _liveEquation = '${_formatWithCommas(_formatNumber(_firstOperand))} $op';
      _isResult = true;
    });
  }

  void _calculate({String? chainOperation}) {
    _vibrate();
    if (_operation.isEmpty) return;
    
    double secondOperand = double.tryParse(_currentEntry) ?? 0;
    double result = 0;
    
    switch (_operation) {
      case '+': result = _firstOperand + secondOperand; break;
      case '-': result = _firstOperand - secondOperand; break;
      case '×': result = _firstOperand * secondOperand; break;
      case '÷': 
        if (secondOperand == 0) {
          setState(() { _currentEntry = "Can't divide by zero"; _isResult = true; _operation = ''; _liveEquation = ''; });
          return;
        }
        result = _firstOperand / secondOperand; 
        break;
      case 'x^y': result = math.pow(_firstOperand, secondOperand).toDouble(); break;
      case 'mod': 
        if (secondOperand == 0) {
          setState(() { _currentEntry = "Can't divide by zero"; _isResult = true; _operation = ''; _liveEquation = ''; });
          return;
        }
        result = _firstOperand % secondOperand; 
        break;
    }

    setState(() {
      final eqStr = '${_formatWithCommas(_formatNumber(_firstOperand))} $_operation ${_formatWithCommas(_formatNumber(secondOperand))} =';
      _currentEntry = _formatNumber(result);
      _history.insert(0, {'equation': eqStr, 'result': _formatWithCommas(_currentEntry)});
      
      if (chainOperation != null) {
        _firstOperand = result;
        _operation = chainOperation;
        _liveEquation = '${_formatWithCommas(_formatNumber(result))} $chainOperation';
      } else {
        _liveEquation = eqStr;
        _operation = '';
        _firstOperand = result;
      }
      _isResult = true;
    });
  }

  void _applyAdvancedOperation(String op) {
    _vibrate();
    if (op == 'π') { setState(() { _currentEntry = math.pi.toStringAsFixed(8); _isResult = true; }); return; }
    if (op == 'e') { setState(() { _currentEntry = math.e.toStringAsFixed(8); _isResult = true; }); return; }

    // CRITICAL FIX: Handle +/- as string manipulation to preserve partial decimals
    if (op == '+/-') {
      setState(() {
        if (_currentEntry == '0' || _currentEntry == '0.') return; 
        if (_currentEntry.startsWith('-')) {
          _currentEntry = _currentEntry.substring(1);
        } else {
          _currentEntry = '-$_currentEntry';
        }
        _updateLiveEquation();
      });
      return;
    }

    // CRITICAL FIX: Push current state to memory when opening a bracket
    if (op == '(') {
      setState(() {
        _parenStack.add({
          'operand': _firstOperand,
          'operation': _operation,
          'equation': _liveEquation,
        });
        _firstOperand = 0;
        _operation = '';
        _currentEntry = '0';
        _isResult = false;
        _liveEquation = _liveEquation.isEmpty ? '(' : '$_liveEquation (';
      });
      return;
    }

    // CRITICAL FIX: Calculate inner math and pop previous state on closing bracket
    if (op == ')') {
      setState(() {
        if (_parenStack.isEmpty) return;
        
        // Calculate whatever is inside the parenthesis first
        if (_operation.isNotEmpty) _calculate();
        
        // Restore the state from before the '(' was pressed
        final prevState = _parenStack.removeLast();
        double innerResult = double.tryParse(_currentEntry) ?? 0;

        _firstOperand = prevState['operand'];
        _operation = prevState['operation'];
        String prevEq = prevState['equation'];

        _currentEntry = _formatNumber(innerResult);
        _liveEquation = prevEq.isEmpty ? '(${_formatWithCommas(_currentEntry)})' : '$prevEq (${_formatWithCommas(_currentEntry)})';
        _isResult = true;
        
        // CRITICAL FIX: Immediately execute the restored outer operation against the inner result
        if (_operation.isNotEmpty) {
           _calculate();
        }
      });
      return;
    }

    double val = double.tryParse(_currentEntry) ?? 0;
    double result = 0;
    String eq = '';

    setState(() {
      switch (op) {
        case '1/x':
          if (val == 0) { _currentEntry = "Can't divide by zero"; _isResult = true; return; }
          result = 1 / val; eq = '1/(${_formatWithCommas(_formatNumber(val))})'; break;
        case 'x²': result = val * val; eq = 'sqr(${_formatWithCommas(_formatNumber(val))})'; break;
        case '√x':
          if (val < 0) { _currentEntry = "Invalid input"; _isResult = true; return; }
          result = math.sqrt(val); eq = '√(${_formatWithCommas(_formatNumber(val))})'; break;
        case '%': result = val / 100; eq = '${_formatWithCommas(_formatNumber(val))}%'; break;
        case '|x|': result = val.abs(); eq = '|${_formatWithCommas(_formatNumber(val))}|'; break;
        case 'exp': result = math.exp(val); eq = 'exp(${_formatWithCommas(_formatNumber(val))})'; break;
        case '10^x': result = math.pow(10, val).toDouble(); eq = '10^(${_formatWithCommas(_formatNumber(val))})'; break;
        case 'log': 
          if (val <= 0) { _currentEntry = "Invalid input"; _isResult = true; return; }
          result = math.log(val) / math.ln10; eq = 'log(${_formatWithCommas(_formatNumber(val))})'; break;
        case 'ln': 
          if (val <= 0) { _currentEntry = "Invalid input"; _isResult = true; return; }
          result = math.log(val); eq = 'ln(${_formatWithCommas(_formatNumber(val))})'; break;
        case 'n!': 
          if (val < 0 || val != val.toInt() || val > 170) { _currentEntry = "Invalid input"; _isResult = true; return; }
          result = 1; for(int i=2; i<=val.toInt(); i++) { result *= i; } eq = 'fact(${_formatWithCommas(_formatNumber(val))})'; break;
      }

      _currentEntry = _formatNumber(result);
      _liveEquation = eq;
      _history.insert(0, {'equation': eq, 'result': _formatWithCommas(_currentEntry)});
      _isResult = true;
    });
  }

  void _clear() {
    _vibrate();
    setState(() { 
      _currentEntry = '0'; 
      _liveEquation = ''; 
      _operation = ''; 
      _firstOperand = 0; 
      _isResult = false; 
      _currencyAmount = 0; 
      // CRITICAL FIX: Clear the parenthesis memory stack when resetting the calculator
      _parenStack.clear(); 
    });
  }

  void _clearEntry() {
    _vibrate();
    setState(() { _currentEntry = '0'; _currencyAmount = 0; _updateLiveEquation(); });
  }

  void _backspace() {
    _vibrate();
    setState(() {
      if (_isResult) return;
      if (_currentEntry.length > 1) _currentEntry = _currentEntry.substring(0, _currentEntry.length - 1);
      else _currentEntry = '0';
      _currencyAmount = double.tryParse(_currentEntry) ?? 0;
      _updateLiveEquation();
    });
  }

  String _formatNumber(double num) {
  // CRITICAL FIX: Guard against Infinity or Not-a-Number crashes before parsing
  if (num.isInfinite || num.isNaN) return "Error";
  
  if (num == num.toInt()) return num.toInt().toString();
  String str = num.toString();
  if (str.length > 12) return num.toStringAsPrecision(10);
  return str;
}

  String _formatCurrencyAmount(double num) {
    if (num == 0) return '0';
    if (num == num.toInt()) return num.toInt().toString();
    if (num < 0.01 && num > -0.01) return num.toStringAsFixed(6); 
    String formatted = num.toStringAsFixed(2);
    if (formatted.endsWith('.00')) return formatted.substring(0, formatted.length - 3);
    return formatted;
  }

  String _formatWithCommas(String str) {
    if (str.isEmpty || str.contains('Invalid') || str.contains('zero')) return str;
    List<String> parts = str.split('.');
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String mathFunc(Match match) => '${match[1]},';
    parts[0] = parts[0].replaceAllMapped(reg, mathFunc);
    return parts.join('.');
  }

  Future<void> _pickDate(bool isFrom) async {
    _vibrate();
    final themeState = context.read<ThemeState>();
    final isDark = themeState.isDarkMode;
    
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark 
                ? ColorScheme.dark(
                    primary: themeState.foregroundAccentColor,
                    onPrimary: themeState.textOnAccentColor,
                    surface: const Color(0xFF2B2B2B),
                  )
                : ColorScheme.light(
                    primary: themeState.foregroundAccentColor,
                    onPrimary: themeState.textOnAccentColor,
                    surface: Colors.white,
                  ),
          ),
          child: child!,
        );
      }
    );
    if (picked != null) {
      setState(() {
        if (isFrom) _fromDate = picked;
        else _toDate = picked;
      });
    }
  }

  String _getDateDiffString() {
    DateTime from = _fromDate;
    DateTime to = _toDate;
    if (from.isAfter(to)) { final temp = from; from = to; to = temp; }
    
    int years = to.year - from.year;
    int months = to.month - from.month;
    int days = to.day - from.day;
    
    if (days < 0) {
      months -= 1;
      int prevMonth = to.month == 1 ? 12 : to.month - 1;
      int prevYear = to.month == 1 ? to.year - 1 : to.year;
      final prevMonthDays = DateTime(prevYear, prevMonth + 1, 0).day;
      days += prevMonthDays;
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    
    int weeks = days ~/ 7;
    days = days % 7;

    List<String> parts = [];
    if (years > 0) parts.add('$years years');
    if (months > 0) parts.add('$months months');
    if (weeks > 0) parts.add('$weeks weeks');
    if (days > 0) parts.add('$days days');

    final totalDays = to.difference(from).inDays;
return parts.isEmpty 
    ? 'Same dates\nTotal: 0 days' 
    : '${parts.join(', ')}\nTotal: $totalDays days';
  }

  String _formatDateFull(DateTime d) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _buildDrawer(Color bgColor, Color displayColor) {
    return Drawer(
      backgroundColor: bgColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(child: Text('Calculator', style: TextStyle(color: displayColor, fontSize: 20, fontWeight: FontWeight.bold))),
          _buildDrawerItem('Standard', Icons.calculate_outlined, CalcMode.standard, displayColor),
          _buildDrawerItem('Scientific', Icons.science_outlined, CalcMode.scientific, displayColor),
          _buildDrawerItem('Date Calculation', Icons.calendar_month_outlined, CalcMode.date, displayColor),
          _buildDrawerItem('Currency', Icons.monetization_on_outlined, CalcMode.currency, displayColor),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(String title, IconData icon, CalcMode mode, Color textColor) {
    final isSelected = _currentMode == mode;
    final themeState = context.read<ThemeState>();
    return ListTile(
      leading: Icon(icon, color: isSelected ? themeState.foregroundAccentColor : textColor.withOpacity(0.7)),
      title: Text(title, style: TextStyle(color: isSelected ? themeState.foregroundAccentColor : textColor, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      onTap: () {
        _vibrate();
        setState(() { _currentMode = mode; _clear(); });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildKeypadButton(String label, Color bgColor, Color textColor, ThemeState themeState, {bool isAccent = false}) {
    if (label.isEmpty) return Expanded(child: const SizedBox.shrink());
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Material(
          color: isAccent ? themeState.currentAccentColor : bgColor,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () {
              FocusScope.of(context).requestFocus(_focusNode);
              if (RegExp(r'^[0-9]$').hasMatch(label) || label == '.') _onNumberPressed(label);
              else if (['+', '-', '×', '÷', 'x^y', 'mod'].contains(label)) _onOperatorPressed(label);
              else if (label == '=') _calculate();
              else if (label == 'C') _clear();
              else if (label == 'CE') _clearEntry();
              else if (label == '⌫') _backspace();
              else _applyAdvancedOperation(label);
            },
            borderRadius: BorderRadius.circular(6),
            hoverColor: isAccent ? Colors.white24 : (themeState.isDarkMode ? Colors.white10 : Colors.black.withOpacity(0.05)),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: RegExp(r'^[0-9]$').hasMatch(label) ? 22 : 18,
                      fontWeight: RegExp(r'^[0-9]$').hasMatch(label) || isAccent ? FontWeight.w600 : FontWeight.w400,
                      color: isAccent ? themeState.textOnAccentColor : textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardKeypad(Color numBg, Color opBg, Color textCol, ThemeState theme) {
    return Column(
      children: [
        Expanded(child: Row(children: [ _buildKeypadButton('%', opBg, textCol, theme), _buildKeypadButton('CE', opBg, textCol, theme), _buildKeypadButton('C', opBg, textCol, theme), _buildKeypadButton('⌫', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('1/x', opBg, textCol, theme), _buildKeypadButton('x²', opBg, textCol, theme), _buildKeypadButton('√x', opBg, textCol, theme), _buildKeypadButton('÷', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('7', numBg, textCol, theme), _buildKeypadButton('8', numBg, textCol, theme), _buildKeypadButton('9', numBg, textCol, theme), _buildKeypadButton('×', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('4', numBg, textCol, theme), _buildKeypadButton('5', numBg, textCol, theme), _buildKeypadButton('6', numBg, textCol, theme), _buildKeypadButton('-', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('1', numBg, textCol, theme), _buildKeypadButton('2', numBg, textCol, theme), _buildKeypadButton('3', numBg, textCol, theme), _buildKeypadButton('+', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('+/-', numBg, textCol, theme), _buildKeypadButton('0', numBg, textCol, theme), _buildKeypadButton('.', numBg, textCol, theme), _buildKeypadButton('=', opBg, textCol, theme, isAccent: true) ])),
      ],
    );
  }

  Widget _buildScientificKeypad(Color numBg, Color opBg, Color textCol, ThemeState theme) {
    return Column(
      children: [
        Expanded(child: Row(children: [ _buildKeypadButton('2nd', opBg, textCol, theme), _buildKeypadButton('π', opBg, textCol, theme), _buildKeypadButton('e', opBg, textCol, theme), _buildKeypadButton('C', opBg, textCol, theme), _buildKeypadButton('⌫', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('x²', opBg, textCol, theme), _buildKeypadButton('1/x', opBg, textCol, theme), _buildKeypadButton('|x|', opBg, textCol, theme), _buildKeypadButton('exp', opBg, textCol, theme), _buildKeypadButton('mod', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('√x', opBg, textCol, theme), _buildKeypadButton('(', opBg, textCol, theme), _buildKeypadButton(')', opBg, textCol, theme), _buildKeypadButton('n!', opBg, textCol, theme), _buildKeypadButton('÷', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('x^y', opBg, textCol, theme), _buildKeypadButton('7', numBg, textCol, theme), _buildKeypadButton('8', numBg, textCol, theme), _buildKeypadButton('9', numBg, textCol, theme), _buildKeypadButton('×', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('10^x', opBg, textCol, theme), _buildKeypadButton('4', numBg, textCol, theme), _buildKeypadButton('5', numBg, textCol, theme), _buildKeypadButton('6', numBg, textCol, theme), _buildKeypadButton('-', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('log', opBg, textCol, theme), _buildKeypadButton('1', numBg, textCol, theme), _buildKeypadButton('2', numBg, textCol, theme), _buildKeypadButton('3', numBg, textCol, theme), _buildKeypadButton('+', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('ln', opBg, textCol, theme), _buildKeypadButton('+/-', numBg, textCol, theme), _buildKeypadButton('0', numBg, textCol, theme), _buildKeypadButton('.', numBg, textCol, theme), _buildKeypadButton('=', opBg, textCol, theme, isAccent: true) ])),
      ],
    );
  }

  Widget _buildCurrencyKeypad(Color numBg, Color opBg, Color textCol, ThemeState theme) {
    return Column(
      children: [
        Expanded(child: Row(children: [ _buildKeypadButton('', opBg, textCol, theme), _buildKeypadButton('CE', opBg, textCol, theme), _buildKeypadButton('⌫', opBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('7', numBg, textCol, theme), _buildKeypadButton('8', numBg, textCol, theme), _buildKeypadButton('9', numBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('4', numBg, textCol, theme), _buildKeypadButton('5', numBg, textCol, theme), _buildKeypadButton('6', numBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('1', numBg, textCol, theme), _buildKeypadButton('2', numBg, textCol, theme), _buildKeypadButton('3', numBg, textCol, theme) ])),
        Expanded(child: Row(children: [ _buildKeypadButton('', numBg, textCol, theme), _buildKeypadButton('0', numBg, textCol, theme), _buildKeypadButton('.', numBg, textCol, theme) ])),
      ],
    );
  }

  Widget _buildDateCalculator(Color displayColor, Color secondaryTextColor) {
    final diffParts = _getDateDiffString().split('\n');
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickDate(true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatDateFull(_fromDate), style: TextStyle(color: displayColor, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Icon(Icons.calendar_today, color: displayColor, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('To', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _pickDate(false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatDateFull(_toDate), style: TextStyle(color: displayColor, fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Icon(Icons.calendar_today, color: displayColor, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('Difference', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
          const SizedBox(height: 8),
          Text(diffParts[0], style: TextStyle(color: displayColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(diffParts[1], style: TextStyle(color: secondaryTextColor, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCurrencyBlock({
    required bool isActive,
    required String currencyKey,
    required String amountText,
    required ValueChanged<String?> onChanged,
    required VoidCallback onTap,
    required ThemeState theme,
    required Color displayColor,
    required Color secondaryTextColor,
  }) {
    final cur = _currencies[currencyKey]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: isActive ? theme.currentAccentColor : Colors.transparent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(cur['symbol'], style: TextStyle(color: secondaryTextColor, fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft, 
                    fit: BoxFit.scaleDown, 
                    child: Text(_formatWithCommas(amountText), style: TextStyle(color: displayColor, fontSize: 42, fontWeight: FontWeight.bold))
                  )
                ),
              ],
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currencyKey,
                dropdownColor: theme.isDarkMode ? const Color(0xFF2B2B2B) : Colors.white,
                icon: Icon(Icons.keyboard_arrow_down, color: displayColor, size: 16),
                style: TextStyle(color: displayColor, fontSize: 14),
                isDense: true,
                onChanged: onChanged,
                items: _currencies.keys.map((k) => DropdownMenuItem(value: k, child: Text(_currencies[k]!['name']))).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyCalculator(Color displayColor, Color secondaryTextColor, ThemeState theme) {
    double toRate = _currencies[_toCurrency]?['rate'] ?? 1.0;
    double fromRate = _currencies[_fromCurrency]?['rate'] ?? 1.0;
    if (toRate <= 0) toRate = 1.0;
    if (fromRate <= 0) fromRate = 1.0;

    double topAmount = _isTopActive 
        ? _currencyAmount 
        : (_currencyAmount / toRate) * fromRate;
        
    double bottomAmount = !_isTopActive 
        ? _currencyAmount 
        : (_currencyAmount / fromRate) * toRate;
    
    final lastUpdatedStr = '${_lastRatesUpdate.month}/${_lastRatesUpdate.day}/${_lastRatesUpdate.year} ${_lastRatesUpdate.hour % 12 == 0 ? 12 : _lastRatesUpdate.hour % 12}:${_lastRatesUpdate.minute.toString().padLeft(2, '0')} ${_lastRatesUpdate.hour >= 12 ? 'PM' : 'AM'}';
        
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrencyBlock(
            isActive: _isTopActive,
            currencyKey: _fromCurrency,
            amountText: _isTopActive ? _currentEntry : _formatCurrencyAmount(topAmount),
            onChanged: (v) { _vibrate(); setState(() => _fromCurrency = v!); },
            onTap: () { 
              _vibrate(); 
              setState(() { _isTopActive = true; _currentEntry = _formatCurrencyAmount(topAmount); _currencyAmount = topAmount; }); 
            },
            theme: theme, displayColor: displayColor, secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 16),
          _buildCurrencyBlock(
            isActive: !_isTopActive,
            currencyKey: _toCurrency,
            amountText: !_isTopActive ? _currentEntry : _formatCurrencyAmount(bottomAmount),
            onChanged: (v) { _vibrate(); setState(() => _toCurrency = v!); },
            onTap: () { 
              _vibrate(); 
              setState(() { _isTopActive = false; _currentEntry = _formatCurrencyAmount(bottomAmount); _currencyAmount = bottomAmount; }); 
            },
            theme: theme, displayColor: displayColor, secondaryTextColor: secondaryTextColor,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1 $_fromCurrency = ${(toRate / fromRate).toStringAsFixed(4)} $_toCurrency', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Updated $lastUpdatedStr', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    _vibrate();
                    _fetchLiveRates();
                  }, 
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Update rates', style: TextStyle(color: theme.foregroundAccentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                      if (_isUpdatingRates) ...[
                        const SizedBox(width: 8),
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: theme.foregroundAccentColor)),
                      ]
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final isDark = themeState.isDarkMode;

    final bgColor = isDark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
    final displayColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white54 : Colors.black54;
    
    final numBgColor = isDark ? const Color(0xFF333333) : Colors.white;
    final opBgColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE6E6E6);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) { _onKeyPress(event); return KeyEventResult.handled; },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bgColor,
        drawer: _buildDrawer(bgColor, displayColor),
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.menu, color: displayColor, size: 20), onPressed: () { _vibrate(); _scaffoldKey.currentState?.openDrawer(); }, tooltip: 'Menu'),
                      const Spacer(),
                      if (_currentMode == CalcMode.standard || _currentMode == CalcMode.scientific)
                        IconButton(icon: Icon(Icons.history, color: displayColor, size: 20), onPressed: () { _vibrate(); setState(() => _showHistory = !_showHistory); }, tooltip: 'History'),
                    ],
                  ),
                ),
                
                if (_currentMode == CalcMode.standard || _currentMode == CalcMode.scientific)
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          reverse: true,
                          child: Container(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                            alignment: Alignment.bottomRight,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_liveEquation, style: TextStyle(color: secondaryTextColor, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(_formatWithCommas(_currentEntry), style: TextStyle(color: displayColor, fontSize: 48, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                  ),

                if (_currentMode == CalcMode.date) Expanded(flex: 4, child: _buildDateCalculator(displayColor, secondaryTextColor)),
                if (_currentMode == CalcMode.currency) Expanded(flex: 4, child: _buildCurrencyCalculator(displayColor, secondaryTextColor, themeState)),

                if (_currentMode != CalcMode.date)
                  Expanded(
                    flex: _currentMode == CalcMode.scientific ? 6 : 5,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: _currentMode == CalcMode.scientific
                          ? _buildScientificKeypad(numBgColor, opBgColor, displayColor, themeState)
                          : _currentMode == CalcMode.currency
                              ? _buildCurrencyKeypad(numBgColor, opBgColor, displayColor, themeState)
                              : _buildStandardKeypad(numBgColor, opBgColor, displayColor, themeState),
                    ),
                  ),
              ],
            ),

            if (_showHistory && (_currentMode == CalcMode.standard || _currentMode == CalcMode.scientific))
              Positioned(
                top: 48, right: 0, bottom: 0, width: 250,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2B2B2B).withOpacity(0.95) : Colors.white.withOpacity(0.95),
                    border: Border(left: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(-2, 0))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('History', style: TextStyle(color: displayColor, fontSize: 16, fontWeight: FontWeight.bold)),
                            if (_history.isNotEmpty)
                              InkWell(onTap: () { _vibrate(); setState(() => _history.clear()); }, child: Icon(Icons.delete_outline, color: secondaryTextColor, size: 18))
                          ],
                        ),
                      ),
                      Expanded(
                        child: _history.isEmpty
                          ? Center(child: Text("There's no history yet", style: TextStyle(color: secondaryTextColor, fontSize: 13)))
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: _history.length,
                              itemBuilder: (context, index) {
                                final item = _history[index];
                                return InkWell(
                                  onTap: () {
                                    _vibrate();
                                    setState(() { _currentEntry = item['result']!.replaceAll(',', ''); _liveEquation = ''; _operation = ''; _isResult = true; _showHistory = false; });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(item['equation']!, style: TextStyle(color: secondaryTextColor, fontSize: 12)), const SizedBox(height: 4),
                                        Text(item['result']!, style: TextStyle(color: displayColor, fontSize: 18, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}