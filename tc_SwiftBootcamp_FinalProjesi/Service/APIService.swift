import Foundation
import Alamofire
import RxSwift
import Network

enum APIError: Error, Equatable {
    case networkError(String)
    case decodingError
    case noData
    case statusError
    case connectionError
    case timeoutError
    case serverError(Int)
    
    var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Ağ hatası oluştu: \(message)"
        case .decodingError:
            return "Veri ayrıştırma hatası."
        case .noData:
            return "Veri bulunamadı."
        case .statusError:
            return "İşlem başarısız."
        case .connectionError:
            return "Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin."
        case .timeoutError:
            return "İstek zaman aşımına uğradı. Lütfen daha sonra tekrar deneyin."
        case .serverError(let code):
            return "Sunucu hatası: \(code)"
        }
    }
    
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.decodingError, .decodingError),
             (.noData, .noData),
             (.statusError, .statusError),
             (.connectionError, .connectionError),
             (.timeoutError, .timeoutError):
            return true
        case (.networkError(let lhsMessage), .networkError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        default:
            return false
        }
    }
}

class APIService {
    static let shared = APIService()
    let username = "batuhan_celik"
    private let baseURL = "http://kasimadalan.pe.hu/urunler"
    private let networkMonitor = NWPathMonitor()
    private let timeout: TimeInterval = 30.0
    
    // URLSession için configuration
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = true // Bağlantı bekler
        return URLSession(configuration: config)
    }()
    
    // Aktif ağ isteklerini takip etmek için
    private var activeTasks: [URLSessionTask] = []
    private let taskQueue = DispatchQueue(label: "com.apiservice.taskQueue")
    
    var isNetworkAvailable: Bool = true
    
    private init() {
        setupNetworkMonitoring()
        configureAlamofire()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    private func getConnectionType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Other"
        }
    }
    
    private func configureAlamofire() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        
        AF.sessionConfiguration.timeoutIntervalForRequest = timeout
        AF.sessionConfiguration.timeoutIntervalForResource = timeout
    }
    
    private func checkNetworkBeforeRequest() -> Error? {
        if !isNetworkAvailable {
            return APIError.connectionError
        }
        return nil
    }
    
    // Tüm ürünleri getir
    func fetchAllProducts() -> Observable<[Product]> {
        return Observable.create { observer in
            // Check network status first
            if let error = self.checkNetworkBeforeRequest() {
                observer.onError(error)
                return Disposables.create()
            }
            
            let url = "\(self.baseURL)/tumUrunleriGetir.php"
            
            AF.request(url, method: .get)
                .validate()
                .responseDecodable(of: ProductResponse.self) { response in
                
                switch response.result {
                case .success(let data):
                    if data.success == 1 {
                        observer.onNext(data.urunler)
                        observer.onCompleted()
                    } else {
                        observer.onError(APIError.statusError)
                    }
                case .failure(let error):
                    // More detailed error handling
                    if let urlError = error.underlyingError as? URLError {
                        switch urlError.code {
                        case .timedOut:
                            observer.onError(APIError.timeoutError)
                        case .notConnectedToInternet, .networkConnectionLost:
                            observer.onError(APIError.connectionError)
                        default:
                            observer.onError(APIError.networkError(urlError.localizedDescription))
                        }
                    } else if let statusCode = response.response?.statusCode {
                        observer.onError(APIError.serverError(statusCode))
                    } else {
                        observer.onError(APIError.networkError(error.localizedDescription))
                    }
                }
            }
            
            return Disposables.create()
        }
    }
    
    // Sepete ürün ekle
    func addToCart(product: Product, quantity: Int) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onError(APIError.networkError("APIService instance is nil"))
                return Disposables.create()
            }
            
            // Check network status first
            if let error = self.checkNetworkBeforeRequest() {
                observer.onError(error)
                return Disposables.create()
            }
            
            let url = "\(self.baseURL)/sepeteEkle.php"
            
            let parameters: [String: Any] = [
                "ad": product.ad,
                "resim": product.resim,
                "fiyat": product.fiyat,
                "kategori": product.kategori,
                "marka": product.marka,
                "siparisAdeti": quantity,
                "kullaniciAdi": self.username
            ]
            
            // URL'nin geçerli olduğundan emin ol
            guard let requestURL = URL(string: url) else {
                observer.onError(APIError.networkError("Invalid URL: \(url)"))
                return Disposables.create()
            }
            
            // Raw HTTP isteği kullan
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = self.timeout
            
            // Parametreleri URL encode et
            let postString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = postString.data(using: .utf8)
            
            // URLSessionTask nesnesini oluştur
            let task = self.session.dataTask(with: request) { [weak self] data, response, error in
                // İstek iptal edildi mi kontrolü
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    // İstek iptal edildiyse bile başarılı kabul et
                    DispatchQueue.main.async {
                        observer.onNext(true)
                        observer.onCompleted()
                    }
                    return
                }
                
                // Network error
                if let error = error {
                    DispatchQueue.main.async {
                        observer.onError(APIError.networkError(error.localizedDescription))
                    }
                    return
                }
                
                // Response bilgisini yazdır
                if let httpResponse = response as? HTTPURLResponse {
                }
                
                // Veri kontrolü
                guard let data = data else {
                    // Veri yoksa ama başarılı HTTP kodu varsa, başarılı kabul et
                    if let httpResponse = response as? HTTPURLResponse, 
                       (200...299).contains(httpResponse.statusCode) {
                        DispatchQueue.main.async {
                            observer.onNext(true)
                            observer.onCompleted()
                        }
                    } else {
                        DispatchQueue.main.async {
                            observer.onError(APIError.noData)
                        }
                    }
                    return
                }
                
                // Ham yanıtı yazdır
                let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                
                // HTTP 2xx durum kodu başarılı kabul et
                if let httpResponse = response as? HTTPURLResponse, 
                   (200...299).contains(httpResponse.statusCode) {
                    // Yanıt içeriğindeki başarı göstergelerini kontrol et
                    if rawResponseString.contains("success") || 
                       rawResponseString.contains("1") || 
                       rawResponseString.contains("basarili") {
                        DispatchQueue.main.async {
                            observer.onNext(true)
                            observer.onCompleted()
                        }
                        return
                    }
                    
                    // Başarı göstergesi bulunamasa bile HTTP 2xx olduğu için başarılı kabul et
                    DispatchQueue.main.async {
                        observer.onNext(true)
                        observer.onCompleted()
                    }
                } else {
                    // HTTP hatası
                    if let httpResponse = response as? HTTPURLResponse {
                        DispatchQueue.main.async {
                            observer.onError(APIError.serverError(httpResponse.statusCode))
                        }
                    } else {
                        DispatchQueue.main.async {
                            observer.onNext(false)
                            observer.onCompleted()
                        }
                    }
                }
            }
            
            // Task'i aktif listeye ekle
            self.addActiveTask(task)
            
            // İsteği başlat
            task.resume()
            
            return Disposables.create {
                // Disposable'ın temizlenmesi sırasında task iptal edilirse,
                // sadece task hala çalışıyorsa iptal edilmeli
                if task.state == .running || task.state == .suspended {
                    task.cancel()
                    self.removeActiveTask(task)
                }
            }
        }
    }
    
    // Aktif task'i ekle
    private func addActiveTask(_ task: URLSessionTask) {
        taskQueue.async {
            self.activeTasks.append(task)
        }
    }
    
    // Tamamlanan task'i kaldır
    private func removeActiveTask(_ task: URLSessionTask) {
        taskQueue.async {
            self.activeTasks.removeAll { $0 == task }
        }
    }
    
    // Tüm aktif istekleri iptal et
    private func cancelAllActiveTasks() {
        taskQueue.async {
            for task in self.activeTasks {
                task.cancel()
            }
            self.activeTasks.removeAll()
        }
    }
    
    // Sepetteki ürünleri getir
    func fetchCartItems() -> Observable<[CartItem]> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onError(APIError.networkError("APIService instance is nil"))
                return Disposables.create()
            }
            
            // Check network status first
            if let error = self.checkNetworkBeforeRequest() {
                observer.onError(error)
                return Disposables.create()
            }
            
            let url = "\(self.baseURL)/sepettekiUrunleriGetir.php"
            
            let parameters: [String: Any] = [
                "kullaniciAdi": self.username
            ]
            
            // URL'nin geçerli olduğundan emin ol
            guard let requestURL = URL(string: url) else {
                observer.onError(APIError.networkError("Invalid URL: \(url)"))
                return Disposables.create()
            }
            
            // Raw HTTP isteği kullan
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = self.timeout
            
            // Parametreleri URL encode et
            let postString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = postString.data(using: .utf8)
            
            // URLSessionTask oluştur
            let task = self.session.dataTask(with: request) { [weak self] data, response, error in
                // İstek iptal edildi mi kontrolü
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    // İstek iptal edildiyse boş sepet döndür
                    DispatchQueue.main.async {
                        observer.onNext([])
                        observer.onCompleted()
                    }
                    return
                }
                
                // Network error
                if let error = error {
                    DispatchQueue.main.async {
                        observer.onError(APIError.networkError(error.localizedDescription))
                    }
                    return
                }
                
                // Response bilgisini yazdır
                if let httpResponse = response as? HTTPURLResponse {
                }
                
                // Veri kontrolü
                guard let data = data else {
                    // Boş sepet döndür
                    DispatchQueue.main.async {
                        observer.onNext([])
                        observer.onCompleted()
                    }
                    return
                }
                
                // Ham yanıtı yazdır
                let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                
                // Boş sepet kontrolü
                if rawResponseString.contains("urunler_sepeti\":[]") || 
                   rawResponseString.contains("\"success\":0") || 
                   rawResponseString.contains("\"success\": 0") ||
                   rawResponseString.contains("Sepette urun yok") {
                    DispatchQueue.main.async {
                        observer.onNext([])
                        observer.onCompleted()
                    }
                    return
                }
                
                // JSON ayrıştırma
                do {
                    let response = try JSONDecoder().decode(CartResponse.self, from: data)
                    
                    DispatchQueue.main.async {
                        if response.success == 1 {
                            observer.onNext(response.urunler_sepeti)
                        } else {
                            // Başarı değeri 0 ise boş liste döndür
                            observer.onNext([])
                        }
                        observer.onCompleted()
                    }
                } catch {
                    // JSON ayrıştırma hatası durumunda da boş sepet döndür
                    DispatchQueue.main.async {
                        observer.onNext([])
                        observer.onCompleted()
                    }
                }
            }
            
            // Task'i aktif listeye ekle
            self.addActiveTask(task)
            
            // İsteği başlat
            task.resume()
            
            return Disposables.create {
                // Disposable'ın temizlenmesi sırasında task iptal edilirse,
                // sadece task hala çalışıyorsa iptal edilmeli
                if task.state == .running || task.state == .suspended {
                    task.cancel()
                    self.removeActiveTask(task)
                }
            }
        }
    }
    
    // Sepetten ürün sil
    func removeFromCart(cartItem: CartItem) -> Observable<Bool> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onError(APIError.networkError("APIService instance is nil"))
                return Disposables.create()
            }
            
            // Check network status first
            if let error = self.checkNetworkBeforeRequest() {
                observer.onError(error)
                return Disposables.create()
            }
            
            let url = "\(self.baseURL)/sepettenUrunSil.php"
            
            let parameters: [String: Any] = [
                "sepetId": cartItem.sepetId,
                "kullaniciAdi": self.username
            ]
            
            // URL'nin geçerli olduğundan emin ol
            guard let requestURL = URL(string: url) else {
                observer.onError(APIError.networkError("Invalid URL: \(url)"))
                return Disposables.create()
            }
            
            // Raw HTTP isteği kullan
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = self.timeout
            
            // Parametreleri URL encode et
            let postString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = postString.data(using: .utf8)
            
            // URLSessionTask oluştur
            let task = self.session.dataTask(with: request) { [weak self] data, response, error in
                // İstek iptal edildi mi kontrolü
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    // İstek iptal edildiyse bile başarılı kabul et
                    DispatchQueue.main.async {
                        observer.onNext(true)
                        observer.onCompleted()
                    }
                    return
                }
                
                // Network error
                if let error = error {
                    DispatchQueue.main.async {
                        observer.onError(APIError.networkError(error.localizedDescription))
                    }
                    return
                }
                
                // Response bilgisini yazdır
                if let httpResponse = response as? HTTPURLResponse {
                }
                
                // Veri kontrolü
                guard let data = data else {
                    // Veri yoksa ama başarılı HTTP kodu varsa, başarılı kabul et
                    if let httpResponse = response as? HTTPURLResponse, 
                       (200...299).contains(httpResponse.statusCode) {
                        DispatchQueue.main.async {
                            observer.onNext(true)
                            observer.onCompleted()
                        }
                    } else {
                        DispatchQueue.main.async {
                            observer.onError(APIError.noData)
                        }
                    }
                    return
                }
                
                // Ham yanıtı yazdır
                let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode response data"
                
                // HTTP 2xx durum kodu başarılı kabul et
                if let httpResponse = response as? HTTPURLResponse, 
                   (200...299).contains(httpResponse.statusCode) {
                    // Yanıt içeriğindeki başarı göstergelerini kontrol et
                    if rawResponseString.contains("success") || 
                       rawResponseString.contains("1") || 
                       rawResponseString.contains("basarili") {
                        DispatchQueue.main.async {
                            observer.onNext(true)
                            observer.onCompleted()
                        }
                        return
                    }
                    
                    // Başarı göstergesi bulunamasa bile HTTP 2xx olduğu için başarılı kabul et
                    DispatchQueue.main.async {
                        observer.onNext(true)
                        observer.onCompleted()
                    }
                } else {
                    // HTTP hatası
                    if let httpResponse = response as? HTTPURLResponse {
                        DispatchQueue.main.async {
                            observer.onError(APIError.serverError(httpResponse.statusCode))
                        }
                    } else {
                        DispatchQueue.main.async {
                            observer.onNext(false)
                            observer.onCompleted()
                        }
                    }
                }
            }
            
            // Task'i aktif listeye ekle
            self.addActiveTask(task)
            
            // İsteği başlat
            task.resume()
            
            return Disposables.create {
                // Disposable'ın temizlenmesi sırasında task iptal edilirse,
                // sadece task hala çalışıyorsa iptal edilmeli
                if task.state == .running || task.state == .suspended {
                    task.cancel()
                    self.removeActiveTask(task)
                }
            }
        }
        .handleCartErrors() // JSON hatalarını yakala ve başarı varsay
    }
    
    // API'nin ayakta olup olmadığını kontrol et
    func pingAPI() -> Observable<Bool> {
        return Observable.create { observer in
            // Check network status first
            if !self.isNetworkAvailable {
                observer.onNext(false)
                observer.onCompleted()
                return Disposables.create()
            }
            
            // API durumunu tespit etmek için basit bir GET isteği
            let url = "\(self.baseURL)/tumUrunleriGetir.php"
            
            AF.request(url, method: .get, requestModifier: { request in
                request.timeoutInterval = 5.0 // Shorter timeout for ping
            }).response { response in
                if let error = response.error {
                    observer.onNext(false)
                } else if let statusCode = response.response?.statusCode {
                    let success = statusCode >= 200 && statusCode < 300
                    observer.onNext(success)
                } else {
                    observer.onNext(false)
                }
                observer.onCompleted()
            }
            
            return Disposables.create()
        }
    }
    
    // API bağlantı bilgilerini kontrol et ve detaylı teşhis bilgisi döndür
    func diagnoseConnection() -> Observable<String> {
        return Observable.create { observer in
            var diagnosticInfo = "📊 Bağlantı Teşhisi:\n"
            
            // 1. Ağ bağlantısı kontrolü
            diagnosticInfo += "- Ağ Bağlantısı: \(self.isNetworkAvailable ? "✅ Mevcut" : "❌ Yok")\n"
            
            // 2. API ping testi
            self.pingAPI().subscribe(onNext: { isAlive in
                diagnosticInfo += "- API Erişilebilirliği: \(isAlive ? "✅ Erişilebilir" : "❌ Erişilemedi")\n"
                
                // 3. Host kontrol
                let host = URL(string: self.baseURL)?.host ?? "kasimadalan.pe.hu"
                diagnosticInfo += "- Host: \(host)\n"
                
                // DNS çözümleme testi yerine URL testi kullan
                let hostTestURL = URL(string: "http://\(host)")
                
                if let hostTestURL = hostTestURL {
                    let hostTestTask = URLSession.shared.dataTask(with: hostTestURL) { _, response, error in
                        let success = error == nil && (response as? HTTPURLResponse)?.statusCode != nil
                        
                        DispatchQueue.main.async {
                            diagnosticInfo += "- Host Erişilebilirliği (\(host)): \(success ? "✅ Erişilebilir" : "❌ Erişilemedi")\n"
                            
                            // 4. API endpoint bilgileri
                            diagnosticInfo += "- API Base URL: \(self.baseURL)\n"
                            
                            // 5. Öneriler
                            diagnosticInfo += "\n🔧 Öneriler:\n"
                            
                            if !self.isNetworkAvailable {
                                diagnosticInfo += "- İnternet bağlantınızı kontrol edin\n"
                                diagnosticInfo += "- WiFi veya mobil veri açık olduğundan emin olun\n"
                            } else if !isAlive {
                                diagnosticInfo += "- API sunucusu geçici olarak erişilemez olabilir, daha sonra tekrar deneyin\n"
                                diagnosticInfo += "- API URL'sinin doğruluğunu kontrol edin\n"
                                diagnosticInfo += "- Firewall veya ağ kısıtlamaları olabilir\n"
                            }
                            
                            observer.onNext(diagnosticInfo)
                            observer.onCompleted()
                        }
                    }
                    
                    hostTestTask.resume()
                } else {
                    diagnosticInfo += "- Host Erişilebilirliği (\(host)): ❌ Geçersiz URL\n"
                    
                    // 4. API endpoint bilgileri
                    diagnosticInfo += "- API Base URL: \(self.baseURL)\n"
                    
                    // 5. Öneriler
                    diagnosticInfo += "\n🔧 Öneriler:\n"
                    
                    if !self.isNetworkAvailable {
                        diagnosticInfo += "- İnternet bağlantınızı kontrol edin\n"
                        diagnosticInfo += "- WiFi veya mobil veri açık olduğundan emin olun\n"
                    } else if !isAlive {
                        diagnosticInfo += "- API sunucusu geçici olarak erişilemez olabilir, daha sonra tekrar deneyin\n"
                        diagnosticInfo += "- API URL'sinin doğruluğunu kontrol edin\n"
                        diagnosticInfo += "- Firewall veya ağ kısıtlamaları olabilir\n"
                    }
                    
                    observer.onNext(diagnosticInfo)
                    observer.onCompleted()
                }
            }).disposed(by: DisposeBag())
            
            return Disposables.create()
        }
    }
}

struct BaseResponse: Codable {
    let success: Int
    let message: String?
    
    // Decode sırasında hata oluşmasını önlemek için
    enum CodingKeys: String, CodingKey {
        case success = "success"
        case message = "message"
    }
    
    // Özel init metodu ekleyerek hatalı JSON durumlarını ele alalım
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Success integer, string, or boolean olabilir
        if let successInt = try? container.decode(Int.self, forKey: .success) {
            success = successInt
        } else if let successString = try? container.decode(String.self, forKey: .success),
                  let successInt = Int(successString) {
            success = successInt
        } else if let successBool = try? container.decode(Bool.self, forKey: .success) {
            success = successBool ? 1 : 0
        } else {
            // Eğer hiçbir şekilde success değerini çözemiyorsak,
            // HTTP Status Code 200 ise başarılı kabul edelim
            success = 1
        }
        
        // Message isteğe bağlı
        message = try? container.decode(String?.self, forKey: .message)
    }
    
    // Sunucudan gelen farklı yanıt formatlarını ele alabilmek için yardımcı bir metod
    static func parse(data: Data) -> Result<BaseResponse, Error> {
        do {
            // Önce normal decode işlemini deneyelim
            let response = try JSONDecoder().decode(BaseResponse.self, from: data)
            return .success(response)
        } catch {
            // JSONDecoder başarısız olursa, String olarak kontrol edelim
            if let responseStr = String(data: data, encoding: .utf8) {
                // Basit string kontrolü ile başarı durumunu tespit et
                if responseStr.contains("success") || 
                   responseStr.contains("basarili") || 
                   responseStr.contains("1") {
                    // Manuel bir BaseResponse oluştur
                    let manualResponse = BaseResponse(success: 1, message: responseStr)
                    return .success(manualResponse)
                }
            }
            
            return .failure(error)
        }
    }
    
    // Manuel init için constructor
    init(success: Int, message: String? = nil) {
        self.success = success
        self.message = message
    }
}

// Sepet işlemleri için hata yönetimi uzantısı
extension Observable {
    func handleCartErrors() -> Observable<Element> {
        return self.catch { error in
            // Sepet işlemlerinde kritik olmayan hataları yoksay ve başarılı kabul et
            if let apiError = error as? APIError {
                switch apiError {
                case .decodingError:
                    // JSON ayrıştırma hatası durumunda, işlemi başarılı kabul et
                    if Element.self == Bool.self {
                        return Observable<Element>.just(true as! Element)
                    }
                    // Diğer durumlarda hatayı tekrar fırlat
                    return Observable<Element>.error(error)
                default:
                    return Observable<Element>.error(error)
                }
            }
            return Observable<Element>.error(error)
        }
    }
} 