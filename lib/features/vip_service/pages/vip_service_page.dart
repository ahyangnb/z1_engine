import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:z1_engine/features/home/controllers/engine_menu_controller.dart';
import 'package:z1_engine/shared/widgets/section_panel.dart';

enum _PaymentMethod {
  wechat('微信支付', Icons.chat_bubble_outline),
  alipay('支付宝', Icons.account_balance_wallet_outlined);

  const _PaymentMethod(this.label, this.icon);

  final String label;
  final IconData icon;
}

class VipServicePage extends StatefulWidget {
  const VipServicePage({super.key});

  @override
  State<VipServicePage> createState() => _VipServicePageState();
}

class _VipServicePageState extends State<VipServicePage> {
  final TextEditingController _activationCodeController =
      TextEditingController();
  _PaymentMethod _selectedPaymentMethod = _PaymentMethod.wechat;

  @override
  void dispose() {
    _activationCodeController.dispose();
    super.dispose();
  }

  Future<void> _activate(BuildContext context) async {
    final controller = context.read<EngineMenuController>();
    final activated = await controller.activateVipService(
      _activationCodeController.text,
    );
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(activated ? '增值服务已激活' : controller.vipActivationMessage),
      ),
    );
  }

  Future<void> _confirmPayment(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('支付正在对接中'),
          content: Text('已选择${_selectedPaymentMethod.label}，确认支付能力正在对接中。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<EngineMenuController>();

    return SectionPanel(
      title: '增值服务',
      subtitle: 'VIP 增值服务支持更多混淆参数与超过 5 个渠道包。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VipHero(active: controller.isVipServiceActive),
          const SizedBox(height: 18),
          const _FeatureGrid(),
          const SizedBox(height: 24),
          Text(
            '收银台',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _CheckoutPanel(
            selectedPaymentMethod: _selectedPaymentMethod,
            onPaymentMethodChanged: (method) {
              setState(() {
                _selectedPaymentMethod = method;
              });
            },
            onConfirmPayment: () => _confirmPayment(context),
          ),
          const SizedBox(height: 24),
          Text(
            '激活增值服务',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ActivationPanel(
            controller: _activationCodeController,
            active: controller.isVipServiceActive,
            activationCode: controller.vipActivationCode,
            message: controller.vipActivationMessage,
            onActivate: () => _activate(context),
          ),
        ],
      ),
    );
  }
}

class _VipHero extends StatelessWidget {
  const _VipHero({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF8D36A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1B8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: Color(0xFF8A5A00),
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'VIP 增值服务',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusPill(active: active),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '200 元 / 月，解锁更多混淆参数，提升防重复度，并允许渠道包数量超过 5 个。',
                  style: TextStyle(color: Color(0xFF647084), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8FFF3) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? const Color(0xFF22C55E) : const Color(0xFFF8D36A),
        ),
      ),
      child: Text(
        active ? '已激活' : '未激活',
        style: TextStyle(
          color: active ? const Color(0xFF15803D) : const Color(0xFF8A5A00),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _FeatureCard(
          icon: Icons.tune_outlined,
          title: '更多混淆参数',
          description: '支持控制流、调用链、资源指纹等高级参数。',
        ),
        _FeatureCard(
          icon: Icons.fingerprint_outlined,
          title: '防重复度更高',
          description: '增强重复度扰动，降低包体特征相似度。',
        ),
        _FeatureCard(
          icon: Icons.sell_outlined,
          title: 'VIP 渠道包',
          description: '渠道包生成数量可超过免费版 5 个限制。',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 330,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD6DDE8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF1F2937),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF647084),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  const _CheckoutPanel({
    required this.selectedPaymentMethod,
    required this.onPaymentMethodChanged,
    required this.onConfirmPayment,
  });

  final _PaymentMethod selectedPaymentMethod;
  final ValueChanged<_PaymentMethod> onPaymentMethodChanged;
  final VoidCallback onConfirmPayment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DDE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('增值服务月费', style: TextStyle(fontWeight: FontWeight.w800)),
              Spacer(),
              Text(
                '¥200 / 月',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _PaymentMethod.values.map((method) {
              return ChoiceChip(
                selected: selectedPaymentMethod == method,
                avatar: Icon(method.icon, size: 18),
                label: Text(method.label),
                onSelected: (_) => onPaymentMethodChanged(method),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onConfirmPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('确认支付'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已取消本次支付')));
                },
                icon: const Icon(Icons.close_outlined),
                label: const Text('取消'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivationPanel extends StatelessWidget {
  const _ActivationPanel({
    required this.controller,
    required this.active,
    required this.activationCode,
    required this.message,
    required this.onActivate,
  });

  final TextEditingController controller;
  final bool active;
  final String activationCode;
  final String message;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final helperText = active
        ? '当前激活码：$activationCode'
        : '购买后会弹出激活码，请粘贴到这里完成激活。';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6DDE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            enabled: !active,
            decoration: InputDecoration(
              labelText: '激活码',
              hintText: '例如：Z1VIP-ABC123',
              helperText: helperText,
              prefixIcon: const Icon(Icons.key_outlined),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                color: active ? const Color(0xFF15803D) : Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: active ? null : onActivate,
            icon: const Icon(Icons.verified_user_outlined),
            label: Text(active ? '已激活' : '立即激活'),
          ),
        ],
      ),
    );
  }
}
