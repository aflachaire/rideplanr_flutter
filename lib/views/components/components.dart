import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/nav_preference.dart';

// MARK: - Skeleton shimmer

class _SkeletonShimmer extends StatefulWidget {
  const _SkeletonShimmer({required this.child});

  final Widget child;

  @override
  State<_SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<_SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = -1 + _controller.value * 2.2;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + phase, 0),
              end: Alignment(phase + 0.42, 0),
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.02),
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.26),
                Colors.white.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({this.width, required this.height, this.cornerRadius});

  final double? width;
  final double height;
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final resolvedCornerRadius =
        cornerRadius ?? (height / 2 < 14 ? height / 2 : 14.0);

    return _SkeletonShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(resolvedCornerRadius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.elevated(context).withValues(alpha: 0.88),
              Colors.white.withValues(alpha: 0.05),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.035),
            width: 0.8,
          ),
        ),
      ),
    );
  }
}

class LoadingCardView extends StatelessWidget {
  const LoadingCardView({super.key, this.lineCount = 3, this.showsFooter = true});

  final int lineCount;
  final bool showsFooter;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SkeletonBlock(width: 86, height: 13),
                    _SkeletonBlock(width: 52, height: 13),
                  ],
                ),
                const SizedBox(height: 14),
                _SkeletonBlock(
                    width: contentWidth * 0.58, height: 18, cornerRadius: 8),
                const SizedBox(height: 14),
                _SkeletonBlock(width: contentWidth * 0.88, height: 13),
                for (var i = 0; i < lineCount - 2; i++) ...[
                  const SizedBox(height: 14),
                  _SkeletonBlock(width: contentWidth * 0.72, height: 12),
                ],
                const SizedBox(height: 14),
                const Row(
                  children: [
                    _SkeletonBlock(width: 82, height: 26),
                    SizedBox(width: 8),
                    _SkeletonBlock(width: 72, height: 26),
                  ],
                ),
                if (showsFooter) ...[
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Expanded(
                          child: _SkeletonBlock(height: 42, cornerRadius: 14)),
                      SizedBox(width: 10),
                      Expanded(
                          child: _SkeletonBlock(height: 42, cornerRadius: 14)),
                    ],
                  ),
                ],
              ],
            );
        },
      ),
    );
  }
}

// MARK: - Score / signal cards

class ScoreCardView extends StatelessWidget {
  const ScoreCardView({super.key, required this.score, required this.headline});

  final int score;
  final String headline;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global potential',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '/100',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              color: AppTheme.gold,
              backgroundColor: AppTheme.elevated(context),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class OpportunityCategoryTagView extends StatelessWidget {
  const OpportunityCategoryTagView({super.key, required this.category});

  final SignalCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: category.tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 14, color: category.tint),
          const SizedBox(width: 5),
          Text(
            category.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: category.tint,
            ),
          ),
        ],
      ),
    );
  }
}

class PotentialIndicatorView extends StatelessWidget {
  const PotentialIndicatorView({
    super.key,
    required this.filledStars,
    this.totalStars = 3,
  });

  final int filledStars;
  final int totalStars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < totalStars; index++)
          Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 4),
            child: Icon(
              index < filledStars ? Icons.star : Icons.star_border,
              size: 14,
              color: index < filledStars
                  ? AppTheme.gold
                  : AppTheme.textSecondary(context).withValues(alpha: 0.45),
            ),
          ),
      ],
    );
  }
}

int starCountForOpportunity(Opportunity opportunity) {
  if (opportunity.potentialCustomers < 7) return 1;
  if (opportunity.potentialCustomers < 13) return 2;
  return 3;
}

// MARK: - Opportunity card

class OpportunityCardView extends StatelessWidget {
  const OpportunityCardView({
    super.key,
    required this.opportunity,
    required this.distanceDisplayUnit,
    this.showsRecommendation = true,
    this.actionTitle,
    this.actionIcon,
    this.onAction,
    this.secondaryActionTitle,
    this.secondaryActionForeground,
    this.secondaryActionBackground,
    this.secondaryActionIcon,
    this.onSecondaryAction,
  });

  final Opportunity opportunity;
  final DistanceDisplayUnit distanceDisplayUnit;
  final bool showsRecommendation;
  final String? actionTitle;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionTitle;
  final Color? secondaryActionForeground;
  final Color? secondaryActionBackground;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  List<SignalCategory> get _visibleCategories => opportunity.categories
      .where((c) => c != SignalCategory.traffic)
      .toList();

  String get _timeRemainingText =>
      opportunity.startsInMinutes.driverIntelTimeRemainingText;

  Color get _timeRemainingColor =>
      opportunity.startsInMinutes.isDriverIntelImmediateTime
          ? AppTheme.success
          : AppTheme.gold;

  String get _distanceText {
    switch (distanceDisplayUnit) {
      case DistanceDisplayUnit.kilometers:
        return '${opportunity.distanceKilometers.toStringAsFixed(1)} km';
      case DistanceDisplayUnit.miles:
        return '${(opportunity.distanceKilometers * 0.621371).toStringAsFixed(1)} mi';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleCategories = _visibleCategories;
    final primaryCategory =
        visibleCategories.isEmpty ? null : visibleCategories.first;
    final secondaryCategories =
        visibleCategories.length > 1 ? visibleCategories.sublist(1) : const <SignalCategory>[];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (primaryCategory != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(primaryCategory.icon,
                          size: 16, color: primaryCategory.tint),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          primaryCategory.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primaryCategory.tint,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              PotentialIndicatorView(
                filledStars: starCountForOpportunity(opportunity),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  opportunity.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeRemainingText,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _timeRemainingColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            opportunity.subtitle,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary(context),
            ),
          ),
          if (showsRecommendation) ...[
            const SizedBox(height: 14),
            Text(
              opportunity.recommendation,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ],
          if (secondaryCategories.isNotEmpty) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < secondaryCategories.length; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: OpportunityCategoryTagView(
                          category: secondaryCategories[i]),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _infoPill(context, _distanceText, Icons.location_on),
              const SizedBox(width: 8),
              _infoPill(context, '${opportunity.driveTimeMinutes} min',
                  Icons.directions_car),
            ],
          ),
          if (actionTitle != null || secondaryActionTitle != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (secondaryActionTitle != null && onSecondaryAction != null)
                  Expanded(
                    child: _actionButton(
                      context,
                      title: secondaryActionTitle!,
                      icon: secondaryActionIcon,
                      foreground: secondaryActionForeground ??
                          AppTheme.textOnAccent(context),
                      background: secondaryActionBackground ?? Colors.white,
                      onPressed: onSecondaryAction!,
                    ),
                  )
                else if (actionTitle != null)
                  const Expanded(child: SizedBox()),
                if (actionTitle != null && onAction != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _actionButton(
                      context,
                      title: actionTitle!,
                      icon: actionIcon,
                      foreground: AppTheme.textOnAccent(context),
                      background: AppTheme.gold,
                      onPressed: onAction!,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoPill(BuildContext context, String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.elevated(context),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary(context)),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String title,
    IconData? icon,
    required Color foreground,
    required Color background,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: - Hourly potential ("Trend") card

class HourlyPotentialCardView extends StatelessWidget {
  const HourlyPotentialCardView({
    super.key,
    required this.values,
    required this.timeDisplayFormat,
    required this.title,
  });

  final List<HourlyPotential> values;
  final TimeDisplayFormat timeDisplayFormat;
  final String title;

  int get _peakScore {
    var peak = 1;
    for (final value in values) {
      if (value.score > peak) peak = value.score;
    }
    return peak;
  }

  ({int startHour, int endHour})? get _peakWindowRange {
    if (values.length < 2) return null;

    ({int startHour, int endHour})? bestPair;
    var bestScore = -1 << 62;

    for (var index = 0; index < values.length - 1; index++) {
      final combinedScore = values[index].score + values[index + 1].score;
      if (combinedScore > bestScore) {
        bestScore = combinedScore;
        bestPair = (
          startHour: values[index].hour,
          endHour: (values[index + 1].hour + 1) % 24,
        );
      }
    }

    return bestPair;
  }

  String get _peakWindowText {
    final peakWindow = _peakWindowRange;
    if (peakWindow == null) return 'N/A';
    return timeDisplayFormat.formatHourWindow(
      startHour: peakWindow.startHour,
      endHour: peakWindow.endHour,
    );
  }

  @override
  Widget build(BuildContext context) {
    final peakScore = _peakScore;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Next 12h',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Busiest window',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _peakWindowText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 124,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      // Equal horizontal padding on every bar so they all render
                      // the same width (an asymmetric left-only pad made the
                      // first bar wider than the rest).
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Container(
                        height: (values[i].score / peakScore * 120)
                            .clamp(18.0, 120.0)
                            .toDouble(),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: values[i].score == peakScore
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppTheme.gold,
                                    AppTheme.gold.withValues(alpha: 0.72),
                                  ],
                                )
                              : LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    AppTheme.textSecondary(context)
                                        .withValues(alpha: 0.28),
                                    AppTheme.elevated(context),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Row(
              children: [
                for (var index = 0; index < values.length; index += 2)
                  Expanded(
                    child: Center(
                      child: Text(
                        timeDisplayFormat.formatHourLabel(values[index].hour),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Weather forecast card

class WeatherForecastCardView extends StatelessWidget {
  const WeatherForecastCardView({
    super.key,
    required this.badge,
    required this.city,
    required this.forecast,
    required this.timeDisplayFormat,
  });

  final WeatherBadge badge;
  final String city;
  final List<WeatherForecastSlot> forecast;
  final TimeDisplayFormat timeDisplayFormat;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$city forecast',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Next 12h',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < forecast.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.elevated(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Icon(forecast[i].icon,
                                size: 20, color: AppTheme.gold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          timeDisplayFormat.formatHourWindow(
                            startHour: forecast[i].startHour,
                            endHour: forecast[i].endHour,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// MARK: - Banners and headers

class RecommendationBannerView extends StatelessWidget {
  const RecommendationBannerView({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 22, color: AppTheme.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top recommendation',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
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
}

class SectionHeaderView extends StatelessWidget {
  const SectionHeaderView({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 15,
            color: AppTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class FilterChipView extends StatelessWidget {
  const FilterChipView({super.key, required this.title, required this.isSelected});

  final String title;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.gold : AppTheme.elevated(context),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isSelected
              ? AppTheme.textOnAccent(context)
              : AppTheme.textPrimary(context),
        ),
      ),
    );
  }
}

// MARK: - Navigation dialog

/// Presents an "Open directions" sheet for a tapped Opportunity, mirroring the
/// iOS confirmation dialog with Apple Maps / Google Maps / Waze options.
Future<void> _launchNav(NavApp app, Opportunity opportunity) async {
  switch (app) {
    case NavApp.apple:
      await _openURL(opportunity.appleMapsURL);
    case NavApp.google:
      if (!await _openURL(opportunity.googleMapsAppURL)) {
        await _openURL(opportunity.googleMapsWebURL);
      }
    case NavApp.waze:
      if (!await _openURL(opportunity.wazeAppURL)) {
        await _openURL(opportunity.wazeWebURL);
      }
    case NavApp.ask:
      break;
  }
}

Future<void> showNavigationDialog(
  BuildContext context,
  Opportunity opportunity,
) async {
  // If the user already picked a nav app, skip the sheet and launch it.
  final preferred = await getPreferredNavApp();
  if (preferred != NavApp.ask) {
    await _launchNav(preferred, opportunity);
    return;
  }

  if (!context.mounted) return;

  // First time (or "Ask each time"): show the picker and remember the pick.
  Future<void> Function() choose(NavApp app) => () async {
        await setPreferredNavApp(app);
        await _launchNav(app, opportunity);
      };

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              'Open directions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary(sheetContext),
              ),
            ),
            Text(
              'We’ll remember your choice',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary(sheetContext).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            _navigationOption(
                sheetContext, NavApp.apple.label, choose(NavApp.apple)),
            _navigationOption(
                sheetContext, NavApp.google.label, choose(NavApp.google)),
            _navigationOption(
                sheetContext, NavApp.waze.label, choose(NavApp.waze)),
            _navigationOption(sheetContext, 'Cancel', () async {}),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Widget _navigationOption(
  BuildContext context,
  String title,
  Future<void> Function() onSelected,
) {
  return ListTile(
    title: Text(
      title,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary(context),
      ),
    ),
    onTap: () async {
      Navigator.of(context).pop();
      await onSelected();
    },
  );
}

Future<bool> _openURL(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
