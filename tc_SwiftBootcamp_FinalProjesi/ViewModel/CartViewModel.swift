import Foundation
import RxSwift
import RxRelay

final class CartViewModel {
    // Singleton (tekil) örnek için static değişken
    static let shared = CartViewModel()
    
    private let disposeBag = DisposeBag()
    private let apiService = APIService.shared
    
    // Yerel sepet verilerini saklayacak BehaviorRelay
    private let cartItemsRelay = BehaviorRelay<[CartItem]>(value: [])
    
    // API ile senkronizasyon durumu
    private var isSyncingWithAPI = false
    private var pendingSync = false
    
    // Zamanlayıcı ve kuyruk için değişkenler
    private var syncTimer: Timer?
    private var lastSyncTime: Date?
    private let minSyncInterval: TimeInterval = 2.0 // Senkronizasyon aralığı
    
    // Sepet öğeleri için getter/setter
    private(set) var cartItems: [CartItem] = [] {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("CartViewModel.cartItemsChanged"), object: nil)
            // Relay'i de güncelle
            cartItemsRelay.accept(cartItems)
        }
    }
    
    var isLoading = false {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("CartViewModel.isLoadingChanged"), object: nil)
        }
    }
    
    var errorMessage: String? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("CartViewModel.errorMessageChanged"), object: nil)
        }
    }
    
    // Toplam tutarı hesapla
    var totalAmount: Int {
        return cartItems.reduce(0) { $0 + ($1.fiyat * $1.siparisAdeti) }
    }
    
    // Formatlı toplam tutar (₺ sembolü ile)
    var formattedTotalAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.currencySymbol = "₺"
        
        if let formattedString = formatter.string(from: NSNumber(value: totalAmount)) {
            return formattedString
        } else {
            return "\(totalAmount) ₺"
        }
    }
    
    // Toplam ürün sayısı
    var totalItemCount: Int {
        return cartItems.reduce(0) { $0 + $1.siparisAdeti }
    }
    
    // Private initializer for singleton
    private init() {
        // Sepet değişikliklerini dinle
        cartItemsRelay.skip(1).subscribe(onNext: { [weak self] items in
            self?.scheduleSyncWithAPI()
        }).disposed(by: disposeBag)
        
        // Başlangıçta sepeti yükle
        loadInitialCart()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    // Başlangıç sepetini yükle
    private func loadInitialCart() {
        isLoading = true
        
        // API'den sepeti getir, hataları sessizce yönet
        apiService.fetchCartItems()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] items in
                guard let self = self else { return }
                self.cartItems = items
                self.isLoading = false
                
                // İlk yükleme tamamlandığında senkronizasyon bayrağını sıfırla
                self.isSyncingWithAPI = false
            }, onError: { [weak self] error in
                guard let self = self else { return }
                // Hataları sessizce yönet, boş sepet göster
                self.cartItems = []
                self.isLoading = false
                self.isSyncingWithAPI = false
            })
            .disposed(by: disposeBag)
    }
    
    // Sepeti API ile senkronize etmek için zamanlayıcı kur
    private func scheduleSyncWithAPI() {
        // Zamanlayıcıyı geçersiz kıl
        syncTimer?.invalidate()
        
        // Senkronizasyon beklemede olarak işaretle
        pendingSync = true
        
        // Senkronizasyon zamanlayıcısını kur
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.syncCartWithAPI()
        }
    }
    
    // Sepeti API ile senkronize et
    private func syncCartWithAPI() {
        // Eğer zaten senkronizasyon yapılıyorsa veya son senkronizasyondan beri çok kısa süre geçtiyse çık
        if isSyncingWithAPI || !shouldSync() {
            return
        }
        
        isSyncingWithAPI = true
        pendingSync = false
        lastSyncTime = Date()
        
        // API ile sepeti senkronize et
        // Önce mevcut sepeti al, sonra eksikleri ekle/güncelle
        apiService.fetchCartItems()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] serverItems in
                guard let self = self else { return }
                
                // Yerel sepet öğelerini API'den dönen öğelerle karşılaştır
                let localItems = self.cartItems
                
                // Senkronizasyon algoritması
                var updatedCart = localItems
                
                // API'de olup yerel sepette olmayan öğeleri ekle
                for serverItem in serverItems {
                    if !localItems.contains(where: { $0.sepetId == serverItem.sepetId }) {
                        // Yerel sepete ekle
                        updatedCart.append(serverItem)
                    }
                }
                
                // Yerel sepette olup API'de olmayan öğeleri API'ye ekle veya kaldır
                for (index, localItem) in localItems.enumerated().reversed() {
                    // Geçici ID'ler için kontrol (yerel eklenen öğeler için)
                    if localItem.sepetId >= 10000 && localItem.sepetId <= 99999 {
                        // Kampanya paketi kontrolü - eğer kampanya paketiyse sunucuya yükleme
                        if localItem.isPromotionPackage {
                            continue
                        }
                        
                        // Sunucuya ekle
                        self.addLocalItemToServer(localItem)
                    } else if !serverItems.contains(where: { $0.sepetId == localItem.sepetId }) {
                        // Server'dan silinmiş bir öğe, yerel sepetten de kaldır
                        updatedCart.remove(at: index)
                    }
                }
                
                // Sepeti güncelle
                if updatedCart != self.cartItems {
                    self.cartItems = updatedCart
                }
                
                self.isSyncingWithAPI = false
                
                // Eğer bekleyen bir senkronizasyon varsa tekrar çalıştır
                if self.pendingSync {
                    self.syncCartWithAPI()
                }
            }, onError: { [weak self] error in
                // Hataları sessizce yönet
                self?.isSyncingWithAPI = false
            })
            .disposed(by: disposeBag)
    }
    
    // Yerel öğeyi sunucuya ekle
    private func addLocalItemToServer(_ localItem: CartItem) {
        // Kampanya paketi kontrolü - eğer kampanya paketiyse sunucuya yükleme
        if localItem.isPromotionPackage {
            return
        }
        
        // CartItem'dan Product oluştur
        let product = Product(
            id: 0,
            ad: localItem.ad,
            resim: localItem.resim,
            kategori: localItem.kategori,
            fiyat: localItem.fiyat,
            marka: localItem.marka
        )
        
        // Sunucuya ekle
        apiService.addToCart(product: product, quantity: localItem.siparisAdeti)
            .subscribe(onNext: { success in
            }, onError: { error in
            })
            .disposed(by: disposeBag)
    }
    
    // Senkronizasyon yapılmalı mı?
    private func shouldSync() -> Bool {
        guard let lastSync = lastSyncTime else {
            return true
        }
        
        return Date().timeIntervalSince(lastSync) >= minSyncInterval
    }
    
    // Sepete ürün ekle - tamamen yerel olarak çalışan versiyon
    func addToCart(product: Product, quantity: Int) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Sepette benzer ürün var mı kontrol et
            let existingItemIndex = self.cartItems.firstIndex { $0.ad == product.ad && $0.marka == product.marka }
            
            if let index = existingItemIndex {
                // Var olan ürünün miktarını artır
                let existingItem = self.cartItems[index]
                let updatedQuantity = existingItem.siparisAdeti + quantity
                
                let newCartItem = NewCartItem(
                    sepetId: existingItem.sepetId,
                    ad: existingItem.ad,
                    resim: existingItem.resim,
                    kategori: existingItem.kategori,
                    fiyat: existingItem.fiyat,
                    marka: existingItem.marka,
                    siparisAdeti: updatedQuantity,
                    kullaniciAdi: existingItem.kullaniciAdi
                )
                
                // Geçici bir CartItem nesnesi oluşturalım
                guard let tempCartItem = newCartItem.toCartItem() else {
                    observer.onNext(false)
                    observer.onCompleted()
                    return Disposables.create()
                }
                
                // Sepet listesini güncelleyelim
                var updatedCart = self.cartItems
                updatedCart[index] = tempCartItem
                self.cartItems = updatedCart
            } else {
                // Yeni ürün ekleyelim
                let newCartItem = NewCartItem(
                    sepetId: Int.random(in: 10000...99999), // Geçici bir ID
                    ad: product.ad,
                    resim: product.resim,
                    kategori: product.kategori,
                    fiyat: product.fiyat,
                    marka: product.marka,
                    siparisAdeti: quantity,
                    kullaniciAdi: self.apiService.username
                )
                
                // Geçici CartItem'ı oluştur
                guard let tempCartItem = newCartItem.toCartItem() else {
                    observer.onNext(false)
                    observer.onCompleted()
                    return Disposables.create()
                }
                
                // Sepete ekle
                var updatedCart = self.cartItems
                updatedCart.append(tempCartItem)
                self.cartItems = updatedCart
            }
            
            // İşlem başarılı
            observer.onNext(true)
            observer.onCompleted()
            
            return Disposables.create()
        }
    }
    
    // Sepetten ürün sil - tamamen yerel olarak çalışan versiyon
    func removeFromCart(cartItem: CartItem) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Önce yerel olarak sepetten kaldır
            var updatedCart = self.cartItems
            updatedCart.removeAll { $0.sepetId == cartItem.sepetId }
            self.cartItems = updatedCart
            
            // Eğer geçici bir ID değilse (gerçek sunucu ID'si ise) veya kampanya paketi değilse, API'den de kaldır
            if (cartItem.sepetId < 10000 || cartItem.sepetId > 99999) && !cartItem.isPromotionPackage {
                // API'den silme işlemini başlat ama sonucu bekleme
                self.apiService.removeFromCart(cartItem: cartItem)
                    .subscribe(onNext: { success in
                    }, onError: { error in
                    })
                    .disposed(by: self.disposeBag)
            } else {
                print("⏩ Skipping server removal for local or promotion item: \(cartItem.ad)")
            }
            
            // İşlem başarılı
            observer.onNext(true)
            observer.onCompleted()
            
            return Disposables.create()
        }
    }
    
    // Sepetten belirli miktarda ürün sil - tamamen yerel olarak çalışan versiyon
    func removeFromCart(cartItem: CartItem, quantity: Int) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Mevcut ürünün indeksini bul
            guard let index = self.cartItems.firstIndex(where: { $0.sepetId == cartItem.sepetId }) else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            let existingItem = self.cartItems[index]
            
            // Kalan miktar hesapla
            let remainingQuantity = existingItem.siparisAdeti - quantity
            
            var updatedCart = self.cartItems
            
            if remainingQuantity <= 0 {
                // Miktar 0 veya negatif ise ürünü tamamen kaldır
                updatedCart.remove(at: index)
                
                // Eğer geçici bir ID değilse (gerçek sunucu ID'si ise) veya kampanya paketi değilse, API'den de kaldır
                if (existingItem.sepetId < 10000 || existingItem.sepetId > 99999) && !existingItem.isPromotionPackage {
                    // API'den silme işlemini başlat ama sonucu bekleme
                    self.apiService.removeFromCart(cartItem: existingItem)
                        .subscribe(onNext: { success in
                        }, onError: { error in
                        })
                        .disposed(by: self.disposeBag)
                }
            } else {
                // Miktar pozitif ise, güncellenmiş miktarla yeni bir CartItem oluştur
                let updatedItem = CartItem(
                    sepetId: existingItem.sepetId,
                    ad: existingItem.ad,
                    resim: existingItem.resim,
                    kategori: existingItem.kategori,
                    fiyat: existingItem.fiyat,
                    marka: existingItem.marka,
                    siparisAdeti: remainingQuantity,
                    kullaniciAdi: existingItem.kullaniciAdi,
                    isPromotionPackage: existingItem.isPromotionPackage,
                    packageDescription: existingItem.packageDescription
                )
                
                // Güncellenmiş ürünü listeye ekle
                updatedCart[index] = updatedItem
                
                // API'de de güncelle (eğer gerçek bir sunucu kaydıysa)
                if (existingItem.sepetId < 10000 || existingItem.sepetId > 99999) && !existingItem.isPromotionPackage {
                    // Burada API'de adet güncelleme işlemi yapılabilir
                    // Not: Mevcut API işlevinde bu özellik yoksa yoksayılabilir
                }
            }
            
            // Sepeti güncelle
            self.cartItems = updatedCart
            
            // İşlem başarılı
            observer.onNext(true)
            observer.onCompleted()
            
            return Disposables.create()
        }
    }
    
    // Sepeti yenile - sadece gerektiğinde API'ye sorgu yapacak
    func fetchCartItems() {
        // Eğer sepet zaten yükleniyorsa çık
        if isLoading {
            return
        }
        
        // Sepeti API ile senkronize et, ancak kullanıcıya yükleme gösterme
        syncCartWithAPI()
    }
    
    // Kampanya paketinin zaten sepette olup olmadığını kontrol et
    func hasPromotionPackage(product1: Product, product2: Product) -> Bool {
        // Yeni ürünlerin adlarını bir sete ekleyelim
        let newProduct1 = product1.ad
        let newProduct2 = product2.ad
        
        return cartItems.contains { item in
            if item.isPromotionPackage {
                // Paket açıklamasını parçalayalım
                let desc = item.packageDescription
                if desc.contains(newProduct1) && desc.contains(newProduct2) {
                    // Her iki ürün adı da paket açıklamasında geçiyorsa, bu paketi zaten eklemişiz demektir
                    return true
                }
                
                // Alternatif olarak, birebir şekilde kontrol edelim
                let possibleDesc1 = "\(newProduct1) ve \(newProduct2)"
                let possibleDesc2 = "\(newProduct2) ve \(newProduct1)"
                
                return desc == possibleDesc1 || desc == possibleDesc2
            }
            return false
        }
    }
    
    // Kampanya paketini sepete ekle - iki ürünü tek paket olarak ekler
    func addPromotionPackageToCart(product1: Product, product2: Product, discountedPrice: Int) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Paket adı ve detaylarını oluştur
            let packageName = "\(product1.ad) + \(product2.ad) Kampanya Paketi"
            let totalRegularPrice = product1.fiyat + product2.fiyat
            let discountAmount = totalRegularPrice - discountedPrice
            let discountPercentage = Int(Double(discountAmount) / Double(totalRegularPrice) * 100)
            let packageDescription = "\(product1.ad) ve \(product2.ad)"
            
            // Sepette aynı ürün kombinasyonu ile oluşturulmuş kampanya paketi var mı diye kontrol et
            let existingPackage = self.cartItems.first { item in
                if item.isPromotionPackage {
                    // Ürün açıklamasını kontrol et - aynı ürünlerin kombinasyonu mu?
                    let desc = item.packageDescription
                    let existingProducts = Set(desc.components(separatedBy: " ve "))
                    let newProducts = Set([product1.ad, product2.ad])
                    
                    return existingProducts == newProducts
                }
                return false
            }
            
            // Eğer bu kampanya paketi zaten sepette varsa hata döndür
            if existingPackage != nil {
                self.errorMessage = "Bu kampanyadan sadece bir adet faydalanabilirsiniz."
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Paket için bir ID oluştur
            let packageId = Int.random(in: 10000...99999)
            
            // Kampanya paketini temsil eden bir CartItem oluştur
            let newCartItem = NewCartItem(
                sepetId: packageId,
                ad: packageName,
                resim: product1.resim, // Birinci ürünün resmini kullan
                kategori: "Kampanya Paketi",
                fiyat: discountedPrice, // İndirimli fiyatı kullan
                marka: "\(product1.marka) & \(product2.marka)",
                siparisAdeti: 1,
                kullaniciAdi: self.apiService.username,
                isPromotionPackage: true,
                packageDescription: packageDescription
            )
            
            // Geçici CartItem'ı oluştur
            guard let tempCartItem = newCartItem.toCartItem() else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Sepete ekle
            var updatedCart = self.cartItems
            updatedCart.append(tempCartItem)
            self.cartItems = updatedCart
            
            observer.onNext(true)
            observer.onCompleted()
            
            return Disposables.create()
        }
    }
    
    // Sepetteki tüm ürünleri temizle
    func clearCart() -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // Sepetteki gerçek sunucu ID'sine sahip (10000-99999 arası değil) öğeleri API'den de kaldır
            let serverItems = self.cartItems.filter { ($0.sepetId < 10000 || $0.sepetId > 99999) && !$0.isPromotionPackage }
            
            if !serverItems.isEmpty {
                // API üzerinden silinmesi gereken öğeleri tek tek sil
                let group = DispatchGroup()
                var hasError = false
                
                for item in serverItems {
                    group.enter()
                    
                    self.apiService.removeFromCart(cartItem: item)
                        .subscribe(onNext: { success in
                            if !success {
                                hasError = true
                            }
                            group.leave()
                        }, onError: { error in
                            hasError = true
                            group.leave()
                        })
                        .disposed(by: self.disposeBag)
                }
                
                // Tüm işlemlerin tamamlanmasını bekle
                group.notify(queue: .main) {
                    // Yerel sepeti tamamen temizle
                    self.cartItems = []
                    
                    observer.onNext(!hasError)
                    observer.onCompleted()
                }
            } else {
                // Yerel sepeti temizle - sunucuda hiç öğe yoktu
                self.cartItems = []
                
                observer.onNext(true)
                observer.onCompleted()
            }
            
            return Disposables.create()
        }
    }
}

// CartItem nesnesi oluşturmak için yardımcı sınıf
struct NewCartItem: Codable {
    let sepetId: Int
    let ad: String
    let resim: String
    let kategori: String
    let fiyat: Int
    let marka: String
    let siparisAdeti: Int
    let kullaniciAdi: String
    let isPromotionPackage: Bool
    let packageDescription: String
    
    // CodingKeys ile CartItem modeline uygun anahtar eşlemesi yapalım
    enum CodingKeys: String, CodingKey {
        case sepetId = "sepet_id"
        case ad
        case resim
        case kategori
        case fiyat
        case marka
        case siparisAdeti = "siparisAdeti"
        case kullaniciAdi = "kullaniciAdi"
        case isPromotionPackage = "isPromotionPackage"
        case packageDescription = "packageDescription"
    }
    
    // Opsiyonel parametreleri içeren initializer
    init(sepetId: Int, ad: String, resim: String, kategori: String, fiyat: Int, marka: String, siparisAdeti: Int, kullaniciAdi: String, isPromotionPackage: Bool = false, packageDescription: String = "") {
        self.sepetId = sepetId
        self.ad = ad
        self.resim = resim
        self.kategori = kategori
        self.fiyat = fiyat
        self.marka = marka
        self.siparisAdeti = siparisAdeti
        self.kullaniciAdi = kullaniciAdi
        self.isPromotionPackage = isPromotionPackage
        self.packageDescription = packageDescription
    }
    
    func toCartItem() -> CartItem? {
        // Doğrudan CartItem nesnesi oluştur
        return CartItem(
            sepetId: sepetId,
            ad: ad,
            resim: resim,
            kategori: kategori,
            fiyat: fiyat,
            marka: marka,
            siparisAdeti: siparisAdeti,
            kullaniciAdi: kullaniciAdi,
            isPromotionPackage: isPromotionPackage,
            packageDescription: packageDescription
        )
    }
} 