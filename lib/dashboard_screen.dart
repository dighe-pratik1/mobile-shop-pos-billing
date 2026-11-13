import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'inventory_screen.dart';
import 'billing_screen.dart';
import 'reports_screen.dart';
import 'auth_screen.dart';
import 'shop_config.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _udhaarDueNotifications = [];
  double _totalUdhaarDueAmount = 0;
  bool _shownDailyAlertOnce = false;

  @override
  void initState() {
    super.initState();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    await ShopConfig.loadFromDatabase();
    await _checkDailyUdhaarNotifications(autoPopup: true);
  }

  /// Requirement 2: Borrow / Udhaar Notification strictly limited to the branch that gave the borrow
  Future<void> _checkDailyUdhaarNotifications({bool autoPopup = false}) async {
    final supabase = Supabase.instance.client;
    final currentBranch = ShopConfig.current.branchName.trim();
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    try {
      final res = await supabase
          .from('sales')
          .select('*, customers(name, phone)')
          .gt('due_amount', 0)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> dueList = [];
      double sumDue = 0;

      for (final dynamic r in res) {
        final sale = Map<String, dynamic>.from(r as Map);
        final due = (sale['due_amount'] as num?)?.toDouble() ?? 0;
        if (due <= 0) continue;

        final saleBranch = (sale['branch_name'] ?? 'Main Branch').toString().trim();
        final soldByUserId = (sale['sold_by_user_id'] ?? '').toString().trim();

        // Only notify the branch that gave the borrow (or the exact user if branch_name was unset)
        final bool isSameBranch =
            saleBranch.toLowerCase() == currentBranch.toLowerCase() ||
            (saleBranch.isEmpty && soldByUserId.isNotEmpty && soldByUserId == currentUserId);

        if (isSameBranch) {
          sumDue += due;
          dueList.add(sale);
        }
      }

      if (!mounted) return;
      setState(() {
        _udhaarDueNotifications = dueList;
        _totalUdhaarDueAmount = sumDue;
      });

      if (autoPopup && !_shownDailyAlertOnce && dueList.isNotEmpty) {
        _shownDailyAlertOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showDailyUdhaarAlertDialog();
        });
      }
    } catch (_) {}
  }

  void _showDailyUdhaarAlertDialog() {
    final activeBranch = ShopConfig.current.branchName;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$activeBranch • Borrow Reminder',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_udhaarDueNotifications.length} Branch Customers • Pending: ₹${_totalUdhaarDueAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 350,
          child: _udhaarDueNotifications.isEmpty
              ? Center(
                  child: Text(
                    'No pending Borrow / Udhaar customers for $activeBranch today! 🎉',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _udhaarDueNotifications.length,
                  itemBuilder: (context, idx) {
                    final sale = _udhaarDueNotifications[idx];
                    final cust = (sale['customers'] as Map?) ?? {};
                    final name = (cust['name'] ?? 'Customer').toString();
                    final phone = (cust['phone'] ?? '').toString();
                    final saleBranch =
                        (sale['branch_name'] ?? activeBranch).toString();
                    final due = (sale['due_amount'] as num?)?.toDouble() ?? 0;
                    final total = (sale['total_amount'] as num?)?.toDouble() ?? 0;
                    final dt =
                        DateTime.tryParse((sale['created_at'] ?? '').toString())?.toLocal() ??
                            DateTime.now();
                    final daysOld = DateTime.now().difference(dt).inDays;

                    final msg =
                        'Hello *$name* ji,\nGentle reminder from *${ShopConfig.current.shopName} ($saleBranch)* regarding your pending Udhaar balance of *₹${due.toStringAsFixed(0)}* (Purchase Date: ${DateFormat('dd MMM yyyy').format(dt)}).\nKindly arrange payment via Cash or UPI. Thank you! 🙏';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$name ($phone)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Due: ₹${due.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Branch: $saleBranch • Total Bill: ₹${total.toStringAsFixed(0)} • ${DateFormat('dd MMM yyyy').format(dt)} (${daysOld == 0 ? "Today" : "$daysOld days ago"})',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF059669),
                                  ),
                                  onPressed: () => ShopConfig.sendWhatsAppMessage(
                                    context: context,
                                    phone: phone,
                                    message: msg,
                                  ),
                                  icon: const Icon(Icons.chat_rounded, size: 14),
                                  label: const Text('WhatsApp', style: TextStyle(fontSize: 11)),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF2563EB),
                                  ),
                                  onPressed: () => ShopConfig.sendSmsMessage(
                                    context: context,
                                    phone: phone,
                                    message: msg,
                                  ),
                                  icon: const Icon(Icons.sms_rounded, size: 14),
                                  label: const Text('SMS', style: TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  /// Preserves Shop Owner Staff & Granular Access Control Dialog + Branch Name assignment
  void _showOwnerStaffPermissionsDialog() {
    final supabase = Supabase.instance.client;
    final ownerId = ShopConfig.current.effectiveTenantId.isNotEmpty
        ? ShopConfig.current.effectiveTenantId
        : supabase.auth.currentUser?.id;
    final linkEmailCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.manage_accounts_rounded, color: Color(0xFF4338CA)),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shop Owner: Staff & Access Control',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Control what each employee can access & assign their branch',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC7D2FE)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: linkEmailCtrl,
                            decoration: InputDecoration(
                              hintText: 'Enter registered Employee Email to link to your shop...',
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
                          onPressed: () async {
                            final email = linkEmailCtrl.text.trim();
                            if (email.isEmpty) return;
                            try {
                              final msg = await supabase.rpc(
                                'owner_link_employee_by_email',
                                params: {'emp_email': email},
                              );
                              linkEmailCtrl.clear();
                              setDialogState(() {});
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: Colors.green,
                                    content: Text(msg.toString()),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: Colors.red,
                                    content: Text('Could not link employee: $e'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                          label: const Text('Link Staff', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: supabase
                          .from('user_profiles')
                          .select('*')
                          .eq('owner_id', ownerId ?? '')
                          .neq('id', ownerId ?? '')
                          .order('created_at', ascending: false),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final staffList = snapshot.data ?? [];
                        if (staffList.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'No employees linked yet.\n\n'
                                'How multi-device staff login works:\n'
                                '1. Employee registers on their phone/PC (or enters your Shop Owner email during sign-up).\n'
                                '2. You approve them and toggle their exact permissions here!',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: staffList.length,
                          itemBuilder: (context, idx) {
                            final emp = staffList[idx];
                            final String empId = emp['id'].toString();
                            final String email = (emp['email'] ?? '').toString();
                            final String branch = (emp['branch_name'] ?? 'Main Branch').toString();
                            final bool approved = emp['is_approved'] == true;
                            final bool pAdd = (emp['perm_add_stock'] ?? true) == true;
                            final bool pEdit = (emp['perm_edit_delete_stock'] ?? false) == true;
                            final bool pSell = (emp['perm_pos_sell'] ?? true) == true;
                            final bool pDisc = (emp['perm_give_discount'] ?? true) == true;
                            final bool pRep = (emp['perm_view_reports'] ?? false) == true;
                            final bool pUdhaar = (emp['perm_settle_udhaar'] ?? true) == true;
                            final bool pProfit = (emp['perm_view_profit'] ?? false) == true;

                            Future<void> updatePerm(String field, dynamic value) async {
                              await supabase
                                  .from('user_profiles')
                                  .update({field: value})
                                  .eq('id', empId);
                              setDialogState(() {});
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: approved ? const Color(0xFFC7D2FE) : Colors.red.shade200,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                email,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                'Branch: $branch • ${approved ? "ACTIVE EMPLOYEE" : "LOCKED / PENDING"}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: approved ? const Color(0xFF059669) : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () async {
                                            final bCtrl = TextEditingController(text: branch);
                                            final newBranch = await showDialog<String>(
                                              context: context,
                                              builder: (bCtx) => AlertDialog(
                                                title: const Text(
                                                  'Assign Branch Name',
                                                  style: TextStyle(fontSize: 15),
                                                ),
                                                content: TextField(
                                                  controller: bCtrl,
                                                  decoration: const InputDecoration(
                                                    labelText: 'Branch Name (e.g. Branch 1, Market Store)',
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(bCtx),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(bCtx, bCtrl.text.trim()),
                                                    child: const Text('Save'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (newBranch != null && newBranch.isNotEmpty) {
                                              await updatePerm('branch_name', newBranch);
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.store_mall_directory_outlined,
                                            size: 15,
                                          ),
                                          label: const Text(
                                            'Set Branch',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        Switch(
                                          value: approved,
                                          activeColor: const Color(0xFF059669),
                                          onChanged: (v) => updatePerm('is_approved', v),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 12),
                                    const Text(
                                      'Toggle Employee Feature Access:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        FilterChip(
                                          label: const Text('Add Stock', style: TextStyle(fontSize: 11)),
                                          selected: pAdd,
                                          onSelected: (v) => updatePerm('perm_add_stock', v),
                                        ),
                                        FilterChip(
                                          label: const Text('Sell in POS', style: TextStyle(fontSize: 11)),
                                          selected: pSell,
                                          onSelected: (v) => updatePerm('perm_pos_sell', v),
                                        ),
                                        FilterChip(
                                          label: const Text('Give Discount', style: TextStyle(fontSize: 11)),
                                          selected: pDisc,
                                          onSelected: (v) => updatePerm('perm_give_discount', v),
                                        ),
                                        FilterChip(
                                          label: const Text('Edit/Revoke Stock', style: TextStyle(fontSize: 11)),
                                          selected: pEdit,
                                          onSelected: (v) => updatePerm('perm_edit_delete_stock', v),
                                        ),
                                        FilterChip(
                                          label: const Text('Collect Udhaar', style: TextStyle(fontSize: 11)),
                                          selected: pUdhaar,
                                          onSelected: (v) => updatePerm('perm_settle_udhaar', v),
                                        ),
                                        FilterChip(
                                          label: const Text('View Sales Reports', style: TextStyle(fontSize: 11)),
                                          selected: pRep,
                                          onSelected: (v) => updatePerm('perm_view_reports', v),
                                        ),
                                        FilterChip(
                                          selectedColor: const Color(0xFFFEE2E2),
                                          checkmarkColor: Colors.red,
                                          label: Text(
                                            'See Profit & Cost (Sensitive)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: pProfit ? Colors.red.shade900 : Colors.black87,
                                            ),
                                          ),
                                          selected: pProfit,
                                          onSelected: (v) => updatePerm('perm_view_profit', v),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAdminApprovalManagerDialog() {
    final supabase = Supabase.instance.client;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF059669)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Database Admin: User Approvals',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 360,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('user_profiles')
                    .select('id, email, shop_name, role, is_approved, created_at')
                    .order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Set your role to "admin" in Supabase user_profiles to manage all users here.\n\nError: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    );
                  }
                  final users = snapshot.data ?? [];
                  if (users.isEmpty) {
                    return const Center(child: Text('No registered users found.'));
                  }

                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, idx) {
                      final u = users[idx];
                      final bool approved = u['is_approved'] == true;
                      final String email = (u['email'] ?? '').toString();
                      final String shopName = (u['shop_name'] ?? '').toString();
                      final String role = (u['role'] ?? 'shop_owner').toString();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: SwitchListTile(
                          value: approved,
                          activeColor: const Color(0xFF059669),
                          title: Text(
                            shopName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            '$email\nRole: $role  •  Status: ${approved ? "APPROVED (true)" : "LOCKED (false)"}',
                            style: TextStyle(
                              fontSize: 11,
                              color: approved ? const Color(0xFF059669) : Colors.red,
                            ),
                          ),
                          onChanged: (val) async {
                            await supabase
                                .from('user_profiles')
                                .update({'is_approved': val})
                                .eq('id', u['id']);
                            setDialogState(() {});
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showShopProfileDialog() {
    if (!ShopConfig.current.isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the Shop Owner can modify store branding.')),
      );
      return;
    }

    final current = ShopConfig.current;
    final nameCtrl = TextEditingController(text: current.shopName);
    final branchCtrl = TextEditingController(text: current.branchName);
    final phoneCtrl = TextEditingController(text: current.shopPhone);
    final addressCtrl = TextEditingController(text: current.shopAddress);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.storefront_rounded, color: Color(0xFF4338CA)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shop Branding & Invoice Header',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Set your shop name once. It will automatically print on all customer bills and barcode stickers.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Shop Name (Displayed on Bills)',
                      prefixIcon: const Icon(Icons.store),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: branchCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Branch Name',
                      prefixIcon: const Icon(Icons.account_tree_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Shop Contact Number (Optional)',
                      prefixIcon: const Icon(Icons.call),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Shop Address / Tagline',
                      hintText: 'e.g. Main Market, Near Bus Stand • Mobiles & Repair',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
              onPressed: isSaving
                  ? null
                  : () async {
                      final navigator = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(this.context);
                      setDialogState(() => isSaving = true);
                      try {
                        await ShopConfig.updateShopProfile(
                          shopName: nameCtrl.text,
                          shopPhone: phoneCtrl.text,
                          shopAddress: addressCtrl.text,
                          branchName: branchCtrl.text,
                        );
                        await _checkDailyUdhaarNotifications(autoPopup: false);
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Shop name & branch updated permanently!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to save shop name: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Save Permanently'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShopProfile>(
      valueListenable: ShopConfig.notifier,
      builder: (context, shop, _) {
        final bool showReportsTab = shop.canViewReports;
        final List<Widget> activeScreens = [
          const InventoryScreen(),
          const BillingScreen(),
          if (showReportsTab) const ReportsScreen(initialTabIndex: 0),
          if (shop.isOwner) const ReportsScreen(initialTabIndex: 5),
        ];

        final int safeIndex =
            _currentIndex >= activeScreens.length ? 0 : _currentIndex;

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            backgroundColor: const Color(0xFF1E1B4B),
            foregroundColor: Colors.white,
            title: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: shop.isOwner ? _showShopProfileDialog : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF312E81),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: Color(0xFF818CF8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  shop.shopName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: shop.isOwner
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFD97706),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  shop.isOwner ? 'OWNER' : 'STAFF (${shop.branchName})',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${shop.branchName} • ${shop.shopAddress}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Color(0xFFC7D2FE)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Printer & Auto-Message Settings Button
              IconButton(
                tooltip: 'Printer & Auto-Message Settings',
                onPressed: () =>
                    ShopConfig.showAutoMessagingAndPrinterSettingsDialog(context),
                icon: const Icon(Icons.print_outlined, color: Color(0xFFA5B4FC)),
              ),
              // Requirement 2: Branch-Isolated Udhaar Notification Bell with Badge
              IconButton(
                tooltip: '${shop.branchName} Borrow / Udhaar Notifications',
                onPressed: () async {
                  await _checkDailyUdhaarNotifications(autoPopup: false);
                  if (mounted) _showDailyUdhaarAlertDialog();
                },
                icon: Badge(
                  isLabelVisible: _udhaarDueNotifications.isNotEmpty,
                  backgroundColor: const Color(0xFFDC2626),
                  label: Text(
                    '${_udhaarDueNotifications.length}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Colors.amber),
                ),
              ),
              if (shop.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: _showAdminApprovalManagerDialog,
                    icon: const Icon(Icons.verified_user_rounded, size: 15, color: Colors.white),
                    label: const Text('Approvals', style: TextStyle(fontSize: 11)),
                  ),
                ),
              if (shop.isOwner) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFF4338CA),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: _showOwnerStaffPermissionsDialog,
                    icon: const Icon(Icons.manage_accounts_rounded, size: 16, color: Colors.white),
                    label: const Text('Staff & Access', style: TextStyle(fontSize: 11)),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: const Color(0xFF312E81),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _showShopProfileDialog,
                  icon: const Icon(
                    Icons.store_mall_directory_rounded,
                    size: 16,
                    color: Color(0xFFA5B4FC),
                  ),
                  label: const Text('Shop Name', style: TextStyle(fontSize: 12)),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.logout_rounded),
                tooltip: 'Sign Out',
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await Supabase.instance.client.auth.signOut();
                  if (!mounted) return;
                  navigator.pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  );
                },
              ),
            ],
          ),
          body: activeScreens[safeIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: NavigationBar(
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFE0E7FF),
              selectedIndex: safeIndex,
              onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2_rounded, color: Color(0xFF4338CA)),
                  label: 'Inventory & SR',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.point_of_sale_outlined),
                  selectedIcon: const Icon(Icons.point_of_sale_rounded, color: Color(0xFF4338CA)),
                  label: shop.canSeeProfit ? 'POS & Billing' : 'POS Counter',
                ),
                if (showReportsTab)
                  NavigationDestination(
                    icon: const Icon(Icons.analytics_outlined),
                    selectedIcon: const Icon(Icons.analytics_rounded, color: Color(0xFF4338CA)),
                    label: shop.canSeeProfit ? 'Reports & Profit' : 'Sales & Udhaar',
                  ),
                if (shop.isOwner)
                  const NavigationDestination(
                    icon: Icon(Icons.store_mall_directory_outlined),
                    selectedIcon: Icon(Icons.store_mall_directory_rounded, color: Color(0xFF4338CA)),
                    label: 'Branch Sales',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}