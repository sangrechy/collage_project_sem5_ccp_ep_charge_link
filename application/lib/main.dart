import 'package:flutter/material.dart';

void main() {
  runApp(const ChargeLinkApp());
}

class ChargeLinkApp extends StatefulWidget {
  const ChargeLinkApp({super.key});

  @override
  State<ChargeLinkApp> createState() => _ChargeLinkAppState();
}

class _ChargeLinkAppState extends State<ChargeLinkApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CHARGE LINK',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: DashboardScreen(
        onToggleTheme: _toggleTheme,
        isDarkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF111315),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF4F8CFF),
        surface: Color(0xFF191C1F),
      ),
      useMaterial3: true,
      fontFamily: 'Arial',
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF3F4F5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF2563EB),
        surface: Color(0xFFFFFFFF),
      ),
      useMaterial3: true,
      fontFamily: 'Arial',
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Temporary UI state.
  // Later these values will come from ChargeLinkRepository / ESP32.
  bool _esp32Connected = true;
  bool _charging = true;

  static const Color connectedColor = Color(0xFF4CAF72);
  static const Color disconnectedColor = Color(0xFFD95C5C);

  void _toggleConnectionForTesting() {
    setState(() {
      _esp32Connected = !_esp32Connected;
    });
  }

  Future<void> _toggleCharging() async {
    if (!_esp32Connected) {
      return;
    }

    // Future:
    //
    // if (_charging) {
    //   await repository.stopCharging();
    // } else {
    //   await repository.startCharging();
    // }
    //
    // The ESP32 will ultimately return the actual state.

    setState(() {
      _charging = !_charging;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);
    final statusColor =
    _esp32Connected ? connectedColor : disconnectedColor;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 22,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CHARGE LINK',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Smart Charge Box',
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isDarkMode
                ? 'Switch to light theme'
                : 'Switch to dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onLongPress: _toggleConnectionForTesting,
            child: Padding(
              padding: const EdgeInsets.only(right: 22),
              child: Center(
                child: _StatusDot(
                  color: statusColor,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChargingCard(
                charging: _charging,
              ),
              const SizedBox(height: 16),
              const _BatteryCard(),
              const SizedBox(height: 16),
              _ActionButton(
                label: 'CHANGE SPEED',
                onPressed: () => _showChangeSpeedSheet(context),
                colors: colors,
              ),
              const SizedBox(height: 10),
              _ActionButton(
                label: 'ANALYSIS',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AnalysisScreen(),
                    ),
                  );
                },
                colors: colors,
              ),
              const SizedBox(height: 10),
              _ActionButton(
                label: _charging ? 'STOP CHARGING' : 'START CHARGING',
                filled: _charging,
                enabled: _esp32Connected,
                onPressed: _toggleCharging,
                colors: colors,
              ),
              const SizedBox(height: 26),
              _DeviceCard(
                connected: _esp32Connected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangeSpeedSheet(BuildContext context) {
    final colors = _DashboardColors.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Text(
                'Change Speed',
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// ANALYSIS
// ============================================================

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'CHARGE ANALYSIS',
          style: TextStyle(
            color: colors.primaryText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AnalysisMetricsCard(colors: colors),
              const SizedBox(height: 26),
              _SectionTitle(
                title: 'POWER',
                colors: colors,
              ),
              const SizedBox(height: 10),
              _GraphPlaceholder(
                title: 'POWER GRAPH',
                colors: colors,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _LegendDot(
                    color: colors.accent,
                    label: 'Charger Power',
                    colors: colors,
                  ),
                  const SizedBox(width: 20),
                  _LegendDot(
                    color: colors.secondaryText,
                    label: 'Battery-side Power',
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'TEMPERATURE',
                colors: colors,
              ),
              const SizedBox(height: 10),
              _GraphPlaceholder(
                title: 'TEMPERATURE GRAPH',
                colors: colors,
              ),
              const SizedBox(height: 10),
              Text(
                'Temperature vs Time',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'CHARGING BEHAVIOR',
                colors: colors,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colors.card,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 22,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Normal',
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CHARGING CARD
// ============================================================

class _ChargingCard extends StatelessWidget {
  const _ChargingCard({
    required this.charging,
  });

  final bool charging;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              charging ? 'CHARGING' : 'NOT CHARGING',
              style: TextStyle(
                color: charging ? colors.accent : colors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            charging ? '6.2 W' : '0.0 W',
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 48,
              fontWeight: FontWeight.w500,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Measurement(
                  value: charging ? '5.02 V' : '—',
                  label: 'Voltage',
                  colors: colors,
                ),
              ),
              Expanded(
                child: _Measurement(
                  value: charging ? '1.24 A' : '—',
                  label: 'Current',
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Measurement extends StatelessWidget {
  const _Measurement({
    required this.value,
    required this.label,
    required this.colors,
  });

  final String value;
  final String label;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.primaryText,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: colors.secondaryText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BATTERY CARD
// ============================================================

class _BatteryCard extends StatelessWidget {
  const _BatteryCard();

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _InfoValue(
              label: 'Battery',
              value: '62%',
              colors: colors,
            ),
          ),
          Expanded(
            child: _InfoValue(
              label: 'Charging Limit',
              value: '80%',
              colors: colors,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoValue extends StatelessWidget {
  const _InfoValue({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.secondaryText,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: colors.primaryText,
            fontSize: 23,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BUTTON
// ============================================================

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.colors,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final _DashboardColors colors;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: filled
          ? FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primaryText,
          foregroundColor: colors.background,
          disabledBackgroundColor: colors.disabled,
          disabledForegroundColor: colors.secondaryText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      )
          : OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primaryText,
          disabledForegroundColor: colors.secondaryText,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DEVICE CARD
// ============================================================

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.connected,
  });

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    final statusColor = connected
        ? const Color(0xFF4CAF72)
        : const Color(0xFFD95C5C);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _StatusDot(color: statusColor),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Device',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                connected
                    ? 'Smart Charge Box Connected'
                    : 'Smart Charge Box Disconnected',
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.color,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ============================================================
// ANALYSIS COMPONENTS
// ============================================================

class _AnalysisMetricsCard extends StatelessWidget {
  const _AnalysisMetricsCard({
    required this.colors,
  });

  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _AnalysisRow(
            label: 'Session',
            value: '1h 12m',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Energy Supplied',
            value: '42.6 Wh',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Energy Stored',
            value: '36.8 Wh',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Efficiency',
            value: '86.4%',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Peak Power',
            value: '28.4 W',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Average Power',
            value: '21.7 W',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Peak Temperature',
            value: 'Unavailable',
            colors: colors,
          ),
          _Divider(colors: colors),
          _AnalysisRow(
            label: 'Battery Health',
            value: '94%',
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  const _AnalysisRow({
    required this.label,
    required this.value,
    required this.colors,
  });

  final String label;
  final String value;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({
    required this.colors,
  });

  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: colors.border,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.colors,
  });

  final String title;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: colors.primaryText,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _GraphPlaceholder extends StatelessWidget {
  const _GraphPlaceholder({
    required this.title,
    required this.colors,
  });

  final String title;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart_rounded,
              size: 30,
              color: colors.secondaryText,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Graph data will appear here',
              style: TextStyle(
                color: colors.secondaryText.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.colors,
  });

  final Color color;
  final String label;
  final _DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: colors.secondaryText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// THEME COLORS
// ============================================================

class _DashboardColors {
  const _DashboardColors({
    required this.background,
    required this.card,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.disabled,
  });

  final Color background;
  final Color card;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color disabled;

  static _DashboardColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    if (brightness == Brightness.dark) {
      return const _DashboardColors(
        background: Color(0xFF111315),
        card: Color(0xFF191C1F),
        border: Color(0xFF2A2F33),
        primaryText: Color(0xFFF1F3F4),
        secondaryText: Color(0xFF9AA1A8),
        accent: Color(0xFF4F8CFF),
        disabled: Color(0xFF24282C),
      );
    }

    return const _DashboardColors(
      background: Color(0xFFF3F4F5),
      card: Color(0xFFFFFFFF),
      border: Color(0xFFDDE1E5),
      primaryText: Color(0xFF202428),
      secondaryText: Color(0xFF6B727A),
      accent: Color(0xFF2563EB),
      disabled: Color(0xFFE4E7EA),
    );
  }
}