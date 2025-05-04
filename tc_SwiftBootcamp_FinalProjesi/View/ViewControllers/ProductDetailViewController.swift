import UIKit
import Kingfisher
import RxSwift

class ProductDetailViewController: UIViewController {
    
    // MARK: - Properties
    
    var product: Product!
    private let productsViewModel = ProductsViewModel.shared
    private let cartViewModel = CartViewModel.shared
    private let disposeBag = DisposeBag()
    
    private var quantity: Int = 1
    
    // MARK: - UI Elements
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var productImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var brandLabel: UILabel!
    @IBOutlet weak var categoryLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    @IBOutlet weak var favoriteButton: UIButton!
    @IBOutlet weak var quantityStepper: UIStepper!
    @IBOutlet weak var quantityLabel: UILabel!
    @IBOutlet weak var addToCartButton: UIButton!
    @IBOutlet weak var relatedProductsLabel: UILabel!
    @IBOutlet weak var relatedProductsCollectionView: UICollectionView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    // MARK: - Initialization
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    static func instantiate(with product: Product) -> ProductDetailViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "ProductDetailViewController") as! ProductDetailViewController
        viewController.product = product
        return viewController
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBindings()
        configureUI()
        setupCollectionView()
        loadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        relatedProductsCollectionView.reloadData()
    }
    
    // MARK: - UI Setup
    
    private func configureUI() {
        title = "Ürün Detayı"
        
        // Ürün bilgilerini göster
        nameLabel.text = product.ad
        brandLabel.text = product.marka
        categoryLabel.text = product.kategori
        priceLabel.text = "\(product.fiyat) ₺"
        
        // Ürün resmini yükle
        if let imageURL = product.imageURL {
            productImageView.kf.setImage(with: imageURL, placeholder: UIImage(systemName: "photo"))
        } else {
            productImageView.image = UIImage(systemName: "photo")
        }
        
        // Favori durumunu göster
        let imageName = product.isFavorite == true ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: imageName), for: .normal)
    }
    
    private func setupCollectionView() {
        // Collection View kaydı
        relatedProductsCollectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "RelatedProductCell")
        relatedProductsCollectionView.delegate = self
        relatedProductsCollectionView.dataSource = self
    }
    
    private func setupBindings() {
        // isLoading değiştiğinde
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadingStateChanged),
            name: NSNotification.Name("CartViewModel.isLoadingChanged"),
            object: nil
        )
        
        // errorMessage değiştiğinde
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorMessageChanged),
            name: NSNotification.Name("CartViewModel.errorMessageChanged"),
            object: nil
        )
    }
    
    @objc private func handleLoadingStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateLoadingState()
        }
    }
    
    @objc private func handleErrorMessageChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let errorMessage = self.cartViewModel.errorMessage else { return }
            self.showErrorAlert(message: errorMessage)
        }
    }
    
    private func updateLoadingState() {
        if cartViewModel.isLoading {
            activityIndicator.startAnimating()
            addToCartButton.isEnabled = false
        } else {
            activityIndicator.stopAnimating()
            addToCartButton.isEnabled = true
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Hata", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Actions
    
    @IBAction func stepperValueChanged(_ sender: UIStepper) {
        quantity = Int(quantityStepper.value)
        quantityLabel.text = "Adet: \(quantity)"
    }
    
    @IBAction func addToCartButtonTapped(_ sender: UIButton) {
        cartViewModel.addToCart(product: product, quantity: quantity)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.showAddToCartSuccess()
                }
            }, onError: { [weak self] error in
                self?.showErrorAlert(message: (error as? APIError)?.localizedDescription ?? "Beklenmeyen bir hata oluştu.")
            })
            .disposed(by: disposeBag)
    }
    
    @IBAction func favoriteButtonTapped(_ sender: UIButton) {
        // Ürünü favorilere ekle/çıkar
        productsViewModel.toggleFavorite(product: product)
        
        // Ürünün güncel favori durumunu ViewModel'dan al
        if let updatedProduct = productsViewModel.products.first(where: { $0.id == product.id }) {
            product = updatedProduct
            
            // Favori butonunun görünümünü güncelle
            let imageName = product.isFavorite == true ? "heart.fill" : "heart"
            favoriteButton.setImage(UIImage(systemName: imageName), for: .normal)
        }
    }
    
    private func showAddToCartSuccess() {
        let alert = UIAlertController(title: "Başarılı", message: "Ürün sepete eklendi.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        alert.addAction(UIAlertAction(title: "Sepete Git", style: .default, handler: { [weak self] _ in
            self?.goToCart()
        }))
        present(alert, animated: true)
    }
    
    private func goToCart() {
        if let tabBarController = tabBarController {
            tabBarController.selectedIndex = 3 // Sepet sekmesine git
            navigationController?.popToRootViewController(animated: true)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData() {
        // Önce ürünleri yükle
        productsViewModel.fetchAllProducts()
        
        // Tüm ürünler yüklendiğinde bildirim alacağız
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProductsChanged),
            name: NSNotification.Name("ProductsViewModel.productsChanged"),
            object: nil
        )
    }
    
    @objc private func handleProductsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.relatedProductsCollectionView.reloadData()
        }
    }
}

// MARK: - UICollectionViewDelegate, UICollectionViewDataSource

extension ProductDetailViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return productsViewModel.getRelatedProducts(for: product).count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "RelatedProductCell", for: indexPath)
        
        // Hücreyi temizle
        for subview in cell.contentView.subviews {
            subview.removeFromSuperview()
        }
        
        // Ürün bilgilerini al
        let relatedProduct = productsViewModel.getRelatedProducts(for: product)[indexPath.item]
        
        // Ürün görseli
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: cell.bounds.width, height: cell.bounds.height * 0.7))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        
        if let imageURL = relatedProduct.imageURL {
            imageView.kf.setImage(with: imageURL, placeholder: UIImage(systemName: "photo"))
        } else {
            imageView.image = UIImage(systemName: "photo")
        }
        
        // Ürün adı
        let nameLabel = UILabel(frame: CGRect(x: 5, y: imageView.frame.maxY + 5, width: cell.bounds.width - 10, height: 20))
        nameLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.text = relatedProduct.ad
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        
        // Ürün fiyatı
        let priceLabel = UILabel(frame: CGRect(x: 5, y: nameLabel.frame.maxY + 5, width: cell.bounds.width - 10, height: 20))
        priceLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        priceLabel.text = "\(relatedProduct.fiyat) ₺"
        priceLabel.textColor = .systemBlue
        priceLabel.textAlignment = .center
        
        // Hücre tasarımı
        cell.contentView.addSubview(imageView)
        cell.contentView.addSubview(nameLabel)
        cell.contentView.addSubview(priceLabel)
        cell.backgroundColor = .systemGray6
        cell.layer.cornerRadius = 10
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let relatedProduct = productsViewModel.getRelatedProducts(for: product)[indexPath.item]
        let detailVC = ProductDetailViewController.instantiate(with: relatedProduct)
        navigationController?.pushViewController(detailVC, animated: true)
    }
} 