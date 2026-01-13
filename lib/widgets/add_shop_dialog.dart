import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/shop_provider.dart';
import '../models/shop_model.dart';
import '../services/opendatalab_service.dart';

/// Шинэ байгууллага/дэлгүүр нэмэх dialog
class AddShopDialog extends StatefulWidget {
  final Function(String)? onShopAdded;

  const AddShopDialog({
    super.key,
    this.onShopAdded,
  });

  @override
  State<AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends State<AddShopDialog> {
  final _formKey = GlobalKey<FormState>();
  final _shopRegistrationNumberController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _shopAddressController = TextEditingController();
  final _shopPhoneController = TextEditingController();
  final _shopEmailController = TextEditingController();
  
  bool _isCheckingShopRegistration = false;
  Map<String, dynamic>? _shopRegistrationInfo;
  String? _shopRegistrationError;
  
  final _opendatalabService = OpendatalabService();

  @override
  void dispose() {
    _shopRegistrationNumberController.dispose();
    _shopNameController.dispose();
    _shopAddressController.dispose();
    _shopPhoneController.dispose();
    _shopEmailController.dispose();
    super.dispose();
  }

  Future<void> _searchOrganization() async {
    if (_shopRegistrationNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Бүртгэлийн дугаар оруулна уу'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isCheckingShopRegistration = true;
      _shopRegistrationInfo = null;
      _shopRegistrationError = null;
    });
    
    final registrationResult = await _opendatalabService.searchOrganization(
      _shopRegistrationNumberController.text.trim(),
    );
    
    setState(() {
      _isCheckingShopRegistration = false;
      if (registrationResult != null) {
        // Network алдаа эсвэл бусад алдаа эсэхийг шалгах
        if (registrationResult.containsKey('error')) {
          // Network алдаа эсвэл бусад алдаа
          _shopRegistrationError = registrationResult['message'] ?? 'Алдаа гарлаа. Гараар мэдээлэл оруулж болно.';
          _shopRegistrationInfo = null;
        } else {
          // Амжилттай мэдээлэл олдсон
          _shopRegistrationInfo = registrationResult;
          _shopRegistrationError = null;
          _shopNameController.text = registrationResult['name'] ?? '';
          _shopAddressController.text = registrationResult['address'] ?? '';
          _shopPhoneController.text = registrationResult['phone'] ?? '';
          _shopEmailController.text = registrationResult['email'] ?? '';
        }
      } else {
        _shopRegistrationError = 'API-аас мэдээлэл олдсонгүй. Гараар мэдээлэл оруулж болно.';
        _shopRegistrationInfo = null;
      }
    });
  }

  Future<void> _openOpendatalabWebsite() async {
    final registrationNumber = _shopRegistrationNumberController.text.trim();
    final url = registrationNumber.isNotEmpty
        ? Uri.parse('https://opendatalab.mn/?q=$registrationNumber')
        : Uri.parse('https://opendatalab.mn');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вэбсайт нээх боломжгүй байна'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _addShop() {
    if (_shopNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Байгууллагын нэр оруулна уу'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    
    final newShop = Shop(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _shopNameController.text.trim(),
      address: _shopAddressController.text.trim(),
      latitude: 47.9200, // Default coordinates - бодит координат ашиглах хэрэгтэй
      longitude: 106.9200,
      phone: _shopPhoneController.text.trim(),
      email: _shopEmailController.text.trim().isNotEmpty
          ? _shopEmailController.text.trim()
          : null,
      registrationNumber: _shopRegistrationNumberController.text.trim().isNotEmpty
          ? _shopRegistrationNumberController.text.trim()
          : null,
      status: 'active',
      orders: [],
      sales: [],
      lastVisit: DateTime.now(),
    );
    
    shopProvider.addShop(newShop);
    
    if (widget.onShopAdded != null) {
      widget.onShopAdded!(newShop.name);
    }
    
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Шинэ байгууллага нэмэх'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // API-аас мэдээлэл хайх хэсэг
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF3B82F6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFF3B82F6), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'API-аас мэдээлэл хайх',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'opendatalab.mn-аас байгууллагын мэдээлэл автоматаар татаж авах',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopRegistrationNumberController,
                decoration: const InputDecoration(
                  labelText: 'Бүртгэлийн дугаар',
                  hintText: 'Бүртгэлийн дугаар оруулна уу',
                  prefixIcon: Icon(Icons.badge, color: Color(0xFF3B82F6)),
                  helperText: 'opendatalab.mn-аас мэдээлэл авах эсвэл гараар оруулах',
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3B82F6), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopNameController,
                decoration: const InputDecoration(
                  labelText: 'Байгууллагын нэр *',
                  hintText: 'Байгууллагын нэр оруулна уу',
                  prefixIcon: Icon(Icons.business),
                  helperText: 'API-аас ирсэн эсвэл гараар оруулсан байгууллагын нэр',
                ),
                enabled: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Байгууллагын нэр оруулна уу';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopAddressController,
                decoration: const InputDecoration(
                  labelText: 'Хаяг',
                  hintText: 'Хаяг оруулна уу',
                  prefixIcon: Icon(Icons.location_on),
                ),
                enabled: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Утас',
                  hintText: 'Утасны дугаар оруулна уу',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                enabled: true,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopEmailController,
                decoration: const InputDecoration(
                  labelText: 'Имэйл (сонголттой)',
                  hintText: 'Имэйл хаяг оруулна уу',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: true,
              ),
              if (_isCheckingShopRegistration) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'opendatalab.mn API-аас мэдээлэл хайж байна...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Бүртгэлийн дугаар: ${_shopRegistrationNumberController.text.trim()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
              if (_shopRegistrationInfo != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF10B981),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF10B981)),
                          SizedBox(width: 8),
                          Text(
                            'Бүртгэл олдсон',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_shopRegistrationInfo!['type'] != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_shopRegistrationInfo!['type'] == 'Дэлгүүр' || _shopRegistrationInfo!['type'].toString().toLowerCase() == 'дэлгүүр')
                                ? const Color(0xFF3B82F6).withOpacity(0.1)
                                : const Color(0xFF10B981).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_shopRegistrationInfo!['type'] == 'Дэлгүүр' || _shopRegistrationInfo!['type'].toString().toLowerCase() == 'дэлгүүр')
                                  ? const Color(0xFF3B82F6)
                                  : const Color(0xFF10B981),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_shopRegistrationInfo!['type'] == 'Дэлгүүр' || _shopRegistrationInfo!['type'].toString().toLowerCase() == 'дэлгүүр')
                                    ? Icons.store
                                    : Icons.business,
                                size: 16,
                                color: (_shopRegistrationInfo!['type'] == 'Дэлгүүр' || _shopRegistrationInfo!['type'].toString().toLowerCase() == 'дэлгүүр')
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _shopRegistrationInfo!['type'] ?? 'Байгууллага',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (_shopRegistrationInfo!['type'] == 'Дэлгүүр' || _shopRegistrationInfo!['type'].toString().toLowerCase() == 'дэлгүүр')
                                      ? const Color(0xFF3B82F6)
                                      : const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        'Бүртгэлтэй байгууллагын нэр:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _shopRegistrationInfo!['name'] ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text('Бүртгэлийн дугаар: ${_shopRegistrationInfo!['registrationNumber'] ?? 'N/A'}'),
                      const SizedBox(height: 4),
                      Text('Хаяг: ${_shopRegistrationInfo!['address'] ?? 'N/A'}'),
                      const SizedBox(height: 4),
                      Text('Утас: ${_shopRegistrationInfo!['phone'] ?? 'N/A'}'),
                    ],
                  ),
                ),
              ],
              if (_shopRegistrationError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi_off, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _shopRegistrationError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Интернэт холболт салсан тохиолдолд гараар мэдээлэл оруулж болно. Дээрх талбаруудыг бөглөнө үү.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Цуцлах'),
        ),
        TextButton.icon(
          onPressed: _openOpendatalabWebsite,
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('opendatalab.mn'),
        ),
        ElevatedButton.icon(
          onPressed: _isCheckingShopRegistration ? null : _searchOrganization,
          icon: const Icon(Icons.search, size: 18),
          label: const Text('API-аас хайх'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              _addShop();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
          ),
          child: const Text('Нэмэх'),
        ),
      ],
    );
  }
}

