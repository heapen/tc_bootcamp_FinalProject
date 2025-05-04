import Foundation

struct CartItem: Codable, Equatable {
    let sepetId: Int
    let ad: String
    let resim: String
    let kategori: String
    let fiyat: Int
    let marka: String
    let siparisAdeti: Int
    let kullaniciAdi: String
    let isPromotionPackage: Bool
    let packageDescription: String
    
    enum CodingKeys: String, CodingKey {
        case sepetId = "sepet_id"
        case ad
        case resim
        case kategori
        case fiyat
        case marka
        case siparisAdeti = "siparisAdeti"
        case kullaniciAdi = "kullaniciAdi"
        case isPromotionPackage = "isPromotionPackage"
        case packageDescription = "packageDescription"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // sepetId integer veya string olabilir
        if let sepetIdInt = try? container.decode(Int.self, forKey: .sepetId) {
            sepetId = sepetIdInt
        } else if let sepetIdString = try? container.decode(String.self, forKey: .sepetId),
                  let sepetIdInt = Int(sepetIdString) {
            sepetId = sepetIdInt
        } else {
            // Varsayılan değer
            sepetId = 0
        }
        
        // Diğer string alanlar
        ad = try container.decode(String.self, forKey: .ad)
        resim = try container.decode(String.self, forKey: .resim)
        kategori = try container.decode(String.self, forKey: .kategori)
        marka = try container.decode(String.self, forKey: .marka)
        kullaniciAdi = try container.decode(String.self, forKey: .kullaniciAdi)
        
        // fiyat integer veya string olabilir
        if let fiyatInt = try? container.decode(Int.self, forKey: .fiyat) {
            fiyat = fiyatInt
        } else if let fiyatString = try? container.decode(String.self, forKey: .fiyat),
                  let fiyatInt = Int(fiyatString) {
            fiyat = fiyatInt
        } else {
            // Varsayılan değer
            fiyat = 0
        }
        
        // siparisAdeti integer veya string olabilir
        if let siparisAdetiInt = try? container.decode(Int.self, forKey: .siparisAdeti) {
            siparisAdeti = siparisAdetiInt
        } else if let siparisAdetiString = try? container.decode(String.self, forKey: .siparisAdeti),
                  let siparisAdetiInt = Int(siparisAdetiString) {
            siparisAdeti = siparisAdetiInt
        } else {
            // Varsayılan değer
            siparisAdeti = 1
        }
        
        // Kampanya paketi özellikleri - opsiyonel olarak decode et
        isPromotionPackage = (try? container.decodeIfPresent(Bool.self, forKey: .isPromotionPackage)) ?? false
        packageDescription = (try? container.decodeIfPresent(String.self, forKey: .packageDescription)) ?? ""
    }
    
    // Equatable uygulaması - iki CartItem nesnesinin eşit olup olmadığını kontrol eder
    static func == (lhs: CartItem, rhs: CartItem) -> Bool {
        return lhs.sepetId == rhs.sepetId &&
               lhs.ad == rhs.ad &&
               lhs.resim == rhs.resim &&
               lhs.kategori == rhs.kategori &&
               lhs.fiyat == rhs.fiyat &&
               lhs.marka == rhs.marka &&
               lhs.siparisAdeti == rhs.siparisAdeti &&
               lhs.kullaniciAdi == rhs.kullaniciAdi &&
               lhs.isPromotionPackage == rhs.isPromotionPackage &&
               lhs.packageDescription == rhs.packageDescription
    }
    
    var imageURL: URL? {
        // Resim URL'sini oluştur
        let baseURLString = "http://kasimadalan.pe.hu/urunler/resimler/"
        let urlString = baseURLString + resim
        
        // URL oluşturulamadıysa nil döndür
        guard let url = URL(string: urlString) else {
            print("⚠️ Invalid image URL for cart item: \(ad)")
            return nil
        }
        
        return url
    }
    
    // Yedek resim URL'si (ana URL erişilemez olduğunda kullanılır)
    var fallbackImageURL: URL? {
        // Placeholder olarak kullanılabilecek bir resim URL'si
        return URL(string: "https://placehold.co/400x400/4b91f7/white?text=\(ad.prefix(1))")
    }
    
    // Ürünün fiyatını formatlanmış string olarak döndürür
    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.currencySymbol = "₺"
        
        if let formattedString = formatter.string(from: NSNumber(value: fiyat)) {
            return formattedString
        } else {
            return "\(fiyat) ₺"
        }
    }
    
    // Toplam tutarı formatlanmış string olarak döndürür
    var formattedTotalPrice: String {
        let total = fiyat * siparisAdeti
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.currencySymbol = "₺"
        
        if let formattedString = formatter.string(from: NSNumber(value: total)) {
            return formattedString
        } else {
            return "\(total) ₺"
        }
    }
    
    // Manuel init için ekleyelim
    init(sepetId: Int, ad: String, resim: String, kategori: String, fiyat: Int, marka: String, siparisAdeti: Int, kullaniciAdi: String, isPromotionPackage: Bool = false, packageDescription: String = "") {
        self.sepetId = sepetId
        self.ad = ad
        self.resim = resim
        self.kategori = kategori
        self.fiyat = fiyat
        self.marka = marka
        self.siparisAdeti = siparisAdeti
        self.kullaniciAdi = kullaniciAdi
        self.isPromotionPackage = isPromotionPackage
        self.packageDescription = packageDescription
    }
}

struct CartResponse: Codable {
    let urunler_sepeti: [CartItem]
    let success: Int
    
    enum CodingKeys: String, CodingKey {
        case urunler_sepeti = "urunler_sepeti"
        case success = "success"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Success değeri farklı tipte olabilir
        if let successInt = try? container.decode(Int.self, forKey: .success) {
            success = successInt
        } else if let successString = try? container.decode(String.self, forKey: .success),
                  let successInt = Int(successString) {
            success = successInt
        } else {
            // HTTP 200 kodu ile gelen yanıtlar için varsayılan olarak başarı kabul edelim
            success = 1
        }
        
        // Sepet öğeleri farklı anahtarlar altında olabilir
        if let items = try? container.decode([CartItem].self, forKey: .urunler_sepeti) {
            urunler_sepeti = items
        } else {
            // Boş sepet
            urunler_sepeti = []
        }
    }
} 