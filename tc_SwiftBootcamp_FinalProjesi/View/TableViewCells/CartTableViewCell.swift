import UIKit
import Kingfisher

class CartTableViewCell: UITableViewCell {
    
    static let identifier = "CartTableViewCell"
    
    // UI Bileşenleri - XIB Bağlantıları
    @IBOutlet weak var productImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var brandLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    @IBOutlet weak var totalPriceLabel: UILabel!
    @IBOutlet weak var quantityLabel: UILabel!
    @IBOutlet weak var packageBadge: UILabel!
    @IBOutlet weak var packageDescriptionLabel: UILabel!
    @IBOutlet weak var removeButton: UIButton!
    @IBOutlet weak var totalAmountLabel: UILabel!
    
    var removeButtonTapped: (() -> Void)?
    
    // MARK: - Lifecycle
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    // MARK: - Actions
    
    @IBAction func removeButtonAction(_ sender: UIButton) {
        removeButtonTapped?()
    }
    
    // MARK: - Configuration
    
    func configure(with cartItem: CartItem) {
        nameLabel.text = cartItem.ad
        brandLabel.text = cartItem.marka
        priceLabel.text = cartItem.formattedPrice
        quantityLabel.text = "Adet: \(cartItem.siparisAdeti)"
        
        // Ana toplam fiyat etiketini güncelle (her zaman göster)
        totalAmountLabel.text = "Toplam: \(cartItem.formattedTotalPrice)"
        totalAmountLabel.isHidden = false
        
        // Eski toplam fiyat etiketini gizle (artık kullanılmıyor)
        totalPriceLabel.isHidden = true
        
        // Kampanya paketi kontrolü
        if cartItem.isPromotionPackage {
            packageBadge.isHidden = false
            packageDescriptionLabel.isHidden = false
            packageDescriptionLabel.text = cartItem.packageDescription
            nameLabel.textColor = .systemGreen
            contentView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.05)
        } else {
            packageBadge.isHidden = true
            packageDescriptionLabel.isHidden = true
            nameLabel.textColor = .label
            contentView.backgroundColor = .clear
        }
        
        // Ürün resmini yükle
        if let imageURL = cartItem.imageURL {
            productImageView.kf.setImage(with: imageURL, placeholder: UIImage(systemName: "photo"))
        } else {
            productImageView.image = UIImage(systemName: "photo")
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        productImageView.image = nil
        nameLabel.text = nil
        brandLabel.text = nil
        priceLabel.text = nil
        totalPriceLabel.text = nil
        totalPriceLabel.isHidden = true
        totalAmountLabel.text = nil
        totalAmountLabel.isHidden = false
        quantityLabel.text = nil
        packageBadge.isHidden = true
        packageDescriptionLabel.isHidden = true
        packageDescriptionLabel.text = nil
        nameLabel.textColor = .label
        contentView.backgroundColor = .clear
    }
} 