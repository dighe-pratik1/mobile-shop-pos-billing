
import 'package:pdf/pdf.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShopProfile {
  final String userId;
  final String effectiveTenantId;
  final String email;
  final String shopName;
  final String shopPhone;
  final String shopAddress;
  final String branchName;
  final String role;
  final bool isApproved;

  // Granular permissions controlled by the Shop Owner
  final bool permAddStock;
  final bool permEditDeleteStock;
  final bool permPosSell;
  final bool permGiveDiscount;
  final bool permViewReports;
  final bool permSettleUdhaar;
  final bool permViewProfit;

  const ShopProfile({
    this.userId = '',
    this.effectiveTenantId = '',
    this.email = '',
    required this.shopName,
    required this.shopPhone,
    required this.shopAddress,
    this.branchName = 'Main Branch',
    this.role = 'shop_owner',
    this.isApproved = false,
    this.permAddStock = true,
    this.permEditDeleteStock = true,
    this.permPosSell = true,
    this.permGiveDiscount = true,
    this.permViewReports = true,
    this.permSettleUdhaar = true,
    this.permViewProfit = true,
  });

  bool get isAdmin => role == 'admin';
  bool get isOwner => role == 'shop_owner' || role == 'admin';
  bool get isEmployee => role == 'cashier';

  // Effective capability getters (Preserves exact Shop Owner permission system)
  bool get canSeeProfit => isOwner || permViewProfit;
  bool get canAddStock => isOwner || permAddStock;
  bool get canEditDeleteStock => isOwner || permEditDeleteStock;
  bool get canSellInPos => isOwner || permPosSell;
  bool get canGiveDiscount => isOwner || permGiveDiscount;
  bool get canViewReports => isOwner || permViewReports;
  bool get canSettleUdhaar => isOwner || permSettleUdhaar;

  ShopProfile copyWith({
    String? userId,
    String? effectiveTenantId,
    String? email,
    String? shopName,
    String? shopPhone,
    String? shopAddress,
    String? branchName,
    String? role,
    bool? isApproved,
    bool? permAddStock,
    bool? permEditDeleteStock,
    bool? permPosSell,
    bool? permGiveDiscount,
    bool? permViewReports,
    bool? permSettleUdhaar,
    bool? permViewProfit,
  }) {
    return ShopProfile(
      userId: userId ?? this.userId,
      effectiveTenantId: effectiveTenantId ?? this.effectiveTenantId,
      email: email ?? this.email,
      shopName: shopName ?? this.shopName,
      shopPhone: shopPhone ?? this.shopPhone,
      shopAddress: shopAddress ?? this.shopAddress,
      branchName: branchName ?? this.branchName,
      role: role ?? this.role,
      isApproved: isApproved ?? this.isApproved,
      permAddStock: permAddStock ?? this.permAddStock,
      permEditDeleteStock: permEditDeleteStock ?? this.permEditDeleteStock,
      permPosSell: permPosSell ?? this.permPosSell,
      permGiveDiscount: permGiveDiscount ?? this.permGiveDiscount,
      permViewReports: permViewReports ?? this.permViewReports,
      permSettleUdhaar: permSettleUdhaar ?? this.permSettleUdhaar,
      permViewProfit: permViewProfit ?? this.permViewProfit,
    );
  }
}

class ShopConfig {
  static final ValueNotifier<ShopProfile> notifier = ValueNotifier(
    const ShopProfile(
      shopName: 'APEX MOBILE STORE',
      shopPhone: '',
      shopAddress: 'Smartphones • Accessories • Service',
      branchName: 'Main Branch',
      role: 'shop_owner',
      isApproved: false,
    ),
  );

  // Automatic Messaging & Printer Hardware Configuration
  static bool autoSendWhatsAppOnBill = true;
  static bool autoSendSmsOnBill = false;
  static bool autoPrintOnBill = false;

  // Optional Silent Background HTTP Gateway settings (Fast2SMS / UltraMsg / Webhook)
  static String smsGatewayUrl = '';
  static String whatsappGatewayUrl = '';

  // Printer Hardware settings
  static String printerConnectionMode = 'System Print (USB / Wi-Fi / PDF)';
  static String thermalPrinterIp = '';
  static int thermalPrinterPort = 9100;

  static ShopProfile get current => notifier.value;

  static Future<void> loadFromDatabase() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('user_profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      if (data != null) {
        final rawRole = (data['role'] ?? 'shop_owner').toString().trim();
        final ownerId = (data['owner_id'] ?? user.id).toString().trim();
        final effectiveTenant = ownerId.isEmpty ? user.id : ownerId;

        String rawName = (data['shop_name'] ?? '').toString().trim();
        String rawPhone = (data['shop_phone'] ?? '').toString().trim();
        String rawAddr = (data['shop_address'] ?? '').toString().trim();
        String rawBranch = (data['branch_name'] ?? 'Main Branch').toString().trim();

        if (rawRole == 'cashier' && effectiveTenant != user.id) {
          final ownerData = await supabase
              .from('user_profiles')
              .select('shop_name, shop_phone, shop_address')
              .eq('id', effectiveTenant)
              .maybeSingle();
          if (ownerData != null) {
            rawName = (ownerData['shop_name'] ?? rawName).toString().trim();
            rawPhone = (ownerData['shop_phone'] ?? rawPhone).toString().trim();
            rawAddr = (ownerData['shop_address'] ?? rawAddr).toString().trim();
          }
        }

        final approved = data['is_approved'] == true;
        final isOwnerOrAdmin = rawRole == 'shop_owner' || rawRole == 'admin';

        notifier.value = ShopProfile(
          userId: user.id,
          effectiveTenantId: effectiveTenant,
          email: (data['email'] ?? user.email ?? '').toString(),
          shopName: rawName.isEmpty ? 'APEX MOBILE STORE' : rawName,
          shopPhone: rawPhone,
          shopAddress: rawAddr.isEmpty ? 'Smartphones • Accessories • Service' : rawAddr,
          branchName: rawBranch.isEmpty ? 'Main Branch' : rawBranch,
          role: rawRole,
          isApproved: approved,
          permAddStock: isOwnerOrAdmin ? true : (data['perm_add_stock'] ?? false) == true,
          permEditDeleteStock:
              isOwnerOrAdmin ? true : (data['perm_edit_delete_stock'] ?? false) == true,
          permPosSell: isOwnerOrAdmin ? true : (data['perm_pos_sell'] ?? true) == true,
          permGiveDiscount: isOwnerOrAdmin ? true : (data['perm_give_discount'] ?? false) == true,
          permViewReports: isOwnerOrAdmin ? true : (data['perm_view_reports'] ?? false) == true,
          permSettleUdhaar: isOwnerOrAdmin ? true : (data['perm_settle_udhaar'] ?? false) == true,
          permViewProfit: isOwnerOrAdmin ? true : (data['perm_view_profit'] ?? false) == true,
        );
      }
    } catch (e) {
      debugPrint('Failed to load shop profile: $e');
    }
  }

  static Future<void> updateShopProfile({
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    String? branchName,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final cleanName = shopName.trim().isEmpty ? 'APEX MOBILE STORE' : shopName.trim();
    final cleanPhone = shopPhone.trim();
    final cleanAddress =
        shopAddress.trim().isEmpty ? 'Smartphones • Accessories • Service' : shopAddress.trim();
    final cleanBranch = (branchName ?? current.branchName).trim().isEmpty
        ? 'Main Branch'
        : (branchName ?? current.branchName).trim();

    try {
      await supabase.from('user_profiles').update({
        'shop_name': cleanName,
        'shop_phone': cleanPhone,
        'shop_address': cleanAddress,
        'branch_name': cleanBranch,
      }).eq('id', current.effectiveTenantId.isEmpty ? user.id : current.effectiveTenantId);
    } catch (_) {
      await supabase.from('user_profiles').update({
        'shop_name': cleanName,
        'shop_phone': cleanPhone,
        'shop_address': cleanAddress,
      }).eq('id', current.effectiveTenantId.isEmpty ? user.id : current.effectiveTenantId);
    }

    notifier.value = notifier.value.copyWith(
      shopName: cleanName,
      shopPhone: cleanPhone,
      shopAddress: cleanAddress,
      branchName: cleanBranch,
    );
  }

  static String formatProductSpecTitle(Map<String, dynamic> prod) {
    final brand = (prod['brand'] ?? '').toString().trim();
    final title = (prod['title'] ?? '').toString().trim();
    final ramRom = (prod['ram_rom'] ?? '').toString().trim();
    final color = (prod['color'] ?? '').toString().trim();
    final details = (prod['variant_details'] ?? '').toString().trim();

    final base = '$brand $title'.trim();
    final extra = <String>[
      if (ramRom.isNotEmpty && !base.toLowerCase().contains(ramRom.toLowerCase())) ramRom,
      if (color.isNotEmpty && !base.toLowerCase().contains(color.toLowerCase())) color,
      if (details.isNotEmpty && !base.toLowerCase().contains(details.toLowerCase())) details,
    ];
    if (extra.isEmpty) return base.isEmpty ? 'Item' : base;
    return '$base (${extra.join(' • ')})';
  }

  // ---------------------------------------------------------------------------
  // MULTI-CHANNEL URL / INTENT LAUNCHER (Pigeon + Legacy + Desktop Process)
  // ---------------------------------------------------------------------------
  static Future<bool> _tryLaunchExternalUrl(String url) async {
    // 1. Try modern Pigeon channel used by url_launcher_android >= 6.1+
    try {
      const pigeonAndroid = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.url_launcher_android.UrlLauncherApi.launchUrl',
        StandardMessageCodec(),
      );
      final reply =
          await pigeonAndroid.send(<Object?>[url, <String, String>{}]) as List<Object?>?;
      if (reply != null && reply.isNotEmpty && reply.first == true) {
        return true;
      }
    } catch (_) {}

    // 2. Try iOS Pigeon channel
    try {
      const pigeonIos = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.launchUrl',
        StandardMessageCodec(),
      );
      final reply = await pigeonIos.send(<Object?>[url, false]) as List<Object?>?;
      if (reply != null && reply.isNotEmpty && reply.first == true) {
        return true;
      }
    } catch (_) {}

    // 3. Try legacy MethodChannel ('plugins.flutter.io/url_launcher')
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    try {
      final res = await channel.invokeMethod<bool>('launch', <String, dynamic>{
        'url': url,
        'useSafariVC': false,
        'useWebView': false,
        'enableJavaScript': true,
        'enableDomStorage': true,
        'universalLinksOnly': false,
        'headers': <String, String>{},
      });
      if (res == true) return true;
    } catch (_) {}

    // 4. Try Android specific MethodChannel
    const androidChannel = MethodChannel('plugins.flutter.io/url_launcher_android');
    try {
      final res = await androidChannel.invokeMethod<bool>('launchUrl', <String, dynamic>{
        'url': url,
        'headers': <String, String>{},
      });
      if (res == true) return true;
    } catch (_) {}

    // 5. Try Desktop / OS native Process launcher
    if (!kIsWeb) {
      try {
        if (Platform.isWindows) {
          await Process.run('cmd', ['/c', 'start', '', url]);
          return true;
        } else if (Platform.isMacOS) {
          await Process.run('open', [url]);
          return true;
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [url]);
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  static Future<bool> _sendSilentHttpGateway(
    String templateUrl,
    String phone,
    String message,
  ) async {
    final cleanTemplate = templateUrl.trim();
    if (cleanTemplate.isEmpty || kIsWeb) return false;

    try {
      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
      final tenDigit =
          digits.length > 10 ? digits.substring(digits.length - 10) : digits;
      final intlPhone = digits.length == 10 ? '91$digits' : digits;

      final resolvedUrl = cleanTemplate
          .replaceAll('{phone}', Uri.encodeComponent(tenDigit))
          .replaceAll('{intl_phone}', Uri.encodeComponent(intlPhone))
          .replaceAll('{message}', Uri.encodeComponent(message));

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.getUrl(Uri.parse(resolvedUrl));
      final resp = await req.close();
      client.close();
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  /// Send Bill or Reminder via WhatsApp (Supports silent API gateway + Direct App Deep-Link)
  static Future<void> sendWhatsAppMessage({
    required BuildContext context,
    required String phone,
    required String message,
    bool silentOnly = false,
  }) async {
    await Clipboard.setData(ClipboardData(text: message));
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final intlPhone = digits.length == 10 ? '91$digits' : digits;

    // 1. If silent HTTP WhatsApp Gateway is configured, dispatch automatically over HTTP
    if (whatsappGatewayUrl.trim().isNotEmpty && intlPhone.isNotEmpty) {
      final apiSent =
          await _sendSilentHttpGateway(whatsappGatewayUrl, intlPhone, message);
      if (apiSent) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text('✓ WhatsApp message automatically sent to +$intlPhone!'),
          ),
        );
        return;
      }
    }

    if (silentOnly) return;

    final encoded = Uri.encodeComponent(message);
    final directSchemeUrl = intlPhone.isNotEmpty
        ? 'whatsapp://send?phone=$intlPhone&text=$encoded'
        : 'whatsapp://send?text=$encoded';
    final webFallbackUrl = intlPhone.isNotEmpty
        ? 'https://wa.me/$intlPhone?text=$encoded'
        : 'https://wa.me/?text=$encoded';

    bool launched = await _tryLaunchExternalUrl(directSchemeUrl);
    if (!launched) {
      launched = await _tryLaunchExternalUrl(webFallbackUrl);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF059669),
        content: Text(
          launched
              ? 'WhatsApp automatically opened for $phone!'
              : 'WhatsApp bill ready! Configure Gateway URL in Settings for background send.',
        ),
      ),
    );
  }

  /// Send Bill or Reminder via SMS (Supports silent SMS Gateway + Direct Native SMS Intent)
  static Future<void> sendSmsMessage({
    required BuildContext context,
    required String phone,
    required String message,
    bool silentOnly = false,
  }) async {
    final cleanMsg = message.replaceAll('*', '');
    await Clipboard.setData(ClipboardData(text: cleanMsg));
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

    // 1. If silent HTTP SMS Gateway (Fast2SMS / TextLocal / Webhook) is configured, send in background
    if (smsGatewayUrl.trim().isNotEmpty && cleanPhone.isNotEmpty) {
      final apiSent =
          await _sendSilentHttpGateway(smsGatewayUrl, cleanPhone, cleanMsg);
      if (apiSent) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2563EB),
            content: Text('✓ SMS automatically dispatched to $cleanPhone!'),
          ),
        );
        return;
      }
    }

    if (silentOnly) return;

    final url = 'sms:$cleanPhone?body=${Uri.encodeComponent(cleanMsg)}';
    final launched = await _tryLaunchExternalUrl(url);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2563EB),
        content: Text(
          launched
              ? 'SMS app automatically opened for $cleanPhone!'
              : 'SMS text ready! Configure SMS Gateway URL in Settings for background auto-SMS.',
        ),
      ),
    );
  }

  /// Requirement 3: Automatic Customer Bill Dispatch when Mobile Number is entered at Final Billing
  static Future<String> autoDispatchCustomerBill({
    required BuildContext context,
    required String customerPhone,
    required String formattedInvoiceText,
  }) async {
    final digits = customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) return 'Skipped (Enter 10-digit mobile number)';

    final List<String> actionsDone = [];

    // 1. Background HTTP Gateways (if configured, both fire silently in background)
    bool waSentViaApi = false;
    bool smsSentViaApi = false;

    if (autoSendWhatsAppOnBill && whatsappGatewayUrl.trim().isNotEmpty) {
      waSentViaApi = await _sendSilentHttpGateway(
        whatsappGatewayUrl,
        digits,
        formattedInvoiceText,
      );
      if (waSentViaApi) actionsDone.add('WhatsApp Sent (API)');
    }

    if (autoSendSmsOnBill && smsGatewayUrl.trim().isNotEmpty) {
      smsSentViaApi = await _sendSilentHttpGateway(
        smsGatewayUrl,
        digits,
        formattedInvoiceText.replaceAll('*', ''),
      );
      if (smsSentViaApi) actionsDone.add('SMS Sent (API)');
    }

    // WhatsApp does not permit silent/background sending through a wa.me deep link.
    // Automatic delivery requires a configured server-side WhatsApp Business API gateway.
    // Do not open WhatsApp and do not report success when no gateway actually sent it.
    if (autoSendWhatsAppOnBill && !waSentViaApi) {
      actionsDone.add('WhatsApp NOT sent: configure a WhatsApp Business API gateway');
    }

    if (autoSendSmsOnBill && !smsSentViaApi && context.mounted) {
      if (autoSendWhatsAppOnBill && !waSentViaApi) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
      if (context.mounted) {
        await sendSmsMessage(
          context: context,
          phone: digits,
          message: formattedInvoiceText,
        );
        actionsDone.add('SMS Auto-Sent');
      }
    }

    // 3. Auto-Print on Bill if enabled
    if (autoPrintOnBill && context.mounted) {
      await executePrintJob(
        context: context,
        title: 'Customer Invoice',
        receiptText: formattedInvoiceText,
        paperFormat: '80mm Thermal',
      );
      actionsDone.add('Printed');
    }

    return actionsDone.isEmpty ? 'Ready to Share' : actionsDone.join(' • ');
  }

  // ---------------------------------------------------------------------------
  // REQUIREMENT 1: REAL HARDWARE & SYSTEM PRINTER ENGINE
  // 1. Local Loopback HTML Print Spooler (Triggers native OS window.print())
  // 2. Direct Wi-Fi / Network ESC/POS Thermal Printer (Raw TCP Socket on port 9100)
  // 3. Direct Android Bluetooth / USB Thermal Printer via RawBT (rawbt:base64,...)
  // ---------------------------------------------------------------------------
  static List<int> _buildEscPosBytes(String cleanText, {String? barcodeData}) {
    final List<int> bytes = [];
    // ESC @ (Initialize printer)
    bytes.addAll([0x1B, 0x40]);
    // ESC a 0 (Left align default)
    bytes.addAll([0x1B, 0x61, 0x00]);

    final normalized = cleanText
        .replaceAll('₹', 'Rs.')
        .replaceAll('•', '-')
        .replaceAll('★', '*')
        .replaceAll('🧾', '')
        .replaceAll('🙏', '');

    for (final line in normalized.split('\n')) {
      bytes.addAll(utf8.encode('$line\n'));
    }

    // Optional native ESC/POS Code128 Barcode
    if (barcodeData != null && barcodeData.trim().isNotEmpty) {
      final code = barcodeData.trim();
      bytes.addAll([0x1B, 0x61, 0x01]); // Center align
      bytes.addAll([0x1D, 0x68, 0x48]); // Barcode height = 72 dots
      bytes.addAll([0x1D, 0x77, 0x02]); // Barcode width = 2
      bytes.addAll([0x1D, 0x48, 0x02]); // HRI characters below barcode
      final codeBytes = ascii.encode(code);
      bytes.addAll([0x1D, 0x6B, 0x49, codeBytes.length + 2, 0x7B, 0x42, ...codeBytes]);
      bytes.addAll([0x0A, 0x1B, 0x61, 0x00]);
    }

    // Feed 4 lines & Full Cut (GS V 66 0)
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x42, 0x00]);
    return bytes;
  }

  static Future<bool> executePrintJob({
    required BuildContext context,
    required String title,
    required String receiptText,
    required String paperFormat,
    String? barcodeData,
  }) async {
    final cleanText = receiptText.replaceAll('*', '');
    await Clipboard.setData(ClipboardData(text: cleanText));

    // MODE A: Direct Wi-Fi / Ethernet ESC/POS Thermal Printer (TCP Socket 9100)
    if (printerConnectionMode == 'Wi-Fi Thermal IP (Port 9100)' &&
        thermalPrinterIp.trim().isNotEmpty &&
        !kIsWeb) {
      try {
        final socket = await Socket.connect(
          thermalPrinterIp.trim(),
          thermalPrinterPort,
          timeout: const Duration(seconds: 4),
        );
        socket.add(_buildEscPosBytes(cleanText, barcodeData: barcodeData));
        await socket.flush();
        await socket.close();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF059669),
              content: Text(
                '✓ Printed directly to Wi-Fi Thermal Printer ($thermalPrinterIp:$thermalPrinterPort)!',
              ),
            ),
          );
        }
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.orange.shade800,
              content: Text(
                'Direct IP Printer ($thermalPrinterIp) unreachable ($e). Opening System Print Spooler...',
              ),
            ),
          );
        }
      }
    }

    // MODE B: Direct Bluetooth / USB Thermal Printer via Android RawBT Print Service
    if (printerConnectionMode == 'Bluetooth / USB RawBT') {
      final escBytes = _buildEscPosBytes(cleanText, barcodeData: barcodeData);
      final b64 = base64Encode(escBytes);
      final rawBtLaunched = await _tryLaunchExternalUrl('rawbt:base64,$b64');
      if (rawBtLaunched) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF059669),
              content: Text('✓ Sent ESC/POS Print Job to Bluetooth/USB Thermal Printer!'),
            ),
          );
        }
        return true;
      }
    }

    // MODE C1: Native Android/iOS print sheet. The desktop loopback spooler below
    // remains unchanged for Windows/macOS/Linux to preserve existing desktop printing.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final widthMm = paperFormat.contains('58mm') ? 58.0
            : (paperFormat.contains('80mm') ? 80.0
            : (paperFormat.contains('50x25') ? 50.0 : 210.0));
        final pageFormat = PdfPageFormat(
          widthMm * PdfPageFormat.mm,
          (paperFormat.contains('50x25') ? 25.0 : 297.0) * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        );
        final doc = pw.Document();
        doc.addPage(pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Container(
            width: double.infinity,
            child: pw.Text(
              cleanText,
              style: pw.TextStyle(
                font: pw.Font.courier(),
                fontSize: paperFormat.contains('58mm') ? 8 : 9,
                lineSpacing: 2,
              ),
            ),
          ),
        ));
        await Printing.layoutPdf(
          name: title,
          format: pageFormat,
          onLayout: (_) async => doc.save(),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Android print dialog opened. Select your printer to print.')),
          );
        }
        return true;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mobile printing failed: $e')),
          );
        }
        return false;
      }
    }

    // MODE C2 (Desktop): Existing Local Loopback HTML Auto-Print Spooler.
    // Kept for Windows/macOS/Linux; do not remove this path.
    if (!kIsWeb) {
      try {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final int port = server.port;

        final String pageWidthCss = paperFormat.contains('50x25')
            ? '50mm'
            : (paperFormat.contains('58mm')
                ? '58mm'
                : (paperFormat.contains('80mm') ? '80mm' : '190mm'));

        final escapedHtmlText = const HtmlEscape().convert(cleanText);
        final escapedTitle = const HtmlEscape().convert(title);

        final String htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$escapedTitle</title>
  <style>
    @page {
      size: $pageWidthCss auto;
      margin: 3mm;
    }
    body {
      font-family: 'Courier New', Courier, monospace;
      margin: 0;
      padding: 8px;
      background: #f1f5f9;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .no-print {
      margin-bottom: 12px;
      display: flex;
      gap: 10px;
    }
    .btn {
      background: #4338CA;
      color: white;
      border: none;
      padding: 10px 18px;
      border-radius: 8px;
      font-weight: bold;
      cursor: pointer;
      font-size: 14px;
    }
    .print-sheet {
      background: white;
      width: $pageWidthCss;
      max-width: 100%;
      padding: 10px;
      box-sizing: border-box;
      border: 1px dashed #333;
      color: #000;
    }
    pre {
      white-space: pre-wrap;
      word-wrap: break-word;
      margin: 0;
      font-family: 'Courier New', Courier, monospace;
      font-size: ${paperFormat.contains('58mm') ? '11px' : '12.5px'};
      line-height: 1.35;
      font-weight: 600;
    }
    .barcode-box {
      text-align: center;
      margin-top: 6px;
      padding-top: 6px;
      border-top: 1px dotted #000;
    }
    @media print {
      body { background: white; padding: 0; }
      .no-print { display: none !important; }
      .print-sheet { border: none; width: 100%; padding: 0; }
    }
  </style>
</head>
<body>
  <div class="no-print">
    <button class="btn" onclick="window.print()">🖨️ Print Now ($paperFormat)</button>
  </div>
  <div class="print-sheet">
    <pre>$escapedHtmlText</pre>
    ${barcodeData != null && barcodeData.isNotEmpty ? '''
    <div class="barcode-box">
      <svg id="barcode"></svg>
      <div style="font-size:12px;font-weight:bold;letter-spacing:1.5px;margin-top:4px;">*${const HtmlEscape().convert(barcodeData)}*</div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js"></script>
    <script>
      try {
        JsBarcode("#barcode", "${const HtmlEscape().convert(barcodeData)}", {
          format: "CODE128",
          width: 1.7,
          height: 45,
          displayValue: false,
          margin: 2
        });
      } catch(e) {}
    </script>
    ''' : ''}
  </div>
  <script>
    window.onload = function() {
      setTimeout(function() { window.print(); }, 350);
    };
  </script>
</body>
</html>
''';

        server.listen((HttpRequest request) async {
          request.response.headers.contentType = ContentType.html;
          request.response.write(htmlContent);
          await request.response.close();
          Future.delayed(const Duration(seconds: 25), () {
            try {
              server.close(force: true);
            } catch (_) {}
          });
        });

        final printUrl = 'http://127.0.0.1:$port/print';
        final launched = await _tryLaunchExternalUrl(printUrl);
        if (launched) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF059669),
                content: Text('✓ Opening System Print Spooler ($paperFormat)...'),
              ),
            );
          }
          return true;
        }
      } catch (e) {
        debugPrint('Local print spooler error: $e');
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF4338CA),
          content: Text(
            'Receipt formatted! Configure Printer IP in Settings for direct Wi-Fi thermal printing.',
          ),
        ),
      );
    }
    return false;
  }

  /// Dialog to configure Automatic Customer SMS/WhatsApp & Thermal Printer IP
  static void showAutoMessagingAndPrinterSettingsDialog(BuildContext context) {
    final ipCtrl = TextEditingController(text: thermalPrinterIp);
    final portCtrl = TextEditingController(text: thermalPrinterPort.toString());
    final smsApiCtrl = TextEditingController(text: smsGatewayUrl);
    final waApiCtrl = TextEditingController(text: whatsappGatewayUrl);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.settings_suggest_rounded, color: Color(0xFF4338CA)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Printer & Auto-Message Setup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Thermal & System Printer Connection',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF4338CA),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: printerConnectionMode,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Printer Mode',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'System Print (USB / Wi-Fi / PDF)',
                        child: Text(
                          'System Print Dialog (USB / Wi-Fi / A4 / Thermal)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Wi-Fi Thermal IP (Port 9100)',
                        child: Text(
                          'Direct Wi-Fi / LAN Thermal Printer (ESC/POS IP)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Bluetooth / USB RawBT',
                        child: Text(
                          'Android Bluetooth / USB Thermal (RawBT)',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => printerConnectionMode = v);
                    },
                  ),
                  if (printerConnectionMode == 'Wi-Fi Thermal IP (Port 9100)') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: ipCtrl,
                            decoration: InputDecoration(
                              labelText: 'Thermal Printer IP',
                              hintText: 'e.g. 192.168.1.200',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: portCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Port',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Auto-Print Receipt on Sale Confirmation',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    value: autoPrintOnBill,
                    onChanged: (v) => setModalState(() => autoPrintOnBill = v),
                  ),
                  const Divider(height: 18),
                  const Text(
                    '2. Automatic Customer WhatsApp & SMS on Billing',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Auto-Send WhatsApp Bill to Customer Mobile',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Automatically sends/launches WhatsApp when mobile no. is billed',
                      style: TextStyle(fontSize: 10),
                    ),
                    value: autoSendWhatsAppOnBill,
                    activeColor: const Color(0xFF059669),
                    onChanged: (v) => setModalState(() => autoSendWhatsAppOnBill = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Auto-Send Text SMS Bill to Customer Mobile',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Automatically sends/launches SMS when mobile no. is billed',
                      style: TextStyle(fontSize: 10),
                    ),
                    value: autoSendSmsOnBill,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (v) => setModalState(() => autoSendSmsOnBill = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: waApiCtrl,
                    decoration: InputDecoration(
                      labelText: 'Optional: Silent WhatsApp Gateway URL',
                      hintText: 'https://api.ultramsg.com/...?to={phone}&body={message}',
                      helperText: 'Use {phone} & {message} for 100% background auto-send',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: smsApiCtrl,
                    decoration: InputDecoration(
                      labelText: 'Optional: Silent SMS Gateway URL (Fast2SMS / Webhook)',
                      hintText: 'https://www.fast2sms.com/dev/bulkV2?...&numbers={phone}&message={message}',
                      helperText: 'Use {phone} & {message} for 100% background auto-SMS',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
              onPressed: () {
                thermalPrinterIp = ipCtrl.text.trim();
                thermalPrinterPort = int.tryParse(portCtrl.text.trim()) ?? 9100;
                smsGatewayUrl = smsApiCtrl.text.trim();
                whatsappGatewayUrl = waApiCtrl.text.trim();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF059669),
                    content: Text('Printer & Auto-Message settings saved!'),
                  ),
                );
              },
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  static String buildInvoiceText({
    required String invoiceId,
    required String customerName,
    required String customerPhone,
    required List<Map<String, dynamic>> lineItems,
    required num subtotalAmount,
    required num discountAmount,
    required num finalAmount,
    required num paidAmount,
    required num dueAmount,
    required String paymentMode,
    required String warrantyPeriod,
    required String notes,
    required DateTime date,
  }) {
    final shop = ShopConfig.current;
    final sb = StringBuffer();
    sb.writeln('🧾 *${shop.shopName.toUpperCase()}*');
    sb.writeln('${shop.shopAddress} (${shop.branchName})');
    if (shop.shopPhone.isNotEmpty) sb.writeln('Contact: ${shop.shopPhone}');
    sb.writeln('--------------------------------');
    sb.writeln('Invoice: #INV-$invoiceId');
    sb.writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(date)}');
    sb.writeln('Customer: $customerName ($customerPhone)');
    sb.writeln('--------------------------------');
    for (int i = 0; i < lineItems.length; i++) {
      final item = lineItems[i];
      final name = (item['itemName'] ?? 'Item').toString();
      final specs = (item['specs'] ?? '').toString();
      final imei1 = (item['imei1'] ?? '').toString();
      final imei2 = (item['imei2'] ?? '').toString();
      final qty = item['quantity'] ?? 1;
      final unitPrice = (item['unitPrice'] as num?) ?? 0;
      final lineTotal = (item['lineTotal'] as num?) ?? (unitPrice * qty);

      sb.writeln('${i + 1}. *$name* ${specs.isNotEmpty ? "($specs)" : ""}');
      sb.writeln('   Qty: $qty × ₹${unitPrice.toStringAsFixed(0)} = ₹${lineTotal.toStringAsFixed(0)}');
      if (imei1.isNotEmpty) sb.writeln('   IMEI 1/SKU: $imei1');
      if (imei2.trim().isNotEmpty) sb.writeln('   IMEI 2: $imei2');
    }
    sb.writeln('--------------------------------');
    sb.writeln('Subtotal: ₹${subtotalAmount.toStringAsFixed(0)}');
    if (discountAmount > 0) {
      sb.writeln('Special Discount: -₹${discountAmount.toStringAsFixed(0)}');
    }
    sb.writeln('*Net Bill Payable: ₹${finalAmount.toStringAsFixed(0)}*');
    sb.writeln('Paid ($paymentMode): ₹${paidAmount.toStringAsFixed(0)}');
    if (dueAmount > 0) {
      sb.writeln('*BALANCE DUE (UDHAAR): ₹${dueAmount.toStringAsFixed(0)}*');
    }
    sb.writeln('Warranty: $warrantyPeriod');
    if (notes.trim().isNotEmpty) sb.writeln('Note: $notes');
    sb.writeln('--------------------------------');
    sb.writeln('Thank you for shopping at ${shop.shopName}! 🙏');
    return sb.toString();
  }

  /// Requirement 1: Interactive Print Preview & Real Printer Execution Dialog
  static Future<void> printReceiptDialog({
    required BuildContext context,
    required String title,
    required String receiptText,
    String? customerPhone,
    String? barcodeData,
  }) async {
    await Clipboard.setData(ClipboardData(text: receiptText.replaceAll('*', '')));
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        String paperFormat = '80mm Thermal';
        bool isPrinting = false;
        return StatefulBuilder(
          builder: (context, setPrintState) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                const Icon(Icons.print_rounded, color: Color(0xFF4338CA)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Printer Settings',
                  icon: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF4338CA)),
                  onPressed: () => showAutoMessagingAndPrinterSettingsDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: ['58mm Thermal', '80mm Thermal', 'A4 Tax Invoice'].map((fmt) {
                        final selected = paperFormat == fmt;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(fmt, style: const TextStyle(fontSize: 10)),
                            selected: selected,
                            onSelected: (_) => setPrintState(() => paperFormat = fmt),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mode: $printerConnectionMode${thermalPrinterIp.isNotEmpty ? " ($thermalPrinterIp)" : ""}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF4338CA),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: paperFormat == '58mm Thermal'
                          ? 250
                          : (paperFormat == '80mm Thermal' ? 320 : 400),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFEF7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black87, width: 1.2),
                      ),
                      child: SelectableText(
                        receiptText.replaceAll('*', ''),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (customerPhone != null && customerPhone.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    sendWhatsAppMessage(
                      context: context,
                      phone: customerPhone,
                      message: receiptText,
                    );
                  },
                  icon: const Icon(Icons.chat_rounded, size: 15, color: Color(0xFF059669)),
                  label: const Text('WhatsApp', style: TextStyle(fontSize: 11)),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
                onPressed: isPrinting
                    ? null
                    : () async {
                        setPrintState(() => isPrinting = true);
                        await executePrintJob(
                          context: context,
                          title: title,
                          receiptText: receiptText,
                          paperFormat: paperFormat,
                          barcodeData: barcodeData,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                icon: isPrinting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.print, size: 16),
                label: Text(
                  isPrinting ? 'Sending to Printer...' : 'Print Now ($paperFormat)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<String?> openCameraScanner(
    BuildContext context, {
    String title = 'Scan QR Code / Barcode / IMEI',
  }) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _CameraScannerDialog(title: title),
    );
  }

  static void showFullInvoiceDialog({
    required BuildContext context,
    required String invoiceId,
    required String customerName,
    required String customerPhone,
    required List<Map<String, dynamic>> lineItems,
    required num subtotalAmount,
    required num discountAmount,
    required num finalAmount,
    required num paidAmount,
    required num dueAmount,
    required num cashPaid,
    required num onlinePaid,
    required String paymentMode,
    required String paymentStatus,
    required String warrantyPeriod,
    required String notes,
    required DateTime date,
    num? totalProfit,
    num? totalCost,
    String? autoDispatchStatus,
  }) {
    final shop = ShopConfig.current;
    bool showOwnerProfit = false;

    final formattedText = buildInvoiceText(
      invoiceId: invoiceId,
      customerName: customerName,
      customerPhone: customerPhone,
      lineItems: lineItems,
      subtotalAmount: subtotalAmount,
      discountAmount: discountAmount,
      finalAmount: finalAmount,
      paidAmount: paidAmount,
      dueAmount: dueAmount,
      paymentMode: paymentMode,
      warrantyPeriod: warrantyPeriod,
      notes: notes,
      date: date,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.all(20),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: dueAmount > 0
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              dueAmount > 0
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle_rounded,
                              color: dueAmount > 0
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF059669),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dueAmount > 0
                                  ? 'Udhaar Bill (₹${dueAmount.toStringAsFixed(0)} Due)'
                                  : 'Tax Invoice (Full Paid)',
                              style: TextStyle(
                                color: dueAmount > 0
                                    ? const Color(0xFF991B1B)
                                    : const Color(0xFF065F46),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          if (totalProfit != null && shop.canSeeProfit)
                            IconButton(
                              tooltip: 'Owner Only: Toggle Secret Profit View',
                              icon: Icon(
                                showOwnerProfit
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_outlined,
                                color: showOwnerProfit
                                    ? const Color(0xFF059669)
                                    : Colors.grey,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setModalState(() => showOwnerProfit = !showOwnerProfit),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.grey),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (autoDispatchStatus != null && autoDispatchStatus.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mark_chat_read_rounded,
                            size: 15,
                            color: Color(0xFF4338CA),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Auto-Sent ($customerPhone): $autoDispatchStatus',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4338CA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (showOwnerProfit && totalProfit != null && shop.canSeeProfit) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Owner View • Cost: ₹${(totalCost ?? 0).toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF065F46)),
                          ),
                          Text(
                            'Net Bill Profit: ${totalProfit >= 0 ? "+" : ""}₹${totalProfit.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              Text(
                                shop.shopName.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF1E1B4B),
                                ),
                              ),
                              Text(
                                '${shop.shopAddress} • ${shop.branchName}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              if (shop.shopPhone.isNotEmpty)
                                Text(
                                  'Contact: ${shop.shopPhone}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                'Invoice #: INV-$invoiceId | ${DateFormat('dd MMM yyyy, hh:mm a').format(date)}',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Customer: $customerName',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              'Mob: $customerPhone',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'BILLED ITEMS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...lineItems.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final item = entry.value;
                          final name = item['itemName'] ?? 'Item';
                          final specs = (item['specs'] ?? '').toString();
                          final imei1 = (item['imei1'] ?? '').toString();
                          final imei2 = (item['imei2'] ?? '').toString();
                          final qty = item['quantity'] ?? 1;
                          final unitPrice = item['unitPrice'] ?? 0;
                          final lineTotal = item['lineTotal'] ?? (unitPrice * qty);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$idx. $name',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '₹${lineTotal.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: Color(0xFF1E1B4B),
                                      ),
                                    ),
                                  ],
                                ),
                                if (specs.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Specs: $specs',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF4338CA),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 3),
                                Text(
                                  'Qty: $qty × ₹${unitPrice.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                if (imei1.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.verified_outlined,
                                        size: 13,
                                        color: Color(0xFF4338CA),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'IMEI 1 / SKU: $imei1',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (imei2.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.sim_card_outlined,
                                        size: 13,
                                        color: Color(0xFF059669),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'IMEI 2: $imei2',
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Subtotal (Original Price):',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Text(
                              '₹${subtotalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Special Discount Given:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF059669),
                              ),
                            ),
                            Text(
                              discountAmount > 0
                                  ? '-₹${discountAmount.toStringAsFixed(0)}'
                                  : '₹0',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Net Bill Payable:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              '₹${finalAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Color(0xFF1E1B4B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Amount Received:',
                              style: TextStyle(fontSize: 12, color: Color(0xFF059669)),
                            ),
                            Text(
                              '₹${paidAmount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                        if (dueAmount > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'BALANCE DUE (UDHAAR):',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                Text(
                                  '₹${dueAmount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Payment Mode:',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$paymentMode ($paymentStatus)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4338CA),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Warranty Status:',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: warrantyPeriod.toLowerCase().contains('no ')
                                    ? Colors.grey.shade200
                                    : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                warrantyPeriod.isEmpty ? 'No Warranty' : warrantyPeriod,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: warrantyPeriod.toLowerCase().contains('no ')
                                      ? Colors.grey.shade700
                                      : const Color(0xFF065F46),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Note: $notes',
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                        onPressed: () {
                          sendWhatsAppMessage(
                            context: context,
                            phone: customerPhone,
                            message: formattedText,
                          );
                        },
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: const Text('WhatsApp Bill', style: TextStyle(fontSize: 12)),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                        onPressed: () {
                          sendSmsMessage(
                            context: context,
                            phone: customerPhone,
                            message: formattedText,
                          );
                        },
                        icon: const Icon(Icons.sms_rounded, size: 16),
                        label: const Text('SMS Bill', style: TextStyle(fontSize: 12)),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          printReceiptDialog(
                            context: context,
                            title: 'Print Invoice #INV-$invoiceId',
                            receiptText: formattedText,
                            customerPhone: customerPhone,
                          );
                        },
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text('Print Bill', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraScannerDialog extends StatefulWidget {
  final String title;
  const _CameraScannerDialog({required this.title});

  @override
  State<_CameraScannerDialog> createState() => _CameraScannerDialogState();
}

class _CameraScannerDialogState extends State<_CameraScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF1E1B4B),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 20),
                    tooltip: 'Toggle Flash',
                    onPressed: () => _controller.toggleTorch(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 20),
                    tooltip: 'Switch Camera',
                    onPressed: () => _controller.switchCamera(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      if (_hasScanned) return;
                      for (final barcode in capture.barcodes) {
                        final raw = barcode.rawValue?.trim();
                        if (raw != null && raw.isNotEmpty) {
                          _hasScanned = true;
                          Navigator.pop(context, raw);
                          break;
                        }
                      }
                    },
                  ),
                  Container(
                    width: 240,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF818CF8), width: 2.5),
                      borderRadius: BorderRadius.circular(16),
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