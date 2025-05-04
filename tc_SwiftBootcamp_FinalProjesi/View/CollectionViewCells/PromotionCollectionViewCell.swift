import UIKit
import Kingfisher

class PromotionCollectionViewCell: UICollectionViewCell {
    
    static let identifier = "PromotionCollectionViewCell"
    
    // UI Bileşenleri - XIB bağlantıları
    @IBOutlet weak var firstImageView: UIImageView!
    @IBOutlet weak var secondImageView: UIImageView!
    @IBOutlet weak var firstNameLabel: UILabel!
    @IBOutlet weak var secondNameLabel: UILabel!
    @IBOutlet weak var firstPriceLabel: UILabel!
    @IBOutlet weak var secondPriceLabel: UILabel!
    @IBOutlet weak var discountContainerView: UIView!
    @IBOutlet weak var discountLabel: UILabel!
    @IBOutlet weak var addToCartButton: UIButton!
    @IBOutlet weak var discountBadge: UILabel!
    
    // Callback for add to cart action
    var addToCartTapped: (() -> Void)?
    
    // Kampaynalı ürünler ve hesaplanan indirimli fiyat
    private var product1: Product?
    private var product2: Product?
    private var discountedTotalPrice: Int = 0
    
    // MARK: - Lifecycle
    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        // Tıklanabilirliği belirtmek için buton tasarımını düzenleme
        addToCartButton.backgroundColor = .clear
        
        // İndirim görünümün köşelerini yuvarla
        discountContainerView.layer.cornerRadius = 8
        discountContainerView.layer.masksToBounds = true
        
        // İndirim rozeti ayarları
        discountBadge.layer.masksToBounds = true
        discountBadge.layer.cornerRadius = 8
    }
    
    // MARK: - Actions
    
    @IBAction func addToCartButtonTapped(_ sender: UIButton) {
        // Butonun basıldığına dair görsel geri bildirim için animasyon
        UIView.animate(withDuration: 0.1, animations: {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            self.discountContainerView.backgroundColor = UIColor.systemGreen.darker()
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                sender.transform = CGAffineTransform.identity
                self.discountContainerView.backgroundColor = UIColor.systemGreen
            }
        }
        
        // Geri çağırma fonksiyonunu çalıştır
        addToCartTapped?()
    }
    
    // MARK: - Configuration
    func configure(with product1: Product, and product2: Product, discountRate: Double = 0.15) {
        // Ürünleri kaydet
        self.product1 = product1
        self.product2 = product2
        
        // Product 1
        firstNameLabel.text = product1.ad
        firstPriceLabel.text = "\(product1.fiyat) ₺"
        
        // Product 2
        secondNameLabel.text = product2.ad
        secondPriceLabel.text = "\(product2.fiyat) ₺"
        
        // İndirim ve toplam fiyat hesaplama
        let totalPrice = product1.fiyat + product2.fiyat
        let discountAmount = Int(Double(totalPrice) * discountRate)
        let discountedPrice = totalPrice - discountAmount
        
        // İndirimli fiyatı kaydet
        self.discountedTotalPrice = discountedPrice
        
        // Yüzde olarak indirim oranı
        let discountPercentage = Int(discountRate * 100)
        
        // İndirim bilgisi güncelleme - sadece fiyat göster
        discountLabel.text = "\(discountedPrice) ₺"
        
        // İndirim rozeti - % işaretini güncelle
        discountBadge.text = "%\(discountPercentage)"
        discountBadge.backgroundColor = .systemRed
        
        // Orijinal fiyatlar
        let originalPrice1 = NSMutableAttributedString(string: "\(product1.fiyat) ₺")
        originalPrice1.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: originalPrice1.length))
        firstPriceLabel.attributedText = originalPrice1
        
        let originalPrice2 = NSMutableAttributedString(string: "\(product2.fiyat) ₺")
        originalPrice2.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: originalPrice2.length))
        secondPriceLabel.attributedText = originalPrice2
        
        // Ürün resimlerini yükle
        if let imageURL1 = product1.imageURL {
            firstImageView.kf.setImage(with: imageURL1, placeholder: UIImage(systemName: "photo"))
        } else {
            firstImageView.image = UIImage(systemName: "photo")
        }
        
        if let imageURL2 = product2.imageURL {
            secondImageView.kf.setImage(with: imageURL2, placeholder: UIImage(systemName: "photo"))
        } else {
            secondImageView.image = UIImage(systemName: "photo")
        }
    }
    
    // Kampanya bilgilerini döndüren yardımcı metod
    func getPromotionInfo() -> (product1: Product, product2: Product, discountedPrice: Int)? {
        guard let product1 = self.product1, let product2 = self.product2 else {
            return nil
        }
        return (product1, product2, discountedTotalPrice)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        firstImageView.image = nil
        secondImageView.image = nil
        firstNameLabel.text = nil
        secondNameLabel.text = nil
        firstPriceLabel.text = nil
        secondPriceLabel.text = nil
        discountLabel.text = nil
        discountBadge.text = nil
        product1 = nil
        product2 = nil
        discountedTotalPrice = 0
    }
}

// UIColor extension to create darker variant for button animation
extension UIColor {
    func darker(by percentage: CGFloat = 0.2) -> UIColor {
        return self.adjustBrightness(by: -percentage)
    }
    
    func adjustBrightness(by percentage: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if self.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return UIColor(hue: h, saturation: s, brightness: max(min(b + percentage, 1.0), 0.0), alpha: a)
        }
        return self
    }
} 