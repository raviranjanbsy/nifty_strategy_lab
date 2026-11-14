import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'engine/market.dart';
import 'engine/reference.dart';
import 'ui/lab_page.dart';
import 'ui/learn_page.dart';
import 'ui/overview_page.dart';
import 'ui/replay_page.dart';
import 'ui/risk_page.dart';

void main() => runApp(const StrategyLabApp());

Future<AppState> loadAppState() async {
  final market = MarketData.fromJson(await rootBundle.loadString('assets/data/market.json'));
  final reference = ReferenceData.fromJson(await rootBundle.loadString('assets/data/reference.json'));
  final state = AppState(market, reference);
  state.tab = tabFromQuery(Uri.base.queryParameters['tab']);
  state.run();
  return state;
}

/// `?tab=lab` etc. opens a tab directly, so links to a tab can be shared.
int tabFromQuery(String? name) => switch (name) {
      'lab' => 1,
      'replay' => 2,
      'learn' => 3,
      'risk' => 4,
      _ => 0,
    };

ThemeData _theme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F6FEB), brightness: b);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(elevation: 0, color: scheme.surfaceContainerLow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    dataTableTheme: const DataTableThemeData(headingTextStyle: TextStyle(fontWeight: FontWeight.w600)),
  );
}

class StrategyLabApp extends StatefulWidget {
  const StrategyLabApp({super.key, this.loader = loadAppState});

  final Future<AppState> Function() loader;

  @override
  State<StrategyLabApp> createState() => _StrategyLabAppState();
}

class _StrategyLabAppState extends State<StrategyLabApp> {
  late final Future<AppState> _state = widget.loader();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nifty Strategy Lab',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: FutureBuilder<AppState>(
        future: _state,
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(body: Center(child: Text('Could not load the market data: ${snap.error}')));
          }
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return AppScope(state: snap.data!, child: const HomeShell());
        },
      ),
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon, selectedIcon;
  final Widget page;
}

const _dests = [
  _Dest('Overview', Icons.dashboard_outlined, Icons.dashboard, OverviewPage()),
  _Dest('Strategy lab', Icons.science_outlined, Icons.science, LabPage()),
  _Dest('Replay', Icons.candlestick_chart_outlined, Icons.candlestick_chart, ReplayPage()),
  _Dest('Learn', Icons.school_outlined, Icons.school, LearnPage()),
  _Dest('Risk', Icons.calculate_outlined, Icons.calculate, RiskPage()),
];

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = _dests[app.tab].page;
    final title = Row(children: [
      Icon(Icons.candlestick_chart, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      const Flexible(child: Text('Nifty Strategy Lab', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700))),
    ]);
    if (wide) {
      return Scaffold(
        appBar: AppBar(title: title, scrolledUnderElevation: 0),
        body: Row(children: [
          NavigationRail(
            selectedIndex: app.tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: app.goTo,
            destinations: [
              for (final d in _dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title, scrolledUnderElevation: 0),
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: app.tab,
        onDestinationSelected: app.goTo,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: [for (final d in _dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)],
      ),
    );
  }
}
