import UIKit
import RxSwift

class PromotionsViewController: UIViewController {
    
    private let disposeBag = DisposeBag()
    private let cartViewModel = CartViewModel.shared
    private let productsViewModel = ProductsViewModel.shared
    
    // Promosyon paketleri için varsayılan indirim oranı (%15)
    private let discountRate = 0.15
    
    private var promotionPackages: [(product1: Product, product2: Product)] = []
    
    // UI Bileşenleri - Storyboard Bağlantıları
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var emptyPromotionsLabel: UILabel!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kampanyalar"
        setupCollectionView()
        checkNetworkAndFetchProducts()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Sepet değiştiğinde kampanya durumlarını güncelle
        updatePromotionAvailability()
    }
    
    // MARK: - Setup Methods
    
    private func setupCollectionView() {
        // CollectionView delegate ve datasource
        collectionView.delegate = self
        collectionView.dataSource = self
        
        // PromotionCollectionViewCell için XIB dosyasını kaydet
        collectionView.register(UINib(nibName: "PromotionCollectionViewCell", bundle: nil), forCellWithReuseIdentifier: PromotionCollectionViewCell.identifier)
    }
    
    // MARK: - Data Handling
    
    private func checkNetworkAndFetchProducts() {
        activityIndicator.startAnimating()
        
        APIService.shared.pingAPI()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] isConnected in
                guard let self = self else { return }
                
                if isConnected {
                    self.fetchProducts()
                } else {
                    self.showErrorAlert(message: "İnternet bağlantısı bulunamadı.")
                    self.activityIndicator.stopAnimating()
                    self.updateUI()
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func fetchProducts() {
        // Observe products changes via notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProductsChanged),
            name: NSNotification.Name("ProductsViewModel.productsChanged"),
            object: nil
        )
        
        // Observe error message changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorMessageChanged),
            name: NSNotification.Name("ProductsViewModel.errorMessageChanged"),
            object: nil
        )
        
        // Observe loading state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadingStateChanged),
            name: NSNotification.Name("ProductsViewModel.isLoadingChanged"),
            object: nil
        )
        
        // Sepet değişikliklerini dinle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCartUpdated),
            name: NSNotification.Name("CartViewModel.cartItemsChanged"),
            object: nil
        )
        
        // Start fetching products
        productsViewModel.fetchAllProducts()
    }
    
    @objc private func handleProductsChanged() {
        createPromotionPackages(from: productsViewModel.products)
        activityIndicator.stopAnimating()
        updateUI()
    }
    
    @objc private func handleErrorMessageChanged() {
        if let errorMessage = productsViewModel.errorMessage {
            activityIndicator.stopAnimating()
            showErrorAlert(message: errorMessage)
            updateUI()
        }
    }
    
    @objc private func handleLoadingStateChanged() {
        if !productsViewModel.isLoading {
            activityIndicator.stopAnimating()
        }
    }
    
    @objc private func handleCartUpdated() {
        // Sepet değiştiğinde, kampanya durumlarını güncelle
        updatePromotionAvailability()
    }
    
    private func updatePromotionAvailability() {
        // Sepetteki ürünlere göre kampanya durumlarını güncelle
        collectionView.reloadData()
    }
    
    private func createPromotionPackages(from products: [Product]) {
        // Promosyon paketlerini oluştur (benzer kategori ürünleri eşleştirerek)
        var packages: [(product1: Product, product2: Product)] = []
        var usedProductIds = Set<Int>()
        
        // Kategori bazlı ürün gruplaması
        let categorizedProducts = Dictionary(grouping: products) { $0.kategori }
        
        // Her kategoride en az 2 ürün varsa, onları eşleştir
        for (_, products) in categorizedProducts {
            guard products.count >= 2 else { continue }
            
            // Ürünleri fiyata göre sırala (en pahalıdan en ucuza)
            let sortedProducts = products.sorted { $0.fiyat > $1.fiyat }
            
            for i in 0..<sortedProducts.count {
                let product1 = sortedProducts[i]
                
                // Zaten kullanılmış ürünleri atla
                if usedProductIds.contains(product1.id) {
                    continue
                }
                
                // Eşleşme bulma
                for j in i+1..<sortedProducts.count {
                    let product2 = sortedProducts[j]
                    
                    // Zaten kullanılmış ürünleri atla
                    if usedProductIds.contains(product2.id) {
                        continue
                    }
                    
                    // Paket oluştur
                    packages.append((product1: product1, product2: product2))
                    
                    // Kullanılan ürünleri işaretle
                    usedProductIds.insert(product1.id)
                    usedProductIds.insert(product2.id)
                    
                    // Her kategori için en fazla 2 paket oluştur
                    if packages.filter({ $0.product1.kategori == product1.kategori }).count >= 2 {
                        break
                    }
                }
            }
        }
        
        // Sonuçları sakla
        promotionPackages = packages
        
        // Sonuçları karıştır (her seferinde farklı kampanyalar göster)
        promotionPackages.shuffle()
        
        // Maksimum 10 kampanya paketi göster
        if promotionPackages.count > 10 {
            promotionPackages = Array(promotionPackages.prefix(10))
        }
    }
    
    private func updateUI() {
        // Promosyon paketlerinin durumuna göre UI'ı güncelle
        emptyPromotionsLabel.isHidden = !promotionPackages.isEmpty
        collectionView.reloadData()
    }
    
    // MARK: - Helpers
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Hata", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
    
    private func showPromotionAlreadyInCartAlert() {
        let alert = UIAlertController(
            title: "Uyarı",
            message: "Bu kampanya paketi zaten sepetinizde bulunuyor. Her kampanya paketinden sadece bir tane ekleyebilirsiniz.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate, UICollectionViewDataSource

extension PromotionsViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return promotionPackages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PromotionCollectionViewCell.identifier, for: indexPath) as? PromotionCollectionViewCell else {
            return UICollectionViewCell()
        }
        
        let package = promotionPackages[indexPath.row]
        cell.configure(with: package.product1, and: package.product2, discountRate: discountRate)
        
        // Sepete ekle butonuna tıklama
        cell.addToCartTapped = { [weak self] in
            guard let self = self else { return }
            self.addPromotionToCart(cell)
        }
        
        return cell
    }
    
    // MARK: - Actions
    
    private func addPromotionToCart(_ cell: PromotionCollectionViewCell) {
        // Hücreden paket bilgilerini al
        guard let packageInfo = cell.getPromotionInfo() else { return }
        
        // Sepetteki öğeleri kontrol et - aynı paket zaten var mı?
        let hasSamePackage = cartViewModel.hasPromotionPackage(product1: packageInfo.product1, product2: packageInfo.product2)
        
        if hasSamePackage {
            // Sepette zaten bu paket var, uyarı göster
            showPromotionAlreadyInCartAlert()
            return
        }
        
        // Promosyon paketini sepete ekle
        cartViewModel.addPromotionPackageToCart(
            product1: packageInfo.product1,
            product2: packageInfo.product2,
            discountedPrice: packageInfo.discountedPrice
        )
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] success in
                if success {
                    // Sepete ekleme başarılı, bildirim göster
                    self?.showSuccessAlert()
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func showSuccessAlert() {
        let alert = UIAlertController(
            title: "Başarılı",
            message: "Kampanya paketi sepetinize eklendi.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
} 