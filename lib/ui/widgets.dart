import 'package:flutter/material.dart';

/// Green for profit, red for loss, readable in light and dark themes.
Color pnlColor(BuildContext context, num? v) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (v == null || v == 0) return Theme.of(context).colorScheme.onSurface;
  return v > 0 ? (dark ? const Color(0xFF5BD68A) : const Color(0xFF1A7F37)) : (dark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E));
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.subtitle, required this.child, this.trailing});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
              ?trailing,
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.color, this.hint, this.width = 168});

  final String label, value;
  final Color? color;
  final String? hint;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tile = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant))),
          if (hint != null) ...[const SizedBox(width: 4), Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant)],
        ]),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: color)),
      ]),
    );
    return hint == null ? tile : Tooltip(message: hint!, waitDuration: const Duration(milliseconds: 300), child: tile);
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.secondaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: cs.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: cs.onSecondaryContainer))),
      ]),
    );
  }
}

/// A labelled slider with its value shown on the right.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  final String label;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        Text(format(value), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
      ]),
      Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: format(value), onChanged: onChanged),
    ]);
  }
}

/// Page scaffold: scrollable, centred, max width.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1200});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class Bullet extends StatelessWidget {
  const Bullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 6)),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
