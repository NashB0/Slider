import 'package:flutter/material.dart';

void main() {
  runApp(const SliderApp());
}

class SliderApp extends StatelessWidget {
  const SliderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slider',
      home: Scaffold(
        appBar: AppBar(title: const Text('Slider')),
        body: const Center(
          child: Text('¡Slider funciona!'),
        ),
      ),
    );
  }
}
