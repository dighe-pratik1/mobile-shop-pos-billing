import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shop_config.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;

  // Controllers for POS Counter
  final codeSearchCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final discountCtrl = TextEditingController(text: '0');
  final paidNowCtrl = TextEditingController();
  final cashGivenCtrl = TextEditingController();
  final splitCashCtrl = TextEditingController(text: '0');
  final splitOnlineCtrl = TextEditingController(text: '0');
  final notesCtrl = TextEditingController();
  final customWarrantyCtrl = TextEditingController();

  // Search filter for Available Stock tab & Sold Bills tab
  final availSearchCtrl = TextEditingController();
  final soldBillSearchCtrl = TextEditingController();

  final List<Map<String, dynamic>> _cartItems = [];
  List<dynamic> _availableStockList = [];
  List<dynamic> _recentSalesList = [];
  bool _loadingStock = false;
  bool _loadingSales = false;
  bool _isSearching = false;
  bool _isSelling = false;
  String _selectedPaymentMode = 'Cash';
  String _availSearchQuery = '';
  String _availCategoryFilter = 'All';
  String _soldSearchQuery = '';

  String _selectedWarrantyOption = 'No Warranty';
  final List<String> _warrantyPresets = const [
    'No Warranty',
    '3 Months Shop Warranty',
    '6 Months Warranty',
    '1 Year Brand Warranty',
    '2 Years Brand Warranty',
    'Custom Warranty',
  ];

  final List<Map<String, dynamic>> _paymentOptions = const [
    {'label': 'Cash', 'icon': Icons.payments_rounded, 'color': Color(0xFF059669)},
    {'label': 'UPI / QR', 'icon': Icons.qr_code_scanner_rounded, 'color': Color(0xFF4338CA)},
    {'label': 'Borrow / Udhaar', 'icon': Icons.menu_book_rounded, 'color': Color(0xFFDC2626)},
    {'label': 'Split (Cash + UPI)', 'icon': Icons.call_split_rounded, 'color': Color(0xFFD97706)},
    {'label': 'Card', 'icon': Icons.credit_card_rounded, 'color': Color(0xFF2563EB)},
    {'label': 'Bajaj / EMI', 'icon': Icons.account_balance_rounded, 'color': Color(0xFF7C3AED)},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAvailableStock();
    _loadRecentSales();
  }

  @override
  void dispose() {
    _tabController.dispose();
    codeSearchCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    discountCtrl.dispose();
    paidNowCtrl.dispose();
    cashGivenCtrl.dispose();
    splitCashCtrl.dispose();
    splitOnlineCtrl.dispose();
    notesCtrl.dispose();
    customWarrantyCtrl.dispose();
    availSearchCtrl.dispose();
    soldBillSearchCtrl.dispose();
    super.dispose();
  }

  /// Strips internal SR metadata tags like [SR_IN:...] or [SR:...] so they never show on customer bills
  String _stripSrMetadata(String raw) {
    if (raw.isEmpty) return '';
    var cleaned = raw.replaceAll(
      RegExp(r'\[SR(?:_IN|_OUT)?\s*:[^\]]*\]', caseSensitive: false),
      '',
    );
    cleaned = cleaned
        .replaceAll(RegExp(r'(\s*•\s*)+'), ' • ')
        .replaceAll(RegExp(r'^\s*•\s*|\s*•\s*$'), '')
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return cleaned;
  }

  /// Returns a copy of the product map with SR metadata stripped from title and variant_details
  Map<String, dynamic> _cleanProductForCustomer(Map<String, dynamic> prod) {
    final copy = Map<String, dynamic>.from(prod);
    copy['title'] = _stripSrMetadata((copy['title'] ?? '').toString());
    copy['variant_details'] =
        _stripSrMetadata((copy['variant_details'] ?? '').toString());
    return copy;
  }

  Future<void> _loadAvailableStock() async {
    if (mounted) setState(() => _loadingStock = true);
    try {
      final res = await supabase
          .from('stock_items')
          .select('id, imei_or_serial, imei_2, status, quantity, product_id, products(*)')
          .eq('status', 'Available')
          .gt('quantity', 0)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _availableStockList = res;
          _loadingStock = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStock = false);
    }
  }

  Future<void> _loadRecentSales() async {
    if (mounted) setState(() => _loadingSales = true);
    try {
      final res = await supabase
          .from('sales')
          .select('*, customers(name, phone), sale_items(*, products(*), stock_items(*))')
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _recentSalesList = res;
          _loadingSales = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSales = false);
    }
  }

  num _unitPriceOfCartRow(Map<String, dynamic> cartRow) {
    final prod = cartRow['stock']['products'] ?? {};
    return (cartRow['custom_unit_price'] as num?) ?? (prod['selling_price'] ?? 0);
  }

  num _cartSubtotal() {
    num total = 0;
    for (final cartRow in _cartItems) {
      final num unitPrice = _unitPriceOfCartRow(cartRow);
      final int qty = cartRow['buy_qty'] ?? 1;
      total += unitPrice * qty;
    }
    return total;
  }

  num _cartTotalCost() {
    num totalCost = 0;
    for (final cartRow in _cartItems) {
      final prod = cartRow['stock']['products'] ?? {};
      final num unitCost = prod['cost_price'] ?? 0;
      final int qty = cartRow['buy_qty'] ?? 1;
      totalCost += unitCost * qty;
    }
    return totalCost;
  }

  num _netPayableAmount() {
    final num subtotal = _cartSubtotal();
    final num discount = num.tryParse(discountCtrl.text.trim()) ?? 0;
    return (subtotal - discount) > 0 ? (subtotal - discount) : 0;
  }

  void _syncPaymentFieldsWithNetAmount() {
    final net = _netPayableAmount();
    if (_selectedPaymentMode == 'Borrow / Udhaar') {
      paidNowCtrl.text = '0';
    } else if (_selectedPaymentMode == 'Split (Cash + UPI)') {
      final half = (net / 2).round();
      splitCashCtrl.text = half.toString();
      splitOnlineCtrl.text = (net - half).toStringAsFixed(0);
      paidNowCtrl.text = net.toStringAsFixed(0);
    } else {
      paidNowCtrl.text = net.toStringAsFixed(0);
    }
  }

  void _editCartItemPriceDialog(Map<String, dynamic> cartRow) {
    final shop = ShopConfig.current;
    if (!shop.canGiveDiscount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only Shop Owner or authorized staff can modify unit price.')),
      );
      return;
    }

    final prod = _cleanProductForCustomer(
      Map<String, dynamic>.from((cartRow['stock']['products'] as Map?) ?? {}),
    );
    final num currentSell = _unitPriceOfCartRow(cartRow);
    final ctrl = TextEditingController(text: currentSell.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Selling Price: ${prod['brand']} ${prod['title']}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Custom Unit Selling Price (₹)',
            prefixText: '₹ ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newPrice = num.tryParse(ctrl.text.trim());
              if (newPrice != null && newPrice >= 0) {
                setState(() {
                  cartRow['custom_unit_price'] = newPrice;
                  _syncPaymentFieldsWithNetAmount();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Update Price'),
          ),
        ],
      ),
    );
  }

  void _addStockItemToCart(Map<String, dynamic> stockItem, {bool switchToPosTab = false}) {
    if (!ShopConfig.current.canSellInPos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('POS Selling permission is disabled for your account by Shop Owner.'),
        ),
      );
      return;
    }

    final String stockId = stockItem['id'].toString();
    final prod = _cleanProductForCustomer(
      Map<String, dynamic>.from((stockItem['products'] as Map?) ?? {}),
    );
    final bool isBulk = prod['is_bulk'] == true;
    final int availableQty = (stockItem['quantity'] as num?)?.toInt() ?? 1;

    final existingIdx = _cartItems.indexWhere((e) => e['stock']['id'].toString() == stockId);

    setState(() {
      if (existingIdx != -1) {
        if (isBulk) {
          final currentBuyQty = _cartItems[existingIdx]['buy_qty'] as int;
          if (currentBuyQty < availableQty) {
            _cartItems[existingIdx]['buy_qty'] = currentBuyQty + 1;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Max available stock ($availableQty) already in cart!')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This IMEI handset is already in the cart!')),
          );
        }
      } else {
        _cartItems.add({
          'stock': stockItem,
          'buy_qty': 1,
          'custom_unit_price': prod['selling_price'] ?? 0,
        });
      }
      codeSearchCtrl.clear();
      _syncPaymentFieldsWithNetAmount();
    });

    if (switchToPosTab) {
      _tabController.animateTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 1),
          content: Text('Added "${prod['brand']} ${prod['title']}" to POS Bill!'),
        ),
      );
    }
  }

  Future<void> _searchBarcodeOrImei([String? explicitCode]) async {
    final code = (explicitCode ?? codeSearchCtrl.text).trim();
    if (code.isEmpty) return;
    setState(() => _isSearching = true);

    try {
      final List<dynamic> res = await supabase
          .from('stock_items')
          .select('id, imei_or_serial, imei_2, status, quantity, product_id, products(*)')
          .eq('status', 'Available')
          .gt('quantity', 0)
          .or('imei_or_serial.eq.$code,imei_2.eq.$code')
          .limit(1);

      setState(() => _isSearching = false);

      if (res.isNotEmpty) {
        _addStockItemToCart(Map<String, dynamic>.from(res.first));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.amber.shade900,
            content: const Text(
              'Item not found in available stock! Browse the "Available Items" tab.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade700, content: Text('Search Error: $e')),
        );
      }
    }
  }

  String _resolvedWarrantyText() {
    if (_selectedWarrantyOption == 'Custom Warranty') {
      final custom = customWarrantyCtrl.text.trim();
      return custom.isEmpty ? 'Custom Warranty' : custom;
    }
    return _selectedWarrantyOption;
  }

  Future<void> _processSale() async {
    if (_cartItems.isEmpty) return;
    if (!ShopConfig.current.canSellInPos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('You do not have permission to process sales.'),
        ),
      );
      return;
    }

    final customerName = nameCtrl.text.trim();
    final customerPhone = phoneCtrl.text.trim();

    if (customerName.isEmpty ||
        !RegExp(r'^\d{10}$').hasMatch(customerPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Please enter Customer Name and a valid 10-digit Mobile Number',
          ),
        ),
      );
      return;
    }

    final num subtotal = _cartSubtotal();
    final num discount = num.tryParse(discountCtrl.text.trim()) ?? 0;
    final num finalSell = _netPayableAmount();
    final num totalCost = _cartTotalCost();
    final num totalProfit = finalSell - totalCost;
    final String warrantyText = _resolvedWarrantyText();

    num cashPaid = 0;
    num onlinePaid = 0;
    num totalPaidNow = 0;

    if (_selectedPaymentMode == 'Split (Cash + UPI)') {
      cashPaid = num.tryParse(splitCashCtrl.text.trim()) ?? 0;
      onlinePaid = num.tryParse(splitOnlineCtrl.text.trim()) ?? 0;
      totalPaidNow = cashPaid + onlinePaid;
    } else if (_selectedPaymentMode == 'Cash') {
      totalPaidNow = num.tryParse(paidNowCtrl.text.trim()) ?? finalSell;
      cashPaid = totalPaidNow;
    } else if (_selectedPaymentMode == 'Borrow / Udhaar') {
      totalPaidNow = num.tryParse(paidNowCtrl.text.trim()) ?? 0;
      cashPaid = totalPaidNow;
    } else {
      totalPaidNow = num.tryParse(paidNowCtrl.text.trim()) ?? finalSell;
      onlinePaid = totalPaidNow;
    }

    if (totalPaidNow > finalSell) totalPaidNow = finalSell;

    final num dueAmount = (finalSell - totalPaidNow) > 0 ? (finalSell - totalPaidNow) : 0;
    final String paymentStatus = dueAmount == 0
        ? 'Paid'
        : (totalPaidNow > 0 ? 'Partial / Due' : 'Udhaar (Unpaid)');
    final String effectivePaymentMode =
        dueAmount > 0 && _selectedPaymentMode != 'Borrow / Udhaar'
            ? '$_selectedPaymentMode + Udhaar'
            : _selectedPaymentMode;

    setState(() => _isSelling = true);

    try {
      final effectiveTenantId = ShopConfig.current.effectiveTenantId.isNotEmpty
          ? ShopConfig.current.effectiveTenantId
          : supabase.auth.currentUser?.id;

      final List<Map<String, dynamic>> invoiceLineItems = [];
      final List<Map<String, dynamic>> rpcPayloadItems = [];

      for (final cartRow in _cartItems) {
        final stock = cartRow['stock'] as Map<String, dynamic>;
        final rawProduct = Map<String, dynamic>.from((stock['products'] as Map?) ?? {});
        final product = _cleanProductForCustomer(rawProduct);
        final bool isBulk = product['is_bulk'] == true;
        final int buyQty = cartRow['buy_qty'] ?? 1;

        final num unitCost = product['cost_price'] ?? 0;
        final num unitSell = _unitPriceOfCartRow(cartRow);
        final num lineCost = unitCost * buyQty;
        final num lineGrossSell = unitSell * buyQty;
        final num lineDiscountShare =
            subtotal > 0 ? (discount * (lineGrossSell / subtotal)) : 0;
        final num lineNetSell =
            (lineGrossSell - lineDiscountShare) > 0 ? (lineGrossSell - lineDiscountShare) : 0;
        final num lineProfit = lineNetSell - lineCost;

        final ramRom = (product['ram_rom'] ?? '').toString().trim();
        final color = (product['color'] ?? '').toString().trim();
        final details = (product['variant_details'] ?? '').toString().trim();
        final specsStr = [
          if (ramRom.isNotEmpty) ramRom,
          if (color.isNotEmpty) color,
          if (details.isNotEmpty) details,
        ].join(' • ');

        rpcPayloadItems.add({
          'stock_id': stock['id'],
          'product_id': product['id'],
          'buy_qty': buyQty,
          'is_bulk': isBulk,
          'sold_price': lineNetSell,
          'cost_price': lineCost,
          'profit': lineProfit,
        });

        invoiceLineItems.add({
          'itemName': ShopConfig.formatProductSpecTitle(product),
          'specs': specsStr,
          'imei1': (stock['imei_or_serial'] ?? '').toString(),
          'imei2': (stock['imei_2'] ?? '').toString(),
          'quantity': buyQty,
          'unitPrice': unitSell,
          'lineTotal': lineGrossSell,
          'costPrice': lineCost,
          'profit': lineProfit,
        });
      }

      String saleIdString = '';

      try {
        final rpcRes = await supabase.rpc('process_pos_sale_atomic', params: {
          'p_customer_name': customerName,
          'p_customer_phone': customerPhone,
          'p_subtotal': subtotal,
          'p_discount': discount,
          'p_total_amount': finalSell,
          'p_total_cost': totalCost,
          'p_total_profit': totalProfit,
          'p_paid_amount': totalPaidNow,
          'p_due_amount': dueAmount,
          'p_cash_paid': cashPaid,
          'p_online_paid': onlinePaid,
          'p_payment_mode': effectivePaymentMode,
          'p_payment_status': paymentStatus,
          'p_warranty_period': warrantyText,
          'p_notes': notesCtrl.text.trim(),
          'p_items': rpcPayloadItems,
        });
        saleIdString = rpcRes.toString();
      } catch (rpcErr) {
        if (rpcErr.toString().contains('Concurrency Alert')) {
          rethrow;
        }
        final customer = await supabase
            .from('customers')
            .insert({
              'user_id': effectiveTenantId,
              'name': customerName,
              'phone': customerPhone,
            })
            .select()
            .single();

        final sale = await supabase
            .from('sales')
            .insert({
              'user_id': effectiveTenantId,
              'customer_id': customer['id'],
              'subtotal_amount': subtotal,
              'discount_amount': discount,
              'total_amount': finalSell,
              'total_cost': totalCost,
              'total_profit': totalProfit,
              'paid_amount': totalPaidNow,
              'due_amount': dueAmount,
              'cash_paid': cashPaid,
              'online_paid': onlinePaid,
              'payment_mode': effectivePaymentMode,
              'payment_status': paymentStatus,
              'warranty_period': warrantyText,
              'notes': notesCtrl.text.trim(),
              'sold_by_user_id': supabase.auth.currentUser?.id,
              'sold_by_email': ShopConfig.current.email,
              'branch_name': ShopConfig.current.branchName,
            })
            .select()
            .single();

        saleIdString = sale['id'].toString();

        for (final cartRow in _cartItems) {
          final stock = cartRow['stock'] as Map<String, dynamic>;
          final product = stock['products'] ?? {};
          final bool isBulk = product['is_bulk'] == true;
          final int currentStockQty = (stock['quantity'] as num?)?.toInt() ?? 1;
          final int buyQty = cartRow['buy_qty'] ?? 1;

          final num unitCost = product['cost_price'] ?? 0;
          final num unitSell = _unitPriceOfCartRow(cartRow);
          final num lineCost = unitCost * buyQty;
          final num lineGrossSell = unitSell * buyQty;
          final num lineDiscountShare =
              subtotal > 0 ? (discount * (lineGrossSell / subtotal)) : 0;
          final num lineNetSell =
              (lineGrossSell - lineDiscountShare) > 0 ? (lineGrossSell - lineDiscountShare) : 0;
          final num lineProfit = lineNetSell - lineCost;

          await supabase.from('sale_items').insert({
            'user_id': effectiveTenantId,
            'sale_id': sale['id'],
            'product_id': product['id'],
            'stock_item_id': stock['id'],
            'quantity': buyQty,
            'sold_price': lineNetSell,
            'cost_price': lineCost,
            'profit': lineProfit,
            'warranty_period': warrantyText,
          });

          final int remainingQty = currentStockQty - buyQty;
          if (isBulk && remainingQty > 0) {
            await supabase
                .from('stock_items')
                .update({'quantity': remainingQty, 'status': 'Available'})
                .eq('id', stock['id']);
          } else {
            await supabase
                .from('stock_items')
                .update({'status': 'Sold', 'quantity': 0})
                .eq('id', stock['id']);
          }
        }
      }

      final savedNotes = notesCtrl.text.trim();
      final saleNow = DateTime.now();
      final shortInvId = saleIdString.length >= 8
          ? saleIdString.substring(0, 8).toUpperCase()
          : saleIdString.toUpperCase();

      final formattedInvoiceText = ShopConfig.buildInvoiceText(
        invoiceId: shortInvId,
        customerName: customerName,
        customerPhone: customerPhone,
        lineItems: invoiceLineItems,
        subtotalAmount: subtotal,
        discountAmount: discount,
        finalAmount: finalSell,
        paidAmount: totalPaidNow,
        dueAmount: dueAmount,
        paymentMode: _selectedPaymentMode,
        warrantyPeriod: warrantyText,
        notes: savedNotes,
        date: saleNow,
      );

      if (mounted) {
        setState(() {
          _cartItems.clear();
          codeSearchCtrl.clear();
          nameCtrl.clear();
          phoneCtrl.clear();
          discountCtrl.text = '0';
          paidNowCtrl.clear();
          cashGivenCtrl.clear();
          notesCtrl.clear();
          customWarrantyCtrl.clear();
          _selectedWarrantyOption = 'No Warranty';
          _isSelling = false;
        });

        _loadAvailableStock();
        _loadRecentSales();

        // Requirement 3: Automatically dispatch WhatsApp / SMS / Print to Customer Mobile
        final dispatchStatus = await ShopConfig.autoDispatchCustomerBill(
          context: context,
          customerPhone: customerPhone,
          formattedInvoiceText: formattedInvoiceText,
        );

        if (!mounted) return;

        ShopConfig.showFullInvoiceDialog(
          context: context,
          invoiceId: shortInvId,
          customerName: customerName,
          customerPhone: customerPhone,
          lineItems: invoiceLineItems,
          subtotalAmount: subtotal,
          discountAmount: discount,
          finalAmount: finalSell,
          paidAmount: totalPaidNow,
          dueAmount: dueAmount,
          cashPaid: cashPaid,
          onlinePaid: onlinePaid,
          paymentMode: _selectedPaymentMode,
          paymentStatus: paymentStatus,
          warrantyPeriod: warrantyText,
          notes: savedNotes,
          date: saleNow,
          totalProfit: totalProfit,
          totalCost: totalCost,
          autoDispatchStatus: dispatchStatus,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSelling = false);
        _loadAvailableStock();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade700, content: Text('Sale Failed: $e')),
        );
      }
    }
  }

  Future<void> _editSoldBillDialog(Map<String, dynamic> sale) async {
    final customer = sale['customers'] ?? {};
    final saleId = sale['id'];
    final nameEditCtrl = TextEditingController(text: (customer['name'] ?? '').toString());
    final phoneEditCtrl = TextEditingController(text: (customer['phone'] ?? '').toString());
    final warrantyEditCtrl =
        TextEditingController(text: (sale['warranty_period'] ?? 'No Warranty').toString());
    final notesEditCtrl = TextEditingController(text: (sale['notes'] ?? '').toString());
    final paidEditCtrl = TextEditingController(text: (sale['paid_amount'] ?? '0').toString());
    final totalAmount = (sale['total_amount'] as num?)?.toDouble() ?? 0;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Color(0xFF4338CA)),
            const SizedBox(width: 8),
            Text(
              'Edit Bill #INV-${saleId.toString().substring(0, 6).toUpperCase()}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Bill Amount: ₹${totalAmount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF1E1B4B),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameEditCtrl,
                decoration: InputDecoration(
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneEditCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: warrantyEditCtrl,
                decoration: InputDecoration(
                  labelText: 'Warranty Period',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: paidEditCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount Paid (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesEditCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Note / Remark',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (updated != true) return;

    if (!RegExp(r'^\d{10}$').hasMatch(phoneEditCtrl.text.trim())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mobile Number must contain exactly 10 digits.'),
          ),
        );
      }
      return;
    }

    final newPaid = double.tryParse(paidEditCtrl.text.trim()) ?? 0;
    final newDue = (totalAmount - newPaid) > 0 ? (totalAmount - newPaid) : 0;
    final newStatus =
        newDue == 0 ? 'Paid' : (newPaid > 0 ? 'Partial / Due' : 'Udhaar (Unpaid)');

    try {
      if (sale['customer_id'] != null) {
        await supabase.from('customers').update({
          'name': nameEditCtrl.text.trim(),
          'phone': phoneEditCtrl.text.trim(),
        }).eq('id', sale['customer_id']);
      }

      await supabase.from('sales').update({
        'warranty_period': warrantyEditCtrl.text.trim(),
        'notes': notesEditCtrl.text.trim(),
        'paid_amount': newPaid,
        'due_amount': newDue,
        'payment_status': newStatus,
      }).eq('id', saleId);

      _loadRecentSales();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Bill details updated successfully!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Failed to update bill: $e')),
        );
      }
    }
  }

  void _openInvoiceDialogForExistingSale(Map<String, dynamic> sale) {
    final customer = sale['customers'] ?? {};
    final items = sale['sale_items'] as List<dynamic>? ?? [];
    final saleId = (sale['id'] ?? '').toString();
    final invId = saleId.length >= 8 ? saleId.substring(0, 8).toUpperCase() : saleId;
    final date =
        DateTime.tryParse((sale['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now();

    final List<Map<String, dynamic>> lineItems = [];
    for (final dynamic item in items) {
      final line = item as Map<String, dynamic>;
      final rawProd = Map<String, dynamic>.from((line['products'] as Map?) ?? {});
      final prod = _cleanProductForCustomer(rawProd);
      final stock = line['stock_items'] ?? {};
      final int qty = (line['quantity'] as num?)?.toInt() ?? 1;
      final num soldPrice = (line['sold_price'] as num?) ?? 0;

      final ramRom = (prod['ram_rom'] ?? '').toString().trim();
      final color = (prod['color'] ?? '').toString().trim();
      final details = (prod['variant_details'] ?? '').toString().trim();
      final specs = [
        if (ramRom.isNotEmpty) ramRom,
        if (color.isNotEmpty) color,
        if (details.isNotEmpty) details,
      ].join(' • ');

      lineItems.add({
        'itemName': ShopConfig.formatProductSpecTitle(prod),
        'specs': specs,
        'imei1': (stock['imei_or_serial'] ?? '').toString(),
        'imei2': (stock['imei_2'] ?? '').toString(),
        'quantity': qty,
        'unitPrice': qty > 0 ? (soldPrice / qty) : soldPrice,
        'lineTotal': soldPrice,
      });
    }

    ShopConfig.showFullInvoiceDialog(
      context: context,
      invoiceId: invId,
      customerName: (customer['name'] ?? 'Walk-in Customer').toString(),
      customerPhone: (customer['phone'] ?? '').toString(),
      lineItems: lineItems,
      subtotalAmount:
          (sale['subtotal_amount'] as num?) ?? (sale['total_amount'] as num?) ?? 0,
      discountAmount: (sale['discount_amount'] as num?) ?? 0,
      finalAmount: (sale['total_amount'] as num?) ?? 0,
      paidAmount: (sale['paid_amount'] as num?) ?? 0,
      dueAmount: (sale['due_amount'] as num?) ?? 0,
      cashPaid: (sale['cash_paid'] as num?) ?? 0,
      onlinePaid: (sale['online_paid'] as num?) ?? 0,
      paymentMode: (sale['payment_mode'] ?? 'Cash').toString(),
      paymentStatus: (sale['payment_status'] ?? 'Paid').toString(),
      warrantyPeriod: (sale['warranty_period'] ?? 'No Warranty').toString(),
      notes: (sale['notes'] ?? '').toString(),
      date: date,
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: CLEAN POS BILLING COUNTER (With Auto-Send WhatsApp/SMS & Print Toggles)
  // ---------------------------------------------------------------------------
  Widget _buildPosCounterTab(BuildContext context, ShopProfile shop) {
    final num subtotalPrice = _cartSubtotal();
    final num discountVal = num.tryParse(discountCtrl.text.trim()) ?? 0;
    final num finalPrice = _netPayableAmount();

    num paidNow = 0;
    if (_selectedPaymentMode == 'Split (Cash + UPI)') {
      paidNow = (num.tryParse(splitCashCtrl.text.trim()) ?? 0) +
          (num.tryParse(splitOnlineCtrl.text.trim()) ?? 0);
    } else {
      paidNow = num.tryParse(paidNowCtrl.text.trim()) ?? finalPrice;
    }
    if (paidNow > finalPrice) paidNow = finalPrice;
    final num balanceDue = (finalPrice - paidNow) > 0 ? (finalPrice - paidNow) : 0;
    final num cashTendered = num.tryParse(cashGivenCtrl.text.trim()) ?? 0;
    final num changeToReturn = (cashTendered - paidNow) > 0 ? (cashTendered - paidNow) : 0;

    int totalUnitsInCart = 0;
    for (final item in _cartItems) {
      totalUnitsInCart += (item['buy_qty'] as int? ?? 1);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 1: Customer Details + Auto-Send Message Bar
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '1. Customer Details & Auto-Bill Dispatch',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF4338CA),
                        ),
                        onPressed: () async {
                          ShopConfig.showAutoMessagingAndPrinterSettingsDialog(context);
                        },
                        icon: const Icon(Icons.settings_suggest_rounded, size: 16),
                        label: const Text(
                          'Auto-Msg & Printer Setup',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Customer Full Name *',
                            prefixIcon: const Icon(Icons.person, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Mobile Number (Auto-Send) *',
                            prefixIcon: const Icon(Icons.phone_android, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text(
                          'On Final Bill:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFECFDF5),
                          checkmarkColor: const Color(0xFF059669),
                          label: const Text('Auto WhatsApp', style: TextStyle(fontSize: 11)),
                          selected: ShopConfig.autoSendWhatsAppOnBill,
                          onSelected: (v) =>
                              setState(() => ShopConfig.autoSendWhatsAppOnBill = v),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFEFF6FF),
                          checkmarkColor: const Color(0xFF2563EB),
                          label: const Text('Auto SMS', style: TextStyle(fontSize: 11)),
                          selected: ShopConfig.autoSendSmsOnBill,
                          onSelected: (v) =>
                              setState(() => ShopConfig.autoSendSmsOnBill = v),
                        ),
                        const SizedBox(width: 6),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          selectedColor: const Color(0xFFEEF2FF),
                          checkmarkColor: const Color(0xFF4338CA),
                          label: const Text('Auto Print', style: TextStyle(fontSize: 11)),
                          selected: ShopConfig.autoPrintOnBill,
                          onSelected: (v) => setState(() => ShopConfig.autoPrintOnBill = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Step 2: Scan IMEI / Barcode OR Switch to "Available Stock" Tab
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '2. Add Product to Bill',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF059669),
                        ),
                        onPressed: () => _tabController.animateTo(1),
                        icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        label: Text(
                          'Browse Available Stock (${_availableStockList.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: codeSearchCtrl,
                          onSubmitted: (val) => _searchBarcodeOrImei(val),
                          decoration: InputDecoration(
                            labelText: 'Scan or Type IMEI 1, IMEI 2, or Bulk SKU',
                            prefixIcon: const Icon(Icons.qr_code_2_rounded),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Color(0xFF059669),
                              ),
                              tooltip: 'Scan via Camera',
                              onPressed: () async {
                                final scanned = await ShopConfig.openCameraScanner(context);
                                if (scanned != null && scanned.isNotEmpty) {
                                  _searchBarcodeOrImei(scanned);
                                }
                              },
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4338CA),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        onPressed: _isSearching ? null : () => _searchBarcodeOrImei(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_cartItems.isEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 44, color: Colors.indigo.shade200),
                    const SizedBox(height: 10),
                    const Text(
                      'Customer Cart is Empty',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Scan an IMEI/Barcode above or tap "Available Stock" tab to pick items.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _tabController.animateTo(1),
                      icon: const Icon(Icons.touch_app_rounded, size: 18),
                      label: const Text('Select from Available Stock Tab'),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Step 3: Customer Cart & Checkout
          if (_cartItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFC7D2FE), width: 1.5),
              ),
              color: const Color(0xFFF8FAFC),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3. Customer Cart (${_cartItems.length} Products / $totalUnitsInCart Units)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1E1B4B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._cartItems.asMap().entries.map((entry) {
                      final int index = entry.key;
                      final Map<String, dynamic> cartRow = entry.value;
                      final Map<String, dynamic> stock = cartRow['stock'];
                      final Map<String, dynamic> prod = _cleanProductForCustomer(
                        Map<String, dynamic>.from((stock['products'] as Map?) ?? {}),
                      );
                      final bool isBulk = prod['is_bulk'] == true;
                      final int maxAvail = (stock['quantity'] as num?)?.toInt() ?? 1;
                      final int buyQty = cartRow['buy_qty'] ?? 1;
                      final num unitPrice = _unitPriceOfCartRow(cartRow);
                      final num lineGross = unitPrice * buyQty;
                      final String code1 = (stock['imei_or_serial'] ?? '').toString();
                      final String code2 = (stock['imei_2'] ?? '').toString();
                      final String ramRom = (prod['ram_rom'] ?? '').toString();
                      final String color = (prod['color'] ?? '').toString();
                      final String details = (prod['variant_details'] ?? '').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ShopConfig.formatProductSpecTitle(prod),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (ramRom.isNotEmpty ||
                                      color.isNotEmpty ||
                                      details.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        if (ramRom.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'RAM/ROM: $ramRom',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF4338CA),
                                              ),
                                            ),
                                          ),
                                        if (color.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Color: $color',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF334155),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 3),
                                  Text(
                                    '${isBulk ? "SKU" : "IMEI 1"}: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Text(
                                        'Price: ₹$unitPrice × $buyQty = ₹${lineGross.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF4338CA),
                                        ),
                                      ),
                                      if (shop.canGiveDiscount) ...[
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () => _editCartItemPriceDialog(cartRow),
                                          child: const Icon(
                                            Icons.edit_outlined,
                                            size: 14,
                                            color: Color(0xFF4338CA),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (isBulk)
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: buyQty > 1
                                        ? () => setState(() {
                                              cartRow['buy_qty'] = buyQty - 1;
                                              _syncPaymentFieldsWithNetAmount();
                                            })
                                        : null,
                                  ),
                                  Text(
                                    '$buyQty',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: buyQty < maxAvail
                                        ? () => setState(() {
                                              cartRow['buy_qty'] = buyQty + 1;
                                              _syncPaymentFieldsWithNetAmount();
                                            })
                                        : null,
                                  ),
                                ],
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => setState(() {
                                _cartItems.removeAt(index);
                                _syncPaymentFieldsWithNetAmount();
                              }),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 18),
                    const Text(
                      'Warranty Period (Given to Customer):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _warrantyPresets.map((preset) {
                        final selected = _selectedWarrantyOption == preset;
                        return ChoiceChip(
                          label: Text(preset, style: const TextStyle(fontSize: 11)),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedWarrantyOption = preset),
                        );
                      }).toList(),
                    ),
                    if (_selectedWarrantyOption == 'Custom Warranty') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customWarrantyCtrl,
                        decoration: InputDecoration(
                          labelText: 'Type Custom Warranty Period',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Payment Mode:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _paymentOptions.map((opt) {
                        final String label = opt['label'];
                        final bool isSelected = _selectedPaymentMode == label;
                        return ChoiceChip(
                          label: Text(label, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          onSelected: (_) => setState(() {
                            _selectedPaymentMode = label;
                            _syncPaymentFieldsWithNetAmount();
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (shop.canGiveDiscount)
                          Expanded(
                            child: TextField(
                              controller: discountCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) =>
                                  setState(() => _syncPaymentFieldsWithNetAmount()),
                              decoration: InputDecoration(
                                labelText: 'Special Discount (₹)',
                                prefixText: '₹ ',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        if (shop.canGiveDiscount &&
                            _selectedPaymentMode != 'Split (Cash + UPI)')
                          const SizedBox(width: 10),
                        if (_selectedPaymentMode != 'Split (Cash + UPI)')
                          Expanded(
                            child: TextField(
                              controller: paidNowCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Amount Paid Now (₹)',
                                prefixText: '₹ ',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_selectedPaymentMode == 'Split (Cash + UPI)') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: splitCashCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Cash Received (₹)',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: splitOnlineCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'UPI / Online (₹)',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_selectedPaymentMode == 'Cash') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: cashGivenCtrl,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Cash Note Given (Optional)',
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Return Change: ₹$changeToReturn',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Bill Note / Remark',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          if (discountVal > 0) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Subtotal: ₹${subtotalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                Text(
                                  'Discount Given: -₹${discountVal.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 14),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Net Bill: ₹$finalPrice',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Paid: ₹$paidNow',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669),
                                ),
                              ),
                              Text(
                                'Due: ₹$balanceDue',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: balanceDue > 0 ? Colors.red : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: balanceDue > 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF4338CA),
                        ),
                        onPressed: _isSelling ? null : _processSale,
                        icon: const Icon(Icons.send_and_archive_rounded),
                        label: Text(
                          _isSelling
                              ? 'Processing & Sending Bill...'
                              : 'Confirm Sale & Auto-Send Bill (₹$finalPrice)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: DEDICATED AVAILABLE ITEMS TAB IN POS
  // ---------------------------------------------------------------------------
  Widget _buildAvailableStockCatalogTab() {
    final q = _availSearchQuery.toLowerCase();
    final filtered = _availableStockList.where((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final prod = Map<String, dynamic>.from((item['products'] as Map?) ?? {});
      final bool isBulk = prod['is_bulk'] == true;

      if (_availCategoryFilter == 'Smartphones' && isBulk) return false;
      if (_availCategoryFilter == 'Accessories' && !isBulk) return false;

      if (q.isEmpty) return true;
      final text =
          '${prod['brand'] ?? ''} ${prod['title'] ?? ''} ${prod['ram_rom'] ?? ''} ${prod['color'] ?? ''} ${item['imei_or_serial'] ?? ''} ${item['imei_2'] ?? ''}'
              .toLowerCase();
      return text.contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadAvailableStock,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                TextField(
                  controller: availSearchCtrl,
                  onChanged: (v) => setState(() => _availSearchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search available stock by Model, RAM/ROM, Color, or IMEI...',
                    prefixIcon: const Icon(Icons.search, size: 19),
                    suffixIcon: _availSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              availSearchCtrl.clear();
                              setState(() => _availSearchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['All', 'Smartphones', 'Accessories'].map((cat) {
                    final sel = _availCategoryFilter == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(cat, style: const TextStyle(fontSize: 11)),
                        selected: sel,
                        onSelected: (_) => setState(() => _availCategoryFilter = cat),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingStock
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF4338CA)))
                : filtered.isEmpty
                    ? const Center(child: Text('No available stock items match your filter.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, idx) {
                          final item = Map<String, dynamic>.from(filtered[idx] as Map);
                          final prod = _cleanProductForCustomer(
                            Map<String, dynamic>.from((item['products'] as Map?) ?? {}),
                          );
                          final bool isBulk = prod['is_bulk'] == true;
                          final int qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final num sell = (prod['selling_price'] as num?) ?? 0;
                          final String code1 = (item['imei_or_serial'] ?? '').toString();
                          final String code2 = (item['imei_2'] ?? '').toString();
                          final String ramRom = (prod['ram_rom'] ?? '').toString();
                          final String color = (prod['color'] ?? '').toString();

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              leading: CircleAvatar(
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
                                ),
                              ),
                              title: Text(
                                ShopConfig.formatProductSpecTitle(prod),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (ramRom.isNotEmpty || color.isNotEmpty)
                                    Text(
                                      '${ramRom.isNotEmpty ? "RAM/ROM: $ramRom  " : ""}${color.isNotEmpty ? "Color: $color" : ""}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF4338CA),
                                      ),
                                    ),
                                  Text(
                                    '${isBulk ? "SKU: $code1 • Qty: $qty" : "IMEI 1: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}"}',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF4338CA),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () =>
                                    _addStockItemToCart(item, switchToPosTab: true),
                                icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
                                label: Text(
                                  '₹$sell • Add',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: SOLD BILLS TAB (View, Edit, WhatsApp, SMS & Print)
  // ---------------------------------------------------------------------------
  Widget _buildSoldBillsTab() {
    final filteredBills = _recentSalesList.where((sale) {
      if (_soldSearchQuery.isEmpty) return true;
      final cust = sale['customers'] ?? {};
      final name = (cust['name'] ?? '').toString().toLowerCase();
      final phone = (cust['phone'] ?? '').toString().toLowerCase();
      final id = (sale['id'] ?? '').toString().toLowerCase();
      final q = _soldSearchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q) || id.contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadRecentSales,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: TextField(
              controller: soldBillSearchCtrl,
              onChanged: (v) => setState(() => _soldSearchQuery = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search sold bills by Customer, Phone, or Invoice ID...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _soldSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          soldBillSearchCtrl.clear();
                          setState(() => _soldSearchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          Expanded(
            child: _loadingSales
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF4338CA)))
                : filteredBills.isEmpty
                    ? const Center(child: Text('No sold bills found.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredBills.length,
                        itemBuilder: (ctx, idx) {
                          final sale = filteredBills[idx] as Map<String, dynamic>;
                          final customer = sale['customers'] ?? {};
                          final saleId = (sale['id'] ?? '').toString();
                          final shortId =
                              saleId.length >= 6 ? saleId.substring(0, 6).toUpperCase() : saleId;
                          final date =
                              DateTime.tryParse((sale['created_at'] ?? '').toString())?.toLocal() ??
                                  DateTime.now();
                          final totalAmount = (sale['total_amount'] as num?)?.toDouble() ?? 0;
                          final paidAmount = (sale['paid_amount'] as num?)?.toDouble() ?? 0;
                          final dueAmount = (sale['due_amount'] as num?)?.toDouble() ?? 0;
                          final items = (sale['sale_items'] as List<dynamic>?) ?? [];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: dueAmount > 0
                                    ? Colors.red.shade200
                                    : Colors.grey.shade200,
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
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '#INV-$shortId',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Color(0xFF4338CA),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            DateFormat('dd MMM, hh:mm a').format(date),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '₹${totalAmount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                          color: Color(0xFF1E1B4B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Customer: ${customer['name'] ?? 'Walk-in'} • Mob: ${customer['phone'] ?? 'N/A'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mode: ${sale['payment_mode'] ?? 'Cash'} | Paid: ₹${paidAmount.toStringAsFixed(0)}${dueAmount > 0 ? " • Due: ₹${dueAmount.toStringAsFixed(0)}" : ""}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: dueAmount > 0
                                          ? const Color(0xFFDC2626)
                                          : const Color(0xFF059669),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (items.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Items: ${items.map((i) {
                                        final prod = _cleanProductForCustomer(
                                          Map<String, dynamic>.from((i['products'] as Map?) ?? {}),
                                        );
                                        return '${ShopConfig.formatProductSpecTitle(prod)} (x${i['quantity'] ?? 1})';
                                      }).join(', ')}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 14),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.end,
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        onPressed: () =>
                                            _openInvoiceDialogForExistingSale(sale),
                                        icon: const Icon(Icons.receipt_long, size: 14),
                                        label: const Text(
                                          'Bill / Print / Share',
                                          style: TextStyle(fontSize: 11),
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        style: FilledButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: const Color(0xFFEEF2FF),
                                          foregroundColor: const Color(0xFF4338CA),
                                        ),
                                        onPressed: () => _editSoldBillDialog(sale),
                                        icon: const Icon(Icons.edit, size: 14),
                                        label: const Text(
                                          'Edit Bill',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShopProfile>(
      valueListenable: ShopConfig.notifier,
      builder: (context, shop, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF4338CA),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF4338CA),
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                    text: 'POS Counter (${_cartItems.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.inventory_2_outlined, size: 17),
                    text: 'Available Items (${_availableStockList.length})',
                  ),
                  const Tab(
                    icon: Icon(Icons.receipt_rounded, size: 17),
                    text: 'Sold Bills (Edit)',
                  ),
                ],
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildPosCounterTab(context, shop),
              _buildAvailableStockCatalogTab(),
              _buildSoldBillsTab(),
            ],
          ),
        );
      },
    );
  }
}