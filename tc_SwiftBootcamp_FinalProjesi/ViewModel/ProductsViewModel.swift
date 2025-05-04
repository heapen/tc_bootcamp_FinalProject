import Foundation
import RxSwift
import RxRelay

final class ProductsViewModel {
    // Statik paylaşılan örnek
    static let shared = ProductsViewModel()
    
    private let disposeBag = DisposeBag()
    private let apiService = APIService.shared
    
    // User Defaults için anahtarlar
    private let favoritesKey = "favoritedProductIds"
    
    init() {
        loadFavorites()
    }
    
    private(set) var products: [Product] = [] {
        didSet {
            // Ürünler yüklendiğinde, favorilerin de doğru şekilde işaretlendiğinden emin olalım
            syncFavoriteStatus()
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.productsChanged"), object: nil)
        }
    }
    
    private(set) var favoriteProducts: [Product] = [] {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.favoriteProductsChanged"), object: nil)
        }
    }
    
    private(set) var filteredProducts: [Product] = [] {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.filteredProductsChanged"), object: nil)
        }
    }
    
    var isLoading = false {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.isLoadingChanged"), object: nil)
        }
    }
    
    var errorMessage: String? {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.errorMessageChanged"), object: nil)
        }
    }
    
    var searchText: String = "" {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.searchTextChanged"), object: nil)
        }
    }
    
    // Favorileri yükle
    private func loadFavorites() {
        if let favoritedIds = UserDefaults.standard.array(forKey: favoritesKey) as? [Int] {
            // Favorileri UserDefaults'tan yükle
            
            // Favorileri ürünlerle eşleştir (ürünler yüklendikten sonra)
            if !products.isEmpty {
                syncFavoriteStatus()
            }
        }
    }
    
    // Favorileri kaydet
    private func saveFavorites() {
        let favoritedIds = favoriteProducts.map { $0.id }
        UserDefaults.standard.set(favoritedIds, forKey: favoritesKey)
    }
    
    // Ürünler ve favoriler arasında senkronizasyon
    private func syncFavoriteStatus() {
        // UserDefaults'tan favori ID'leri al
        guard let favoritedIds = UserDefaults.standard.array(forKey: favoritesKey) as? [Int] else {
            return
        }
        
        // Tüm ürünlerin favori durumunu güncelle
        for (index, product) in products.enumerated() {
            let isFavorite = favoritedIds.contains(product.id)
            if product.isFavorite != isFavorite {
                var updatedProduct = product
                updatedProduct.isFavorite = isFavorite
                products[index] = updatedProduct
            }
        }
        
        // Favorilere eklenmiş ürünler
        favoriteProducts = products.filter { favoritedIds.contains($0.id) }
        
        // Filtrelenmiş ürünleri de güncelle
        for (index, product) in filteredProducts.enumerated() {
            let isFavorite = favoritedIds.contains(product.id)
            if product.isFavorite != isFavorite {
                var updatedProduct = product
                updatedProduct.isFavorite = isFavorite
                filteredProducts[index] = updatedProduct
            }
        }
    }
    
    // Kategoriye göre ürünleri filtrele
    func getProductsByCategory(category: String) -> [Product] {
        return products.filter { $0.kategori == category }
    }
    
    // Markaya göre ürünleri filtrele
    func getProductsByBrand(brand: String) -> [Product] {
        return products.filter { $0.marka == brand }
    }
    
    // Ürün ara
    func searchProducts(query: String) {
        searchText = query
        if query.isEmpty {
            filteredProducts = products
        } else {
            filteredProducts = products.filter { 
                $0.ad.lowercased().contains(query.lowercased()) || 
                $0.marka.lowercased().contains(query.lowercased()) || 
                $0.kategori.lowercased().contains(query.lowercased())
            }
        }
    }
    
    // Ürünleri filtrele (searchProducts ile aynı işlevi görür)
    func filterProducts(by query: String) {
        searchProducts(query: query)
    }
    
    // Tüm ürünleri getir
    func fetchAllProducts() {
        isLoading = true
        errorMessage = nil
        
        apiService.fetchAllProducts()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] products in
                guard let self = self else { return }
                self.products = products
                self.filteredProducts = products
                self.syncFavoriteStatus() // Favori durumunu senkronize et
                self.isLoading = false
            }, onError: { [weak self] error in
                guard let self = self else { return }
                self.errorMessage = (error as? APIError)?.localizedDescription ?? "Beklenmeyen bir hata oluştu."
                self.isLoading = false
            })
            .disposed(by: disposeBag)
    }
    
    // Favorilere ekle/çıkar
    func toggleFavorite(product: Product) {
        // Favori durumunu tersine çevir
        let newFavoriteStatus = !(product.isFavorite ?? false)
        
        // Ürünü tüm koleksiyonlarda güncelle
        updateProductFavoriteStatus(productId: product.id, isFavorite: newFavoriteStatus)
        
        // UserDefaults'ı güncelle ve kaydet
        saveFavorites()
        
        // Değişikliği bildir
        NotificationCenter.default.post(
            name: NSNotification.Name("ProductsViewModel.favoriteStatusChanged"), 
            object: nil, 
            userInfo: ["productId": product.id, "isFavorite": newFavoriteStatus]
        )
    }
    
    // Yardımcı metod: Ürün favori durumunu tüm koleksiyonlarda günceller
    private func updateProductFavoriteStatus(productId: Int, isFavorite: Bool) {
        // Ana ürün listesinde güncelle
        if let index = products.firstIndex(where: { $0.id == productId }) {
            var updatedProduct = products[index]
            updatedProduct.isFavorite = isFavorite
            products[index] = updatedProduct
            
            // Filtrelenmiş listede güncelle
            if let filteredIndex = filteredProducts.firstIndex(where: { $0.id == productId }) {
                var updatedFilteredProduct = filteredProducts[filteredIndex]
                updatedFilteredProduct.isFavorite = isFavorite
                filteredProducts[filteredIndex] = updatedFilteredProduct
            }
            
            // Favoriler listesini güncelle
            if isFavorite {
                // Eğer zaten favorilerde yoksa ekle
                if !favoriteProducts.contains(where: { $0.id == productId }) {
                    favoriteProducts.append(updatedProduct)
                }
            } else {
                // Favorilerden kaldır
                favoriteProducts.removeAll(where: { $0.id == productId })
            }
            
            // Her türlü değişiklik bildirimini tetikle
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.productsChanged"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.filteredProductsChanged"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("ProductsViewModel.favoriteProductsChanged"), object: nil)
        }
    }
    
    // Aynı kategorideki ürünleri getir
    func getRelatedProducts(for product: Product, limit: Int = 5) -> [Product] {
        return products
            .filter { $0.kategori == product.kategori && $0.id != product.id }
            .prefix(limit)
            .map { $0 }
    }
    
    // Kampanya paketleri oluştur
    func getPromotionalPackages() -> [(product1: Product, product2: Product, discount: Int)] {
        var packages: [(product1: Product, product2: Product, discount: Int)] = []
        
        // Kategorileri al
        let categories = Set(products.map { $0.kategori })
        
        // Her kategoriden sadece bir paket oluştur
        for category in categories {
            let categoryProducts = products.filter { $0.kategori == category }
            
            // Kategoride en az 2 ürün varsa
            if categoryProducts.count >= 2 {
                // En pahalı ve en ucuz ürünleri seç (kampanya daha dikkat çekici olsun)
                let sortedProducts = categoryProducts.sorted { $0.fiyat > $1.fiyat }
                let expensiveProduct = sortedProducts.first!
                let cheaperProduct = sortedProducts.last!
                
                // Ürünler farklı ise paketi oluştur
                if expensiveProduct.id != cheaperProduct.id {
                    // Toplam fiyatın %15'i kadar indirim
                    let totalPrice = expensiveProduct.fiyat + cheaperProduct.fiyat
                    let discountAmount = Int(Double(totalPrice) * 0.15)
                    
                    packages.append((product1: expensiveProduct, product2: cheaperProduct, discount: discountAmount))
                    
                    // Maximum 5 farklı kategoriden paket oluştur
                    if packages.count >= 5 {
                        break
                    }
                }
            }
        }
        
        return packages
    }
} 