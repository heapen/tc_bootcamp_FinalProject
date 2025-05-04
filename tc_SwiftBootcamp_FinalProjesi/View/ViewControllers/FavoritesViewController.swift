import UIKit
import RxSwift

class FavoritesViewController: UIViewController {
    
    private let productsViewModel = ProductsViewModel.shared
    private let disposeBag = DisposeBag()
    
    // UI Bileşenleri - Storyboard Bağlantıları
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var emptyFavoritesLabel: UILabel!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Favorilerim"
        setupTableView()
        setupBindings()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUI()
    }
    
    // MARK: - Setup Methods
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        
        // ProductTableViewCell için XIB dosyasını kaydet
        tableView.register(UINib(nibName: "ProductTableViewCell", bundle: nil), forCellReuseIdentifier: ProductTableViewCell.identifier)
        
        // RefreshControl ekle
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupBindings() {
        // favoriteProducts değiştiğinde
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoriteProductsChanged),
            name: NSNotification.Name("ProductsViewModel.favoriteProductsChanged"),
            object: nil
        )
        
        // Favori durumu değiştiğinde
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoriteStatusChanged),
            name: NSNotification.Name("ProductsViewModel.favoriteStatusChanged"),
            object: nil
        )
    }
    
    @objc private func handleFavoriteProductsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateUI()
        }
    }
    
    @objc private func handleFavoriteStatusChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, 
                  let productId = notification.userInfo?["productId"] as? Int,
                  let isFavorite = notification.userInfo?["isFavorite"] as? Bool else { return }
            
            // Sadece favoriden çıkarılırsa yenile
            if !isFavorite {
                self.updateUI()
            } else {
                // Sadece ilgili hücreleri güncelle
                for cell in self.tableView.visibleCells {
                    if let productCell = cell as? ProductTableViewCell,
                       let indexPath = self.tableView.indexPath(for: cell),
                       self.productsViewModel.favoriteProducts[indexPath.row].id == productId {
                        let product = self.productsViewModel.favoriteProducts[indexPath.row]
                        productCell.configure(with: product)
                    }
                }
            }
        }
    }
    
    // MARK: - Data Handling
    
    @objc private func refreshData() {
        updateUI()
        tableView.refreshControl?.endRefreshing()
    }
    
    private func updateUI() {
        // Favori ürünlerin durumuna göre UI'ı güncelle
        let isFavoritesEmpty = productsViewModel.favoriteProducts.isEmpty
        
        // Favoriler boşsa uygun mesajı göster
        emptyFavoritesLabel.isHidden = !isFavoritesEmpty
        
        // Tabloyu yenile
        tableView.reloadData()
        
        // Yükleme durumunu güncelle
        activityIndicator.stopAnimating()
    }
    
    // MARK: - Helpers
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Hata", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension FavoritesViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return productsViewModel.favoriteProducts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ProductTableViewCell.identifier, for: indexPath) as? ProductTableViewCell else {
            return UITableViewCell()
        }
        
        let product = productsViewModel.favoriteProducts[indexPath.row]
        cell.configure(with: product)
        
        // Favorilerden çıkar aksiyonu
        cell.favoriteButtonTapped = { [weak self] in
            self?.removeFromFavorites(product)
        }
        
        // Sepete ekle aksiyonu
        cell.addToCartButtonTapped = { [weak self] in
            self?.addToCart(product)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let product = productsViewModel.favoriteProducts[indexPath.row]
        let detailVC = ProductDetailViewController.instantiate(with: product)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func removeFromFavorites(_ product: Product) {
        productsViewModel.toggleFavorite(product: product)
    }
    
    private func addToCart(_ product: Product) {
        let cartViewModel = CartViewModel.shared
        
        cartViewModel.addToCart(product: product, quantity: 1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { success in
                if success {
                    // Sepete ekleme başarılı olduğunda bildirim göster
                    NotificationCenter.default.post(name: NSNotification.Name("CartUpdated"), object: nil)
                }
            })
            .disposed(by: disposeBag)
    }
} 