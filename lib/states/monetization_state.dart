import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MonetizationState extends ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  final String _proProductId = 'win11_pro_upgrade';

  bool _isPro = false;
  bool get isPro => _isPro;

  bool _isStoreAvailable = false;
  bool get isStoreAvailable => _isStoreAvailable;

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  bool _isPurchasePending = false;
  bool get isPurchasePending => _isPurchasePending;

  MonetizationState() {
    _initOfflineState();
    _initializeStore();
  }

  @override
  void dispose() {
    _purchaseSubscription.cancel();
    super.dispose();
  }

  Future<void> _initOfflineState() async {
    const storage = FlutterSecureStorage();
    final proStatus = await storage.read(key: 'is_pro_user');
    _isPro = proStatus == 'true';
    notifyListeners();
  }

  void _initializeStore() {
    final purchaseUpdated = _iap.purchaseStream;
    _purchaseSubscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSubscription.cancel(),
      onError: (error) {
        debugPrint("Purchase stream error: $error");
      },
    );
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    _isStoreAvailable = await _iap.isAvailable();
    if (!_isStoreAvailable) {
      notifyListeners();
      return;
    }

    final ProductDetailsResponse response = await _iap.queryProductDetails({_proProductId});
    if (response.error == null) {
      _products = response.productDetails;
    }
    notifyListeners();
  }

  Future<void> buyProUpgrade() async {
    if (_products.isEmpty) return;
    
    final targetProduct = _products.firstWhere((p) => p.id == _proProductId);
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: targetProduct);
    
    _isPurchasePending = true;
    notifyListeners();
    
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    _isPurchasePending = true;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _isPurchasePending = true;
      } else {
        try {
          if (purchaseDetails.status == PurchaseStatus.error) {
            debugPrint("Purchase error: ${purchaseDetails.error}");
          } else if (purchaseDetails.status == PurchaseStatus.purchased || 
                     purchaseDetails.status == PurchaseStatus.restored) {
            
            await _deliverPremiumContent(purchaseDetails);
            
            if (purchaseDetails.pendingCompletePurchase) {
              await _iap.completePurchase(purchaseDetails);
            }
          }
        } catch (e) {
           debugPrint("Premium delivery failed, purchase will not be acknowledged: $e");
        } finally {
          _isPurchasePending = false;
        }
      }
    }
    notifyListeners();
  }

  Future<void> _deliverPremiumContent(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.productID == _proProductId) {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'is_pro_user', value: 'true');
      _isPro = true;
      notifyListeners();
    }
  }
}