import Foundation
import Combine

struct ShopifyLineItem: Codable, Hashable {
    let productId: Int?
    let title: String?
    let quantity: Int?
    let price: String?

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case title
        case quantity
        case price
    }
}

struct ShopifyOrder: Codable, Identifiable, Hashable {
    let id: Int
    let createdAt: String?
    let totalPrice: String?
    let financialStatus: String?
    let lineItems: [ShopifyLineItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case totalPrice = "total_price"
        case financialStatus = "financial_status"
        case lineItems = "line_items"
    }
}

struct ShopifyProductVariant: Codable, Hashable {
    let price: String?
}

struct ShopifyProductImage: Codable, Hashable {
    let src: String?
}

struct ShopifyProduct: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let variants: [ShopifyProductVariant]?
    let image: ShopifyProductImage?
}

struct ShopifyData: Codable {
    let updatedAt: String?
    let orders: [ShopifyOrder]
    let products: [ShopifyProduct]
}

@MainActor
final class ShopifyService: ObservableObject {
    @Published var data: ShopifyData?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sourceURL = URL(string: "https://raw.githubusercontent.com/nicklasstenlander/sds-dashboard/HEAD/public/data/shopify.json")!

    func loadShopifyData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: sourceURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            self.data = try JSONDecoder().decode(ShopifyData.self, from: data)
        } catch {
            errorMessage = "Kunde inte hämta Shopify-data. \(error.localizedDescription)"
        }
    }
}
