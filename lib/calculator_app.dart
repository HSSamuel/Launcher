import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'launcher_state.dart';

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({Key? key}) : super(key: key);

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  String _history = "";
  String _output = "0";
  double _num1 = 0.0;
  String _operand = "";
  bool _isNewEquation = true;

  void _buttonPressed(String buttonText) {
    setState(() {
      if (buttonText == "C") {
        _output = "0";
        _history = "";
        _num1 = 0.0;
        _operand = "";
        _isNewEquation = true;
      } else if (buttonText == "⌫") {
        if (_output.length > 1) {
          _output = _output.substring(0, _output.length - 1);
        } else {
          _output = "0";
          _isNewEquation = true;
        }
      } else if (buttonText == "+" || buttonText == "-" || buttonText == "x" || buttonText == "/") {
        if (_output.isNotEmpty) {
          _num1 = double.parse(_output);
          _operand = buttonText;
          _history = "${_output.endsWith('.0') ? _output.replaceAll('.0', '') : _output} $_operand";
          _isNewEquation = true;
        }
      } else if (buttonText == "=") {
        if (_operand.isNotEmpty && _output.isNotEmpty) {
          double num2 = double.parse(_output);
          _history = "$_history ${_output.endsWith('.0') ? _output.replaceAll('.0', '') : _output} =";
          
          double result = 0.0;
          if (_operand == "+") result = _num1 + num2;
          if (_operand == "-") result = _num1 - num2;
          if (_operand == "x") result = _num1 * num2;
          if (_operand == "/") result = num2 != 0 ? _num1 / num2 : 0.0;
          
          _output = result.toString();
          if (_output.endsWith(".0")) {
            _output = _output.substring(0, _output.length - 2);
          }
          _operand = "";
          _isNewEquation = true;
        }
      } else {
        if (_isNewEquation) {
          _output = buttonText == "." ? "0." : buttonText;
          _isNewEquation = false;
        } else {
          if (buttonText == "." && _output.contains(".")) return;
          _output += buttonText;
        }
      }
    });
  }

  // FIX: Converted to Pure Expanded/Flex to completely eliminate RenderFlex Overflows
  Widget _buildButton(String text, {Color? textColor, Color? bgColor, int flexWidth = 1}) {
    return Expanded(
      flex: flexWidth,
      child: Container(
        margin: const EdgeInsets.all(3.0),
        child: InkWell(
          onTap: () => _buttonPressed(text),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color: bgColor ?? Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
            ),
            child: Center(
              child: Text(
                text, 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: textColor ?? Colors.white)
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black, // Strict Black and White Theme
      child: Column(
        children: [
          // FIX: Close icon at the edge
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => context.read<LauncherState>().closeApp('calculator'),
            ),
          ),
          
          // FIX: Display Area wrapped in Expanded/FittedBox to prevent vertical overflow
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
                    Text(_history, style: const TextStyle(fontSize: 16, color: Colors.white54)),
                    const SizedBox(height: 4),
                    Text(_output, style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w600, color: Colors.white)),
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
                  Expanded(child: Row(children: [_buildButton("C", textColor: Colors.white), _buildButton("⌫", textColor: Colors.white), _buildButton("/", textColor: Colors.white), _buildButton("x", textColor: Colors.white)])),
                  Expanded(child: Row(children: [_buildButton("7"), _buildButton("8"), _buildButton("9"), _buildButton("-", textColor: Colors.white)])),
                  Expanded(child: Row(children: [_buildButton("4"), _buildButton("5"), _buildButton("6"), _buildButton("+", textColor: Colors.white)])),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              Expanded(child: Row(children: [_buildButton("1"), _buildButton("2"), _buildButton("3")])),
                              Expanded(child: Row(children: [_buildButton("0", flexWidth: 2), _buildButton(".")])),
                            ],
                          ),
                        ),
                        _buildButton("=", bgColor: Colors.white24, flexWidth: 1), // Black & White theme equals button
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