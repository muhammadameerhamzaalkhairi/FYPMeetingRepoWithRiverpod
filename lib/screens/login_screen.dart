import 'package:flutter/material.dart';
import 'package:livemeet/screens/main_screen.dart';
import 'package:livemeet/widgets/Button.dart';
import 'package:livemeet/widgets/CustomText.dart';
import 'package:livemeet/widgets/TextBox.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  TextEditingController email = TextEditingController();
  TextEditingController password = TextEditingController();
  bool isLoading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  final formKey = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    // Responsive: smaller paddings, logo and heading on narrow phones.
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 24 : 42,
            narrow ? 60 : 80,
            narrow ? 24 : 42,
            42,
          ),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'lib/assets/images/logo.png',
                      height: narrow ? 44 : 56,
                    ),
                    const SizedBox(width: 10),
                    // Expanded + FittedBox: the app name scales down instead
                    // of overflowing next to the logo on narrow screens.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: CustomText(
                          text: 'BIIT FYP Meetings',
                          fontSize: narrow ? 20 : 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: narrow ? 50 : 80),
                const CustomText(text: 'Welcome back'),
                CustomText(
                  text: 'Sign in',
                  fontSize: narrow ? 38 : 48,
                  fontWeight: FontWeight.w900,
                ),

                const SizedBox(height: 20),
                TextBox(
                  hintText: 'Email',
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextBox(
                  hintText: 'Password',
                  controller: password,
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Button(
                  text: isLoading ? 'Signing in...' : 'Sign in',
                  enabled: !isLoading,
                  onTap: () async {
                    if (isLoading) return;

                    if (!formKey.currentState!.validate()) {
                      return;
                    }

                    setState(() => isLoading = true);

                    try {
                      await Supabase.instance.client.auth.signInWithPassword(
                        email: email.text.trim(),
                        password: password.text,
                      );
                      if (!mounted) return;

                      Navigator.pushReplacement(
                        this.context,
                        MaterialPageRoute(builder: (context) => MainScreen()),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        this.context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      setState(() => isLoading = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}