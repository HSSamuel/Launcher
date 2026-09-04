import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({Key? key}) : super(key: key);

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  String _leftOperand = "0";
  String _operator = "";
  String _rightOperand = "";
  String _history = "";

  void _buttonPressed(String buttonText) {
    setState(() {
      if (buttonText == "C") {
        _leftOperand = "0";
        _operator = "";
        _rightOperand = "";
        _history = "";
      } else if (buttonText == "⌫") {
        if (_rightOperand.isNotEmpty) {
          _rightOperand = _rightOperand.substring(0, _rightOperand.length - 1);
        } else if (_operator.isNotEmpty) {
          _operator = "";
        } else if (_leftOperand.length > 1) {
          _leftOperand = _leftOperand.substring(0, _leftOperand.length - 1);
        } else {
          _leftOperand = "0";
        }
      } else if (buttonText == "+" || buttonText == "-" || buttonText == "x" || buttonText == "/") {
        if (_rightOperand.isNotEmpty) {
          _calculateResult();
        }
        if (_leftOperand != "Error") {
          _operator = buttonText;
        }
      } else if (buttonText == "=") {
        if (_operator.isNotEmpty && _rightOperand.isNotEmpty) {
          _history = "$_leftOperand $_operator $_rightOperand =";
          _calculateResult();
          _operator = "";
          _rightOperand = "";
        }
      } else {
        // Handle numbers and decimal points
        if (_operator.isEmpty) {
          if (_leftOperand == "Error") _leftOperand = "0";
          if (buttonText == "." && _leftOperand.contains(".")) return;
          if (_leftOperand == "0" && buttonText != ".") {
            _leftOperand = buttonText;
          } else {
            _leftOperand += buttonText;
          }
        } else {
          if (buttonText == "." && _rightOperand.contains(".")) return;
          if (_rightOperand == "0" && buttonText != ".") {
            _rightOperand = buttonText;
          } else {
            _rightOperand += buttonText;
          }
        }
      }
    });
  }

  void _calculateResult() {
    double num1 = double.tryParse(_leftOperand) ?? 0.0;
    double num2 = double.tryParse(_rightOperand) ?? 0.0;
    double res = 0.0;
    
    if (_operator == "+") res = num1 + num2;
    if (_operator == "-") res = num1 - num2;
    if (_operator == "x") res = num1 * num2;
    if (_operator == "/") {
      if (num2 == 0) {
        _leftOperand = "Error";
        return;
      }
      res = num1 / num2;
    }
    
    _leftOperand = res.toString();
    if (_leftOperand.endsWith(".0")) {
      _leftOperand = _leftOperand.substring(0, _leftOperand.length - 2);
    }
  }

  // FIX: Dynamically builds the visible string so users can see the full equation being typed
  String get _displayText {
    String text = _leftOperand;
    if (_operator.isNotEmpty) {
      text += " $_operator";
      if (_rightOperand.isNotEmpty) {
        text += " $_rightOperand";
      }
    }
    return text;
  }

  Widget _buildButton(String text, bool isDark, {Color? textColor, Color? bgColor, int flexWidth = 1}) {
    final defaultBg = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    final defaultBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);
    final defaultText = isDark ? Colors.white : Colors.black87;

    return Expanded(
      flex: flexWidth,
      child: Container(
        margin: const EdgeInsets.all(3.0),
        child: InkWell(
          onTap: () => _buttonPressed(text),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor ?? defaultBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: defaultBorder, width: 1),
            ),
            child: Center(
              child: Text(
                text, 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: textColor ?? defaultText)
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LauncherState>();
    final isDark = state.isDarkMode;
    
    // FIX: Theme-aware colors for light and dark modes
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final operatorColor = isDark ? Colors.blueAccent.shade100 : Colors.blueAccent.shade700;
    final equalBgColor = isDark ? Colors.blueAccent.withOpacity(0.3) : Colors.blueAccent.withOpacity(0.15);
    final equalTextColor = isDark ? Colors.blueAccent.shade100 : Colors.blueAccent.shade700;

    return Container(
      // FIX: Seamlessly blends with the parent AppWindow background, erasing the white padding
      color: Colors.transparent, 
      child: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: Icon(Icons.close, color: subTextColor, size: 20),
              onPressed: () => state.closeApp('calculator'),
            ),
          ),
          
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomRight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_history, style: TextStyle(fontSize: 16, color: subTextColor)),
                    const SizedBox(height: 4),
                    Text(_displayText, style: TextStyle(fontSize: 54, fontWeight: FontWeight.w600, color: textColor)),
                  ],
                ),
              ),
            ),
          ),
          
          // Keypad Area
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                children: [
                  Expanded(child: Row(children: [_buildButton("C", isDark, textColor: Colors.redAccent), _buildButton("⌫", isDark, textColor: operatorColor), _buildButton("/", isDark, textColor: operatorColor), _buildButton("x", isDark, textColor: operatorColor)])),
                  Expanded(child: Row(children: [_buildButton("7", isDark), _buildButton("8", isDark), _buildButton("9", isDark), _buildButton("-", isDark, textColor: operatorColor)])),
                  Expanded(child: Row(children: [_buildButton("4", isDark), _buildButton("5", isDark), _buildButton("6", isDark), _buildButton("+", isDark, textColor: operatorColor)])),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              Expanded(child: Row(children: [_buildButton("1", isDark), _buildButton("2", isDark), _buildButton("3", isDark)])),
                              Expanded(child: Row(children: [_buildButton("0", isDark, flexWidth: 2), _buildButton(".", isDark)])),
                            ],
                          ),
                        ),
                        _buildButton("=", isDark, bgColor: equalBgColor, textColor: equalTextColor, flexWidth: 1), 
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}