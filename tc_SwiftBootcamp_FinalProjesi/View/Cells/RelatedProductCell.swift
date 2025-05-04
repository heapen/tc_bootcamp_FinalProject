import UIKit
import Kingfisher

class RelatedProductCell: UICollectionViewCell {
    
    static let identifier = "RelatedProductCell"
    
    // IBOutlet'ler
    @IBOutlet weak var productImageView: UIImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }
    
    private func setupUI() {
        // Hücre görünümünü düzenle
        contentView.backgroundColor = .systemGray6
        contentView.layer.cornerRadius = 10
        contentView.clipsToBounds = true
        
        // ImageView ayarları
        productImageView.contentMode = .scaleAspectFit
        productImageView.clipsToBounds = true
        productImageView.layer.cornerRadius = 8
    }
    
    func configure(with product: Product) {
        // Ürün adını ve fiyatını ayarla
        nameLabel.text = product.ad
        priceLabel.text = "\(product.fiyat) ₺"
        
        // Ürün resmini yükle
        if let imageURL = product.imageURL {
            productImageView.kf.setImage(with: imageURL, placeholder: UIImage(systemName: "photo"))
        } else {
            productImageView.image = UIImage(systemName: "photo")
        }
    }
} 