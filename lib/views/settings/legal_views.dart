import 'package:flutter/material.dart';

import '../../design/app_theme.dart';
import 'legal_texts.dart';

class TermsOfServiceView extends StatelessWidget {
  const TermsOfServiceView({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScreen(title: 'Terms of service', text: termsOfServiceText);
  }
}

class PrivacyPolicyView extends StatelessWidget {
  const PrivacyPolicyView({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalScreen(title: 'Privacy Policy', text: privacyPolicyText);
  }
}

class _LegalScreen extends StatelessWidget {
  const _LegalScreen({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        foregroundColor: AppTheme.textPrimary(context),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'AF Creative',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 18),
            SelectableText(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
