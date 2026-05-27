import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/core/models/main_menu.dart';
import 'package:z1_engine/features/channel_package/pages/channel_package_page.dart';
import 'package:z1_engine/features/duplication/pages/duplication_page.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/features/home/widgets/top_menu_bar.dart';
import 'package:z1_engine/features/obfuscation/pages/obfuscation_page.dart';
import 'package:z1_engine/features/package/pages/package_page.dart';
// import 'package:z1_engine/features/package_security/pages/package_security_page.dart';
import 'package:z1_engine/features/protect/pages/protect_page.dart';
import 'package:z1_engine/features/sign/pages/sign_page.dart';
import 'package:z1_engine/shared/widgets/placeholder_page.dart';

class EngineHomePage extends StatelessWidget {
  const EngineHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopMenuBar(
              selected: controller.selectedMenu,
              onSelected: controller.selectMenu,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: _CurrentMenuContent(menu: controller.selectedMenu),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentMenuContent extends StatelessWidget {
  const _CurrentMenuContent({required this.menu});

  final MainMenu menu;

  @override
  Widget build(BuildContext context) {
    switch (menu) {
      case MainMenu.obfuscation:
        return const ObfuscationPage();
      case MainMenu.package:
        return const PackagePage();
      case MainMenu.channelPackage:
        return const ChannelPackagePage();
      case MainMenu.sign:
        return const SignPage();
      // case MainMenu.packageSecurity:
      //   return const PackageSecurityPage();
      case MainMenu.protect:
        return const ProtectPage();
      case MainMenu.duplication:
        return const DuplicationPage();
      case MainMenu.review:
        return const PlaceholderPage(
          icon: Icons.fact_check_outlined,
          title: '预审',
          description: '预审界面预留，可继续接入上架前规则、权限、隐私和包体检查。',
        );
      case MainMenu.about:
        return const PlaceholderPage(
          icon: Icons.info_outline,
          title: '关于',
          description: 'Z1 Engine 工具界面。当前版本先展示菜单与配置表单，功能逻辑可按模块继续接入。',
        );
    }
  }
}
