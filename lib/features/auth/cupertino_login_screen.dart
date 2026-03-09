import 'package:flutter/cupertino.dart';

class CupertinoLoginScreen extends StatelessWidget {
  const CupertinoLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Login iOS')),
      child: SafeArea(
        // Using SafeArea to avoid notch
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: Text(
                  'MODO IOS DEMO',
                  style: TextStyle(
                    color: CupertinoColors.systemRed,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Icon(
                CupertinoIcons.person_circle,
                size: 80,
                color: CupertinoColors.activeBlue,
              ),
              const SizedBox(height: 40),
              CupertinoTextField(
                placeholder: 'Email',
                padding: const EdgeInsets.all(16),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.mail,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.extraLightBackgroundGray,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              CupertinoTextField(
                placeholder: 'Senha',
                obscureText: true,
                padding: const EdgeInsets.all(16),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.lock,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.extraLightBackgroundGray,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 32),
              CupertinoButton.filled(
                child: const Text('Entrar'),
                onPressed: () {}, // Placeholder action
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                child: const Text('Esqueci minha senha'),
                onPressed: () {},
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
