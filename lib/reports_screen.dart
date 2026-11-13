import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shop_config.dart';

class ReportsScreen extends StatefulWidget {
  final int initialTabIndex;
  const ReportsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;

  late final TabController _reportTabController;

  bool _loading = true;
  bool _summaryLoading = true;

  String _selectedFilter = 'Last 7 Days';
  String _chartViewMode = 'Daily';

  // Requirement 4: Compact layout controls for Tab 1 so all sold items are visible at a time
  bool _showExpandedKpisInTab1 = false;
  bool _showFlatSoldItemsInTab1 = true; // true = All Sold Items compact rows, false = Compact Bill Cards

  // State for the dedicated Item Profit tab
  String _profitCategoryFilter = 'All'; // 'All', 'Smartphones', 'Accessories'
  bool _groupProfitByModel = false; // false = Every Sold Item, true = Model-Wise Profit Rank
  String _profitSearchQuery = '';
  String _profitSortBy = 'Newest'; // 'Newest', 'Highest Profit', 'Lowest Profit', 'Margin %'

  // Sales Tab Search & Payment Mode Filter
  String _salesSearchQuery = '';
  String _salesPaymentFilter = 'All'; // 'All', 'Cash', 'UPI', 'Udhaar', 'Card/EMI'

  // Udhaar Tab Search & Customer Grouping Toggle
  String _udhaarSearchQuery = '';
  bool _groupUdhaarByCustomer = false;

  // Unsold Stock Tab Search & Filter
  String _unsoldSearchQuery = '';
  String _unsoldFilterType = 'All'; // 'All', 'Phones', 'Accessories', 'Low Stock', 'Old (>30d)'

  // Branch Sales Search
  String _branchSearchQuery = '';

  // Chart Metric Toggle & Brand / Branch Breakdown
  bool _showProfitInChart = false;
  Map<String, Map<String, dynamic>> _brandPerformanceMap = {};
  Map<String, Map<String, dynamic>> _branchPerformanceMap = {};
  Map<String, double> _paymentModeBreakdown = {};

  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  double _totalRevenue = 0;
  double _totalCost = 0;
  double _totalProfit = 0;
  double _totalDiscountGiven = 0;
  double _totalCashCollected = 0;
  double _totalOnlineCollected = 0;
  double _totalUdhaarDue = 0;
  int _totalItemsSold = 0;

  List<dynamic> _salesList = [];
  List<dynamic> _udhaarSalesList = [];
  List<Map<String, dynamic>> _itemizedProfitList = [];

  double _todayRevenue = 0;
  double _todayProfit = 0;
  double _weekRevenue = 0;
  double _weekProfit = 0;
  double _monthRevenue = 0;
  double _monthProfit = 0;
  double _yearRevenue = 0;
  double _yearProfit = 0;

  List<dynamic> _unsoldStockItems = [];
  double _unsoldTotalCost = 0;
  double _unsoldTotalValue = 0;

  Map<String, Map<String, dynamic>> _topProductsMap = {};
  List<Map<String, dynamic>> _chartDataPoints = [];

  double _smartphoneRevenue = 0;
  double _accessoryRevenue = 0;
  double _smartphoneProfit = 0;
  double _accessoryProfit = 0;

  @override
  void initState() {
    super.initState();

    // 6 Tabs: Sales & Cashbook, Item Profit, Udhaar Khata, Charts & Top Sellers, Unsold Stock, Branch Sales
    _reportTabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );

    _applyFilter('Last 7 Days', fetch: false);
    _fetchSummaryAndUnsold();
    _fetchFilteredReports();
  }

  @override
  void dispose() {
    _reportTabController.dispose();
    super.dispose();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int _integer(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    return value is List ? value : <dynamic>[];
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _money(dynamic value) => _number(value).toStringAsFixed(0);

  void _openFullBillFromSale(Map<String, dynamic> sale) {
    final customer = _asMap(sale['customers']);
    final items = _asList(sale['sale_items']);
    final saleId = (sale['id'] ?? '').toString();
    final invoiceId =
        saleId.length >= 8 ? saleId.substring(0, 8).toUpperCase() : saleId;
    final date = _parseDate(sale['created_at']) ?? DateTime.now();

    num calculatedOriginalSubtotal = 0;
    final List<Map<String, dynamic>> lineItems = [];

    for (final dynamic entry in items) {
      final line = _asMap(entry);
      final prod = _asMap(line['products']);
      final stock = _asMap(line['stock_items']);
      final int qty = _integer(line['quantity'], fallback: 1);
      final num unitMrp = _number(prod['selling_price']);
      final num soldPrice = _number(line['sold_price']);
      final num lineOriginal = unitMrp > 0 ? (unitMrp * qty) : soldPrice;

      calculatedOriginalSubtotal += lineOriginal;

      final ramRom = (prod['ram_rom'] ?? '').toString().trim();
      final color = (prod['color'] ?? '').toString().trim();
      final details = (prod['variant_details'] ?? '').toString().trim();
      final specParts = [
        if (ramRom.isNotEmpty) ramRom,
        if (color.isNotEmpty) color,
        if (details.isNotEmpty) details,
      ];

      lineItems.add({
        'itemName': '${prod['brand'] ?? ''} ${prod['title'] ?? 'Item'}'.trim(),
        'specs': specParts.join(' • '),
        'imei1': (stock['imei_or_serial'] ?? '').toString(),
        'imei2': (stock['imei_2'] ?? '').toString(),
        'quantity': qty,
        'unitPrice': unitMrp > 0 ? unitMrp : (soldPrice / max(1, qty)),
        'lineTotal': lineOriginal,
        'costPrice': _number(line['cost_price']),
        'profit': _number(line['profit']),
      });
    }

    final num finalBill = _number(sale['total_amount']);
    final num storedSubtotal = _number(sale['subtotal_amount']);
    final num storedDiscount = _number(sale['discount_amount']);

    final num effectiveSubtotal = storedSubtotal > 0
        ? storedSubtotal
        : (calculatedOriginalSubtotal > finalBill
            ? calculatedOriginalSubtotal
            : finalBill);
    final num effectiveDiscount = storedDiscount > 0
        ? storedDiscount
        : max(0, effectiveSubtotal - finalBill);

    ShopConfig.showFullInvoiceDialog(
      context: context,
      invoiceId: invoiceId,
      customerName: (customer['name'] ?? 'Walk-in Customer').toString(),
      customerPhone: (customer['phone'] ?? '').toString(),
      lineItems: lineItems,
      subtotalAmount: effectiveSubtotal,
      discountAmount: effectiveDiscount,
      finalAmount: finalBill,
      paidAmount: _number(sale['paid_amount']),
      dueAmount: _number(sale['due_amount']),
      cashPaid: _number(sale['cash_paid']),
      onlinePaid: _number(sale['online_paid']),
      paymentMode: (sale['payment_mode'] ?? 'Cash').toString(),
      paymentStatus: (sale['payment_status'] ?? 'Paid').toString(),
      warrantyPeriod: (sale['warranty_period'] ?? 'No Warranty').toString(),
      notes: (sale['notes'] ?? '').toString(),
      date: date,
      totalProfit: _number(sale['total_profit']),
      totalCost: _number(sale['total_cost']),
    );
  }

  Future<void> _editSaleNotesOrWarrantyDialog(Map<String, dynamic> sale) async {
    final saleId = sale['id'];
    if (saleId == null) return;

    final notesCtrl =
        TextEditingController(text: (sale['notes'] ?? '').toString());
    final warrantyCtrl = TextEditingController(
        text: (sale['warranty_period'] ?? 'No Warranty').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Edit Bill Warranty / Note',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: warrantyCtrl,
              decoration: InputDecoration(
                labelText: 'Warranty Period',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Bill Note / Remark',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    try {
      await supabase.from('sales').update({
        'warranty_period': warrantyCtrl.text.trim(),
        'notes': notesCtrl.text.trim(),
      }).eq('id', saleId);

      _showMessage('Bill details updated!');
      await _fetchFilteredReports();
    } catch (e) {
      _showMessage('Could not update bill: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // NEW FUNCTION 1: EDIT SOLD ITEM (PRICE, COST, WARRANTY, CUSTOMER & NOTES)
  // ---------------------------------------------------------------------------
  Future<void> _editSoldItemDialog(Map<String, dynamic> item) async {
    final sale = _asMap(item['sale']);
    final line = _asMap(item['line']);
    final saleId = sale['id'];
    final saleItemId = line['id'] ?? item['sale_item_id'];
    if (saleId == null) return;

    final canSeeProfit = ShopConfig.current.canSeeProfit;
    final customer = _asMap(sale['customers']);

    final soldPriceCtrl =
        TextEditingController(text: _money(item['sold_price']));
    final costPriceCtrl =
        TextEditingController(text: _money(item['cost_price']));
    final custNameCtrl = TextEditingController(
        text: (customer['name'] ?? item['customer_name'] ?? '').toString());
    final custPhoneCtrl = TextEditingController(
        text: (customer['phone'] ?? item['customer_phone'] ?? '').toString());
    final warrantyCtrl = TextEditingController(
        text: (item['warranty'] ?? sale['warranty_period'] ?? 'No Warranty')
            .toString());
    final notesCtrl =
        TextEditingController(text: (sale['notes'] ?? '').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Color(0xFF4338CA)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Edit Sold Item: ${item['name']}',
                style:
                    const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: soldPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Net Sold Price (₹)',
                        prefixText: '₹ ',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (canSeeProfit) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: costPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Cost Price (₹)',
                          prefixText: '₹ ',
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: custNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Customer Name',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: custPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Customer Phone',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: warrantyCtrl,
                decoration: InputDecoration(
                  labelText: 'Warranty Period',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Bill Note / Remark',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4338CA)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    try {
      final oldSold = _number(item['sold_price']);
      final oldCost = _number(item['cost_price']);
      final newSold = _number(soldPriceCtrl.text.trim());
      final newCost =
          canSeeProfit ? _number(costPriceCtrl.text.trim()) : oldCost;
      final newProfit = newSold - newCost;

      if (saleItemId != null) {
        await supabase.from('sale_items').update({
          'sold_price': newSold,
          'cost_price': newCost,
          'profit': newProfit,
          'warranty_period': warrantyCtrl.text.trim(),
        }).eq('id', saleItemId);
      }

      if (sale['customer_id'] != null) {
        await supabase.from('customers').update({
          'name': custNameCtrl.text.trim(),
          'phone': custPhoneCtrl.text.trim(),
        }).eq('id', sale['customer_id']);
      }

      final diffSold = newSold - oldSold;
      final diffCost = newCost - oldCost;

      final currentTotal = _number(sale['total_amount']);
      final currentCost = _number(sale['total_cost']);
      final currentPaid = _number(sale['paid_amount']);
      final currentDue = _number(sale['due_amount']);
      final currentCash = _number(sale['cash_paid']);
      final currentOnline = _number(sale['online_paid']);

      final updatedTotal = max(0.0, currentTotal + diffSold);
      final updatedCost = max(0.0, currentCost + diffCost);
      final updatedProfit = updatedTotal - updatedCost;

      double updatedPaid = currentPaid;
      double updatedDue = currentDue;
      double updatedCash = currentCash;
      double updatedOnline = currentOnline;

      if (currentDue <= 0) {
        updatedPaid = updatedTotal;
        updatedDue = 0;
        if (currentOnline > 0 && currentCash == 0) {
          updatedOnline = updatedTotal;
        } else if (currentCash > 0 && currentOnline == 0) {
          updatedCash = updatedTotal;
        }
      } else {
        updatedDue = max(0.0, updatedTotal - updatedPaid);
      }

      await supabase.from('sales').update({
        'total_amount': updatedTotal,
        'total_cost': updatedCost,
        'total_profit': updatedProfit,
        'paid_amount': updatedPaid,
        'due_amount': updatedDue,
        'cash_paid': updatedCash,
        'online_paid': updatedOnline,
        'payment_status': updatedDue <= 0
            ? 'Paid'
            : (updatedPaid > 0 ? 'Partial / Due' : 'Udhaar (Unpaid)'),
        'warranty_period': warrantyCtrl.text.trim(),
        'notes': notesCtrl.text.trim(),
      }).eq('id', saleId);

      _showMessage('Sold item and bill updated successfully!');
      await _fetchFilteredReports();
      await _fetchSummaryAndUnsold();
    } catch (e) {
      _showMessage('Failed to update sold item: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // NEW FUNCTION 2: REVOKE SOLD ITEM (SINGLE ITEM RETURN OR FULL BILL RETURN)
  // ---------------------------------------------------------------------------
  Future<void> _revokeSoldItem(Map<String, dynamic> item) async {
    final sale = _asMap(item['sale']);
    final allSaleItems = _asList(sale['sale_items']);

    // If this bill only has 1 item, revoking the item is identical to revoking the bill
    if (allSaleItems.length <= 1) {
      await _revokeSale(sale);
      return;
    }

    final line = _asMap(item['line']);
    final saleId = sale['id'];
    final saleItemId = line['id'] ?? item['sale_item_id'];
    final stockItemId = line['stock_item_id'] ?? item['stock_item_id'];
    if (saleId == null || saleItemId == null) {
      await _revokeSale(sale);
      return;
    }

    final bool isBulk = item['is_bulk'] == true;
    final int soldQty = _integer(item['quantity'], fallback: 1);
    final double itemSoldPrice = _number(item['sold_price']);
    final double itemCostPrice = _number(item['cost_price']);
    final String itemName = (item['name'] ?? 'Item').toString();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Revoke / Return Sold Item?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$itemName × $soldQty (₹${_money(itemSoldPrice)})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'This bill contains ${allSaleItems.length} items. Would you like to revoke only this item or the entire bill?',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'FULL_BILL'),
            child: const Text('Revoke Entire Bill',
                style: TextStyle(fontSize: 11.5)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'SINGLE_ITEM'),
            child: const Text('Revoke This Item',
                style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );

    if (choice == null) return;
    if (choice == 'FULL_BILL') {
      await _revokeSale(sale);
      return;
    }

    try {
      if (stockItemId != null) {
        if (isBulk) {
          final stock = await supabase
              .from('stock_items')
              .select('quantity')
              .eq('id', stockItemId)
              .maybeSingle();

          if (stock != null) {
            final currentQty = _integer(stock['quantity']);
            await supabase.from('stock_items').update({
              'quantity': currentQty + soldQty,
              'status': 'Available',
            }).eq('id', stockItemId);
          }
        } else {
          await supabase.from('stock_items').update({
            'status': 'Available',
            'quantity': 1,
          }).eq('id', stockItemId);
        }
      }

      await supabase.from('sale_items').delete().eq('id', saleItemId);

      final currentTotal = _number(sale['total_amount']);
      final currentCost = _number(sale['total_cost']);
      final currentPaid = _number(sale['paid_amount']);
      final currentDue = _number(sale['due_amount']);
      final currentCash = _number(sale['cash_paid']);
      final currentOnline = _number(sale['online_paid']);

      final newTotal = max(0.0, currentTotal - itemSoldPrice);
      final newCost = max(0.0, currentCost - itemCostPrice);
      final newProfit = newTotal - newCost;

      double newPaid = currentPaid;
      double newDue = currentDue;
      double newCash = currentCash;
      double newOnline = currentOnline;

      if (currentDue <= 0) {
        newPaid = newTotal;
        newDue = 0;
        if (currentOnline > 0 && currentCash == 0) {
          newOnline = newTotal;
        } else if (currentCash > 0 && currentOnline == 0) {
          newCash = newTotal;
        }
      } else {
        if (newPaid > newTotal) newPaid = newTotal;
        newDue = max(0.0, newTotal - newPaid);
      }

      await supabase.from('sales').update({
        'total_amount': newTotal,
        'total_cost': newCost,
        'total_profit': newProfit,
        'paid_amount': newPaid,
        'due_amount': newDue,
        'cash_paid': newCash,
        'online_paid': newOnline,
        'payment_status': newDue <= 0
            ? 'Paid'
            : (newPaid > 0 ? 'Partial / Due' : 'Udhaar (Unpaid)'),
      }).eq('id', saleId);

      if (!mounted) return;
      _showMessage('Sold item revoked and restored to Available Stock.');
      await _fetchFilteredReports();
      await _fetchSummaryAndUnsold();
    } catch (error) {
      _showMessage('Failed to revoke item: $error', isError: true);
    }
  }

  void _openExportReportSheet() {
    final dateFmt = DateFormat('dd MMM yyyy');
    final periodStr =
        '${dateFmt.format(_selectedDateRange.start)} to ${dateFmt.format(_selectedDateRange.end)}';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export / Share Business Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Period: $periodStr (${_salesList.length} Bills)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFECFDF5),
                child: Icon(Icons.chat_rounded, color: Color(0xFF059669)),
              ),
              title: const Text(
                'Share WhatsApp Daily / Period Summary',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: const Text(
                'Formatted summary of Cash, UPI, Udhaar, Sales & Net Profit',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                final sb = StringBuffer();
                sb.writeln('📊 *SHOP REPORT ($periodStr)*');
                sb.writeln('----------------------------');
                sb.writeln(
                    '🧾 Total Bills: ${_salesList.length} ($_totalItemsSold Units)');
                sb.writeln('💰 Net Sales: ₹${_money(_totalRevenue)}');
                sb.writeln('🏷️ Discounts Given: ₹${_money(_totalDiscountGiven)}');
                sb.writeln('📦 Purchase Cost: ₹${_money(_totalCost)}');
                sb.writeln('📈 *Net Profit: +₹${_money(_totalProfit)}*');
                sb.writeln('----------------------------');
                sb.writeln('💵 Cash Collected: ₹${_money(_totalCashCollected)}');
                sb.writeln('📱 UPI / Online: ₹${_money(_totalOnlineCollected)}');
                sb.writeln(
                  '📕 Pending Udhaar: ₹${_money(_totalUdhaarDue)} (${_udhaarSalesList.length} Bills)',
                );
                sb.writeln('----------------------------');
                sb.writeln('📱 Phone Profit: +₹${_money(_smartphoneProfit)}');
                sb.writeln('🎧 Accessory Profit: +₹${_money(_accessoryProfit)}');

                Navigator.pop(ctx);
                ShopConfig.sendWhatsAppMessage(
                  context: context,
                  phone: ShopConfig.current.shopPhone,
                  message: sb.toString(),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEEF2FF),
                child: Icon(Icons.table_chart_rounded, color: Color(0xFF4338CA)),
              ),
              title: const Text(
                'Copy CSV Data (For Excel / Google Sheets / CA)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: const Text(
                'All invoices with Date, Branch, Customer, Mode, Total, Cost, Profit & Due',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                final csv = StringBuffer();
                csv.writeln(
                  'Date,Branch,InvoiceID,CustomerName,Phone,PaymentMode,Subtotal,Discount,NetBill,Paid,Due,Cost,Profit',
                );
                for (final dynamic entry in _salesList) {
                  final s = _asMap(entry);
                  final c = _asMap(s['customers']);
                  final dt = _parseDate(s['created_at']) ?? DateTime.now();
                  final idStr = (s['id'] ?? '').toString();
                  final inv = idStr.length >= 8
                      ? idStr.substring(0, 8).toUpperCase()
                      : idStr;
                  final branch = (s['branch_name'] ?? 'Main Branch')
                      .toString()
                      .replaceAll(',', ' ');
                  final name =
                      (c['name'] ?? 'Walk-in').toString().replaceAll(',', ' ');
                  final phone = (c['phone'] ?? '').toString();
                  final mode = (s['payment_mode'] ?? 'Cash')
                      .toString()
                      .replaceAll(',', ' ');
                  csv.writeln(
                    '${DateFormat('yyyy-MM-dd HH:mm').format(dt)},$branch,$inv,$name,$phone,$mode,${_money(s['subtotal_amount'])},${_money(s['discount_amount'])},${_money(s['total_amount'])},${_money(s['paid_amount'])},${_money(s['due_amount'])},${_money(s['total_cost'])},${_money(s['total_profit'])}',
                  );
                }
                Clipboard.setData(ClipboardData(text: csv.toString()));
                Navigator.pop(ctx);
                _showMessage(
                    'CSV Spreadsheet data copied! Paste into Excel or Sheets.');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sendUdhaarReminder(String customerName, String phone, double dueAmount,
      DateTime? date, {bool isSms = false}) {
    final dateStr =
        date != null ? DateFormat('dd MMM yyyy').format(date) : 'recent purchase';
    final msg =
        'Hello *$customerName* ji,\nThis is a gentle reminder from *${ShopConfig.current.shopName}* regarding your pending balance of *₹${_money(dueAmount)}* from your purchase on $dateStr.\nKindly arrange the payment at your earliest convenience via Cash or UPI. Thank you! 🙏';
    if (isSms) {
      ShopConfig.sendSmsMessage(
        context: context,
        phone: phone,
        message: msg.replaceAll('*', ''),
      );
    } else {
      ShopConfig.sendWhatsAppMessage(
        context: context,
        phone: phone,
        message: msg,
      );
    }
  }

  Future<void> _editUnsoldStockPriceDialog(
      Map<String, dynamic> stockItem) async {
    final prod = _asMap(stockItem['products']);
    final prodId = prod['id'];
    if (prodId == null) return;

    final costCtrl = TextEditingController(text: _money(prod['cost_price']));
    final sellCtrl = TextEditingController(text: _money(prod['selling_price']));

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Update Pricing: ${prod['brand'] ?? ''} ${prod['title'] ?? ''}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Purchase Cost Price (₹)',
                prefixText: '₹ ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sellCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Selling / MRP Price (₹)',
                prefixText: '₹ ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Price'),
          ),
        ],
      ),
    );

    if (updated != true) return;

    final newCost = _number(costCtrl.text.trim());
    final newSell = _number(sellCtrl.text.trim());

    try {
      await supabase.from('products').update({
        'cost_price': newCost,
        'selling_price': newSell,
      }).eq('id', prodId);

      _showMessage('Product pricing updated!');
      await _fetchSummaryAndUnsold();
    } catch (e) {
      _showMessage('Failed to update price: $e', isError: true);
    }
  }

  Future<void> _fetchSummaryAndUnsold() async {
    if (mounted) {
      setState(() => _summaryLoading = true);
    }

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart =
          todayStart.subtract(Duration(days: todayStart.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);
      final yearStart = DateTime(now.year, 1, 1);

      final allSales = await supabase
          .from('sales')
          .select('total_amount, total_profit, created_at')
          .gte('created_at', yearStart.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      double todayRevenue = 0;
      double todayProfit = 0;
      double weekRevenue = 0;
      double weekProfit = 0;
      double monthRevenue = 0;
      double monthProfit = 0;
      double yearRevenue = 0;
      double yearProfit = 0;

      for (final dynamic entry in allSales) {
        final sale = _asMap(entry);
        final revenue = _number(sale['total_amount']);
        final profit = _number(sale['total_profit']);
        final date = _parseDate(sale['created_at']);

        if (date == null) continue;

        if (!date.isBefore(yearStart)) {
          yearRevenue += revenue;
          yearProfit += profit;
        }
        if (!date.isBefore(monthStart)) {
          monthRevenue += revenue;
          monthProfit += profit;
        }
        if (!date.isBefore(weekStart)) {
          weekRevenue += revenue;
          weekProfit += profit;
        }
        if (!date.isBefore(todayStart)) {
          todayRevenue += revenue;
          todayProfit += profit;
        }
      }

      final unsoldResponse = await supabase
          .from('stock_items')
          .select('*, products(*)')
          .eq('status', 'Available')
          .gt('quantity', 0)
          .order('created_at', ascending: false);

      double unsoldCost = 0;
      double unsoldValue = 0;

      for (final dynamic entry in unsoldResponse) {
        final item = _asMap(entry);
        final product = _asMap(item['products']);

        final cost = _number(product['cost_price']);
        final selling = _number(product['selling_price']);
        final quantity = _integer(item['quantity'], fallback: 1);

        unsoldCost += cost * quantity;
        unsoldValue += selling * quantity;
      }

      if (!mounted) return;

      setState(() {
        _todayRevenue = todayRevenue;
        _todayProfit = todayProfit;
        _weekRevenue = weekRevenue;
        _weekProfit = weekProfit;
        _monthRevenue = monthRevenue;
        _monthProfit = monthProfit;
        _yearRevenue = yearRevenue;
        _yearProfit = yearProfit;

        _unsoldStockItems = List<dynamic>.from(unsoldResponse);
        _unsoldTotalCost = unsoldCost;
        _unsoldTotalValue = unsoldValue;
        _summaryLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _summaryLoading = false);
        _showMessage('Could not load summary: $error', isError: true);
      }
    }
  }

  void _applyFilter(String period, {bool fetch = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    late DateTime start;
    final DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );

    switch (period) {
      case 'Today':
        start = today;
        break;
      case 'Last 7 Days':
        start = today.subtract(const Duration(days: 6));
        break;
      case 'This Month':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'This Year':
        start = DateTime(now.year, 1, 1);
        break;
      case 'All Time':
        start = DateTime(2000, 1, 1);
        break;
      default:
        start = today.subtract(const Duration(days: 6));
    }

    setState(() {
      _selectedFilter = period;
      _selectedDateRange = DateTimeRange(start: start, end: end);
    });

    if (fetch) {
      _fetchFilteredReports();
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedFilter = 'Custom';
      _selectedDateRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
          999,
        ),
      );
    });

    _fetchFilteredReports();
  }

  Future<void> _fetchFilteredReports() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final startUtc = _selectedDateRange.start.toUtc().toIso8601String();
      final endUtc = _selectedDateRange.end.toUtc().toIso8601String();

      final response = await supabase
          .from('sales')
          .select(
            '*, customers(name, phone), '
            'sale_items(*, products(*), stock_items(*))',
          )
          .gte('created_at', startUtc)
          .lte('created_at', endUtc)
          .order('created_at', ascending: false);

      double revenue = 0;
      double totalCost = 0;
      double profit = 0;
      double discountGiven = 0;
      double cashCollected = 0;
      double onlineCollected = 0;
      double udhaarDue = 0;
      int itemsSold = 0;
      double smartphoneRevenue = 0;
      double accessoryRevenue = 0;
      double smartphoneProfit = 0;
      double accessoryProfit = 0;

      final Map<String, Map<String, dynamic>> ranking = {};
      final Map<String, Map<String, dynamic>> brandRanking = {};
      final Map<String, Map<String, dynamic>> branchRanking = {};
      final Map<String, double> paymentBreakdown = {};
      final List<dynamic> dueList = [];
      final List<Map<String, dynamic>> itemizedProfits = [];

      final shop = ShopConfig.current;

      for (final dynamic entry in response) {
        final sale = _asMap(entry);
        final customer = _asMap(sale['customers']);
        final saleDate = _parseDate(sale['created_at']) ?? DateTime.now();

        final billTotal = _number(sale['total_amount']);
        final billCost = _number(sale['total_cost']);
        final billProfit = _number(sale['total_profit']);
        final due = _number(sale['due_amount']);
        final cash = _number(sale['cash_paid']);
        final online = _number(sale['online_paid']);
        final disc = _number(sale['discount_amount']);
        final payMode = (sale['payment_mode'] ?? 'Cash').toString();

        final rawBranch = (sale['branch_name'] ?? '').toString().trim();
        final sellerEmail = (sale['sold_by_email'] ?? '').toString().trim();
        final branchKey = rawBranch.isNotEmpty
            ? rawBranch
            : (sellerEmail.isNotEmpty ? 'Branch ($sellerEmail)' : 'Main Branch');

        branchRanking.putIfAbsent(
          branchKey,
          () => {
            'branch_name': branchKey,
            'seller_emails': <String>{},
            'bills_count': 0,
            'units_sold': 0,
            'phones_sold': 0,
            'accessories_sold': 0,
            'total_revenue': 0.0,
            'total_profit': 0.0,
            'total_due': 0.0,
            'items_list': <Map<String, dynamic>>[],
          },
        );
        if (sellerEmail.isNotEmpty) {
          (branchRanking[branchKey]!['seller_emails'] as Set<String>)
              .add(sellerEmail);
        }
        branchRanking[branchKey]!['bills_count'] =
            _integer(branchRanking[branchKey]!['bills_count']) + 1;
        branchRanking[branchKey]!['total_revenue'] =
            _number(branchRanking[branchKey]!['total_revenue']) + billTotal;
        branchRanking[branchKey]!['total_profit'] =
            _number(branchRanking[branchKey]!['total_profit']) + billProfit;
        branchRanking[branchKey]!['total_due'] =
            _number(branchRanking[branchKey]!['total_due']) + due;

        revenue += billTotal;
        totalCost += billCost;
        profit += billProfit;
        discountGiven += disc;
        cashCollected += cash;
        onlineCollected += online;

        paymentBreakdown[payMode] =
            (paymentBreakdown[payMode] ?? 0.0) + billTotal;

        // Requirement 2: Branch-limited Udhaar visibility for staff, full visibility for Owner
        final bool belongsToCurrentBranch = shop.isOwner ||
            rawBranch.toLowerCase() == shop.branchName.trim().toLowerCase() ||
            sale['sold_by_user_id']?.toString() == shop.userId;

        if (due > 0 && belongsToCurrentBranch) {
          udhaarDue += due;
          dueList.add(sale);
        }

        final items = _asList(sale['sale_items']);

        for (final dynamic itemEntry in items) {
          final line = _asMap(itemEntry);
          final product = _asMap(line['products']);
          final stock = _asMap(line['stock_items']);
          final int qty = _integer(line['quantity'], fallback: 1);

          itemsSold += qty;

          final title = product['title']?.toString() ?? 'Unknown Item';
          final brand = product['brand']?.toString() ?? '';
          final isBulk = product['is_bulk'] == true;
          final unitMrp = _number(product['selling_price']);
          final soldPrice = _number(line['sold_price']);
          final costPrice = _number(line['cost_price']);
          final itemProfit = _number(line['profit']);
          final lineMrp = unitMrp > 0 ? (unitMrp * qty) : soldPrice;
          final lineDiscountShare = max(0.0, lineMrp - soldPrice);

          final productName = ShopConfig.formatProductSpecTitle(product);
          final key = productName.isEmpty ? 'Unknown Item' : productName;
          final brandKey =
              brand.trim().isEmpty ? 'Other / Generic' : brand.trim();

          if (isBulk) {
            accessoryRevenue += soldPrice;
            accessoryProfit += itemProfit;
            branchRanking[branchKey]!['accessories_sold'] =
                _integer(branchRanking[branchKey]!['accessories_sold']) + qty;
          } else {
            smartphoneRevenue += soldPrice;
            smartphoneProfit += itemProfit;
            branchRanking[branchKey]!['phones_sold'] =
                _integer(branchRanking[branchKey]!['phones_sold']) + qty;
          }
          branchRanking[branchKey]!['units_sold'] =
              _integer(branchRanking[branchKey]!['units_sold']) + qty;
          (branchRanking[branchKey]!['items_list']
                  as List<Map<String, dynamic>>)
              .add({
            'name': key,
            'qty': qty,
            'sold_price': soldPrice,
            'profit': itemProfit,
            'imei': (stock['imei_or_serial'] ?? '').toString(),
            'date': saleDate,
          });

          itemizedProfits.add({
            'sale': sale,
            'line': line,
            'sale_item_id': line['id'],
            'stock_item_id': line['stock_item_id'],
            'product_id': line['product_id'],
            'name': key,
            'brand': brand,
            'title': title,
            'is_bulk': isBulk,
            'imei1': (stock['imei_or_serial'] ?? '').toString(),
            'imei2': (stock['imei_2'] ?? '').toString(),
            'customer_name': (customer['name'] ?? 'Walk-in').toString(),
            'customer_phone': (customer['phone'] ?? '').toString(),
            'branch_name': branchKey,
            'payment_mode': payMode,
            'due_amount': due,
            'quantity': qty,
            'mrp_total': lineMrp,
            'discount_share': lineDiscountShare,
            'sold_price': soldPrice,
            'cost_price': costPrice,
            'profit': itemProfit,
            'warranty': (line['warranty_period'] ??
                    sale['warranty_period'] ??
                    'No Warranty')
                .toString(),
            'date': saleDate,
          });

          ranking.putIfAbsent(
            key,
            () => {
              'name': key,
              'brand': brand,
              'title': title,
              'is_bulk': isBulk,
              'units_sold': 0,
              'total_cost': 0.0,
              'total_revenue': 0.0,
              'total_profit': 0.0,
            },
          );

          ranking[key]!['units_sold'] =
              _integer(ranking[key]!['units_sold']) + qty;
          ranking[key]!['total_cost'] =
              _number(ranking[key]!['total_cost']) + costPrice;
          ranking[key]!['total_revenue'] =
              _number(ranking[key]!['total_revenue']) + soldPrice;
          ranking[key]!['total_profit'] =
              _number(ranking[key]!['total_profit']) + itemProfit;

          brandRanking.putIfAbsent(
            brandKey,
            () => {
              'brand': brandKey,
              'units_sold': 0,
              'total_revenue': 0.0,
              'total_profit': 0.0,
            },
          );
          brandRanking[brandKey]!['units_sold'] =
              _integer(brandRanking[brandKey]!['units_sold']) + qty;
          brandRanking[brandKey]!['total_revenue'] =
              _number(brandRanking[brandKey]!['total_revenue']) + soldPrice;
          brandRanking[brandKey]!['total_profit'] =
              _number(brandRanking[brandKey]!['total_profit']) + itemProfit;
        }
      }

      final sales = List<dynamic>.from(response);
      final chartPoints = _generateChartPoints(sales, _chartViewMode);

      if (!mounted) return;

      setState(() {
        _salesList = sales;
        _udhaarSalesList = dueList;
        _itemizedProfitList = itemizedProfits;
        _totalRevenue = revenue;
        _totalCost = totalCost;
        _totalProfit = profit;
        _totalDiscountGiven = discountGiven;
        _totalCashCollected = cashCollected;
        _totalOnlineCollected = onlineCollected;
        _totalUdhaarDue = udhaarDue;
        _totalItemsSold = itemsSold;
        _topProductsMap = ranking;
        _brandPerformanceMap = brandRanking;
        _branchPerformanceMap = branchRanking;
        _paymentModeBreakdown = paymentBreakdown;
        _chartDataPoints = chartPoints;
        _smartphoneRevenue = smartphoneRevenue;
        _accessoryRevenue = accessoryRevenue;
        _smartphoneProfit = smartphoneProfit;
        _accessoryProfit = accessoryProfit;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Error loading reports: $error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green,
      ),
    );
  }

  Future<void> _settleUdhaarDialog(Map<String, dynamic> sale) async {
    final saleId = sale['id'];
    if (saleId == null) return;

    final customer = _asMap(sale['customers']);
    final currentDue = _number(sale['due_amount']);
    final currentPaid = _number(sale['paid_amount']);
    final currentCash = _number(sale['cash_paid']);
    final currentOnline = _number(sale['online_paid']);

    final collectCtrl =
        TextEditingController(text: currentDue.toStringAsFixed(0));
    String receiveMode = 'Cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.payments_rounded, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Expanded(child: Text('Collect Udhaar / Due Payment')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer: ${customer['name'] ?? 'Customer'} (${customer['phone'] ?? ''})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Pending Balance Due: ₹${_money(currentDue)}',
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: collectCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount Received Now (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: receiveMode,
                decoration: InputDecoration(
                  labelText: 'Received Via',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(
                      value: 'UPI / Online', child: Text('UPI / Online')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => receiveMode = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final collected =
        (_number(collectCtrl.text.trim())).clamp(0.0, currentDue).toDouble();
    if (collected <= 0) return;

    final newDue = max(0.0, currentDue - collected);
    final newPaid = currentPaid + collected;
    final newCash =
        receiveMode == 'Cash' ? currentCash + collected : currentCash;
    final newOnline = receiveMode == 'UPI / Online'
        ? currentOnline + collected
        : currentOnline;

    try {
      await supabase.from('sales').update({
        'due_amount': newDue,
        'paid_amount': newPaid,
        'cash_paid': newCash,
        'online_paid': newOnline,
        'payment_status': newDue <= 0 ? 'Paid' : 'Partial / Due',
      }).eq('id', saleId);

      _showMessage('Collected ₹${_money(collected)} successfully!');
      await _fetchFilteredReports();
      await _fetchSummaryAndUnsold();
    } catch (e) {
      _showMessage('Failed to update Udhaar: $e', isError: true);
    }
  }

  Future<void> _revokeSale(Map<String, dynamic> sale) async {
    final saleId = sale['id'];
    if (saleId == null) return;

    final items = _asList(sale['sale_items']);
    final totalBill = _number(sale['total_amount']);
    final saleIdText = saleId.toString();
    final invoiceNumber =
        saleIdText.substring(0, min(6, saleIdText.length)).toUpperCase();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.undo_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Revoke / Return Sale?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Return Bill #INV-$invoiceNumber?'),
            const SizedBox(height: 8),
            Text(
              'Amount: ₹${totalBill.toStringAsFixed(0)} (${items.length} line items)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'The sale will be deleted and all sold items/quantities will be restored to Available Stock.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm Return'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      for (final dynamic itemEntry in items) {
        final line = _asMap(itemEntry);
        final product = _asMap(line['products']);
        final stockItemId = line['stock_item_id'];
        final isBulk = product['is_bulk'] == true;
        final soldQty = _integer(line['quantity'], fallback: 1);

        if (stockItemId == null) continue;

        if (isBulk) {
          final stock = await supabase
              .from('stock_items')
              .select('quantity')
              .eq('id', stockItemId)
              .maybeSingle();

          if (stock != null) {
            final currentQty = _integer(stock['quantity']);
            await supabase.from('stock_items').update({
              'quantity': currentQty + soldQty,
              'status': 'Available',
            }).eq('id', stockItemId);
          }
        } else {
          await supabase.from('stock_items').update({
            'status': 'Available',
            'quantity': 1,
          }).eq('id', stockItemId);
        }
      }

      await supabase.from('sales').delete().eq('id', saleId);

      if (!mounted) return;

      _showMessage('Sale revoked. Stock quantities were restored.');
      await _fetchFilteredReports();
      await _fetchSummaryAndUnsold();
    } catch (error) {
      _showMessage('Failed to revoke sale: $error', isError: true);
    }
  }

  List<Map<String, dynamic>> _generateChartPoints(
    List<dynamic> sales,
    String mode,
  ) {
    final Map<String, double> revenueBuckets = {};
    final Map<String, double> profitBuckets = {};
    final now = DateTime.now();

    if (mode == 'Daily') {
      for (int i = 6; i >= 0; i--) {
        final date =
            DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final key = DateFormat('dd MMM').format(date);
        revenueBuckets[key] = 0;
        profitBuckets[key] = 0;
      }
    } else if (mode == 'Weekly') {
      for (int w = 1; w <= 5; w++) {
        revenueBuckets['Week $w'] = 0;
        profitBuckets['Week $w'] = 0;
      }
    } else if (mode == 'Monthly') {
      for (int i = 11; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        final key = DateFormat('MMM yy').format(date);
        revenueBuckets[key] = 0;
        profitBuckets[key] = 0;
      }
    } else {
      for (int i = 4; i >= 0; i--) {
        final year = (now.year - i).toString();
        revenueBuckets[year] = 0;
        profitBuckets[year] = 0;
      }
    }

    for (final dynamic entry in sales) {
      final sale = _asMap(entry);
      final date = _parseDate(sale['created_at']);
      if (date == null) continue;

      String? key;
      if (mode == 'Daily') {
        key = DateFormat('dd MMM').format(date);
      } else if (mode == 'Weekly') {
        final weekNumber = ((date.day - 1) ~/ 7) + 1;
        key = 'Week ${min(weekNumber, 5)}';
      } else if (mode == 'Monthly') {
        key = DateFormat('MMM yy').format(date);
      } else {
        key = date.year.toString();
      }

      if (revenueBuckets.containsKey(key)) {
        revenueBuckets[key] =
            revenueBuckets[key]! + _number(sale['total_amount']);
        profitBuckets[key] =
            profitBuckets[key]! + _number(sale['total_profit']);
      }
    }

    return revenueBuckets.entries
        .map((entry) => {
              'label': entry.key,
              'amount': entry.value,
              'profit': profitBuckets[entry.key] ?? 0.0,
            })
        .toList();
  }

  Widget _buildMiniMetric(
    String title,
    String revenue,
    String subtitle,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                revenue,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSummaryPill(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REQUIREMENT 4: TAB 1 - ULTRA-COMPACT SALES & SOLD ITEMS VIEW
  // Reduces top summary clutter so all sold items are clearly visible at a time
  // ---------------------------------------------------------------------------
  Widget _buildTransactionsTab() {
    final searchQ = _salesSearchQuery.toLowerCase();
    final canSeeProfit = ShopConfig.current.canSeeProfit;

    bool matchesPaymentFilter(String mode, double due) {
      if (_salesPaymentFilter == 'Cash' &&
          !mode.toLowerCase().contains('cash')) {
        return false;
      }
      if (_salesPaymentFilter == 'UPI' &&
          !mode.toLowerCase().contains('upi') &&
          !mode.toLowerCase().contains('qr')) {
        return false;
      }
      if (_salesPaymentFilter == 'Udhaar' &&
          due <= 0 &&
          !mode.toLowerCase().contains('udhaar') &&
          !mode.toLowerCase().contains('borrow')) {
        return false;
      }
      if (_salesPaymentFilter == 'Card/EMI' &&
          !mode.toLowerCase().contains('card') &&
          !mode.toLowerCase().contains('emi') &&
          !mode.toLowerCase().contains('bajaj')) {
        return false;
      }
      return true;
    }

    final filteredSales = _salesList.where((dynamic raw) {
      final sale = _asMap(raw);
      final mode = (sale['payment_mode'] ?? 'Cash').toString();
      final due = _number(sale['due_amount']);

      if (!matchesPaymentFilter(mode, due)) return false;
      if (searchQ.isEmpty) return true;

      final customer = _asMap(sale['customers']);
      final custName = (customer['name'] ?? '').toString().toLowerCase();
      final custPhone = (customer['phone'] ?? '').toString().toLowerCase();
      final saleId = (sale['id'] ?? '').toString().toLowerCase();
      final notes = (sale['notes'] ?? '').toString().toLowerCase();
      final branch = (sale['branch_name'] ?? '').toString().toLowerCase();

      if (custName.contains(searchQ) ||
          custPhone.contains(searchQ) ||
          saleId.contains(searchQ) ||
          notes.contains(searchQ) ||
          branch.contains(searchQ)) {
        return true;
      }

      final items = _asList(sale['sale_items']);
      for (final dynamic item in items) {
        final line = _asMap(item);
        final prod = _asMap(line['products']);
        final stock = _asMap(line['stock_items']);
        final prodText = ShopConfig.formatProductSpecTitle(prod).toLowerCase();
        final imei1 = (stock['imei_or_serial'] ?? '').toString().toLowerCase();
        final imei2 = (stock['imei_2'] ?? '').toString().toLowerCase();
        if (prodText.contains(searchQ) ||
            imei1.contains(searchQ) ||
            imei2.contains(searchQ)) {
          return true;
        }
      }
      return false;
    }).toList();

    final filteredSoldItems = _itemizedProfitList.where((item) {
      final mode = (item['payment_mode'] ?? 'Cash').toString();
      final due = _number(item['due_amount']);
      if (!matchesPaymentFilter(mode, due)) return false;
      if (searchQ.isEmpty) return true;

      final name = (item['name'] ?? '').toString().toLowerCase();
      final imei1 = (item['imei1'] ?? '').toString().toLowerCase();
      final imei2 = (item['imei2'] ?? '').toString().toLowerCase();
      final cust = (item['customer_name'] ?? '').toString().toLowerCase();
      final phone = (item['customer_phone'] ?? '').toString().toLowerCase();
      final branch = (item['branch_name'] ?? '').toString().toLowerCase();

      return name.contains(searchQ) ||
          imei1.contains(searchQ) ||
          imei2.contains(searchQ) ||
          cust.contains(searchQ) ||
          phone.contains(searchQ) ||
          branch.contains(searchQ);
    }).toList();

    return Column(
      children: [
        // Ultra-compact top bar so sold items get maximum vertical screen height
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCompactSummaryPill(
                            'Sold',
                            '$_totalItemsSold Units (${_salesList.length} Bills)',
                            const Color(0xFF4338CA),
                          ),
                          _buildCompactSummaryPill(
                            'Net Sales',
                            '₹${_money(_totalRevenue)}',
                            const Color(0xFF0F172A),
                          ),
                          if (canSeeProfit)
                            _buildCompactSummaryPill(
                              'Profit',
                              '+₹${_money(_totalProfit)}',
                              const Color(0xFF059669),
                            ),
                          _buildCompactSummaryPill(
                            'Cash',
                            '₹${_money(_totalCashCollected)}',
                            const Color(0xFF059669),
                          ),
                          _buildCompactSummaryPill(
                            'UPI',
                            '₹${_money(_totalOnlineCollected)}',
                            const Color(0xFF2563EB),
                          ),
                          if (_totalUdhaarDue > 0)
                            _buildCompactSummaryPill(
                              'Due',
                              '₹${_money(_totalUdhaarDue)}',
                              const Color(0xFFDC2626),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(
                        () => _showExpandedKpisInTab1 = !_showExpandedKpisInTab1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showExpandedKpisInTab1 ? 'Hide KPIs' : 'KPIs',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                          Icon(
                            _showExpandedKpisInTab1
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 15,
                            color: const Color(0xFF4338CA),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_showExpandedKpisInTab1 && !_summaryLoading) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildMiniMetric(
                      'Today',
                      '₹${_money(_todayRevenue)}',
                      canSeeProfit ? '+₹${_money(_todayProfit)}' : 'Sales',
                      const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 4),
                    _buildMiniMetric(
                      'This Week',
                      '₹${_money(_weekRevenue)}',
                      canSeeProfit ? '+₹${_money(_weekProfit)}' : 'Sales',
                      const Color(0xFF4F46E5),
                    ),
                    const SizedBox(width: 4),
                    _buildMiniMetric(
                      'This Month',
                      '₹${_money(_monthRevenue)}',
                      canSeeProfit ? '+₹${_money(_monthProfit)}' : 'Sales',
                      const Color(0xFF059669),
                    ),
                    const SizedBox(width: 4),
                    _buildMiniMetric(
                      'This Year',
                      '₹${_money(_yearRevenue)}',
                      canSeeProfit ? '+₹${_money(_yearProfit)}' : 'Sales',
                      const Color(0xFFD97706),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              // Single compact row combining Search + Payment Filter + View Switcher
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _salesSearchQuery = v.trim()),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Search sold item, IMEI, customer, branch...',
                          hintStyle: const TextStyle(fontSize: 11),
                          prefixIcon: const Icon(Icons.search, size: 16),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _salesPaymentFilter,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                        items: ['All', 'Cash', 'UPI', 'Udhaar', 'Card/EMI']
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m == 'All' ? 'Mode: All' : m),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _salesPaymentFilter = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(
                        () => _showFlatSoldItemsInTab1 = !_showFlatSoldItemsInTab1),
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4338CA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _showFlatSoldItemsInTab1
                                ? Icons.view_list_rounded
                                : Icons.receipt_long_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showFlatSoldItemsInTab1
                                ? 'Items (${filteredSoldItems.length})'
                                : 'Bills (${filteredSales.length})',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF4338CA)),
                )
              : _showFlatSoldItemsInTab1
                  // HIGH-DENSITY ALL SOLD ITEMS VIEW (See all sold items at a time!)
                  ? (filteredSoldItems.isEmpty
                      ? Center(
                          child: Text(
                            'No sold items found for $_selectedFilter.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchFilteredReports,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            itemCount: filteredSoldItems.length,
                            itemBuilder: (context, idx) {
                              final item = filteredSoldItems[idx];
                              final sale = _asMap(item['sale']);
                              final bool isBulk = item['is_bulk'] == true;
                              final int qty =
                                  _integer(item['quantity'], fallback: 1);
                              final num sold = _number(item['sold_price']);
                              final num cost = _number(item['cost_price']);
                              final num profit = _number(item['profit']);
                              final num disc = _number(item['discount_share']);
                              final num due = _number(item['due_amount']);
                              final String imei1 =
                                  (item['imei1'] ?? '').toString();
                              final String imei2 =
                                  (item['imei2'] ?? '').toString();
                              final DateTime date = item['date'] as DateTime;

                              return Card(
                                elevation: 0.5,
                                margin: const EdgeInsets.only(bottom: 5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: due > 0
                                        ? Colors.red.shade200
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _openFullBillFromSale(sale),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: isBulk
                                                ? const Color(0xFFFEF3C7)
                                                : const Color(0xFFEEF2FF),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            isBulk
                                                ? Icons.headphones_rounded
                                                : Icons.smartphone_rounded,
                                            size: 17,
                                            color: isBulk
                                                ? const Color(0xFFD97706)
                                                : const Color(0xFF4338CA),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      '${idx + 1}. ${item['name']} × $qty',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12.5,
                                                        color:
                                                            Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 5,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFEEF2FF),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      '${item['branch_name']}',
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF4338CA),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${isBulk ? "SKU" : "IMEI"}: $imei1${imei2.isNotEmpty ? " / $imei2" : ""}  •  ${item['customer_name']} (${item['customer_phone']})',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontFamily: 'monospace',
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Wrap(
                                                spacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    DateFormat('dd MMM, hh:mm a')
                                                        .format(date),
                                                    style: const TextStyle(
                                                      fontSize: 9.5,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                  Text(
                                                    '• ${item['payment_mode']}',
                                                    style: const TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                  if (disc > 0)
                                                    Text(
                                                      '• Disc: -₹${_money(disc)}',
                                                      style: const TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFFD97706),
                                                      ),
                                                    ),
                                                  if (due > 0)
                                                    Text(
                                                      '• DUE: ₹${_money(due)}',
                                                      style: const TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFFDC2626),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '₹${_money(sold)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13,
                                                color: Color(0xFF1E1B4B),
                                              ),
                                            ),
                                            if (canSeeProfit) ...[
                                              Text(
                                                'Cost: ₹${_money(cost)}',
                                                style: const TextStyle(
                                                  fontSize: 9.5,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: profit >= 0
                                                      ? const Color(0xFFECFDF5)
                                                      : const Color(0xFFFEF2F2),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${profit >= 0 ? "+" : ""}₹${_money(profit)}',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: profit >= 0
                                                        ? const Color(
                                                            0xFF059669)
                                                        : Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  onTap: () =>
                                                      _editSoldItemDialog(item),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFEEF2FF),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.edit_outlined,
                                                          size: 11,
                                                          color:
                                                              Color(0xFF4338CA),
                                                        ),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          'Edit',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Color(
                                                                0xFF4338CA),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  onTap: () =>
                                                      _revokeSoldItem(item),
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFFEF2F2),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.undo_rounded,
                                                          size: 11,
                                                          color:
                                                              Color(0xFFDC2626),
                                                        ),
                                                        SizedBox(width: 2),
                                                        Text(
                                                          'Revoke',
                                                          style: TextStyle(
                                                            fontSize: 9.5,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Color(
                                                                0xFFDC2626),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ))
                  // COMPACT BILL CARDS VIEW
                  : (filteredSales.isEmpty
                      ? Center(
                          child: Text(
                            'No transactions found for $_selectedFilter.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchFilteredReports,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            itemCount: filteredSales.length,
                            itemBuilder: (context, index) {
                              final sale = _asMap(filteredSales[index]);
                              final customer = _asMap(sale['customers']);
                              final items = _asList(sale['sale_items']);
                              final date = _parseDate(sale['created_at']) ??
                                  DateTime.now();
                              final paymentMode =
                                  sale['payment_mode']?.toString() ?? 'Cash';
                              final dueAmount = _number(sale['due_amount']);
                              final paidAmount = _number(sale['paid_amount']);
                              final discountAmount =
                                  _number(sale['discount_amount']);
                              final branchName =
                                  (sale['branch_name'] ?? 'Main Branch')
                                      .toString();
                              final saleId = sale['id']?.toString() ?? '';

                              return Card(
                                elevation: 0.5,
                                margin: const EdgeInsets.only(bottom: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: dueAmount > 0
                                        ? Colors.red.shade200
                                        : Colors.grey.shade200,
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openFullBillFromSale(sale),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Wrap(
                                                spacing: 6,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    '₹${_money(sale['total_amount'])}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    '• ${customer['name'] ?? 'Walk-in'} (${customer['phone'] ?? ''})',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 5,
                                                      vertical: 1,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFFEEF2FF),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      branchName,
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF4338CA),
                                                      ),
                                                    ),
                                                  ),
                                                  if (discountAmount > 0)
                                                    Text(
                                                      'Disc: -₹${_money(discountAmount)}',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF059669),
                                                      ),
                                                    ),
                                                  if (dueAmount > 0)
                                                    Text(
                                                      'DUE: ₹${_money(dueAmount)}',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFFDC2626),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            if (canSeeProfit)
                                              Text(
                                                '+₹${_money(sale['total_profit'])}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF16A34A),
                                                  fontSize: 13,
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        ...items.map((dynamic entry) {
                                          final line = _asMap(entry);
                                          final product =
                                              _asMap(line['products']);
                                          final stock =
                                              _asMap(line['stock_items']);
                                          final qty = _integer(line['quantity'],
                                              fallback: 1);
                                          final code1 = stock['imei_or_serial']
                                                  ?.toString() ??
                                              '';
                                          final fullSpecTitle = ShopConfig
                                              .formatProductSpecTitle(product);
                                          final lineSold =
                                              _number(line['sold_price']);
                                          final lineProfit =
                                              _number(line['profit']);

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 1.5),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '• $fullSpecTitle × $qty ($code1)',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '₹${_money(lineSold)}${canSeeProfit ? " (+₹${_money(lineProfit)})" : ""}',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF4338CA),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${DateFormat('dd MMM, hh:mm a').format(date)} • $paymentMode (Paid: ₹${_money(paidAmount)})',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                InkWell(
                                                  onTap: () =>
                                                      _editSaleNotesOrWarrantyDialog(
                                                          sale),
                                                  child: const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 4),
                                                    child: Icon(
                                                      Icons.edit_note_rounded,
                                                      size: 17,
                                                      color: Color(0xFF475569),
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () =>
                                                      _openFullBillFromSale(
                                                          sale),
                                                  child: const Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 6),
                                                    child: Text(
                                                      'Print/Share',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFF4338CA),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (dueAmount > 0)
                                                  InkWell(
                                                    onTap: () =>
                                                        _settleUdhaarDialog(
                                                            sale),
                                                    child: const Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 6),
                                                      child: Text(
                                                        'Collect',
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color:
                                                              Color(0xFF059669),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (saleId.isNotEmpty)
                                                  InkWell(
                                                    onTap: () =>
                                                        _revokeSale(sale),
                                                    child: const Padding(
                                                      padding: EdgeInsets.only(
                                                          left: 4),
                                                      child: Icon(
                                                        Icons.undo_rounded,
                                                        size: 16,
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )),
        ),
      ],
    );
  }

  /// TAB 2: DEDICATED ITEM PROFIT TAB
  Widget _buildItemProfitTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4338CA)),
      );
    }

    final q = _profitSearchQuery.toLowerCase();

    final filteredItems = _itemizedProfitList.where((item) {
      final bool isBulk = item['is_bulk'] == true;
      if (_profitCategoryFilter == 'Smartphones' && isBulk) return false;
      if (_profitCategoryFilter == 'Accessories' && !isBulk) return false;

      if (q.isEmpty) return true;
      final name = (item['name'] ?? '').toString().toLowerCase();
      final imei1 = (item['imei1'] ?? '').toString().toLowerCase();
      final imei2 = (item['imei2'] ?? '').toString().toLowerCase();
      final cust = (item['customer_name'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          imei1.contains(q) ||
          imei2.contains(q) ||
          cust.contains(q);
    }).toList();

    if (_profitSortBy == 'Highest Profit') {
      filteredItems
          .sort((a, b) => _number(b['profit']).compareTo(_number(a['profit'])));
    } else if (_profitSortBy == 'Lowest Profit') {
      filteredItems
          .sort((a, b) => _number(a['profit']).compareTo(_number(b['profit'])));
    } else if (_profitSortBy == 'Margin %') {
      filteredItems.sort((a, b) {
        final soldA = _number(a['sold_price']);
        final soldB = _number(b['sold_price']);
        final mA = soldA > 0 ? (_number(a['profit']) / soldA) : 0.0;
        final mB = soldB > 0 ? (_number(b['profit']) / soldB) : 0.0;
        return mB.compareTo(mA);
      });
    }

    final rankedModels = _topProductsMap.values.where((m) {
      final bool isBulk = m['is_bulk'] == true;
      if (_profitCategoryFilter == 'Smartphones' && isBulk) return false;
      if (_profitCategoryFilter == 'Accessories' && !isBulk) return false;

      if (q.isEmpty) return true;
      final name = (m['name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList()
      ..sort(
        (a, b) =>
            _number(b['total_profit']).compareTo(_number(a['total_profit'])),
      );

    final String overallMarginPercent = _totalRevenue > 0
        ? ((_totalProfit / _totalRevenue) * 100).toStringAsFixed(1)
        : '0.0';

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  _buildMiniMetric(
                    'Purchase Cost',
                    '₹${_money(_totalCost)}',
                    '$_totalItemsSold Units Sold',
                    const Color(0xFF475569),
                  ),
                  const SizedBox(width: 5),
                  _buildMiniMetric(
                    'Net Sold Value',
                    '₹${_money(_totalRevenue)}',
                    'Disc: -₹${_money(_totalDiscountGiven)}',
                    const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 5),
                  _buildMiniMetric(
                    'Phone Profit',
                    '+₹${_money(_smartphoneProfit)}',
                    'Handsets',
                    const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 5),
                  _buildMiniMetric(
                    'Total Net Profit',
                    '+₹${_money(_totalProfit)}',
                    '$overallMarginPercent% Margin',
                    const Color(0xFF059669),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _profitSearchQuery = val.trim()),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              'Search item profit by model, specs, IMEI, SKU or customer...',
                          prefixIcon: const Icon(Icons.search, size: 17),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    initialValue: _profitSortBy,
                    tooltip: 'Sort Profit List',
                    onSelected: (v) => setState(() => _profitSortBy = v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'Newest', child: Text('Newest First')),
                      PopupMenuItem(
                          value: 'Highest Profit',
                          child: Text('Highest Profit')),
                      PopupMenuItem(
                          value: 'Lowest Profit',
                          child: Text('Lowest Profit / Loss')),
                      PopupMenuItem(
                          value: 'Margin %', child: Text('Highest Margin %')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.sort_rounded,
                              size: 16, color: Color(0xFF4338CA)),
                          const SizedBox(width: 4),
                          Text(
                            _profitSortBy,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('All Items',
                                style: TextStyle(fontSize: 11)),
                            selected: _profitCategoryFilter == 'All',
                            onSelected: (_) =>
                                setState(() => _profitCategoryFilter = 'All'),
                          ),
                          const SizedBox(width: 5),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Phones (+₹${_money(_smartphoneProfit)})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _profitCategoryFilter == 'Smartphones',
                            onSelected: (_) => setState(
                                () => _profitCategoryFilter = 'Smartphones'),
                          ),
                          const SizedBox(width: 5),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              'Accessories (+₹${_money(_accessoryProfit)})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _profitCategoryFilter == 'Accessories',
                            onSelected: (_) => setState(
                                () => _profitCategoryFilter = 'Accessories'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFFEEF2FF),
                      foregroundColor: const Color(0xFF4338CA),
                    ),
                    onPressed: () => setState(
                        () => _groupProfitByModel = !_groupProfitByModel),
                    icon: Icon(
                      _groupProfitByModel
                          ? Icons.receipt_long_rounded
                          : Icons.leaderboard_rounded,
                      size: 15,
                    ),
                    label: Text(
                      _groupProfitByModel ? 'Every Item' : 'By Model',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _groupProfitByModel
              ? (rankedModels.isEmpty
                  ? const Center(child: Text('No model profit records found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: rankedModels.length,
                      itemBuilder: (ctx, idx) {
                        final model = rankedModels[idx];
                        final bool isBulk = model['is_bulk'] == true;
                        final int unitsSold =
                            _integer(model['units_sold'], fallback: 1);
                        final num totalCost = _number(model['total_cost']);
                        final num totalRev = _number(model['total_revenue']);
                        final num totalProf = _number(model['total_profit']);
                        final num avgProfitPerUnit =
                            unitsSold > 0 ? (totalProf / unitsSold) : totalProf;
                        final String marginPct = totalRev > 0
                            ? ((totalProf / totalRev) * 100).toStringAsFixed(1)
                            : '0.0';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFFECFDF5),
                                  child: Text(
                                    '#${idx + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            isBulk
                                                ? Icons.headphones_rounded
                                                : Icons.smartphone_rounded,
                                            size: 15,
                                            color: isBulk
                                                ? const Color(0xFFD97706)
                                                : const Color(0xFF4338CA),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              '${model['name']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Units Sold: $unitsSold  •  Cost: ₹${_money(totalCost)}  •  Sales: ₹${_money(totalRev)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      Text(
                                        'Avg Profit / Unit: +₹${_money(avgProfitPerUnit)}',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: totalProf >= 0
                                            ? const Color(0xFFECFDF5)
                                            : const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${totalProf >= 0 ? "+" : ""}₹${_money(totalProf)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                          color: totalProf >= 0
                                              ? const Color(0xFF059669)
                                              : Colors.red,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$marginPct% Margin',
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ))
              : (filteredItems.isEmpty
                  ? const Center(
                      child: Text('No sold items found for this filter.'),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchFilteredReports,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: filteredItems.length,
                        itemBuilder: (ctx, idx) {
                          final item = filteredItems[idx];
                          final sale = _asMap(item['sale']);
                          final bool isBulk = item['is_bulk'] == true;
                          final int qty =
                              _integer(item['quantity'], fallback: 1);
                          final num cost = _number(item['cost_price']);
                          final num mrp = _number(item['mrp_total']);
                          final num disc = _number(item['discount_share']);
                          final num sold = _number(item['sold_price']);
                          final num profit = _number(item['profit']);
                          final String imei1 = (item['imei1'] ?? '').toString();
                          final String imei2 = (item['imei2'] ?? '').toString();
                          final String marginPct = sold > 0
                              ? ((profit / sold) * 100).toStringAsFixed(1)
                              : '0.0';
                          final DateTime date = item['date'] as DateTime;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openFullBillFromSale(sale),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: isBulk
                                              ? const Color(0xFFFEF3C7)
                                              : const Color(0xFFEEF2FF),
                                          child: Icon(
                                            isBulk
                                                ? Icons.headphones_rounded
                                                : Icons.smartphone_rounded,
                                            color: isBulk
                                                ? const Color(0xFFD97706)
                                                : const Color(0xFF4338CA),
                                            size: 17,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${item['name']} × $qty',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                '${isBulk ? "SKU" : "IMEI 1"}: $imei1${imei2.isNotEmpty ? " | IMEI 2: $imei2" : ""}',
                                                style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 10.5,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              Text(
                                                '${item['customer_name']} (${item['customer_phone']}) • ${item['branch_name']} • ${DateFormat('dd MMM, hh:mm a').format(date)}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: profit >= 0
                                                    ? const Color(0xFFECFDF5)
                                                    : const Color(0xFFFEF2F2),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${profit >= 0 ? "+" : ""}₹${_money(profit)} Profit',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                  color: profit >= 0
                                                      ? const Color(0xFF059669)
                                                      : Colors.red,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '$marginPct% Margin',
                                              style: const TextStyle(
                                                fontSize: 9.5,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 8,
                                            children: [
                                              Text(
                                                'Cost: ₹${_money(cost)}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              Text(
                                                'MRP: ₹${_money(mrp)}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFF475569),
                                                ),
                                              ),
                                              if (disc > 0)
                                                Text(
                                                  'Disc: -₹${_money(disc)}',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFD97706),
                                                  ),
                                                ),
                                              Text(
                                                'Net Sold: ₹${_money(sold)}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF4338CA),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () =>
                                                  _editSoldItemDialog(item),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 5),
                                                child: Text(
                                                  'Edit',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF0284C7),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: () =>
                                                  _revokeSoldItem(item),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 5),
                                                child: Text(
                                                  'Revoke',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFFDC2626),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () =>
                                                  _openFullBillFromSale(sale),
                                              child: const Text(
                                                'Full Bill →',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF4338CA),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )),
        ),
      ],
    );
  }

  /// TAB 3: Udhaar Khata (Branch-aware + WhatsApp & SMS Reminder Buttons)
  Widget _buildUdhaarLedgerTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF4338CA)));
    }

    final uQuery = _udhaarSearchQuery.toLowerCase();
    final filteredUdhaar = _udhaarSalesList.where((dynamic raw) {
      if (uQuery.isEmpty) return true;
      final sale = _asMap(raw);
      final cust = _asMap(sale['customers']);
      final name = (cust['name'] ?? '').toString().toLowerCase();
      final phone = (cust['phone'] ?? '').toString().toLowerCase();
      final notes = (sale['notes'] ?? '').toString().toLowerCase();
      final branch = (sale['branch_name'] ?? '').toString().toLowerCase();
      return name.contains(uQuery) ||
          phone.contains(uQuery) ||
          notes.contains(uQuery) ||
          branch.contains(uQuery);
    }).toList();

    final Map<String, Map<String, dynamic>> customerDueGroups = {};
    for (final dynamic raw in filteredUdhaar) {
      final s = _asMap(raw);
      final c = _asMap(s['customers']);
      final phone = (c['phone'] ?? '').toString();
      final name = (c['name'] ?? 'Customer').toString();
      final key = phone.isNotEmpty ? phone : name;
      customerDueGroups.putIfAbsent(
        key,
        () => {
          'name': name,
          'phone': phone,
          'total_due': 0.0,
          'total_bill': 0.0,
          'bills_count': 0,
          'latest_sale': s,
        },
      );
      customerDueGroups[key]!['total_due'] =
          _number(customerDueGroups[key]!['total_due']) +
              _number(s['due_amount']);
      customerDueGroups[key]!['total_bill'] =
          _number(customerDueGroups[key]!['total_bill']) +
              _number(s['total_amount']);
      customerDueGroups[key]!['bills_count'] =
          _integer(customerDueGroups[key]!['bills_count']) + 1;
    }
    final groupedCustomersList = customerDueGroups.values.toList()
      ..sort((a, b) =>
          _number(b['total_due']).compareTo(_number(a['total_due'])));

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          color: const Color(0xFFFEF2F2),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ShopConfig.current.isOwner
                            ? 'Total Market Udhaar (All Branches)'
                            : 'Branch Udhaar (${ShopConfig.current.branchName})',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        '₹${_money(_totalUdhaarDue)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_udhaarSalesList.length} Pending Bills',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        onChanged: (v) =>
                            setState(() => _udhaarSearchQuery = v.trim()),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          hintText:
                              'Search Udhaar by Customer Name, Mobile or Branch...',
                          prefixIcon: const Icon(Icons.search, size: 17),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.red.shade200),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: () => setState(
                        () => _groupUdhaarByCustomer = !_groupUdhaarByCustomer),
                    icon: Icon(
                      _groupUdhaarByCustomer
                          ? Icons.receipt_rounded
                          : Icons.people_alt_rounded,
                      size: 16,
                    ),
                    label: Text(
                      _groupUdhaarByCustomer ? 'By Bill' : 'By Customer',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredUdhaar.isEmpty
              ? const Center(
                  child: Text(
                      'No pending Udhaar / customer dues in this period! 🎉'),
                )
              : _groupUdhaarByCustomer
                  ? ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: groupedCustomersList.length,
                      itemBuilder: (ctx, idx) {
                        final grp = groupedCustomersList[idx];
                        final due = _number(grp['total_due']);
                        final count = _integer(grp['bills_count']);
                        final latestSale = _asMap(grp['latest_sale']);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFFEF2F2),
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              '${grp['name']} • ${grp['phone']}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13.5),
                            ),
                            subtitle: Text(
                              '$count Pending Bill(s) • Total Billed: ₹${_money(grp['total_bill'])}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Due: ₹${_money(due)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'WhatsApp Reminder',
                                  icon: const Icon(
                                    Icons.chat_rounded,
                                    size: 18,
                                    color: Color(0xFF059669),
                                  ),
                                  onPressed: () => _sendUdhaarReminder(
                                    grp['name'].toString(),
                                    grp['phone'].toString(),
                                    due,
                                    null,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'SMS Reminder',
                                  icon: const Icon(
                                    Icons.sms_rounded,
                                    size: 18,
                                    color: Color(0xFF2563EB),
                                  ),
                                  onPressed: () => _sendUdhaarReminder(
                                    grp['name'].toString(),
                                    grp['phone'].toString(),
                                    due,
                                    null,
                                    isSms: true,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _settleUdhaarDialog(latestSale),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: filteredUdhaar.length,
                      itemBuilder: (ctx, idx) {
                        final sale = _asMap(filteredUdhaar[idx]);
                        final customer = _asMap(sale['customers']);
                        final due = _number(sale['due_amount']);
                        final paid = _number(sale['paid_amount']);
                        final total = _number(sale['total_amount']);
                        final discount = _number(sale['discount_amount']);
                        final branch =
                            (sale['branch_name'] ?? 'Main Branch').toString();
                        final notes = (sale['notes'] ?? '').toString();
                        final date =
                            _parseDate(sale['created_at']) ?? DateTime.now();

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openFullBillFromSale(sale),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 17,
                                        backgroundColor: Color(0xFFFEF2F2),
                                        child: Icon(Icons.person,
                                            size: 18, color: Color(0xFFDC2626)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${customer['name'] ?? 'Customer'} • ${customer['phone'] ?? ''} ($branch)',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Net Bill: ₹${_money(total)}${discount > 0 ? ' (Disc: -₹${_money(discount)})' : ''} | Paid: ₹${_money(paid)}',
                                              style:
                                                  const TextStyle(fontSize: 11.5),
                                            ),
                                            Text(
                                              'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(date)}',
                                              style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        'Due: ₹${_money(due)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (notes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Note: $notes',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: Color(0xFF991B1B),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor:
                                              const Color(0xFF059669),
                                        ),
                                        onPressed: () => _sendUdhaarReminder(
                                          (customer['name'] ?? 'Customer')
                                              .toString(),
                                          (customer['phone'] ?? '').toString(),
                                          due,
                                          date,
                                        ),
                                        icon: const Icon(Icons.chat_rounded,
                                            size: 14),
                                        label: const Text('WhatsApp',
                                            style: TextStyle(fontSize: 11)),
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor:
                                              const Color(0xFF2563EB),
                                        ),
                                        onPressed: () => _sendUdhaarReminder(
                                          (customer['name'] ?? 'Customer')
                                              .toString(),
                                          (customer['phone'] ?? '').toString(),
                                          due,
                                          date,
                                          isSms: true,
                                        ),
                                        icon: const Icon(Icons.sms_rounded,
                                            size: 14),
                                        label: const Text('SMS',
                                            style: TextStyle(fontSize: 11)),
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor:
                                              const Color(0xFF4338CA),
                                        ),
                                        onPressed: () =>
                                            _openFullBillFromSale(sale),
                                        icon: const Icon(
                                            Icons.receipt_long_rounded,
                                            size: 14),
                                        label: const Text('Bill',
                                            style: TextStyle(fontSize: 11)),
                                      ),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF059669),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () =>
                                            _settleUdhaarDialog(sale),
                                        icon: const Icon(
                                            Icons.payments_outlined,
                                            size: 14),
                                        label: const Text('Settle',
                                            style: TextStyle(fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// TAB 4: Charts & Top Sellers
  Widget _buildAnalyticsChartsTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4338CA)),
      );
    }

    final products = _topProductsMap.values.toList()
      ..sort((a, b) =>
          _integer(b['units_sold']).compareTo(_integer(a['units_sold'])));

    final brands = _brandPerformanceMap.values.toList()
      ..sort((a, b) =>
          _number(b['total_profit']).compareTo(_number(a['total_profit'])));

    double maxAmount = 0;
    for (final point in _chartDataPoints) {
      final val = _showProfitInChart
          ? _number(point['profit'])
          : _number(point['amount']);
      maxAmount = max(maxAmount, val);
    }

    final categoryTotal = _smartphoneRevenue + _accessoryRevenue;
    final phoneShare = categoryTotal > 0
        ? ((_smartphoneRevenue / categoryTotal) * 100).toStringAsFixed(0)
        : '0';
    final accessoryShare = categoryTotal > 0
        ? ((_accessoryRevenue / categoryTotal) * 100).toStringAsFixed(0)
        : '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sales & Profit Trends',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Row(
                children: [
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      _showProfitInChart
                          ? 'Showing: Profit'
                          : 'Showing: Revenue',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _showProfitInChart,
                    onSelected: (v) => setState(() => _showProfitInChart = v),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    initialValue: _chartViewMode,
                    onSelected: (mode) {
                      setState(() {
                        _chartViewMode = mode;
                        _chartDataPoints =
                            _generateChartPoints(_salesList, mode);
                      });
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'Daily', child: Text('Daily')),
                      PopupMenuItem(value: 'Weekly', child: Text('Weekly')),
                      PopupMenuItem(value: 'Monthly', child: Text('Monthly')),
                      PopupMenuItem(value: 'Yearly', child: Text('Yearly')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _chartViewMode,
                            style: const TextStyle(
                              color: Color(0xFF4338CA),
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down,
                              color: Color(0xFF4338CA)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _showProfitInChart
                            ? 'Net Profit ($_totalItemsSold units sold)'
                            : 'Revenue ($_totalItemsSold units sold)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      Text(
                        _showProfitInChart
                            ? '+₹${_money(_totalProfit)}'
                            : '₹${_money(_totalRevenue)}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: _showProfitInChart
                              ? const Color(0xFF059669)
                              : const Color(0xFF4338CA),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _chartDataPoints.map((point) {
                        final amount = _showProfitInChart
                            ? _number(point['profit'])
                            : _number(point['amount']);
                        final label = point['label']?.toString() ?? '';
                        final ratio = maxAmount > 0
                            ? (amount / maxAmount).clamp(0.0, 1.0)
                            : 0.0;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (amount > 0)
                                  FittedBox(
                                    child: Text(
                                      '₹${_money(amount)}',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  height: max(8.0, ratio * 110).toDouble(),
                                  decoration: BoxDecoration(
                                    color: amount > 0
                                        ? (_showProfitInChart
                                            ? const Color(0xFF059669)
                                            : const Color(0xFF4338CA))
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FittedBox(
                                  child: Text(label,
                                      style: const TextStyle(fontSize: 9)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildMiniMetric(
                    'Smartphones ($phoneShare%)',
                    '₹${_money(_smartphoneRevenue)}',
                    'Profit: +₹${_money(_smartphoneProfit)}',
                    const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 8),
                  _buildMiniMetric(
                    'Accessories ($accessoryShare%)',
                    '₹${_money(_accessoryRevenue)}',
                    'Profit: +₹${_money(_accessoryProfit)}',
                    const Color(0xFFD97706),
                  ),
                ],
              ),
            ),
          ),
          if (_paymentModeBreakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Collection by Payment Mode',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _paymentModeBreakdown.entries.map((e) {
                        return Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: const Color(0xFFF8FAFC),
                          label: Text(
                            '${e.key}: ₹${_money(e.value)}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (brands.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Brand-Wise Profit Leaderboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 82,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: brands.length,
                itemBuilder: (ctx, i) {
                  final b = brands[i];
                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${b['brand']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${b['units_sold']} Sold • ₹${_money(b['total_revenue'])}',
                          style:
                              const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '+₹${_money(b['total_profit'])} Profit',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Top Selling Models',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          ...products.map((product) {
            final num modelProfit = _number(product['total_profit']);
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(
                  product['is_bulk'] == true
                      ? Icons.headphones_rounded
                      : Icons.phone_android_rounded,
                  color: const Color(0xFF4338CA),
                ),
                title: Text(
                  product['name']?.toString() ?? 'Item',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                subtitle: Text(
                  '${product['units_sold']} units sold  •  Sales: ₹${_money(product['total_revenue'])}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '+₹${_money(modelProfit)} Profit',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// TAB 5: Unsold Stock
  Widget _buildUnsoldItemsTab() {
    final unrealizedProfit = _unsoldTotalValue - _unsoldTotalCost;
    final now = DateTime.now();
    final q = _unsoldSearchQuery.toLowerCase();

    final filteredUnsold = _unsoldStockItems.where((dynamic raw) {
      final item = _asMap(raw);
      final prod = _asMap(item['products']);
      final bool isBulk = prod['is_bulk'] == true;
      final int qty = _integer(item['quantity'], fallback: 1);
      final DateTime created = _parseDate(item['created_at']) ?? now;
      final int ageDays = now.difference(created).inDays;

      if (_unsoldFilterType == 'Phones' && isBulk) return false;
      if (_unsoldFilterType == 'Accessories' && !isBulk) return false;
      if (_unsoldFilterType == 'Low Stock' && (!isBulk || qty > 2)) {
        return false;
      }
      if (_unsoldFilterType == 'Old (>30d)' && ageDays < 30) return false;

      if (q.isEmpty) return true;
      final fullSpec = ShopConfig.formatProductSpecTitle(prod).toLowerCase();
      final code1 = (item['imei_or_serial'] ?? '').toString().toLowerCase();
      final code2 = (item['imei_2'] ?? '').toString().toLowerCase();
      return fullSpec.contains(q) || code1.contains(q) || code2.contains(q);
    }).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: [
                  _buildMiniMetric(
                    'Capital Cost',
                    '₹${_money(_unsoldTotalCost)}',
                    'Purchase Cost',
                    const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniMetric(
                    'Selling Value',
                    '₹${_money(_unsoldTotalValue)}',
                    'MRP Value',
                    const Color(0xFF059669),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniMetric(
                    'Expected Margin',
                    '₹${_money(unrealizedProfit)}',
                    'Potential Profit',
                    const Color(0xFFD97706),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _unsoldSearchQuery = v.trim()),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText:
                        'Search unsold stock by Brand, Model, Specs, IMEI or SKU...',
                    prefixIcon: const Icon(Icons.search, size: 17),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    'All',
                    'Phones',
                    'Accessories',
                    'Low Stock',
                    'Old (>30d)'
                  ].map((t) {
                    final sel = _unsoldFilterType == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _unsoldFilterType = t),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredUnsold.isEmpty
              ? const Center(child: Text('No unsold stock matches your filter.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: filteredUnsold.length,
                  itemBuilder: (context, index) {
                    final item = _asMap(filteredUnsold[index]);
                    final product = _asMap(item['products']);
                    final bool isBulk = product['is_bulk'] == true;
                    final int qty = _integer(item['quantity'], fallback: 1);
                    final code1 = item['imei_or_serial']?.toString() ?? '';
                    final code2 = item['imei_2']?.toString() ?? '';
                    final cost = _number(product['cost_price']);
                    final selling = _number(product['selling_price']);
                    final expectedProfit = (selling - cost) * qty;
                    final created = _parseDate(item['created_at']) ?? now;
                    final ageDays = now.difference(created).inDays;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        onTap: () => _editUnsoldStockPriceDialog(item),
                        leading: Icon(
                          isBulk
                              ? Icons.headphones_rounded
                              : Icons.smartphone_rounded,
                          color: isBulk
                              ? const Color(0xFFD97706)
                              : const Color(0xFF4338CA),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ShopConfig.formatProductSpecTitle(product),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                            ),
                            if (ageDays >= 30)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${ageDays}d old',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          isBulk
                              ? 'SKU: $code1  •  Slab Qty: $qty Units\nCost: ₹${_money(cost)}/u  •  Exp Profit: +₹${_money(expectedProfit)}'
                              : 'IMEI 1: $code1${code2.isNotEmpty ? ' | IMEI 2: $code2' : ''}\nCost: ₹${_money(cost)}  •  Exp Profit: +₹${_money(expectedProfit)}',
                          style: const TextStyle(
                              fontSize: 10.5, fontFamily: 'monospace'),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${_money(selling * qty)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4338CA),
                              ),
                            ),
                            if (isBulk)
                              Text(
                                '$qty × ₹${_money(selling)}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              )
                            else
                              const Text(
                                'Tap to Edit ₹',
                                style:
                                    TextStyle(fontSize: 9, color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// TAB 6: Dedicated Branch Sales Tab for Owner
  Widget _buildBranchSalesTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4338CA)),
      );
    }

    final q = _branchSearchQuery.toLowerCase();
    final branchList = _branchPerformanceMap.values.where((b) {
      if (q.isEmpty) return true;
      final bName = (b['branch_name'] ?? '').toString().toLowerCase();
      final emails = (b['seller_emails'] as Set<String>).join(' ').toLowerCase();
      return bName.contains(q) || emails.contains(q);
    }).toList()
      ..sort((a, b) =>
          _integer(b['units_sold']).compareTo(_integer(a['units_sold'])));

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildMiniMetric(
                    'Active Branches',
                    '${_branchPerformanceMap.length}',
                    'Selling Counters',
                    const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniMetric(
                    'Total Items Sold',
                    '$_totalItemsSold Units',
                    'Across Branches',
                    const Color(0xFF059669),
                  ),
                  const SizedBox(width: 6),
                  _buildMiniMetric(
                    'Total Sales',
                    '₹${_money(_totalRevenue)}',
                    '${_salesList.length} Bills',
                    const Color(0xFF2563EB),
                  ),
                  if (ShopConfig.current.canSeeProfit) ...[
                    const SizedBox(width: 6),
                    _buildMiniMetric(
                      'Total Profit',
                      '+₹${_money(_totalProfit)}',
                      'All Branches',
                      const Color(0xFF7C3AED),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _branchSearchQuery = v.trim()),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search branch name or staff email...',
                    prefixIcon: const Icon(
                        Icons.store_mall_directory_outlined,
                        size: 17),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: branchList.isEmpty
              ? const Center(
                  child: Text('No branch sales recorded in this period.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: branchList.length,
                  itemBuilder: (ctx, idx) {
                    final branch = branchList[idx];
                    final branchName =
                        (branch['branch_name'] ?? 'Main Branch').toString();
                    final staffEmails =
                        (branch['seller_emails'] as Set<String>).toList();
                    final billsCount = _integer(branch['bills_count']);
                    final unitsSold = _integer(branch['units_sold']);
                    final phonesSold = _integer(branch['phones_sold']);
                    final accessoriesSold =
                        _integer(branch['accessories_sold']);
                    final revenue = _number(branch['total_revenue']);
                    final profit = _number(branch['total_profit']);
                    final due = _number(branch['total_due']);
                    final soldItemsList = (branch['items_list']
                            as List<Map<String, dynamic>>?) ??
                        [];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFEEF2FF),
                          child: Text(
                            '#${idx + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                branchName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF1E1B4B),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$unitsSold Items Sold',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    '📱 Phones: $phonesSold',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4338CA),
                                    ),
                                  ),
                                  Text(
                                    '🎧 Accessories: $accessoriesSold',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                  Text(
                                    '🧾 Bills: $billsCount',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 10,
                                children: [
                                  Text(
                                    'Sales: ₹${_money(revenue)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  if (ShopConfig.current.canSeeProfit)
                                    Text(
                                      'Profit: +₹${_money(profit)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  if (due > 0)
                                    Text(
                                      'Udhaar Due: ₹${_money(due)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                ],
                              ),
                              if (staffEmails.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Staff: ${staffEmails.join(", ")}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        children: [
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Items Sold by This Branch:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                ...soldItemsList.take(25).map((it) {
                                  final dt = it['date'] as DateTime;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '• ${it['name']} × ${it['qty']} (${it['imei']})',
                                            style:
                                                const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        Text(
                                          '₹${_money(it['sold_price'])} • ${DateFormat('dd MMM').format(dt)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF4338CA),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // Compact 104px AppBar combining period filter chips + custom date picker + Export
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(104),
        child: Container(
          color: Colors.white,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _filterChip('Today'),
                              _filterChip('Last 7 Days'),
                              _filterChip('This Month'),
                              _filterChip('This Year'),
                              _filterChip('All Time'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _pickDateRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: Color(0xFF4338CA),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${dateFormat.format(_selectedDateRange.start)}-${dateFormat.format(_selectedDateRange.end)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                  color: Color(0xFF4338CA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Export / Share Report',
                        onPressed: _openExportReportSheet,
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          size: 17,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                TabBar(
                  controller: _reportTabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: const Color(0xFF4338CA),
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: const Color(0xFF4338CA),
                  indicatorWeight: 2.5,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                  tabs: [
                    Tab(
                      height: 36,
                      text: 'Sold Items & Bills ($_totalItemsSold)',
                    ),
                    Tab(
                      height: 36,
                      text: 'Profit (+₹${_money(_totalProfit)})',
                    ),
                    Tab(
                      height: 36,
                      text: 'Udhaar (${_udhaarSalesList.length})',
                    ),
                    const Tab(
                      height: 36,
                      text: 'Charts & Top',
                    ),
                    const Tab(
                      height: 36,
                      text: 'Unsold Stock',
                    ),
                    Tab(
                      height: 36,
                      text: 'Branches (${_branchPerformanceMap.length})',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _reportTabController,
        children: [
          _buildTransactionsTab(),
          _buildItemProfitTab(),
          _buildUdhaarLedgerTab(),
          _buildAnalyticsChartsTab(),
          _buildUnsoldItemsTab(),
          _buildBranchSalesTab(),
        ],
      ),
    );
  }

  Widget _filterChip(String period) {
    final selected = _selectedFilter == period;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        label: Text(period, style: const TextStyle(fontSize: 10)),
        selected: selected,
        selectedColor: const Color(0xFFEEF2FF),
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF4338CA) : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => _applyFilter(period),
      ),
    );
  }
}