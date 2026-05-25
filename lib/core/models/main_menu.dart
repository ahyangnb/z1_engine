import 'package:flutter/material.dart';

enum MainMenu {
  obfuscation('混淆', Icons.tune_outlined),
  package('出新包', Icons.inventory_2_outlined),
  sign('签名', Icons.verified_outlined),
  protect('加固', Icons.shield_outlined),
  duplication('重复度', Icons.content_copy_outlined),
  review('预审', Icons.rule_outlined),
  about('关于', Icons.info_outline);

  const MainMenu(this.label, this.icon);

  final String label;
  final IconData icon;
}
