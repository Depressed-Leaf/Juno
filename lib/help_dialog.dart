import 'dart:math';
import 'package:flutter/material.dart';

// Add your quotes here — randomly picked each time the ? is tapped
const List<String> _quotes = [
  "Time is a flat circle, everything we've ever done or will do, we'll do over and over again.",
  "The impediment to action advances action. What stands in the way becomes the way.",
  "We are all just walking each other home.",
  "Not all those who wander are lost.",
  "The most terrifying fact about the universe is not that it is hostile but that it is indifferent.",
  "Whatever you are, be a good one.",
  "Present though, Re-enacting the myth of Sisyphus, except the boulder is this syllabus and the hill is infinite.",
  "Chronology is a comforting illusion; I am merely re-enacting the same roll call that has already occurred an infinite number of times.",
  "We have done this before, we will do this again, and the illusion of a new morning is shattered the moment you call my name.",
  // Add yours here ↓
];

class HelpDialog extends StatelessWidget {
  const HelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final quote = _quotes[Random().nextInt(_quotes.length)];

    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Darkened backdrop
            Container(color: Colors.black.withOpacity(0.82)),

            // Quote centered
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Opening marks
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '\u201C',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 72,
                        height: 0.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    quote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      height: 1.55,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Closing marks
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '\u201D',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 72,
                        height: 0.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tap to dismiss hint
            const Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Text(
                'tap anywhere to close',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 12, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}