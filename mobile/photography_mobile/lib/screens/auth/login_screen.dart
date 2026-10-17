import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../services/auth_session.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final AuthSession session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.session.login(_email.text, _password.text);
      TextInput.finishAutofillContext(shouldSave: true);
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _socialButton(String provider, Widget icon) => OutlinedButton(
    onPressed: _loading ? null : () {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(
          '$provider login is not available yet. Please use email and password.',
        )));
    },
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF514365),
      backgroundColor: const Color(0xFFFAF8FD),
      side: const BorderSide(color: Color(0xFFE5DDEF)),
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        ExcludeSemantics(child: icon),
        Text(provider, textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF12C9D2);
    const teal = Color(0xFF075866);
    const ink = Color(0xFF202126);
    final theme = Theme.of(context);

    InputDecoration fieldDecoration(String label, IconData icon) =>
        InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF858589)),
          prefixIcon: Icon(icon, color: const Color(0xFF77777D), size: 21),
          filled: true,
          fillColor: const Color(0xFFF8F6FB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: purple, width: 1.5),
          ),
          errorMaxLines: 3,
        );

    return Scaffold(
      backgroundColor: const Color(0xFFDFF6F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: EdgeInsets.symmetric(
                    vertical: constraints.maxWidth > 600 ? 32 : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(40),
                        ),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [teal, Color(0xFF0B7A82)],
                                  ),
                                ),
                              ),
                            ),
                            const Positioned(
                              right: -58,
                              top: -40,
                              child: ExcludeSemantics(child: _LensVisual()),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      teal.withValues(alpha: .05),
                                      teal.withValues(alpha: .92),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 30, 28, 76),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.camera, color: Color(0xFFB9F4F4), size: 25),
                                      SizedBox(width: 9),
                                      Text('SnapSync', style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .5,
                                      )),
                                    ],
                                  ),
                                  const SizedBox(height: 92),
                                  Text('Hello, Welcome', style: theme.textTheme.headlineLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                  )),
                                  const SizedBox(height: 10),
                                  const Text('Sign in to continue', style: TextStyle(
                                    color: Color(0xFFD5F1F1), fontSize: 16,
                                  )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // The card paints over the hero while retaining its full
                      // layout height for keyboard and large-text scrolling.
                      Transform.translate(
                        offset: const Offset(0, -36),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [BoxShadow(
                                color: teal.withValues(alpha: .12),
                                blurRadius: 32,
                                offset: const Offset(0, 12),
                              )],
                            ),
                            child: Form(
                              key: _formKey,
                              child: AutofillGroup(
                                onDisposeAction: AutofillContextAction.cancel,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Login', style: theme.textTheme.headlineSmall?.copyWith(
                                      color: ink, fontWeight: FontWeight.w700,
                                    )),
                                    const SizedBox(height: 24),
                                    TextFormField(
                                      controller: _email,
                                      style: const TextStyle(color: ink),
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                                      autocorrect: false,
                                      decoration: fieldDecoration('Email', Icons.mail_outline_rounded),
                                      validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email.' : null,
                                    ),
                                    const SizedBox(height: 18),
                                    TextFormField(
                                      controller: _password,
                                      style: const TextStyle(color: ink),
                                      obscureText: _obscurePassword,
                                      autofillHints: const [AutofillHints.password],
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) { if (!_loading) _submit(); },
                                      decoration: fieldDecoration('Password', Icons.lock_outline_rounded).copyWith(
                                        suffixIcon: IconButton(
                                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                          color: const Color(0xFF77777D),
                                        ),
                                      ),
                                      validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters.' : null,
                                    ),
                                    if (_error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                                        ),
                                      ),
                                    const SizedBox(height: 28),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Color(0xFF087B87), purple]),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          disabledBackgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                          shadowColor: Colors.transparent,
                                          minimumSize: const Size.fromHeight(56),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        onPressed: _loading ? null : _submit,
                                        child: _loading
                                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white, semanticsLabel: 'Signing in',
                                              ))
                                            : const Text('Login'),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    const Text('or login with', textAlign: TextAlign.center,
                                      style: TextStyle(color: Color(0xFF777181), fontSize: 13)),
                                    const SizedBox(height: 16),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: _socialButton('Google', const CustomPaint(
                                          size: Size(22, 22), painter: _GoogleIconPainter(),
                                        ))),
                                        const SizedBox(width: 12),
                                        Expanded(child: _socialButton('Facebook', const Icon(
                                          Icons.facebook, color: Color(0xFF1877F2), size: 24,
                                        ))),
                                      ],
                                    ),
                                    const SizedBox(height: 22),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        const Text("Don't have an account?", style: TextStyle(color: Color(0xFF777181))),
                                        TextButton(
                                          style: TextButton.styleFrom(foregroundColor: teal),
                                          onPressed: _loading ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RegisterScreen(session: widget.session))),
                                          child: const Text('Register', style: TextStyle(fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

// Draw the multicolor G locally so the icon needs no network or new dependency.
class _GoogleIconPainter extends CustomPainter {
  const _GoogleIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    const ring = Rect.fromLTWH(4, 4, 16, 16);
    const radians = 3.141592653589793 / 180;
    void arc(double start, double sweep, Color color) {
      canvas.drawArc(ring, start * radians, sweep * radians, false, paint..color = color);
    }
    arc(180, 135, const Color(0xFFEA4335));
    arc(135, 45, const Color(0xFFFBBC05));
    arc(45, 90, const Color(0xFF34A853));
    arc(0, 45, const Color(0xFF4285F4));
    paint..color = const Color(0xFF4285F4)..style = PaintingStyle.fill;
    canvas.drawRect(const Rect.fromLTWH(12, 10, 10, 4), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleIconPainter oldDelegate) => false;
}

class _LensVisual extends StatelessWidget {
  const _LensVisual();

  @override
  Widget build(BuildContext context) => Container(
    width: 290,
    height: 290,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFF655675), width: 2),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF554960), Color(0xFF121119), Color(0xFF3B304C)],
      ),
    ),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF756186), width: 3),
        color: const Color(0xFF17131F),
      ),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF443B60), width: 5),
          gradient: const RadialGradient(
            center: Alignment(-.4, -.5),
            colors: [Color(0xFFAC90C7), Color(0xFF4B5778), Color(0xFF241E38), Color(0xFF080B13)],
            stops: [0, .22, .55, 1],
          ),
        ),
        child: const Icon(Icons.camera, size: 104, color: Color(0xFF72658C)),
      ),
    ),
  );
}
