import 'package:flutter/material.dart';

/// A section or screen title in the theme's headline style.
class Heading extends StatelessWidget {
  const Heading(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.headlineMedium);
}
