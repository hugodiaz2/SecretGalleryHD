import 'package:flutter/material.dart';
import '../../core/security/pin_service.dart';
import '../lock/pin_screen.dart';
import '../albums/albums_screen.dart';

/// Disfraz de la app: una calculadora normal y funcional. Si el usuario
/// escribe su PIN (como si fuera un número cualquiera) y presiona "=",
/// en vez de mostrar un resultado abre la galería secreta. Cualquier
/// otra operación se comporta como una calculadora real.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _pinService = PinService();

  String _display = '0';
  String _rawEntry = ''; // dígitos escritos desde el último operador/reset
  double? _accumulator;
  String? _pendingOp;
  bool _justEvaluated = false;

  void _inputDigit(String digit) {
    setState(() {
      if (_justEvaluated) {
        _display = digit;
        _rawEntry = digit;
        _justEvaluated = false;
      } else if (_display == '0' && digit != '.') {
        _display = digit;
        _rawEntry += digit;
      } else {
        if (digit == '.' && _display.contains('.')) return;
        _display += digit;
        _rawEntry += digit;
      }
    });
  }

  void _inputOperator(String op) {
    setState(() {
      if (_accumulator != null && _pendingOp != null && !_justEvaluated) {
        _accumulator = _apply(_accumulator!, double.tryParse(_display) ?? 0, _pendingOp!);
      } else {
        _accumulator = double.tryParse(_display) ?? 0;
      }
      _pendingOp = op;
      _justEvaluated = false;
      _rawEntry = '';
      _display = '0';
    });
  }

  double _apply(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '-':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? 0 : a / b;
      default:
        return b;
    }
  }

  String _formatResult(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    return v.toString();
  }

  Future<void> _equals() async {
    // Desbloqueo secreto: número recién escrito (sin operador pendiente
    // usado en esta secuencia) que coincide con el PIN real.
    if (_pendingOp == null && _rawEntry.isNotEmpty) {
      final valid = await _pinService.validatePin(_rawEntry);
      if (valid) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (routeContext) => PinScreen(
              mode: PinMode.unlock,
              onSuccess: () => Navigator.of(routeContext).pushReplacement(
                MaterialPageRoute(builder: (_) => const AlbumsScreen()),
              ),
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      if (_accumulator != null && _pendingOp != null) {
        final result =
            _apply(_accumulator!, double.tryParse(_display) ?? 0, _pendingOp!);
        _display = _formatResult(result);
        _accumulator = null;
        _pendingOp = null;
      }
      _rawEntry = '';
      _justEvaluated = true;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _rawEntry = '';
      _accumulator = null;
      _pendingOp = null;
      _justEvaluated = false;
    });
  }

  void _toggleSign() {
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else if (_display != '0') {
        _display = '-$_display';
      }
      _rawEntry = _display;
    });
  }

  void _percent() {
    setState(() {
      final v = (double.tryParse(_display) ?? 0) / 100;
      _display = _formatResult(v);
      _rawEntry = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _display,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _row([
                    _btn('C', onTap: _clear, bg: const Color(0xFFA5A5A5), fg: Colors.black),
                    _btn('±', onTap: _toggleSign, bg: const Color(0xFFA5A5A5), fg: Colors.black),
                    _btn('%', onTap: _percent, bg: const Color(0xFFA5A5A5), fg: Colors.black),
                    _btn('÷', onTap: () => _inputOperator('÷'), bg: const Color(0xFFFF9F0A)),
                  ]),
                  _row([
                    _btn('7', onTap: () => _inputDigit('7')),
                    _btn('8', onTap: () => _inputDigit('8')),
                    _btn('9', onTap: () => _inputDigit('9')),
                    _btn('×', onTap: () => _inputOperator('×'), bg: const Color(0xFFFF9F0A)),
                  ]),
                  _row([
                    _btn('4', onTap: () => _inputDigit('4')),
                    _btn('5', onTap: () => _inputDigit('5')),
                    _btn('6', onTap: () => _inputDigit('6')),
                    _btn('-', onTap: () => _inputOperator('-'), bg: const Color(0xFFFF9F0A)),
                  ]),
                  _row([
                    _btn('1', onTap: () => _inputDigit('1')),
                    _btn('2', onTap: () => _inputDigit('2')),
                    _btn('3', onTap: () => _inputDigit('3')),
                    _btn('+', onTap: () => _inputOperator('+'), bg: const Color(0xFFFF9F0A)),
                  ]),
                  _row([
                    _btn('0', onTap: () => _inputDigit('0'), flex: 2, alignLeft: true),
                    _btn('.', onTap: () => _inputDigit('.')),
                    _btn('=', onTap: _equals, bg: const Color(0xFFFF9F0A)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: children),
    );
  }

  Widget _btn(
    String label, {
    required VoidCallback onTap,
    Color bg = const Color(0xFF333333),
    Color fg = Colors.white,
    int flex = 1,
    bool alignLeft = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: AspectRatio(
          aspectRatio: flex == 2 ? 2 : 1,
          child: Material(
            color: bg,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Align(
                alignment: alignLeft
                    ? const Alignment(-0.6, 0)
                    : Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
