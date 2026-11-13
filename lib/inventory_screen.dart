import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'shop_config.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  int _activeTabIndex = 0;

  List<dynamic> _availableItems = [];
  List<dynamic> _soldItems = [];
  List<dynamic> _srIncomingItems = [];
  List<dynamic> _srItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _categoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    // 4 Tabs: Available Stock, Sold History, SR Incoming (Also in Available Stock), SR / Member Transfer
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _fetchInventory();
  }

  void _onTabChanged() {
    if (mounted && _activeTabIndex != _tabController.index) {
      setState(() {
        _activeTabIndex = _tabController.index;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HELPER: Check if a stock item was received via SR Member Incoming
  // ---------------------------------------------------------------------------
  bool _isSrIncomingRecord(Map<String, dynamic> stock) {
    final srNotes = (stock['sr_notes'] ?? '').toString();
    final statusStr = (stock['status'] ?? '').toString();
    final prod = stock['products'] ?? {};
    final details = (prod['variant_details'] ?? '').toString();
    return srNotes.startsWith('SR_IN|') ||
        details.contains('[SR_IN:') ||
        statusStr.startsWith('SR_IN|');
  }

  Map<String, dynamic> _extractSrIncomingMetadata(Map<String, dynamic> stock) {
    final srNotes = (stock['sr_notes'] ?? '').toString();
    final prod = stock['products'] ?? {};
    String memberName = (stock['sr_member_name'] ?? '').toString().trim();
    String memberPhone = (stock['sr_member_phone'] ?? '').toString().trim();
    num incomingRate = (stock['sr_transfer_price'] as num?) ?? 0;
    String notes = '';

    if (srNotes.startsWith('SR_IN|')) {
      final parts = srNotes.split('|');
      if (parts.length > 1 && memberName.isEmpty) memberName = parts[1];
      if (parts.length > 2 && memberPhone.isEmpty) memberPhone = parts[2];
      if (parts.length > 3 && incomingRate == 0) {
        incomingRate = num.tryParse(parts[3]) ?? 0;
      }
      if (parts.length > 4) notes = parts[4];
    } else {
      notes = srNotes;
    }

    final details = (prod['variant_details'] ?? '').toString();
    if (details.contains('[SR_IN:')) {
      final start = details.indexOf('[SR_IN:') + 7;
      final end = details.indexOf(']', start);
      if (end != -1) {
        final inside = details.substring(start, end);
        final p = inside.split('|');
        if (p.isNotEmpty && memberName.isEmpty) memberName = p[0].trim();
        if (p.length > 1 && memberPhone.isEmpty) memberPhone = p[1].trim();
        if (p.length > 2 && incomingRate == 0) {
          incomingRate = num.tryParse(p[2].trim()) ?? 0;
        }
        if (p.length > 3 && notes.isEmpty) notes = p[3].trim();
      }
    }

    if (memberName.isEmpty) memberName = 'SR Member';
    if (incomingRate <= 0) {
      incomingRate =
          (prod['cost_price'] as num?) ?? (prod['selling_price'] as num?) ?? 0;
    }

    return {
      'member_name': memberName,
      'member_phone': memberPhone,
      'incoming_rate': incomingRate,
      'notes': notes,
    };
  }

  // ---------------------------------------------------------------------------
  // HELPER: Parse Scanned Box Barcode / QR into Brand, Model, RAM/ROM & Color
  // ---------------------------------------------------------------------------
  Map<String, String> _parseScannedModelSpecs(String rawScan) {
    final raw = rawScan.trim();
    String brand = '';
    String model = '';
    String ramRom = '';
    String color = '';
    String imei = '';

    const knownBrands = [
      'Apple',
      'iPhone',
      'Samsung',
      'OnePlus',
      'Xiaomi',
      'Redmi',
      'Poco',
      'Vivo',
      'Oppo',
      'Realme',
      'Motorola',
      'Nothing',
      'iQOO',
      'Google',
      'Pixel',
      'Nokia',
      'Infinix',
      'Tecno',
      'Lava',
      'Boat',
      'Anker',
    ];

    const knownColors = [
      'Black',
      'White',
      'Blue',
      'Navy',
      'Green',
      'Emerald',
      'Gold',
      'Silver',
      'Titanium',
      'Gray',
      'Grey',
      'Purple',
      'Violet',
      'Red',
      'Pink',
      'Yellow',
      'Orange',
      'Cyan',
      'Teal',
      'Starlight',
      'Midnight',
      'Graphite',
      'Ultramarine',
    ];

    final imeiMatch = RegExp(r'\b\d{15}\b').firstMatch(raw);
    if (imeiMatch != null) {
      imei = imeiMatch.group(0) ?? '';
    }

    final ramRomRegex = RegExp(
      r'\b(\d{1,2}\s*(?:GB)?\s*[\/\+]\s*\d{2,4}\s*(?:GB|TB))\b',
      caseSensitive: false,
    );
    final storageOnlyRegex = RegExp(
      r'\b(\d{1,2}\s*GB\s+\d{2,4}\s*GB|\d{2,4}\s*GB|1\s*TB)\b',
      caseSensitive: false,
    );

    final rrMatch = ramRomRegex.firstMatch(raw);
    if (rrMatch != null) {
      ramRom = rrMatch.group(1)!.toUpperCase().replaceAll(' ', '');
      if (!ramRom.contains('GB') && ramRom.contains('/')) {
        final parts = ramRom.split('/');
        ramRom = '${parts[0]}GB/${parts[1]}';
      }
    } else {
      final stMatch = storageOnlyRegex.firstMatch(raw);
      if (stMatch != null) {
        ramRom =
            stMatch.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '/');
      }
    }

    for (final b in knownBrands) {
      if (raw.toLowerCase().contains(b.toLowerCase())) {
        brand = b == 'iPhone'
            ? 'Apple'
            : (b == 'Redmi' ? 'Xiaomi' : (b == 'Pixel' ? 'Google' : b));
        break;
      }
    }

    for (final c in knownColors) {
      if (RegExp('\\b$c\\b', caseSensitive: false).hasMatch(raw)) {
        color = c;
        break;
      }
    }

    String cleaned = raw;
    if (imei.isNotEmpty) cleaned = cleaned.replaceAll(imei, '');
    if (rrMatch != null) cleaned = cleaned.replaceAll(rrMatch.group(0)!, '');
    if (color.isNotEmpty) {
      cleaned =
          cleaned.replaceAll(RegExp('\\b$color\\b', caseSensitive: false), '');
    }
    cleaned = cleaned
        .replaceAll(RegExp(r'[\|\,\;\(\)\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    model = cleaned.isEmpty ? raw : cleaned;

    return {
      'brand': brand,
      'model': model,
      'ram_rom': ramRom,
      'color': color,
      'imei': imei,
    };
  }

  // ---------------------------------------------------------------------------
  // FETCH INVENTORY (Available, Sold, SR Incoming, and SR Outgoing)
  // ---------------------------------------------------------------------------
  Future<void> _fetchInventory() async {
    setState(() => _isLoading = true);
    try {
      List<dynamic> res;
      try {
        res = await supabase
            .from('stock_items')
            .select(
              '*, products(*), sale_items(id, sold_price, cost_price, profit, quantity, warranty_period, created_at, sales(id, subtotal_amount, discount_amount, total_amount, payment_mode, sold_by_user_id, sold_by_email, customers(name, phone)))',
            )
            .order('created_at', ascending: false);
      } catch (_) {
        res = await supabase
            .from('stock_items')
            .select('*, products(*)')
            .order('created_at', ascending: false);
      }

      final List<dynamic> available = [];
      final List<dynamic> sold = [];
      final List<dynamic> srIncoming = [];
      final List<dynamic> srTransferred = [];

      for (var item in res) {
        final itemMap = Map<String, dynamic>.from(item as Map);
        final statusStr = (itemMap['status'] ?? 'Available').toString();
        final qty = ((itemMap['quantity'] as num?) ?? 1).toInt();

        // Check if this item was received via SR Incoming
        if (_isSrIncomingRecord(itemMap) && !statusStr.startsWith('SR|')) {
          srIncoming.add(itemMap);
        }

        if (statusStr.startsWith('SR')) {
          srTransferred.add(itemMap);
        } else if (statusStr == 'Available' && qty > 0) {
          // SR Incoming items have status == 'Available', so they automatically appear in Available Stock too!
          available.add(itemMap);
        } else {
          sold.add(itemMap);
        }
      }

      if (mounted) {
        setState(() {
          _availableItems = available;
          _soldItems = sold;
          _srIncomingItems = srIncoming;
          _srItems = srTransferred;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error loading inventory: $e'),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // EXTRACT SR METADATA (Works with dedicated SQL columns OR status encoding)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> _extractSrMetadata(Map<String, dynamic> stock) {
    final statusStr = (stock['status'] ?? '').toString();
    String memberName = (stock['sr_member_name'] ?? '').toString().trim();
    String memberPhone = (stock['sr_member_phone'] ?? '').toString().trim();
    num transferPrice = (stock['sr_transfer_price'] as num?) ?? 0;
    String notes = (stock['sr_notes'] ?? '').toString().trim();

    if (statusStr.startsWith('SR|')) {
      final parts = statusStr.split('|');
      if (parts.length > 1 && memberName.isEmpty) memberName = parts[1];
      if (parts.length > 2 && memberPhone.isEmpty) memberPhone = parts[2];
      if (parts.length > 3 && transferPrice == 0) {
        transferPrice = num.tryParse(parts[3]) ?? 0;
      }
      if (parts.length > 4 && notes.isEmpty) notes = parts[4];
    }

    if (memberName.isEmpty) memberName = 'Distributor / Member';
    final prod = stock['products'] ?? {};
    if (transferPrice <= 0) {
      transferPrice =
          (prod['cost_price'] as num?) ?? (prod['selling_price'] as num?) ?? 0;
    }

    return {
      'member_name': memberName,
      'member_phone': memberPhone,
      'transfer_price': transferPrice,
      'notes': notes,
    };
  }

  // ---------------------------------------------------------------------------
  // NEW: SR MEMBER INCOMING DIALOG (Receive Stock from Member -> Goes to Available Stock)
  // ---------------------------------------------------------------------------
  Future<void> _showSrIncomingDialog() async {
    final shop = ShopConfig.current;
    if (!shop.canAddStock && !shop.isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to add SR Incoming stock.'),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final memberNameCtrl = TextEditingController();
    final memberPhoneCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final ramRomCtrl = TextEditingController();
    final colorCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final srRateCtrl = TextEditingController();
    final sellingPriceCtrl = TextEditingController();
    final imei1OrSkuCtrl = TextEditingController();
    final imei2Ctrl = TextEditingController();
    final quantityCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();

    bool isBulk = false;
    bool isSaving = false;
    String? errorMessage;

    final popularBrands = [
      'Apple',
      'Samsung',
      'OnePlus',
      'Xiaomi',
      'Vivo',
      'Oppo',
      'Realme',
      'Motorola',
      'Nothing',
      'iQOO',
      'Boat',
      'Anker',
    ];

    final ramRomPresets = [
      '4GB/64GB',
      '4GB/128GB',
      '6GB/128GB',
      '8GB/128GB',
      '8GB/256GB',
      '12GB/256GB',
    ];

    final colorPresets = [
      'Black',
      'White',
      'Blue',
      'Green',
      'Gold',
      'Titanium',
      'Silver',
      'Purple',
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.call_received_rounded,
                              color: Color(0xFF059669),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SR Member Incoming Stock Entry',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                                Text(
                                  'Item will be added directly to Available Stock & tracked in SR Incoming',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '1. Sender Member / Dealer Details',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: memberNameCtrl,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: InputDecoration(
                                      labelText: 'From Member / Shop Name *',
                                      hintText: 'e.g.Laxmi Mobile / Dealer',
                                      prefixIcon: const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Enter member name'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: memberPhoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Member Mobile No. *',
                                      prefixIcon: const Icon(
                                        Icons.phone_android,
                                        size: 18,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.trim().isEmpty)
                                            ? 'Enter mobile'
                                            : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Phone (IMEI 1 & 2)'),
                              icon: Icon(Icons.smartphone),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Accessory (Bulk Slab)'),
                              icon: Icon(Icons.inventory_2_outlined),
                            ),
                          ],
                          selected: {isBulk},
                          onSelectionChanged: (Set<bool> val) {
                            setDialogState(() {
                              isBulk = val.first;
                              if (isBulk && imei1OrSkuCtrl.text.isEmpty) {
                                imei1OrSkuCtrl.text =
                                    'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
                                imei2Ctrl.clear();
                              } else if (!isBulk &&
                                  imei1OrSkuCtrl.text.startsWith('SKU-')) {
                                imei1OrSkuCtrl.clear();
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: popularBrands.map((b) {
                          final isSelected =
                              brandCtrl.text.toLowerCase() == b.toLowerCase();
                          return ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              b,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF059669),
                            onSelected: (selected) {
                              setDialogState(() {
                                brandCtrl.text = selected ? b : '';
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: brandCtrl,
                              decoration: InputDecoration(
                                labelText: 'Brand *',
                                hintText: 'e.g. Samsung, Apple',
                                prefixIcon: const Icon(
                                  Icons.business_outlined,
                                  size: 18,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Enter brand'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: titleCtrl,
                              decoration: InputDecoration(
                                labelText: isBulk
                                    ? 'Accessory Model *'
                                    : 'Model Name *',
                                hintText: 'Scan Box or Type Model',
                                prefixIcon: const Icon(
                                  Icons.devices_other_outlined,
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                    color: Color(0xFF059669),
                                  ),
                                  tooltip: 'Scan Box QR/Barcode',
                                  onPressed: () async {
                                    final scanned =
                                        await ShopConfig.openCameraScanner(
                                      context,
                                      title:
                                          'Scan Box Label for Model, RAM/ROM & IMEI',
                                    );
                                    if (scanned != null && scanned.isNotEmpty) {
                                      final parsed =
                                          _parseScannedModelSpecs(scanned);
                                      setDialogState(() {
                                        if (parsed['brand']!.isNotEmpty &&
                                            brandCtrl.text.trim().isEmpty) {
                                          brandCtrl.text = parsed['brand']!;
                                        }
                                        if (parsed['model']!.isNotEmpty) {
                                          titleCtrl.text = parsed['model']!;
                                        }
                                        if (parsed['ram_rom']!.isNotEmpty) {
                                          ramRomCtrl.text = parsed['ram_rom']!;
                                        }
                                        if (parsed['color']!.isNotEmpty) {
                                          colorCtrl.text = parsed['color']!;
                                        }
                                        if (parsed['imei']!.isNotEmpty &&
                                            imei1OrSkuCtrl.text
                                                .trim()
                                                .isEmpty) {
                                          imei1OrSkuCtrl.text = parsed['imei']!;
                                        }
                                      });
                                    }
                                  },
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Enter model'
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      if (!isBulk) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: ramRomCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'RAM / ROM',
                                  hintText: 'e.g. 8GB/128GB',
                                  prefixIcon: const Icon(
                                    Icons.memory_rounded,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: colorCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Colour',
                                  hintText: 'e.g. Black',
                                  prefixIcon: const Icon(
                                    Icons.palette_outlined,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ramRomPresets.map((rr) {
                              final selected =
                                  ramRomCtrl.text.toUpperCase() == rr;
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    rr,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  selected: selected,
                                  onSelected: (_) => setDialogState(
                                    () =>
                                        ramRomCtrl.text = selected ? '' : rr,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: colorPresets.map((c) {
                              final selected = colorCtrl.text.toLowerCase() ==
                                  c.toLowerCase();
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    c,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  selected: selected,
                                  onSelected: (_) => setDialogState(
                                    () => colorCtrl.text = selected ? '' : c,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: srRateCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'SR Incoming Rate / Cost (₹) *',
                                prefixText: '₹ ',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Enter SR rate';
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: sellingPriceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Customer Selling MRP (₹) *',
                                prefixText: '₹ ',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Enter MRP';
                                }
                                if (double.tryParse(v.trim()) == null) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: imei1OrSkuCtrl,
                        keyboardType:
                            isBulk ? TextInputType.text : TextInputType.number,
                        inputFormatters: isBulk
                            ? const []
                            : [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(15),
                              ],
                        decoration: InputDecoration(
                          labelText: isBulk
                              ? 'SKU / Barcode *'
                              : 'IMEI 1 (Type or Scan) *',
                          prefixIcon:
                              const Icon(Icons.qr_code_2_rounded, size: 18),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Color(0xFF059669),
                            ),
                            onPressed: () async {
                              final scanned =
                                  await ShopConfig.openCameraScanner(
                                context,
                                title: isBulk
                                    ? 'Scan Accessory SKU'
                                    : 'Scan IMEI 1 Barcode',
                              );
                              if (scanned != null && scanned.isNotEmpty) {
                                setDialogState(
                                    () => imei1OrSkuCtrl.text = scanned);
                              }
                            },
                          ),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Enter IMEI / SKU';
                          }
                          if (!isBulk &&
                              !RegExp(r'^\d{15}$').hasMatch(v.trim())) {
                            return 'IMEI must contain exactly 15 digits';
                          }
                          return null;
                        },
                      ),
                      if (!isBulk) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: imei2Ctrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: InputDecoration(
                            labelText: 'IMEI 2 (Optional)',
                            prefixIcon:
                                const Icon(Icons.sim_card_outlined, size: 18),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Color(0xFF059669),
                              ),
                              onPressed: () async {
                                final scanned =
                                    await ShopConfig.openCameraScanner(
                                  context,
                                  title: 'Scan IMEI 2 Barcode',
                                );
                                if (scanned != null && scanned.isNotEmpty) {
                                  setDialogState(
                                      () => imei2Ctrl.text = scanned);
                                }
                              },
                            ),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                      if (isBulk) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: quantityCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                            labelText: 'Received Quantity *',
                            prefixIcon:
                                const Icon(Icons.layers_rounded, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                          labelText: 'SR Incoming Remark / Note (Optional)',
                          hintText: 'e.g. Received from dealer for customer order',
                          prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    if (!RegExp(r'^\d{10}$').hasMatch(
                                      memberPhoneCtrl.text.trim(),
                                    )) {
                                      setDialogState(() {
                                        errorMessage =
                                            'Member Mobile Number must contain exactly 10 digits.';
                                      });
                                      return;
                                    }
                                    setDialogState(() {
                                      isSaving = true;
                                      errorMessage = null;
                                    });

                                    final memberName = memberNameCtrl.text
                                        .trim()
                                        .replaceAll('|', ' ');
                                    final memberPhone = memberPhoneCtrl.text
                                        .trim()
                                        .replaceAll('|', ' ');
                                    final brand = brandCtrl.text.trim();
                                    final rawModel = titleCtrl.text.trim();
                                    final ramRom = ramRomCtrl.text.trim();
                                    final color = colorCtrl.text.trim();
                                    final extraDetails =
                                        detailsCtrl.text.trim();
                                    final srRate = double.tryParse(
                                          srRateCtrl.text.trim(),
                                        ) ??
                                        0;
                                    final sellPrice = double.tryParse(
                                          sellingPriceCtrl.text.trim(),
                                        ) ??
                                        0;
                                    final code1 = imei1OrSkuCtrl.text.trim();
                                    final code2 =
                                        isBulk ? '' : imei2Ctrl.text.trim();
                                    final qty = int.tryParse(
                                          quantityCtrl.text.trim(),
                                        ) ??
                                        1;
                                    final cleanNote = notesCtrl.text
                                        .trim()
                                        .replaceAll('|', ' ');

                                    final specParts = <String>[
                                      if (ramRom.isNotEmpty &&
                                          !rawModel
                                              .toLowerCase()
                                              .contains(ramRom.toLowerCase()))
                                        ramRom,
                                      if (color.isNotEmpty &&
                                          !rawModel
                                              .toLowerCase()
                                              .contains(color.toLowerCase()))
                                        color,
                                      if (extraDetails.isNotEmpty &&
                                          !rawModel.toLowerCase().contains(
                                              extraDetails.toLowerCase()))
                                        extraDetails,
                                    ];
                                    final fullTitle = specParts.isEmpty
                                        ? rawModel
                                        : '$rawModel (${specParts.join(' • ')})';

                                    final encodedSrInNotes =
                                        'SR_IN|$memberName|$memberPhone|$srRate|$cleanNote';
                                    final fallbackVariantTag =
                                        '${extraDetails.isNotEmpty ? "$extraDetails " : ""}[SR_IN:$memberName|$memberPhone|$srRate|$cleanNote]'
                                            .trim();

                                    final effectiveTenantId =
                                        shop.effectiveTenantId.isNotEmpty
                                            ? shop.effectiveTenantId
                                            : supabase.auth.currentUser?.id;

                                    try {
                                      final baseInsert = <String, dynamic>{
                                        'user_id': effectiveTenantId,
                                        'title': fullTitle,
                                        'brand': brand,
                                        'category': isBulk
                                            ? 'Accessories'
                                            : 'Smartphone',
                                        'cost_price': srRate,
                                        'selling_price': sellPrice,
                                        'has_imei': !isBulk,
                                        'is_bulk': isBulk,
                                      };

                                      Map<String, dynamic> prod;
                                      try {
                                        prod = await supabase
                                            .from('products')
                                            .insert({
                                              ...baseInsert,
                                              'ram_rom': ramRom,
                                              'color': color,
                                              'variant_details':
                                                  fallbackVariantTag,
                                            })
                                            .select()
                                            .single();
                                      } catch (_) {
                                        prod = await supabase
                                            .from('products')
                                            .insert(baseInsert)
                                            .select()
                                            .single();
                                      }

                                      try {
                                        await supabase
                                            .from('stock_items')
                                            .insert({
                                          'user_id': effectiveTenantId,
                                          'product_id': prod['id'],
                                          'imei_or_serial': code1,
                                          'imei_2': code2,
                                          'status': 'Available',
                                          'quantity': isBulk ? qty : 1,
                                          'sr_member_name': memberName,
                                          'sr_member_phone': memberPhone,
                                          'sr_transfer_price': srRate,
                                          'sr_notes': encodedSrInNotes,
                                          'sr_date': DateTime.now()
                                              .toUtc()
                                              .toIso8601String(),
                                        });
                                      } catch (_) {
                                        await supabase
                                            .from('stock_items')
                                            .insert({
                                          'user_id': effectiveTenantId,
                                          'product_id': prod['id'],
                                          'imei_or_serial': code1,
                                          'imei_2': code2,
                                          'status': 'Available',
                                          'quantity': isBulk ? qty : 1,
                                        });
                                      }

                                      if (mounted) {
                                        Navigator.pop(ctx);
                                        await _fetchInventory();
                                        ScaffoldMessenger.of(this.context)
                                            .showSnackBar(
                                          SnackBar(
                                            backgroundColor:
                                                const Color(0xFF059669),
                                            content: Text(
                                              'SR Incoming item "$brand $fullTitle" added to Available Stock!',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      setDialogState(() {
                                        isSaving = false;
                                        errorMessage =
                                            'Could not save SR Incoming: $e';
                                      });
                                    }
                                  },
                            icon: const Icon(
                              Icons.add_task_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isSaving
                                  ? 'Adding...'
                                  : 'Save to Available Stock',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SR TRANSFER DIALOG (Give Present Stock to Another Member)
  // ---------------------------------------------------------------------------
  Future<void> _showSrTransferDialog(
      {Map<String, dynamic>? preselectedStock}) async {
    final shop = ShopConfig.current;
    if (!shop.canSellInPos && !shop.canAddStock && !shop.isOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to transfer stock in SR.'),
        ),
      );
      return;
    }

    if (_availableItems.isEmpty && preselectedStock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No available stock to give in SR! Add stock first.'),
        ),
      );
      return;
    }

    Map<String, dynamic> selectedStock = preselectedStock ??
        Map<String, dynamic>.from(_availableItems.first as Map);
    final initProd = selectedStock['products'] ?? {};

    final memberNameCtrl = TextEditingController();
    final memberPhoneCtrl = TextEditingController();
    final rateCtrl = TextEditingController(
      text: ((initProd['cost_price'] as num?) != null &&
                  (initProd['cost_price'] as num) > 0
              ? initProd['cost_price']
              : (initProd['selling_price'] ?? 0))
          .toString(),
    );
    final qtyCtrl = TextEditingController(text: '1');
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final prod = selectedStock['products'] ?? {};
          final bool isBulk = prod['is_bulk'] == true;
          final int availQty =
              (selectedStock['quantity'] as num?)?.toInt() ?? 1;
          final String code1 =
              (selectedStock['imei_or_serial'] ?? '').toString();
          final String code2 = (selectedStock['imei_2'] ?? '').toString();

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFF4338CA),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SR Stock Transfer (Give to Member)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Give present stock to another distributor / dealer / member',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preselectedStock == null) ...[
                    const Text(
                      'Select Present Stock Item:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedStock['id'].toString(),
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: _availableItems.map((item) {
                        final p = item['products'] ?? {};
                        final c = item['imei_or_serial'] ?? '';
                        return DropdownMenuItem<String>(
                          value: item['id'].toString(),
                          child: Text(
                            '${p['brand'] ?? ''} ${p['title'] ?? ''} ($c)',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        final found = _availableItems.firstWhere(
                          (e) => e['id'].toString() == val,
                        );
                        setDialogState(() {
                          selectedStock =
                              Map<String, dynamic>.from(found as Map);
                          final np = selectedStock['products'] ?? {};
                          rateCtrl.text = ((np['cost_price'] as num?) != null &&
                                      (np['cost_price'] as num) > 0
                                  ? np['cost_price']
                                  : (np['selling_price'] ?? 0))
                              .toString();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${prod['brand'] ?? ''} ${prod['title'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${isBulk ? "SKU" : "IMEI 1"}: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: memberNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Member / Dealer / Distributor Name *',
                      hintText: 'e.g. Royal Telecom / Distributor SR',
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: memberPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Member Mobile Number *',
                      prefixIcon: const Icon(Icons.phone_android, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rateCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'SR Transfer Price (₹)',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      if (isBulk) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                              labelText: 'Qty (Max $availQty)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'SR Remark / Note (Optional)',
                      hintText: 'e.g. Given on credit / exchange stock',
                      prefixIcon: const Icon(Icons.notes_rounded, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4338CA),
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final memberName = memberNameCtrl.text.trim();
                        final memberPhone = memberPhoneCtrl.text.trim();
                        if (memberName.isEmpty ||
                            !RegExp(r'^\d{10}$').hasMatch(memberPhone)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Colors.red,
                              content: Text(
                                'Enter Member Name and a valid 10-digit Mobile Number.',
                              ),
                            ),
                          );
                          return;
                        }

                        final int giveQty =
                            (int.tryParse(qtyCtrl.text.trim()) ?? 1)
                                .clamp(1, availQty);
                        final num rate =
                            num.tryParse(rateCtrl.text.trim()) ?? 0;
                        final String cleanNote =
                            notesCtrl.text.trim().replaceAll('|', ' ');
                        final String encodedStatus =
                            'SR|${memberName.replaceAll('|', ' ')}|$memberPhone|$rate|$cleanNote';

                        setDialogState(() => isSaving = true);

                        try {
                          final effectiveTenantId =
                              shop.effectiveTenantId.isNotEmpty
                                  ? shop.effectiveTenantId
                                  : supabase.auth.currentUser?.id;

                          if (isBulk && giveQty < availQty) {
                            await supabase.from('stock_items').update({
                              'quantity': availQty - giveQty,
                              'status': 'Available',
                            }).eq('id', selectedStock['id']);

                            await supabase.from('stock_items').insert({
                              'user_id': effectiveTenantId,
                              'product_id': selectedStock['product_id'],
                              'imei_or_serial':
                                  '$code1-SR-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                              'imei_2': code2,
                              'status': encodedStatus,
                              'quantity': giveQty,
                            });
                          } else {
                            try {
                              await supabase.from('stock_items').update({
                                'status': encodedStatus,
                                'sr_member_name': memberName,
                                'sr_member_phone': memberPhone,
                                'sr_transfer_price': rate,
                                'sr_notes': cleanNote,
                                'sr_date':
                                    DateTime.now().toUtc().toIso8601String(),
                              }).eq('id', selectedStock['id']);
                            } catch (_) {
                              await supabase.from('stock_items').update({
                                'status': encodedStatus,
                              }).eq('id', selectedStock['id']);
                            }
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            await _fetchInventory();
                            _tabController.animateTo(3);
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF059669),
                                content: Text(
                                  'Stock transferred in SR to $memberName!',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('SR Transfer failed: $e'),
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label:
                    Text(isSaving ? 'Transferring...' : 'Confirm SR Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _returnSrItemToAvailableStock(Map<String, dynamic> stock) async {
    final prod = stock['products'] ?? {};
    final meta = _extractSrMetadata(stock);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Return SR Stock to Available Inventory?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Bring "${prod['brand'] ?? ''} ${prod['title'] ?? ''}" given to ${meta['member_name']} back into your Available Stock?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore to Available'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final qty = (stock['quantity'] as num?)?.toInt() ?? 1;
      await supabase.from('stock_items').update({
        'status': 'Available',
        'quantity': qty > 0 ? qty : 1,
      }).eq('id', stock['id']);

      await _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Item restored to Available Stock!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to restore SR item: $e'),
          ),
        );
      }
    }
  }

  Future<void> _adjustBulkQuantity(Map<String, dynamic> stock, int delta) async {
    if (!ShopConfig.current.canAddStock &&
        !ShopConfig.current.canEditDeleteStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('You do not have permission to adjust stock quantities.'),
        ),
      );
      return;
    }

    final int currentQty = (stock['quantity'] as num?)?.toInt() ?? 1;
    final int newQty = currentQty + delta;

    if (newQty <= 0) {
      _revokeOrDeleteStockItem(stock);
      return;
    }

    try {
      try {
        await supabase.rpc('adjust_bulk_stock_atomic', params: {
          'p_stock_id': stock['id'],
          'p_delta': delta,
        });
      } catch (_) {
        await supabase
            .from('stock_items')
            .update({'quantity': newQty, 'status': 'Available'})
            .eq('id', stock['id']);
      }
      await _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk stock quantity updated to $newQty units'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to update quantity: $e'),
          ),
        );
      }
    }
  }

  Future<void> _revokeOrDeleteStockItem(Map<String, dynamic> stock) async {
    if (!ShopConfig.current.canEditDeleteStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'Only Shop Owner or permitted staff can revoke/delete stock items.',
          ),
        ),
      );
      return;
    }

    final prod = stock['products'] ?? {};
    final String title =
        '${prod['brand'] ?? ''} ${prod['title'] ?? 'Item'}'.trim();
    final String code = (stock['imei_or_serial'] ?? '').toString();
    final int qty = (stock['quantity'] as num?)?.toInt() ?? 1;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Revoke / Remove Stock Entry?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remove "$title" (Qty: $qty) from Available Stock?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'IMEI / SKU: $code',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 10),
            const Text(
              'Use this if you enrolled this stock item or quantity by mistake. This action will permanently remove the entry.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: const Text('Revoke Stock'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('stock_items').delete().eq('id', stock['id']);
      await _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Revoked "$title" from available stock.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              'Could not revoke item (it may be linked to a past sale): $e',
            ),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ADD / EDIT STOCK DIALOG
  // ---------------------------------------------------------------------------
  void _showAddOrEditStockDialog({Map<String, dynamic>? existingStock}) {
    final shop = ShopConfig.current;
    final bool isEditing = existingStock != null;

    if (isEditing && !shop.canEditDeleteStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only Shop Owner or authorized staff can edit stock.'),
        ),
      );
      return;
    }
    if (!isEditing && !shop.canAddStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add Stock permission is disabled for your account.'),
        ),
      );
      return;
    }

    final existingProd = isEditing ? (existingStock['products'] ?? {}) : {};

    String initialTitle =
        isEditing ? (existingProd['title'] ?? '').toString() : '';
    String initialRamRom =
        isEditing ? (existingProd['ram_rom'] ?? '').toString() : '';
    String initialColor =
        isEditing ? (existingProd['color'] ?? '').toString() : '';
    String initialDetails =
        isEditing ? (existingProd['variant_details'] ?? '').toString() : '';

    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: initialTitle);
    final brandCtrl = TextEditingController(
      text: isEditing ? (existingProd['brand'] ?? '').toString() : '',
    );
    final ramRomCtrl = TextEditingController(text: initialRamRom);
    final colorCtrl = TextEditingController(text: initialColor);
    final detailsCtrl = TextEditingController(text: initialDetails);
    final costCtrl = TextEditingController(
      text: isEditing ? (existingProd['cost_price'] ?? '0').toString() : '',
    );
    final priceCtrl = TextEditingController(
      text: isEditing ? (existingProd['selling_price'] ?? '').toString() : '',
    );
    final imei1OrSkuCtrl = TextEditingController(
      text: isEditing ? (existingStock['imei_or_serial'] ?? '').toString() : '',
    );
    final imei2Ctrl = TextEditingController(
      text: isEditing ? (existingStock['imei_2'] ?? '').toString() : '',
    );
    final quantityCtrl = TextEditingController(
      text: isEditing ? ((existingStock['quantity'] ?? 1).toString()) : '1',
    );

    bool isBulk = isEditing ? (existingProd['is_bulk'] == true) : false;
    String selectedCategory = isBulk ? 'Accessories' : 'Smartphone';
    bool isSaving = false;
    String? errorMessage;

    final popularBrands = [
      'Apple',
      'Samsung',
      'OnePlus',
      'Xiaomi',
      'Vivo',
      'Oppo',
      'Realme',
      'Motorola',
      'Nothing',
      'iQOO',
      'Boat',
      'Anker',
    ];

    final ramRomPresets = [
      '4GB/64GB',
      '4GB/128GB',
      '6GB/128GB',
      '8GB/128GB',
      '8GB/256GB',
      '12GB/256GB',
      '12GB/512GB',
      '16GB/512GB',
    ];

    final colorPresets = [
      'Black',
      'White',
      'Blue',
      'Green',
      'Gold',
      'Titanium',
      'Silver',
      'Purple',
    ];

    final quickQtySlabs = [5, 10, 20, 50, 100];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final costVal = double.tryParse(costCtrl.text.trim()) ?? 0;
          final priceVal = double.tryParse(priceCtrl.text.trim()) ?? 0;
          final qtyVal = int.tryParse(quantityCtrl.text.trim()) ?? 1;
          final profitVal = priceVal - costVal;
          final totalSlabProfit = profitVal * (isBulk ? qtyVal : 1);
          final marginPercent = priceVal > 0
              ? ((profitVal / priceVal) * 100).toStringAsFixed(1)
              : '0';

          return Dialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isBulk
                                  ? Icons.headphones_rounded
                                  : Icons.phone_android_rounded,
                              color: const Color(0xFF4338CA),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEditing
                                      ? 'Edit / Correct Stock Entry'
                                      : (isBulk
                                          ? 'Add Bulk Accessory Slab'
                                          : 'Add Smartphone (Dual IMEI & Specs)'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E1B4B),
                                  ),
                                ),
                                const Text(
                                  'Scan Box QR / Barcode for Model, RAM/ROM, Color & IMEI',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Phone (IMEI 1 & 2)'),
                              icon: Icon(Icons.smartphone),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Accessory (Bulk Slab)'),
                              icon: Icon(Icons.inventory_2_outlined),
                            ),
                          ],
                          selected: {isBulk},
                          onSelectionChanged: (Set<bool> val) {
                            setDialogState(() {
                              isBulk = val.first;
                              selectedCategory =
                                  isBulk ? 'Accessories' : 'Smartphone';
                              if (isBulk && imei1OrSkuCtrl.text.isEmpty) {
                                imei1OrSkuCtrl.text =
                                    'SKU-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
                                imei2Ctrl.clear();
                              } else if (!isBulk &&
                                  imei1OrSkuCtrl.text.startsWith('SKU-')) {
                                imei1OrSkuCtrl.clear();
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Brand / Manufacturer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: popularBrands.map((b) {
                          final isSelected =
                              brandCtrl.text.toLowerCase() == b.toLowerCase();
                          return ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              b,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF4338CA),
                            onSelected: (selected) {
                              setDialogState(() {
                                brandCtrl.text = selected ? b : '';
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: brandCtrl,
                        decoration: InputDecoration(
                          hintText: 'Brand Name (e.g. Apple, Samsung, Vivo)',
                          prefixIcon:
                              const Icon(Icons.business_outlined, size: 20),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'Please enter brand'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: titleCtrl,
                        decoration: InputDecoration(
                          labelText: isBulk
                              ? 'Accessory Model / Name (Scan or Type) *'
                              : 'Model & Variant (Scan Box Label or Type) *',
                          hintText: isBulk
                              ? 'e.g. 65W SuperVOOC Charger'
                              : 'e.g. iPhone 16 Pro / Galaxy S24 Ultra',
                          prefixIcon: const Icon(
                            Icons.devices_other_outlined,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Color(0xFF059669),
                            ),
                            tooltip:
                                'Scan Box Label QR/Barcode for Model, RAM/ROM & Color',
                            onPressed: () async {
                              final scanned =
                                  await ShopConfig.openCameraScanner(
                                context,
                                title:
                                    'Scan Box Label for Model, RAM/ROM & Color',
                              );
                              if (scanned != null && scanned.isNotEmpty) {
                                final parsed = _parseScannedModelSpecs(scanned);
                                setDialogState(() {
                                  if (parsed['brand']!.isNotEmpty &&
                                      brandCtrl.text.trim().isEmpty) {
                                    brandCtrl.text = parsed['brand']!;
                                  }
                                  if (parsed['model']!.isNotEmpty) {
                                    titleCtrl.text = parsed['model']!;
                                  }
                                  if (parsed['ram_rom']!.isNotEmpty) {
                                    ramRomCtrl.text = parsed['ram_rom']!;
                                  }
                                  if (parsed['color']!.isNotEmpty) {
                                    colorCtrl.text = parsed['color']!;
                                  }
                                  if (parsed['imei']!.isNotEmpty &&
                                      imei1OrSkuCtrl.text.trim().isEmpty) {
                                    imei1OrSkuCtrl.text = parsed['imei']!;
                                  }
                                });
                              }
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (val) => (val == null || val.trim().isEmpty)
                            ? 'Please enter model name'
                            : null,
                      ),
                      if (!isBulk) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: ramRomCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'RAM / ROM (Storage)',
                                  hintText: 'e.g. 8GB/128GB',
                                  prefixIcon:
                                      const Icon(Icons.memory_rounded, size: 18),
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 18,
                                      color: Color(0xFF4338CA),
                                    ),
                                    tooltip: 'Scan RAM / Storage Barcode',
                                    onPressed: () async {
                                      final scanned =
                                          await ShopConfig.openCameraScanner(
                                        context,
                                        title: 'Scan RAM / ROM Spec Barcode',
                                      );
                                      if (scanned != null &&
                                          scanned.isNotEmpty) {
                                        final parsed =
                                            _parseScannedModelSpecs(scanned);
                                        setDialogState(() {
                                          ramRomCtrl.text =
                                              parsed['ram_rom']!.isNotEmpty
                                                  ? parsed['ram_rom']!
                                                  : scanned;
                                        });
                                      }
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: colorCtrl,
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Colour',
                                  hintText: 'e.g. Natural Titanium',
                                  prefixIcon: const Icon(
                                    Icons.palette_outlined,
                                    size: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: ramRomPresets.map((rr) {
                              final selected =
                                  ramRomCtrl.text.toUpperCase() == rr;
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    rr,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  selected: selected,
                                  onSelected: (_) => setDialogState(
                                    () =>
                                        ramRomCtrl.text = selected ? '' : rr,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: colorPresets.map((c) {
                              final selected = colorCtrl.text.toLowerCase() ==
                                  c.toLowerCase();
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ChoiceChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(
                                    c,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  selected: selected,
                                  onSelected: (_) => setDialogState(
                                    () => colorCtrl.text = selected ? '' : c,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: detailsCtrl,
                        decoration: InputDecoration(
                          labelText:
                              'Additional Variant / Box Details (5G, Condition, Specs)',
                          hintText: 'e.g. 5G • Indian Unit • Sealed Pack',
                          prefixIcon:
                              const Icon(Icons.info_outline_rounded, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (shop.canSeeProfit) ...[
                            Expanded(
                              child: TextFormField(
                                controller: costCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*'),
                                  )
                                ],
                                onChanged: (_) => setDialogState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Unit Cost Price (₹)',
                                  prefixText: '₹ ',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Enter cost';
                                  }
                                  if (double.tryParse(val.trim()) == null) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: TextFormField(
                              controller: priceCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'),
                                )
                              ],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Unit Selling Price / MRP (₹)',
                                prefixText: '₹ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter price';
                                }
                                if (double.tryParse(val.trim()) == null) {
                                  return 'Invalid';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (priceVal > 0 && shop.canSeeProfit) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: profitVal >= 0
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: profitVal >= 0
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFFECACA),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                profitVal >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                size: 18,
                                color: profitVal >= 0
                                    ? const Color(0xFF059669)
                                    : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  profitVal >= 0
                                      ? 'Expected Unit Profit: +₹${profitVal.toStringAsFixed(0)} ($marginPercent%)${isBulk ? '  •  Total Slab Profit: +₹${totalSlabProfit.toStringAsFixed(0)}' : ''}'
                                      : 'Warning: Loss of -₹${(-profitVal).toStringAsFixed(0)} per unit',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: profitVal >= 0
                                        ? const Color(0xFF065F46)
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: imei1OrSkuCtrl,
                        keyboardType:
                            isBulk ? TextInputType.text : TextInputType.number,
                        inputFormatters: isBulk
                            ? const []
                            : [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(15),
                              ],
                        decoration: InputDecoration(
                          labelText: isBulk
                              ? 'QR Code / Barcode / SKU *'
                              : 'IMEI 1 (Enter Manually or Scan Barcode) *',
                          hintText: isBulk
                              ? 'Scan or type accessory SKU'
                              : 'Type 15-digit IMEI 1 manually or scan',
                          prefixIcon:
                              const Icon(Icons.qr_code_2_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Color(0xFF059669),
                            ),
                            tooltip: 'Open Camera to Scan QR / Barcode / IMEI 1',
                            onPressed: () async {
                              final scanned =
                                  await ShopConfig.openCameraScanner(
                                context,
                                title: isBulk
                                    ? 'Scan Accessory QR / Barcode'
                                    : 'Scan Smartphone IMEI 1 Barcode / QR',
                              );
                              if (scanned != null && scanned.isNotEmpty) {
                                setDialogState(() {
                                  imei1OrSkuCtrl.text = scanned;
                                });
                              }
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return isBulk
                                ? 'Scan or enter barcode/SKU'
                                : 'Enter or scan IMEI 1';
                          }
                          if (!isBulk &&
                              !RegExp(r'^\d{15}$').hasMatch(val.trim())) {
                            return 'IMEI 1 must contain exactly 15 digits';
                          }
                          return null;
                        },
                      ),
                      if (!isBulk) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: imei2Ctrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: InputDecoration(
                            labelText:
                                'IMEI 2 (Secondary SIM Slot - Manual or Scan)',
                            hintText: 'Type IMEI 2 manually or scan via camera',
                            prefixIcon:
                                const Icon(Icons.sim_card_outlined, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                color: Color(0xFF059669),
                              ),
                              tooltip: 'Open Camera to Scan IMEI 2',
                              onPressed: () async {
                                final scanned =
                                    await ShopConfig.openCameraScanner(
                                  context,
                                  title: 'Scan Smartphone IMEI 2 Barcode / QR',
                                );
                                if (scanned != null && scanned.isNotEmpty) {
                                  setDialogState(() {
                                    imei2Ctrl.text = scanned;
                                  });
                                }
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (val) {
                            if (val != null && val.trim().isNotEmpty) {
                              if (!RegExp(r'^\d{15}$').hasMatch(val.trim())) {
                                return 'IMEI 2 must contain exactly 15 digits';
                              }
                              if (val.trim() == imei1OrSkuCtrl.text.trim()) {
                                return 'IMEI 2 cannot be identical to IMEI 1';
                              }
                            }
                            return null;
                          },
                        ),
                      ],
                      if (isBulk) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: quantityCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Total Quantity Enrolled in Slab *',
                            prefixIcon:
                                const Icon(Icons.layers_rounded, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (val) {
                            if (val == null ||
                                val.trim().isEmpty ||
                                int.tryParse(val) == null ||
                                int.parse(val) < 1) {
                              return 'Enter valid quantity (minimum 1)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text(
                              'Quick Quantity Slab: ',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                children: quickQtySlabs.map((slab) {
                                  return ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      '+$slab',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        final current =
                                            int.tryParse(quantityCtrl.text) ??
                                                0;
                                        quantityCtrl.text =
                                            (current + slab).toString();
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4338CA),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }

                                    setDialogState(() {
                                      isSaving = true;
                                      errorMessage = null;
                                    });

                                    final cost =
                                        double.tryParse(costCtrl.text.trim()) ??
                                            0;
                                    final price = double.tryParse(
                                          priceCtrl.text.trim(),
                                        ) ??
                                        0;
                                    final qty = int.tryParse(
                                          quantityCtrl.text.trim(),
                                        ) ??
                                        1;
                                    final rawModel = titleCtrl.text.trim();
                                    final ramRom = ramRomCtrl.text.trim();
                                    final color = colorCtrl.text.trim();
                                    final extraDetails =
                                        detailsCtrl.text.trim();
                                    final brand = brandCtrl.text.trim();
                                    final code1 = imei1OrSkuCtrl.text.trim();
                                    final code2 =
                                        isBulk ? '' : imei2Ctrl.text.trim();

                                    final specParts = <String>[
                                      if (ramRom.isNotEmpty &&
                                          !rawModel
                                              .toLowerCase()
                                              .contains(ramRom.toLowerCase()))
                                        ramRom,
                                      if (color.isNotEmpty &&
                                          !rawModel
                                              .toLowerCase()
                                              .contains(color.toLowerCase()))
                                        color,
                                      if (extraDetails.isNotEmpty &&
                                          !rawModel.toLowerCase().contains(
                                              extraDetails.toLowerCase()))
                                        extraDetails,
                                    ];
                                    final fullTitle = specParts.isEmpty
                                        ? rawModel
                                        : '$rawModel (${specParts.join(' • ')})';

                                    final effectiveTenantId =
                                        shop.effectiveTenantId.isNotEmpty
                                            ? shop.effectiveTenantId
                                            : supabase.auth.currentUser?.id;

                                    try {
                                      if (isEditing) {
                                        final prodId =
                                            existingStock['product_id'];
                                        final baseUpdate = <String, dynamic>{
                                          'title': fullTitle,
                                          'brand': brand,
                                          'category': selectedCategory,
                                          'selling_price': price,
                                          'has_imei': !isBulk,
                                          'is_bulk': isBulk,
                                          if (shop.canSeeProfit)
                                            'cost_price': cost,
                                        };
                                        try {
                                          await supabase
                                              .from('products')
                                              .update({
                                                ...baseUpdate,
                                                'ram_rom': ramRom,
                                                'color': color,
                                                'variant_details': extraDetails,
                                              })
                                              .eq('id', prodId);
                                        } catch (_) {
                                          await supabase
                                              .from('products')
                                              .update(baseUpdate)
                                              .eq('id', prodId);
                                        }

                                        await supabase
                                            .from('stock_items')
                                            .update({
                                          'imei_or_serial': code1,
                                          'imei_2': code2,
                                          'quantity': isBulk ? qty : 1,
                                          'status': 'Available',
                                        }).eq('id', existingStock['id']);

                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          _fetchInventory();
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            const SnackBar(
                                              backgroundColor: Colors.green,
                                              content: Text(
                                                'Stock item updated successfully!',
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        final existingSku = await supabase
                                            .from('stock_items')
                                            .select('id, quantity, product_id')
                                            .eq('imei_or_serial', code1)
                                            .maybeSingle();

                                        if (existingSku != null && isBulk) {
                                          final prevQty =
                                              (existingSku['quantity'] as num?)
                                                      ?.toInt() ??
                                                  0;
                                          final newTotalQty = prevQty + qty;

                                          await supabase
                                              .from('products')
                                              .update({
                                            'title': fullTitle,
                                            'brand': brand,
                                            if (shop.canSeeProfit)
                                              'cost_price': cost,
                                            'selling_price': price,
                                            'is_bulk': true,
                                          }).eq('id',
                                                  existingSku['product_id']);

                                          await supabase
                                              .from('stock_items')
                                              .update({
                                            'quantity': newTotalQty,
                                            'status': 'Available',
                                          }).eq('id', existingSku['id']);
                                        } else {
                                          final baseInsert = <String, dynamic>{
                                            'user_id': effectiveTenantId,
                                            'title': fullTitle,
                                            'brand': brand,
                                            'category': selectedCategory,
                                            'cost_price': cost,
                                            'selling_price': price,
                                            'has_imei': !isBulk,
                                            'is_bulk': isBulk,
                                          };

                                          Map<String, dynamic> prod;
                                          try {
                                            prod = await supabase
                                                .from('products')
                                                .insert({
                                                  ...baseInsert,
                                                  'ram_rom': ramRom,
                                                  'color': color,
                                                  'variant_details':
                                                      extraDetails,
                                                })
                                                .select()
                                                .single();
                                          } catch (_) {
                                            prod = await supabase
                                                .from('products')
                                                .insert(baseInsert)
                                                .select()
                                                .single();
                                          }

                                          await supabase
                                              .from('stock_items')
                                              .insert({
                                            'user_id': effectiveTenantId,
                                            'product_id': prod['id'],
                                            'imei_or_serial': code1,
                                            'imei_2': code2,
                                            'status': 'Available',
                                            'quantity': isBulk ? qty : 1,
                                          });
                                        }

                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          _fetchInventory();
                                          _showBarcodeModal(
                                            code1,
                                            code2,
                                            '$brand $fullTitle',
                                            price,
                                          );
                                        }
                                      }
                                    } catch (err) {
                                      setDialogState(() {
                                        isSaving = false;
                                        errorMessage = 'Database error: $err';
                                      });
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    isEditing
                                        ? Icons.save_rounded
                                        : Icons.qr_code,
                                    size: 18,
                                  ),
                            label: Text(
                              isSaving
                                  ? 'Saving...'
                                  : (isEditing
                                      ? 'Update Stock'
                                      : 'Save & Generate Barcode'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REQUIREMENT 1: REAL BARCODE STICKER & THERMAL PRINTER EXECUTION DIALOG
  // ---------------------------------------------------------------------------
  void _showBarcodeModal(
    String imei1,
    String imei2,
    String name, [
    num? sellingPrice,
  ]) {
    final shopName = ShopConfig.current.shopName.toUpperCase();
    String selectedSize = '50x25mm Label';
    bool isPrintingSticker = false;

    final stickerText = [
      '★ $shopName ★',
      name,
      'IMEI/SKU: $imei1',
      if (imei2.trim().isNotEmpty) 'IMEI 2: $imei2',
      if (sellingPrice != null) 'MRP: ₹$sellingPrice (Incl. of all taxes)',
    ].join('\n');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.print_rounded, color: Color(0xFF4338CA)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Barcode Sticker & Thermal Print',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'Printer Setup',
                icon: const Icon(
                  Icons.settings_outlined,
                  size: 19,
                  color: Color(0xFF4338CA),
                ),
                onPressed: () =>
                    ShopConfig.showAutoMessagingAndPrinterSettingsDialog(
                        context),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['50x25mm Label', '58mm Thermal', '80mm Thermal']
                    .map((sz) {
                  final sel = selectedSize == sz;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(sz, style: const TextStyle(fontSize: 10)),
                      selected: sel,
                      onSelected: (_) =>
                          setModalState(() => selectedSize = sz),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black87, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      '★ $shopName ★',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: imei1,
                      width: 240,
                      height: 62,
                      drawText: false,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'CODE: $imei1',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (imei2.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      SelectableText(
                        'IMEI 2: $imei2',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                    if (sellingPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'MRP: ₹$sellingPrice (Incl. of all taxes)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: imei1));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied!')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    label:
                        const Text('Copy Code', style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      ShopConfig.sendWhatsAppMessage(
                        context: this.context,
                        phone: '',
                        message: stickerText,
                      );
                    },
                    icon: const Icon(
                      Icons.chat_rounded,
                      size: 15,
                      color: Color(0xFF059669),
                    ),
                    label: const Text(
                      'Share Sticker',
                      style: TextStyle(fontSize: 12, color: Color(0xFF059669)),
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4338CA),
                    ),
                    onPressed: isPrintingSticker
                        ? null
                        : () async {
                            setModalState(() => isPrintingSticker = true);
                            await ShopConfig.executePrintJob(
                              context: this.context,
                              title: 'Sticker $name',
                              receiptText: stickerText,
                              paperFormat: selectedSize,
                              barcodeData: imei1,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                    icon: isPrintingSticker
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.print, size: 16),
                    label: Text(
                      isPrintingSticker
                          ? 'Sending...'
                          : 'Print ($selectedSize)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1 & TAB 2: AVAILABLE STOCK & SOLD HISTORY
  // ---------------------------------------------------------------------------
  Widget _buildStockList(
    List<dynamic> list, {
    required bool isSoldTab,
    required ShopProfile shop,
  }) {
    final bool canSeeProfit = shop.canSeeProfit;

    final filtered = list.where((item) {
      final prod = item['products'] ?? {};
      final bool isBulk = prod['is_bulk'] == true;

      if (!isSoldTab) {
        if (_categoryFilter == 'Smartphones' && isBulk) return false;
        if (_categoryFilter == 'Bulk Accessories' && !isBulk) return false;
      }

      if (_searchQuery.isEmpty) return true;
      final title = (prod['title'] ?? '').toString().toLowerCase();
      final brand = (prod['brand'] ?? '').toString().toLowerCase();
      final ramRom = (prod['ram_rom'] ?? '').toString().toLowerCase();
      final color = (prod['color'] ?? '').toString().toLowerCase();
      final code1 = (item['imei_or_serial'] ?? '').toString().toLowerCase();
      final code2 = (item['imei_2'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return title.contains(q) ||
          brand.contains(q) ||
          ramRom.contains(q) ||
          color.contains(q) ||
          code1.contains(q) ||
          code2.contains(q);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSoldTab
                      ? Icons.shopping_bag_outlined
                      : Icons.inventory_2_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No items match "$_searchQuery"'
                    : (isSoldTab
                        ? 'No sold items recorded yet.'
                        : 'No stock items in this view. Tap "+ Add Stock" to enroll.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (ctx, idx) {
        final stock = Map<String, dynamic>.from(filtered[idx]);
        final prod = stock['products'] ?? {};
        final bool isBulk = prod['is_bulk'] == true;
        final int qty = (stock['quantity'] as num?)?.toInt() ?? 1;
        final num unitCost = (prod['cost_price'] as num?) ?? 0;
        final num unitMrp = (prod['selling_price'] as num?) ?? 0;

        final bool isSrIncoming = _isSrIncomingRecord(stock);
        final Map<String, dynamic>? srInMeta =
            isSrIncoming ? _extractSrIncomingMetadata(stock) : null;

        final List<dynamic> saleItemsList =
            (stock['sale_items'] as List<dynamic>?) ?? [];
        Map<String, dynamic>? latestSaleItem;
        Map<String, dynamic>? latestSaleHeader;
        if (saleItemsList.isNotEmpty) {
          latestSaleItem =
              Map<String, dynamic>.from(saleItemsList.last as Map);
          if (latestSaleItem['sales'] is Map) {
            latestSaleHeader =
                Map<String, dynamic>.from(latestSaleItem['sales'] as Map);
          }
        }

        final int soldQty = latestSaleItem != null
            ? ((latestSaleItem['quantity'] as num?)?.toInt() ?? 1)
            : 1;
        final num mrpTotalForSold = unitMrp * soldQty;
        final num actualSoldPrice = latestSaleItem != null
            ? ((latestSaleItem['sold_price'] as num?) ?? mrpTotalForSold)
            : unitMrp;
        final num actualCostPrice = latestSaleItem != null
            ? ((latestSaleItem['cost_price'] as num?) ?? (unitCost * soldQty))
            : unitCost;
        final num actualProfit = latestSaleItem != null
            ? ((latestSaleItem['profit'] as num?) ??
                (actualSoldPrice - actualCostPrice))
            : (unitMrp - unitCost);
        final num discountGivenOnItem = isSoldTab
            ? max<num>(0, mrpTotalForSold - actualSoldPrice)
            : 0;

        final num expectedUnitProfit = unitMrp - unitCost;
        final num totalSlabProfit =
            expectedUnitProfit * (isBulk && !isSoldTab ? qty : 1);

        final String code1 = (stock['imei_or_serial'] ?? '').toString();
        final String code2 = (stock['imei_2'] ?? '').toString();
        final String brand = (prod['brand'] ?? 'Mobile').toString();
        final String title = (prod['title'] ?? 'Item').toString();
        final String ramRom = (prod['ram_rom'] ?? '').toString();
        final String color = (prod['color'] ?? '').toString();
        final String customerName = latestSaleHeader != null &&
                latestSaleHeader['customers'] is Map
            ? ((latestSaleHeader['customers']['name'] ?? '').toString())
            : '';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0.8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isBulk && !isSoldTab
                  ? Colors.amber.shade200
                  : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSoldTab
                            ? Colors.red.shade50
                            : (isBulk
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFEEF2FF)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isBulk
                            ? Icons.headphones_rounded
                            : Icons.phone_android_rounded,
                        color: isSoldTab
                            ? Colors.red.shade700
                            : (isBulk
                                ? const Color(0xFFD97706)
                                : const Color(0xFF4338CA)),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  brand.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              if (isSrIncoming && srInMeta != null) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFA7F3D0),
                                    ),
                                  ),
                                  child: Text(
                                    'SR IN: ${srInMeta['member_name']}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (ramRom.isNotEmpty || color.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: [
                                if (ramRom.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
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
                                      vertical: 2,
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
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: code1));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Copied: $code1')),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.qr_code,
                                        size: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isBulk
                                            ? 'SKU: $code1'
                                            : 'IMEI 1: $code1',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.copy,
                                        size: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isBulk && code2.trim().isNotEmpty)
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: code2),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Copied IMEI 2: $code2'),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.sim_card_outlined,
                                          size: 13,
                                          color: Color(0xFF4338CA),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'IMEI 2: $code2',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF4338CA),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          if (isSoldTab)
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'MRP: ₹${mrpTotalForSold.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    decoration: discountGivenOnItem > 0
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (discountGivenOnItem > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'POS Discount: -₹${discountGivenOnItem.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                Text(
                                  'Net Sold: ₹${actualSoldPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                                if (canSeeProfit) ...[
                                  Text(
                                    'Cost: ₹${actualCostPrice.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: actualProfit >= 0
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFFEF2F2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Actual Profit: ${actualProfit >= 0 ? "+" : ""}₹${actualProfit.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: actualProfit >= 0
                                            ? const Color(0xFF059669)
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                                if (customerName.isNotEmpty)
                                  Text(
                                    '• Sold to: $customerName',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                              ],
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'Unit Sell / MRP: ₹$unitMrp',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF4338CA),
                                  ),
                                ),
                                if (canSeeProfit) ...[
                                  Text(
                                    'Cost: ₹$unitCost',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Unit Profit: +₹$expectedUnitProfit',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: expectedUnitProfit >= 0
                                            ? const Color(0xFF059669)
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                  if (isBulk)
                                    Text(
                                      'Total Slab Profit: +₹${totalSlabProfit.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSoldTab
                            ? Colors.red.shade50
                            : (isBulk
                                ? Colors.amber.shade50
                                : Colors.green.shade50),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSoldTab
                              ? Colors.red.shade200
                              : (isBulk
                                  ? Colors.amber.shade300
                                  : Colors.green.shade200),
                        ),
                      ),
                      child: Text(
                        isSoldTab
                            ? 'SOLD'
                            : (isBulk ? 'SLAB QTY: $qty' : '1 IN STOCK'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isSoldTab
                              ? Colors.red.shade800
                              : (isBulk
                                  ? Colors.amber.shade900
                                  : Colors.green.shade800),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!isSoldTab) ...[
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (isBulk)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Slab:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove, size: 15),
                              onPressed: shop.canEditDeleteStock
                                  ? () => _adjustBulkQuantity(stock, -1)
                                  : null,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '$qty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add, size: 15),
                              onPressed: shop.canAddStock
                                  ? () => _adjustBulkQuantity(stock, 1)
                                  : null,
                            ),
                          ],
                        )
                      else
                        const Text(
                          'Dual-IMEI Verified',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      Flexible(
                        child: Wrap(
                          spacing: 2,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF7C3AED),
                              ),
                              onPressed: () => _showSrTransferDialog(
                                preselectedStock: stock,
                              ),
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Give SR',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                foregroundColor: const Color(0xFF4338CA),
                              ),
                              onPressed: () => _showBarcodeModal(
                                code1,
                                code2,
                                '$brand $title',
                                unitMrp,
                              ),
                              icon: const Icon(
                                Icons.print_rounded,
                                size: 15,
                              ),
                              label: const Text(
                                'Print Sticker',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            if (shop.canEditDeleteStock) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFF0284C7),
                                ),
                                onPressed: () => _showAddOrEditStockDialog(
                                  existingStock: stock,
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text(
                                  'Edit',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: const Color(0xFFDC2626),
                                ),
                                onPressed: () =>
                                    _revokeOrDeleteStockItem(stock),
                                icon: const Icon(Icons.undo_rounded, size: 16),
                                label: const Text(
                                  'Revoke',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // NEW TAB 3: SR MEMBER INCOMING TAB (Near Sold History & synced with Available Stock)
  // ---------------------------------------------------------------------------
  Widget _buildSrIncomingTab(ShopProfile shop) {
    final q = _searchQuery.toLowerCase();
    final filteredIncoming = _srIncomingItems.where((item) {
      final stock = Map<String, dynamic>.from(item as Map);
      final prod = stock['products'] ?? {};
      final bool isBulk = prod['is_bulk'] == true;

      if (_categoryFilter == 'Smartphones' && isBulk) return false;
      if (_categoryFilter == 'Bulk Accessories' && !isBulk) return false;

      if (q.isEmpty) return true;
      final meta = _extractSrIncomingMetadata(stock);
      final text =
          '${prod['brand'] ?? ''} ${prod['title'] ?? ''} ${stock['imei_or_serial'] ?? ''} ${meta['member_name']} ${meta['member_phone']}'
              .toLowerCase();
      return text.contains(q);
    }).toList();

    int totalIncomingUnits = 0;
    num totalIncomingCost = 0;
    for (final item in filteredIncoming) {
      final s = Map<String, dynamic>.from(item as Map);
      final meta = _extractSrIncomingMetadata(s);
      final int qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final int safeQty = qty > 0 ? qty : 1;
      final num rate = (meta['incoming_rate'] as num?) ?? 0;
      totalIncomingUnits += safeQty;
      totalIncomingCost += rate * safeQty;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFECFDF5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SR Member Incoming Stock (Added to Available Stock)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF065F46),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalIncomingUnits Units Received  •  SR Cost Value: ₹${totalIncomingCost.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF047857),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                ),
                onPressed: () => _showSrIncomingDialog(),
                icon: const Icon(Icons.call_received_rounded, size: 18),
                label: const Text(
                  '+ Receive SR Stock',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredIncoming.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.call_received_rounded,
                          size: 52,
                          color: Colors.teal.shade200,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No SR Member Incoming Entries Yet',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Tap "+ Receive SR Stock" when you receive a phone or accessory from another dealer/member. It will automatically show in your Available Stock tab for billing!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: filteredIncoming.length,
                  itemBuilder: (ctx, idx) {
                    final stock =
                        Map<String, dynamic>.from(filteredIncoming[idx] as Map);
                    final prod = stock['products'] ?? {};
                    final meta = _extractSrIncomingMetadata(stock);
                    final String memberName = meta['member_name'].toString();
                    final String memberPhone = meta['member_phone'].toString();
                    final num incomingRate =
                        (meta['incoming_rate'] as num?) ?? 0;
                    final num sellingPrice =
                        (prod['selling_price'] as num?) ?? 0;
                    final String notes = meta['notes'].toString();
                    final int qty = (stock['quantity'] as num?)?.toInt() ?? 1;
                    final String statusStr =
                        (stock['status'] ?? 'Available').toString();
                    final bool isStillAvailable =
                        statusStr == 'Available' && qty > 0;
                    final String code1 =
                        (stock['imei_or_serial'] ?? '').toString();
                    final String code2 = (stock['imei_2'] ?? '').toString();
                    final DateTime dt = DateTime.tryParse(
                          (stock['sr_date'] ?? stock['created_at'] ?? '')
                              .toString(),
                        )?.toLocal() ??
                        DateTime.now();

                    final srInSlipText = [
                      '📥 *SR INCOMING STOCK RECEIPT*',
                      'Received At: *${shop.shopName}*',
                      'From Member: *$memberName* ($memberPhone)',
                      'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(dt)}',
                      '----------------------------',
                      'Item: *${prod['brand'] ?? ''} ${prod['title'] ?? ''}*',
                      'Qty: ${qty > 0 ? qty : 1}  •  SR Rate: ₹${incomingRate.toStringAsFixed(0)}',
                      'IMEI/SKU: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                      if (notes.isNotEmpty) 'Note: $notes',
                      '----------------------------',
                    ].join('\n');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.teal.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'SR FROM: ${memberName.toUpperCase()} (${memberPhone.isEmpty ? "N/A" : memberPhone})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isStillAvailable
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isStillAvailable
                                        ? 'IN AVAILABLE STOCK'
                                        : 'SOLD',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isStillAvailable
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${prod['brand'] ?? ''} ${prod['title'] ?? ''}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'IMEI/SKU: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Received: ${DateFormat('dd MMM, hh:mm a').format(dt)}  •  Selling MRP: ₹${sellingPrice.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF4338CA),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (notes.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Note: $notes',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${incomingRate.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Color(0xFF065F46),
                                      ),
                                    ),
                                    const Text(
                                      'SR In Rate',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF059669),
                                  ),
                                  onPressed: () =>
                                      ShopConfig.sendWhatsAppMessage(
                                    context: context,
                                    phone: memberPhone,
                                    message: srInSlipText,
                                  ),
                                  icon:
                                      const Icon(Icons.chat_rounded, size: 14),
                                  label: const Text(
                                    'WhatsApp',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF4338CA),
                                  ),
                                  onPressed: () => _showBarcodeModal(
                                    code1,
                                    code2,
                                    '${prod['brand'] ?? ''} ${prod['title'] ?? ''}',
                                    sellingPrice,
                                  ),
                                  icon:
                                      const Icon(Icons.print_rounded, size: 14),
                                  label: const Text(
                                    'Print Sticker',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                if (isStillAvailable && shop.canEditDeleteStock)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: const Color(0xFFDC2626),
                                    ),
                                    onPressed: () =>
                                        _revokeOrDeleteStockItem(stock),
                                    icon:
                                        const Icon(Icons.undo_rounded, size: 15),
                                    label: const Text(
                                      'Revoke',
                                      style: TextStyle(fontSize: 11),
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
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: SR (DISTRIBUTOR / MEMBER STOCK TRANSFER) TAB
  // ---------------------------------------------------------------------------
  Widget _buildSrTransferTab(ShopProfile shop) {
    final q = _searchQuery.toLowerCase();
    final filteredSr = _srItems.where((item) {
      if (q.isEmpty) return true;
      final stock = Map<String, dynamic>.from(item as Map);
      final prod = stock['products'] ?? {};
      final meta = _extractSrMetadata(stock);
      final text =
          '${prod['brand'] ?? ''} ${prod['title'] ?? ''} ${stock['imei_or_serial'] ?? ''} ${meta['member_name']} ${meta['member_phone']}'
              .toLowerCase();
      return text.contains(q);
    }).toList();

    int totalSrUnits = 0;
    num totalSrValue = 0;
    for (final item in filteredSr) {
      final s = Map<String, dynamic>.from(item as Map);
      final meta = _extractSrMetadata(s);
      final int qty = (s['quantity'] as num?)?.toInt() ?? 1;
      final num rate = (meta['transfer_price'] as num?) ?? 0;
      totalSrUnits += qty;
      totalSrValue += rate * qty;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFF5F3FF),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SR Stock Given to Members / Distributors',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5B21B6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalSrUnits Units Out  •  Total SR Value: ₹${totalSrValue.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4C1D95),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
                onPressed: () => _showSrTransferDialog(),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text(
                  '+ Give Stock in SR',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredSr.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.swap_horizontal_circle_outlined,
                          size: 52,
                          color: Colors.deepPurple.shade200,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No SR Stock Transfers Yet',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When another distributor or member wants stock from your present inventory, tap "+ Give Stock in SR" to record and track it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: filteredSr.length,
                  itemBuilder: (ctx, idx) {
                    final stock =
                        Map<String, dynamic>.from(filteredSr[idx] as Map);
                    final prod = stock['products'] ?? {};
                    final meta = _extractSrMetadata(stock);
                    final String memberName = meta['member_name'].toString();
                    final String memberPhone = meta['member_phone'].toString();
                    final num rate = (meta['transfer_price'] as num?) ?? 0;
                    final String notes = meta['notes'].toString();
                    final int qty = (stock['quantity'] as num?)?.toInt() ?? 1;
                    final String code1 =
                        (stock['imei_or_serial'] ?? '').toString();
                    final String code2 = (stock['imei_2'] ?? '').toString();
                    final DateTime dt = DateTime.tryParse(
                          (stock['sr_date'] ?? stock['created_at'] ?? '')
                              .toString(),
                        )?.toLocal() ??
                        DateTime.now();

                    final srSlipText = [
                      '📦 *SR STOCK TRANSFER CHALLAN*',
                      'From: *${shop.shopName}*',
                      'To Member: *$memberName* ($memberPhone)',
                      'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(dt)}',
                      '----------------------------',
                      'Item: *${prod['brand'] ?? ''} ${prod['title'] ?? ''}*',
                      'Qty: $qty  •  SR Rate: ₹${rate.toStringAsFixed(0)}',
                      'Total SR Amount: *₹${(rate * qty).toStringAsFixed(0)}*',
                      'IMEI/SKU: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                      if (notes.isNotEmpty) 'Note: $notes',
                      '----------------------------',
                    ].join('\n');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.deepPurple.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F3FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'SR TO: ${memberName.toUpperCase()} (${memberPhone.isEmpty ? "N/A" : memberPhone})',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF6D28D9),
                                    ),
                                  ),
                                ),
                                Text(
                                  DateFormat('dd MMM, hh:mm a').format(dt),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${prod['brand'] ?? ''} ${prod['title'] ?? ''} × $qty',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'IMEI/SKU: $code1${code2.isNotEmpty ? " | IMEI 2: $code2" : ""}',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      if (notes.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Note: $notes',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '₹${(rate * qty).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Color(0xFF4C1D95),
                                      ),
                                    ),
                                    const Text(
                                      'SR Value',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF059669),
                                  ),
                                  onPressed: () =>
                                      ShopConfig.sendWhatsAppMessage(
                                    context: context,
                                    phone: memberPhone,
                                    message: srSlipText,
                                  ),
                                  icon:
                                      const Icon(Icons.chat_rounded, size: 14),
                                  label: const Text(
                                    'WhatsApp',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF2563EB),
                                  ),
                                  onPressed: () => ShopConfig.sendSmsMessage(
                                    context: context,
                                    phone: memberPhone,
                                    message: srSlipText,
                                  ),
                                  icon: const Icon(Icons.sms_rounded, size: 14),
                                  label: const Text(
                                    'SMS',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: const Color(0xFF4338CA),
                                  ),
                                  onPressed: () =>
                                      ShopConfig.printReceiptDialog(
                                    context: context,
                                    title: 'Print SR Challan ($memberName)',
                                    receiptText: srSlipText,
                                    customerPhone: memberPhone,
                                    barcodeData: code1,
                                  ),
                                  icon:
                                      const Icon(Icons.print_rounded, size: 14),
                                  label: const Text(
                                    'Print SR',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: const Color(0xFFECFDF5),
                                    foregroundColor: const Color(0xFF059669),
                                  ),
                                  onPressed: () =>
                                      _returnSrItemToAvailableStock(stock),
                                  icon: const Icon(
                                    Icons.settings_backup_restore_rounded,
                                    size: 15,
                                  ),
                                  label: const Text(
                                    'Return to Stock',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ShopProfile>(
      valueListenable: ShopConfig.notifier,
      builder: (context, shop, _) {
        final int distinctModels = _availableItems.length;
        final int soldCount = _soldItems.length;
        final int srIncomingCount = _srIncomingItems.length;
        final int srCount = _srItems.length;

        int totalPhysicalUnits = 0;
        int phoneUnits = 0;
        int bulkAccessoryUnits = 0;
        double totalStockValue = 0;

        for (var item in _availableItems) {
          final p = item['products'] ?? {};
          final bool isBulk = p['is_bulk'] == true;
          final cost = (p['cost_price'] as num?)?.toDouble() ?? 0;
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;

          totalPhysicalUnits += qty;
          if (isBulk) {
            bulkAccessoryUnits += qty;
          } else {
            phoneUnits += qty;
          }
          totalStockValue += cost * qty;
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: const Color(0xFF4338CA),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF4338CA),
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onTap: (index) {
                  setState(() {
                    _activeTabIndex = index;
                  });
                },
                tabs: [
                  Tab(
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    text:
                        'Available ($totalPhysicalUnits Units / $distinctModels SKUs)',
                  ),
                  Tab(
                    icon: const Icon(Icons.sell_outlined, size: 17),
                    text: 'Sold History ($soldCount)',
                  ),
                  Tab(
                    icon: const Icon(Icons.call_received_rounded, size: 17),
                    text: 'SR Incoming ($srIncomingCount)',
                  ),
                  Tab(
                    icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                    text: 'SR / Member Transfer ($srCount)',
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Smartphones',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF4338CA),
                              ),
                            ),
                            Text(
                              '$phoneUnits Handsets',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1B4B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bulk Accessories',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFFB45309),
                              ),
                            ),
                            Text(
                              '$bulkAccessoryUnits Units',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF78350F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (shop.canSeeProfit) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Stock Cost',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF059669),
                                ),
                              ),
                              Text(
                                '₹${totalStockValue.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Column(
                  children: [
                    SizedBox(
                      height: 40,
                      child: TextField(
                        controller: TextEditingController.fromValue(
                          TextEditingValue(
                            text: _searchQuery,
                            selection: TextSelection.collapsed(
                              offset: _searchQuery.length,
                            ),
                          ),
                        ),
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText:
                              'Search model, RAM/ROM, color, IMEI 1, IMEI 2, or scan QR...',
                          prefixIcon: const Icon(Icons.search,
                              color: Colors.grey, size: 18),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchQuery.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 17),
                                  onPressed: () =>
                                      setState(() => _searchQuery = ''),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: Color(0xFF4338CA),
                                  size: 19,
                                ),
                                tooltip: 'Scan QR / Barcode to Find Stock',
                                onPressed: () async {
                                  final scanned =
                                      await ShopConfig.openCameraScanner(
                                    context,
                                    title: 'Scan Stock QR / Barcode',
                                  );
                                  if (scanned != null && scanned.isNotEmpty) {
                                    setState(() => _searchQuery = scanned);
                                  }
                                },
                              ),
                            ],
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCategoryChip(
                            'All',
                            'All Stock ($totalPhysicalUnits Units)',
                          ),
                          const SizedBox(width: 6),
                          _buildCategoryChip(
                            'Smartphones',
                            'Phones ($phoneUnits)',
                          ),
                          const SizedBox(width: 6),
                          _buildCategoryChip(
                            'Bulk Accessories',
                            'Bulk Accessories ($bulkAccessoryUnits Units)',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4338CA),
                        ),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          RefreshIndicator(
                            onRefresh: _fetchInventory,
                            child: _buildStockList(
                              _availableItems,
                              isSoldTab: false,
                              shop: shop,
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: _fetchInventory,
                            child: _buildStockList(
                              _soldItems,
                              isSoldTab: true,
                              shop: shop,
                            ),
                          ),
                          RefreshIndicator(
                            onRefresh: _fetchInventory,
                            child: _buildSrIncomingTab(shop),
                          ),
                          RefreshIndicator(
                            onRefresh: _fetchInventory,
                            child: _buildSrTransferTab(shop),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          // Requirement 2: Remove "+ Add Stock" button in Sold History, SR Incoming, and SR / Member Transfer
          floatingActionButton: (_activeTabIndex == 0 && shop.canAddStock)
              ? FloatingActionButton.extended(
                  backgroundColor: const Color(0xFF4338CA),
                  foregroundColor: Colors.white,
                  elevation: 3,
                  onPressed: () => _showAddOrEditStockDialog(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Add Stock',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildCategoryChip(String value, String label) {
    final bool selected = _categoryFilter == value;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      selectedColor: const Color(0xFFEEF2FF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF4338CA) : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _categoryFilter = value),
    );
  }
}