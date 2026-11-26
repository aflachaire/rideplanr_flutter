import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../design/app_theme.dart';
import '../../services/telemetry_service.dart';
import '../../viewmodels/onboarding_view_model.dart';

class OnboardingFlowView extends StatefulWidget {
  const OnboardingFlowView({super.key, required this.appState});

  final AppState appState;

  @override
  State<OnboardingFlowView> createState() => _OnboardingFlowViewState();
}

class _OnboardingFlowViewState extends State<OnboardingFlowView> {
  final OnboardingViewModel _viewModel = OnboardingViewModel();
  final PageController _pageController = PageController();
  final TelemetryService _telemetryService = TelemetryService.shared;

  @override
  void initState() {
    super.initState();
    _telemetryService.trackScreen(TelemetryScreen.onboarding);
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _pageController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (_pageController.hasClients &&
        _pageController.page?.round() != _viewModel.currentIndex) {
      _pageController.animateToPage(
        _viewModel.currentIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    setState(() {});
  }

  void _handlePrimaryAction() {
    if (_viewModel.isLastPage) {
      _telemetryService.trackOnboardingCompleted(entryPoint: 'get_started');
      widget.appState.hasCompletedOnboarding = true;
    } else {
      _viewModel.advance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _onboardingBackground(context),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                children: [
                  _header(context),
                  Expanded(child: _carousel(context)),
                  _footer(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onboardingBackground(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.background(context),
                  AppTheme.elevated(context),
                  AppTheme.background(context),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -160,
          right: -40,
          child: _blurCircle(AppTheme.gold.withValues(alpha: 0.16), 260),
        ),
        Positioned(
          top: 60,
          left: -90,
          child: _blurCircle(AppTheme.cyan.withValues(alpha: 0.14), 220),
        ),
      ],
    );
  }

  Widget _blurCircle(Color color, double size) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RidePlanr',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Plan the right move before the city gets busy.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {
            _telemetryService.trackOnboardingCompleted(entryPoint: 'skip');
            widget.appState.hasCompletedOnboarding = true;
          },
          child: Text(
            'Skip',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _carousel(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: _viewModel.pages.length,
      onPageChanged: (index) => _viewModel.currentIndex = index,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 18),
          child: SingleChildScrollView(
            child: _onboardingCard(context, _viewModel.pages[index]),
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    return Column(
      children: [
        _pageIndicators(context),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: AppTheme.gold,
            borderRadius: BorderRadius.circular(22),
            elevation: 8,
            shadowColor: AppTheme.gold.withValues(alpha: 0.28),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _handlePrimaryAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    _viewModel.isLastPage ? 'Get started' : 'Continue',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textOnAccent(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageIndicators(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < _viewModel.pages.length; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: index == _viewModel.currentIndex ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: index == _viewModel.currentIndex
                  ? AppTheme.gold
                  : AppTheme.border(context),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }

  Widget _onboardingCard(BuildContext context, OnboardingPage page) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heroCard(context, page),
        const SizedBox(height: 24),
        Text(
          page.eyebrow.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: page.accentColor,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          page.title,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            height: 1.15,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          page.detail,
          style: TextStyle(
            fontSize: 17,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 24),
        _highlightGrid(context, page),
      ],
    );
  }

  Widget _heroCard(BuildContext context, OnboardingPage page) {
    return Container(
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.border(context)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            page.accentColor.withValues(alpha: 0.28),
            AppTheme.surface(context),
            AppTheme.surface(context),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: page.accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(page.icon, size: 28, color: page.accentColor),
              ),
              const Spacer(),
              Text(
                'Step ${_viewModel.currentIndex + 1}/${_viewModel.pages.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _mockInfoRow(context, 'Best nearby move', 'In 24 min',
              page.accentColor),
          const SizedBox(height: 12),
          _mockInfoRow(
              context,
              'Strongest signal',
              page.highlights.isEmpty ? 'Live data' : page.highlights.first,
              AppTheme.gold),
          const SizedBox(height: 12),
          _mockInfoRow(context, 'Coverage', 'Next 12h', AppTheme.mint),
        ],
      ),
    );
  }

  Widget _mockInfoRow(
      BuildContext context, String title, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlightGrid(BuildContext context, OnboardingPage page) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 3.4,
      children: [
        for (final item in page.highlights)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
      ],
    );
  }
}
