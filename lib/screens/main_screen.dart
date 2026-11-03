import 'package:flutter/material.dart';
import 'package:livemeet/screens/dashboard_screen.dart';
import 'package:livemeet/screens/import_screen.dart';
import 'package:livemeet/screens/live_screen.dart';
import 'package:livemeet/screens/meetings_screen.dart';
import 'package:livemeet/widgets/Button.dart';

const kHome = 0;
const kLive = 1;
const kMeetings = 2;
const kImport = 3;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = kHome;
  bool busy = false;

  void go(int i) {
    if (!mounted || busy) return;
    setState(() => index = i);
  }

  void setBusy(bool value) {
    if (!mounted) return;
    setState(() => busy = value);
  }

  Widget navigationButton(String label, int tabIndex, {required bool narrow}) {
    return Expanded(
      child: Button(
        text: label,
        // Responsive: slightly smaller text and height on narrow phones.
        // Button already shrinks its text to fit on one line.
        fontSize: narrow ? 13 : 14,
        height: narrow ? 52 : 60,
        color: index == tabIndex ? const Color(0xFFDDF35C) : Colors.white,
        foreColor: index == tabIndex ? Colors.black : Colors.white,
        onTap: () => go(tabIndex),
        fontWeight: FontWeight.bold,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Responsive: tighter nav bar spacing on narrow phones so the four
    // buttons get more room.
    final narrow = MediaQuery.sizeOf(context).width < 360;

    return Scaffold(
      body: [
        DashboardScreen(onNavigate: go, onBusyChanged: setBusy),
        LiveScreen(onNavigate: go, onBusyChanged: setBusy),
        MeetingsScreen(onNavigate: go, onBusyChanged: setBusy),
        ImportScreen(onNavigate: go, onBusyChanged: setBusy),
      ][index],
      bottomNavigationBar: SafeArea(
        // Keeps the nav bar clear of the system gesture/navigation bar.
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(narrow ? 8 : 12),
          margin: EdgeInsets.all(narrow ? 8 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            color: Colors.black,
          ),
          width: double.infinity,
          child: Row(
            spacing: narrow ? 4 : 6,
            children: [
              navigationButton('Home', kHome, narrow: narrow),
              navigationButton('Live', kLive, narrow: narrow),
              navigationButton('Meetings', kMeetings, narrow: narrow),
              navigationButton('Import', kImport, narrow: narrow),
            ],
          ),
        ),
      ),
    );
  }
}