import UIKit
import RxSwift

class ProductsViewController: UIViewController {
    
    private let productsViewModel = ProductsViewModel.shared
    private let disposeBag = DisposeBag()
    
    // UI Bileşenleri - Storyboard Bağlantıları
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var noConnectionView: UIView!
    @IBOutlet weak var noConnectionImageView: UIImageView!
    @IBOutlet weak var noConnectionLabel: UILabel!
    @IBOutlet weak var retryButton: UIButton!
    
    @IBOutlet weak var searchBar: UISearchBar!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ürünler"
        setupTableView()
        setupBindings()
        checkNetworkAndFetchProducts()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Önceki sayfadan dönüşte ürünlerin güncel favori durumunu göster
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func retryButtonTapped(_ sender: Any) {
        checkNetworkAndFetchProducts()
    }
    
    // MARK: - Setup Methods
    
    private func setupTableView() {
        tableView.register(UINib(nibName: "ProductTableViewCell", bundle: nil), forCellReuseIdentifier: ProductTableViewCell.identifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        searchBar.delegate = self
    }
    
    private func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadingStateChanged),
            name: NSNotification.Name("ProductsViewModel.isLoadingChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorMessageChanged),
            name: NSNotification.Name("ProductsViewModel.errorMessageChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProductsChanged),
            name: NSNotification.Name("ProductsViewModel.productsChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFilteredProductsChanged),
            name: NSNotification.Name("ProductsViewModel.filteredProductsChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoriteProductsChanged),
            name: NSNotification.Name("ProductsViewModel.favoriteProductsChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoriteStatusChanged),
            name: NSNotification.Name("ProductsViewModel.favoriteStatusChanged"),
            object: nil
        )
    }
    
    // MARK: - Handlers 
    
    @objc private func handleLoadingStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if productsViewModel.isLoading {
                activityIndicator.startAnimating()
            } else {
                activityIndicator.stopAnimating()
            }
        }
    }
    
    @objc private func handleErrorMessageChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let errorMessage = self.productsViewModel.errorMessage else { return }
            
            if errorMessage.contains("bağlanılamadı") || errorMessage.contains("ağ") {
                noConnectionView.isHidden = false
                tableView.isHidden = true
            } else {
                showErrorAlert(message: errorMessage)
            }
        }
    }
    
    @objc private func handleProductsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            noConnectionView.isHidden = true
            tableView.isHidden = false
            tableView.reloadData()
        }
    }
    
    @objc private func handleFilteredProductsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
        }
    }
    
    @objc private func handleFavoriteProductsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            tableView.reloadData()
        }
    }
    
    @objc private func handleFavoriteStatusChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, 
                  let productId = notification.userInfo?["productId"] as? Int else { return }
            
            for cell in self.tableView.visibleCells {
                if let productCell = cell as? ProductTableViewCell,
                   let indexPath = self.tableView.indexPath(for: cell),
                   self.productsViewModel.filteredProducts[indexPath.row].id == productId {
                    let product = self.productsViewModel.filteredProducts[indexPath.row]
                    productCell.configure(with: product)
                }
            }
        }
    }
    
    // MARK: - Network & Data
    
    private func checkNetworkAndFetchProducts() {
        APIService.shared.pingAPI()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] isConnected in
                guard let self = self else { return }
                
                if isConnected {
                    noConnectionView.isHidden = true
                    tableView.isHidden = false
                    fetchProducts()
                } else {
                    noConnectionView.isHidden = false
                    tableView.isHidden = true
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func fetchProducts() {
        productsViewModel.fetchAllProducts()
    }
    
    @objc private func refreshData() {
        checkNetworkAndFetchProducts()
        tableView.refreshControl?.endRefreshing()
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Hata", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension ProductsViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return productsViewModel.filteredProducts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ProductTableViewCell.identifier, for: indexPath) as? ProductTableViewCell else {
            return UITableViewCell()
        }
        
        let product = productsViewModel.filteredProducts[indexPath.row]
        cell.configure(with: product)
        
        // Favorilere ekle/çıkar aksiyonu
        cell.favoriteButtonTapped = { [weak self] in
            self?.toggleFavorite(product)
        }
        
        // Sepete ekle aksiyonu
        cell.addToCartButtonTapped = { [weak self] in
            self?.addToCart(product)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let product = productsViewModel.filteredProducts[indexPath.row]
        let detailVC = ProductDetailViewController.instantiate(with: product)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    // MARK: - Helper Methods
    
    private func toggleFavorite(_ product: Product) {
        productsViewModel.toggleFavorite(product: product)
    }
    
    private func addToCart(_ product: Product) {
        let cartViewModel = CartViewModel.shared
        
        cartViewModel.addToCart(product: product, quantity: 1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { success in
                if success {
                    NotificationCenter.default.post(name: NSNotification.Name("CartUpdated"), object: nil)
                }
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UISearchBarDelegate

extension ProductsViewController: UISearchBarDelegate {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        productsViewModel.filterProducts(by: searchText)
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
} 