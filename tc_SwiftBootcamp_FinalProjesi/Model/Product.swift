import Foundation

struct Product: Codable {
    let id: Int
    let ad: String
    let resim: String
    let kategori: String
    let fiyat: Int
    let marka: String
    
    var isFavorite: Bool? = false
    
    enum CodingKeys: String, CodingKey {
        case id, ad, resim, kategori, fiyat, marka
    }
    
    // Constructor ekleyelim
    init(id: Int, ad: String, resim: String, kategori: String, fiyat: Int, marka: String, isFavorite: Bool? = false) {
        self.id = id
        self.ad = ad
        self.resim = resim
        self.kategori = kategori
        self.fiyat = fiyat
        self.marka = marka
        self.isFavorite = isFavorite
    }
    
    var imageURL: URL? {
        // Resim URL'sini oluştur
        let baseURLString = "http://kasimadalan.pe.hu/urunler/resimler/"
        let urlString = baseURLString + resim
        
        // URL oluşturulamadıysa nil döndür
        guard let url = URL(string: urlString) else {
            print("⚠️ Invalid image URL for product: \(ad)")
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
}

struct ProductResponse: Codable {
    let urunler: [Product]
    let success: Int
} 
