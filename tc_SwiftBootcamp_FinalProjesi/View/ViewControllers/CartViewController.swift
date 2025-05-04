import UIKit
import RxSwift
import Combine

class CartViewController: UIViewController {
    
    private let cartViewModel = CartViewModel.shared
    private let disposeBag = DisposeBag()
    private var cancellables = Set<AnyCancellable>()
    
    // UI Bileşenleri - Storyboard Bağlantıları
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var emptyCartLabel: UILabel!
    @IBOutlet weak var totalPriceView: UIView!
    @IBOutlet weak var totalPriceLabel: UILabel!
    @IBOutlet weak var checkoutButton: UIButton!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
        setupBindings()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        fetchCartItems()
        updateUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // TableView'ın alt kısmında toplam fiyat view'ı için boşluk bırak
        let bottomInset = totalPriceView.frame.height + view.safeAreaInsets.bottom
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: bottomInset + 8, right: 0)
        tableView.scrollIndicatorInsets = tableView.contentInset
    }
    
    // MARK: - Setup Methods
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.register(UINib(nibName: "CartTableViewCell", bundle: nil), forCellReuseIdentifier: CartTableViewCell.identifier)
        
        tableView.rowHeight = 120
        tableView.estimatedRowHeight = 120
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    private func setupBindings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoadingStateChanged),
            name: NSNotification.Name("CartViewModel.isLoadingChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleErrorMessageChanged),
            name: NSNotification.Name("CartViewModel.errorMessageChanged"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCartItemsChanged),
            name: NSNotification.Name("CartViewModel.cartItemsChanged"),
            object: nil
        )
    }
    
    @objc private func handleLoadingStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if cartViewModel.isLoading {
                activityIndicator.startAnimating()
            } else {
                activityIndicator.stopAnimating()
            }
        }
    }
    
    @objc private func handleErrorMessageChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let errorMessage = self.cartViewModel.errorMessage else { return }
            
            if errorMessage.contains("200") {
                emptyCartLabel.isHidden = false
                totalPriceView.isHidden = true
                tableView.reloadData()
            } else {
                showErrorAlert(message: errorMessage)
            }
        }
    }
    
    @objc private func handleCartItemsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            updateUI()
        }
    }
    
    // MARK: - Data Handling
    
    private func fetchCartItems() {
        cartViewModel.fetchCartItems()
    }
    
    @objc private func refreshData() {
        fetchCartItems()
        tableView.refreshControl?.endRefreshing()
    }
    
    private func updateUI() {
        let isCartEmpty = cartViewModel.cartItems.isEmpty
        emptyCartLabel.isHidden = !isCartEmpty
        totalPriceView.isHidden = isCartEmpty
        
        totalPriceLabel.text = "Toplam: \(cartViewModel.formattedTotalAmount)"
        
        tableView.reloadData()
    }
    
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(title: "Hata", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Actions
    
    @IBAction func checkoutButtonTapped(_ sender: Any) {
        processCheckout()
    }
    
    private func processCheckout() {
        let alert = UIAlertController(title: "Sipariş Tamamla", 
                                     message: "Siparişiniz toplam \(cartViewModel.formattedTotalAmount) tutarındadır. Onaylıyor musunuz?", 
                                     preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "İptal", style: .cancel))
        alert.addAction(UIAlertAction(title: "Onayla", style: .default, handler: { [weak self] _ in
            self?.showOrderSuccess()
        }))
        
        present(alert, animated: true)
    }
    
    private func showOrderSuccess() {
        let alert = UIAlertController(title: "Başarılı", message: "Siparişiniz başarıyla tamamlandı.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default, handler: { [weak self] _ in
            self?.clearCart()
            
            if let tabBarController = self?.tabBarController {
                tabBarController.selectedIndex = 0
            }
        }))
        present(alert, animated: true)
    }
    
    private func clearCart() {
        cartViewModel.clearCart()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] success in
                guard let self = self else { return }
                if success {
                    updateUI()
                }
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension CartViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cartViewModel.cartItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: CartTableViewCell.identifier, for: indexPath) as? CartTableViewCell else {
            return UITableViewCell()
        }
        
        let cartItem = cartViewModel.cartItems[indexPath.row]
        cell.configure(with: cartItem)
        
        // Silme butonuna tıklama aksiyonu
        cell.removeButtonTapped = { [weak self] in
            self?.removeCartItem(cartItem)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120 // CartTableViewCell.xib'de yeni tanımlandığı yükseklik
    }
    
    // MARK: - Helper Methods
    
    private func removeCartItem(_ cartItem: CartItem) {
        let alert = UIAlertController(title: "Ürünü Sil", message: "Bu ürünü sepetten çıkarmak istediğinize emin misiniz?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "İptal", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sil", style: .destructive, handler: { [weak self] _ in
            self?.performRemoveCartItem(cartItem)
        }))
        
        present(alert, animated: true)
    }
    
    private func performRemoveCartItem(_ cartItem: CartItem) {
        cartViewModel.removeFromCart(cartItem: cartItem)
            .subscribe(onNext: { [weak self] success in
                if success {
                    print("🗑️ Item removed from cart: \(cartItem.ad)")
                    
                    // UI güncellemesi otomatik olarak gerçekleşecek (cartItems değişikliği ile)
                    DispatchQueue.main.async {
                        self?.updateUI()
                    }
                } else {
                    print("❌ Failed to remove item from cart")
                    // Hata durumunda kullanıcıya bildir
                    self?.showErrorAlert(message: "Ürün sepetten çıkarılamadı. Lütfen tekrar deneyin.")
                }
            }, onError: { [weak self] error in
                print("❌ Error removing item from cart: \(error)")
                // Hata durumunda kullanıcıya bildir
                self?.showErrorAlert(message: "Ürün sepetten çıkarılırken bir hata oluştu: \(error.localizedDescription)")
            })
            .disposed(by: disposeBag)
    }
} 