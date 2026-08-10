import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security/pin_service.dart';
import '../../core/security/password_service.dart';
import '../../core/security/biometric_service.dart';
import '../../core/services/prefs_service.dart';
import '../../core/theme/app_colors.dart';
import 'lock_header.dart';
import 'pin_screen.dart';
import 'password_screen.dart';

enum AccessMethodScreenMode { onboarding, manage }

/// Pantalla única para elegir/gestionar el método de acceso (PIN,
/// contraseña o huella). Se usa en dos contextos:
/// - `onboarding`: justo después de crear el PIN por primera vez.
/// - `manage`: desde Ajustes, para cambiar de método más adelante (pide
///   confirmar el método actual antes de dejar cambiarlo).
class AccessMethodScreen extends StatefulWidget {
  final AccessMethodScreenMode mode;
  final VoidCallback? onDone;

  const AccessMethodScreen({super.key, required this.mode, this.onDone});

  @override
  State<AccessMethodScreen> createState() => _AccessMethodScreenState();
}

class _AccessMethodScreenState extends State<AccessMethodScreen> {
  final _pinService = PinService();
  final _passwordService = PasswordService();

  bool _loading = true;
  bool _busy = false;
  AuthMethod _currentMethod = AuthMethod.pin;
  bool _hasPassword = false;

  bool get _isOnboarding => widget.mode == AccessMethodScreenMode.onboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final method = await PrefsService.instance.getAuthMethod();
    final hasPw = await _passwordService.hasPassword();
    if (mounted) {
      setState(() {
        _currentMethod = method;
        _hasPassword = hasPw;
        _loading = false;
      });
    }
  }

  /// Confirma el método ACTUAL antes de dejar cambiarlo por otro. Solo se
  /// exige en modo "manage": en onboarding no hay nada que confirmar
  /// todavía (el PIN se acaba de crear en el paso anterior).
  Future<bool> _reauthCurrentMethod() async {
    if (_isOnboarding) return true;

    switch (_currentMethod) {
      case AuthMethod.pin:
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (routeContext) => PinScreen(
              mode: PinMode.unlock,
              onSuccess: () => Navigator.of(routeContext).pop(true),
            ),
          ),
        );
        return ok == true;
      case AuthMethod.password:
        final ok = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (routeContext) => PasswordScreen(
              mode: PasswordMode.unlock,
              onSuccess: () => Navigator.of(routeContext).pop(true),
            ),
          ),
        );
        return ok == true;
      case AuthMethod.fingerprint:
        return BiometricService.instance.authenticate(
          reason: 'Confirma tu identidad para cambiar el método de acceso',
        );
    }
  }

  Future<void> _selectMethod(AuthMethod target) async {
    if (_busy || target == _currentMethod) return;
    setState(() => _busy = true);

    final reauthed = await _reauthCurrentMethod();
    if (!reauthed || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    switch (target) {
      case AuthMethod.pin:
        // El PIN siempre existe: se crea en la configuración inicial.
        await PrefsService.instance.saveAuthMethod(AuthMethod.pin);
        break;

      case AuthMethod.password:
        if (!_hasPassword) {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (routeContext) => PasswordScreen(
                mode: PasswordMode.setup,
                onSuccess: () => Navigator.of(routeContext).pop(true),
              ),
            ),
          );
          if (created != true || !mounted) {
            if (mounted) setState(() => _busy = false);
            return;
          }
          _hasPassword = true;
        }
        await PrefsService.instance.saveAuthMethod(AuthMethod.password);
        break;

      case AuthMethod.fingerprint:
        final available = await BiometricService.instance.isAvailable();
        if (!available) {
          if (mounted) {
            setState(() => _busy = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor:
                    Theme.of(context).extension<AppColors>()!.surface,
                content: Text(
                  'Tu dispositivo no tiene huella dactilar configurada',
                  style:
                      GoogleFonts.poppins(color: context.colors.textPrimary),
                ),
              ),
            );
          }
          return;
        }
        final confirmed = await BiometricService.instance.authenticate(
          reason: 'Confirma tu huella para activarla como método de acceso',
        );
        if (!confirmed || !mounted) {
          if (mounted) setState(() => _busy = false);
          return;
        }
        await PrefsService.instance.saveAuthMethod(AuthMethod.fingerprint);
        break;
    }

    if (!mounted) return;
    setState(() {
      _currentMethod = target;
      _busy = false;
    });

    if (_isOnboarding) {
      widget.onDone?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text('Método de acceso actualizado',
                style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          ]),
        ),
      );
    }
  }

  void _showChangePinDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          title: Text('Cambiar PIN',
              style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: Text(error!,
                      style: GoogleFonts.poppins(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              _dialogField('PIN actual', currentCtrl, isNumeric: true),
              const SizedBox(height: 12),
              _dialogField('Nuevo PIN', newCtrl, isNumeric: true),
              const SizedBox(height: 12),
              _dialogField('Confirmar PIN', confirmCtrl, isNumeric: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: GoogleFonts.poppins(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                final current = currentCtrl.text.trim();
                final newPin = newCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();

                if (current.length != 4 ||
                    newPin.length != 4 ||
                    confirm.length != 4) {
                  setDialogState(() =>
                      error = 'Todos los PINs deben tener 4 dígitos');
                  return;
                }
                final valid = await _pinService.validatePin(current);
                if (!valid) {
                  setDialogState(() => error = 'PIN actual incorrecto');
                  return;
                }
                if (newPin != confirm) {
                  setDialogState(
                      () => error = 'Los PINs nuevos no coinciden');
                  return;
                }
                await _pinService.savePin(newPin);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor:
                          Theme.of(context).extension<AppColors>()!.surface,
                      content: Text('PIN actualizado',
                          style: GoogleFonts.poppins(
                              color: context.colors.textPrimary)),
                    ),
                  );
                }
              },
              child: Text('Guardar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).extension<AppColors>()!.surface,
          title: Text('Cambiar contraseña',
              style: GoogleFonts.poppins(color: context.colors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent, width: 1),
                  ),
                  child: Text(error!,
                      style: GoogleFonts.poppins(
                          color: Colors.redAccent, fontSize: 12)),
                ),
              _dialogField('Contraseña actual', currentCtrl),
              const SizedBox(height: 12),
              _dialogField('Nueva contraseña', newCtrl),
              const SizedBox(height: 12),
              _dialogField('Confirmar contraseña', confirmCtrl),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar',
                  style: GoogleFonts.poppins(color: context.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary),
              onPressed: () async {
                final current = currentCtrl.text;
                final newPw = newCtrl.text;
                final confirm = confirmCtrl.text;

                if (newPw.length < 4) {
                  setDialogState(() => error = 'Mínimo 4 caracteres');
                  return;
                }
                final valid = await _passwordService.validatePassword(current);
                if (!valid) {
                  setDialogState(
                      () => error = 'Contraseña actual incorrecta');
                  return;
                }
                if (newPw != confirm) {
                  setDialogState(
                      () => error = 'Las contraseñas nuevas no coinciden');
                  return;
                }
                await _passwordService.savePassword(newPw);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor:
                          Theme.of(context).extension<AppColors>()!.surface,
                      content: Text('Contraseña actualizada',
                          style: GoogleFonts.poppins(
                              color: context.colors.textPrimary)),
                    ),
                  );
                }
              },
              child: Text('Guardar',
                  style: GoogleFonts.poppins(color: context.colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl,
      {bool isNumeric = false}) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      maxLength: isNumeric ? 4 : null,
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textMuted),
        counterStyle: TextStyle(color: context.colors.textFaint),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: Center(
            child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: _isOnboarding
          ? null
          : AppBar(
              backgroundColor: context.colors.bg,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text('Métodos de acceso',
                  style: GoogleFonts.poppins(
                      color: context.colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_isOnboarding) ...[
              const SizedBox(height: 10),
              const LockHeader(),
              const SizedBox(height: 30),
              Text('¿Cómo quieres desbloquear tu galería?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Ya creaste tu PIN. Puedes seguir usándolo o elegir otro método.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: context.colors.textMuted, fontSize: 12)),
              const SizedBox(height: 24),
            ],
            _methodCard(AuthMethod.pin, Icons.dialpad, 'PIN',
                'Código numérico de 4 dígitos'),
            const SizedBox(height: 10),
            _methodCard(AuthMethod.password, Icons.password_outlined,
                'Contraseña', 'Texto alfanumérico'),
            const SizedBox(height: 10),
            _methodCard(AuthMethod.fingerprint, Icons.fingerprint,
                'Huella dactilar', 'Usa la huella registrada en el teléfono'),
            if (!_isOnboarding) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('GESTIONAR',
                    style: GoogleFonts.poppins(
                        color: context.colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5)),
              ),
              _manageTile(Icons.lock_outline, 'Cambiar PIN',
                  'Modifica tu PIN de acceso', _showChangePinDialog),
              if (_hasPassword) ...[
                const SizedBox(height: 8),
                _manageTile(Icons.password_outlined, 'Cambiar contraseña',
                    'Modifica tu contraseña de acceso',
                    _showChangePasswordDialog),
              ],
            ],
            if (_isOnboarding) ...[
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Continuar',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _methodCard(
      AuthMethod method, IconData icon, String title, String subtitle) {
    final isSelected = method == _currentMethod;
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: _busy ? null : () => _selectMethod(method),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isSelected ? accent : context.colors.border,
              width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withOpacity(0.15)
                    : context.colors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  color: isSelected ? accent : context.colors.textMuted,
                  size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          color: context.colors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            if (_busy && !isSelected)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? accent : context.colors.textFaint,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  Widget _manageTile(
      IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      tileColor: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: context.colors.textMuted, size: 20),
      ),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: context.colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.poppins(
              color: context.colors.textMuted, fontSize: 11)),
      trailing: Icon(Icons.chevron_right, color: context.colors.textMuted),
    );
  }
}
