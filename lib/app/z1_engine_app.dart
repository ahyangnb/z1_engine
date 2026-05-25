import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/features/home/pages/engine_home_page.dart';

class Z1EngineApp extends StatelessWidget {
  const Z1EngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EngineMenuController(),
      child: MaterialApp(
        title: 'Z1 Engine',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          scaffoldBackgroundColor: const Color(0xFFF6F8FC),
          useMaterial3: true,
        ),
        home: const EngineHomePage(),
      ),
    );
  }
}
