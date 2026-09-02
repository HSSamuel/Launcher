import 'package:flutter/material.dart';

class CalculatorApp extends StatefulWidget {
  const CalculatorApp({Key? key}) : super(key: key);

  @override
  State<CalculatorApp> createState() => _CalculatorAppState();
}

class _CalculatorAppState extends State<CalculatorApp> {
  String _output = "0";
  String _currentInput = "";
  double _num1 = 0.0;
  String _operand = "";
  bool _isNewEquation = true;

  void _buttonPressed(String buttonText) {
    setState(() {
      if (buttonText == "C") {
        _output = "0";
        _currentInput = "";
        _num1 = 0.0;
        _operand = "";
        _isNewEquation = true;
      } else if (buttonText == "+" || buttonText == "-" || buttonText == "x" || buttonText == "/") {
        if (_output.isNotEmpty) {
          _num1 = double.parse(_output);
          _operand = buttonText;
          _isNewEquation = true;
        }
      } else if (buttonText == "=") {
        if (_operand.isNotEmpty && _output.isNotEmpty) {
          double num2 = double.parse(_output);
          double result = 0.0;
          if (_operand == "+") result = _num1 + num2;
          if (_operand == "-") result = _num1 - num2;
          if (_operand == "x") result = _num1 * num2;
          if (_operand == "/") result = num2 != 0 ? _num1 / num2 : 0.0; // Prevent divide by zero
          
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

  Widget _buildCalcButton(String text, {Color? color, Color? textColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: InkWell(
          onTap: () => _buttonPressed(text),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              color: color ?? Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(text, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: textColor ?? Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Text(_output, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              children: [
                Expanded(child: Row(children: [_buildCalcButton("C", textColor: Colors.redAccent), _buildCalcButton(""), _buildCalcButton("/"), _buildCalcButton("x")])),
                Expanded(child: Row(children: [_buildCalcButton("7"), _buildCalcButton("8"), _buildCalcButton("9"), _buildCalcButton("-")])),
                Expanded(child: Row(children: [_buildCalcButton("4"), _buildCalcButton("5"), _buildCalcButton("6"), _buildCalcButton("+")])),
                Expanded(child: Row(children: [_buildCalcButton("1"), _buildCalcButton("2"), _buildCalcButton("3"), _buildCalcButton("=", color: Colors.blueAccent)])),
                Expanded(child: Row(children: [_buildCalcButton("0"), _buildCalcButton(".")])),
              ],
            ),
          ),
        ),
      ],
    );
  }
}