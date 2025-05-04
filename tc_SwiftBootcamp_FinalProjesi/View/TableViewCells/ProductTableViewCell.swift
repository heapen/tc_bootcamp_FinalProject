import UIKit
import Kingfisher

class ProductTableViewCell: UITableViewCell {
    
    static let identifier = "ProductTableViewCell"
    
    // UI Bileşenleri - XIB Bağlantıları
    @IBOutlet weak var productImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var brandLabel: UILabel!
    @IBOutlet weak var categoryLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    @IBOutlet weak var favoriteButton: UIButton!
    @IBOutlet weak var addToCartButton: UIButton!
    
    var favoriteButtonTapped: (() -> Void)?
    var addToCartButtonTapped: (() -> Void)?
    
    // MARK: - Lifecycle
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.accessoryType = .disclosureIndicator
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    // MARK: - Actions
    
    @IBAction func favoriteButtonAction(_ sender: UIButton) {
        // İlk önce kullanıcıya görsel geri bildirim vermek için butonun görünümünü hemen değiştir
        let currentFavoriteStatus = sender.image(for: .normal)?.description.contains("fill") ?? false
        let newImage = UIImage(systemName: currentFavoriteStatus ? "heart" : "heart.fill")
        sender.setImage(newImage, for: .normal)
        sender.tintColor = currentFavoriteStatus ? .systemGray : .systemRed
        
        // Ardından callback'i çalıştır
        favoriteButtonTapped?()
    }
    
    @IBAction func addToCartButtonAction(_ sender: UIButton) {
        addToCartButtonTapped?()
    }
    
    // MARK: - Configuration
    
    func configure(with product: Product) {
        nameLabel.text = product.ad
        brandLabel.text = product.marka
        categoryLabel.text = product.kategori
        priceLabel.text = product.formattedPrice
        
        // Favori durumunu güncelle - kesin bir şekilde ayarla
        updateFavoriteButtonState(isFavorite: product.isFavorite ?? false)
        
        // Ürün resmini yükle
        loadProductImage(product)
    }
    
    // Yardımcı metod - Favori buton durumunu günceller
    private func updateFavoriteButtonState(isFavorite: Bool) {
        let imageName = isFavorite ? "heart.fill" : "heart"
        favoriteButton.setImage(UIImage(systemName: imageName), for: .normal)
        favoriteButton.tintColor = isFavorite ? .systemRed : .systemGray
    }
    
    private func loadProductImage(_ product: Product) {
        let placeholderImage = UIImage(systemName: "photo")
        productImageView.kf.cancelDownloadTask()
        
        if let imageURL = product.imageURL {
            productImageView.kf.setImage(
                with: imageURL,
                placeholder: placeholderImage,
                completionHandler: { [weak self] result in
                    if case .failure = result, let fallbackURL = product.fallbackImageURL {
                        self?.productImageView.kf.setImage(
                            with: fallbackURL,
                            placeholder: placeholderImage
                        )
                    }
                }
            )
        } else if let fallbackURL = product.fallbackImageURL {
            productImageView.kf.setImage(
                with: fallbackURL,
                placeholder: placeholderImage
            )
        } else {
            productImageView.image = placeholderImage
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        productImageView.kf.cancelDownloadTask()
        productImageView.image = nil
        nameLabel.text = nil
        brandLabel.text = nil
        categoryLabel.text = nil
        priceLabel.text = nil
        favoriteButton.setImage(UIImage(systemName: "heart"), for: .normal)
    }
} 