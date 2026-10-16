import Foundation

enum RideauSalesState: Equatable {
    case upcoming
    case open
    case soldOut
    case unknown
}

extension RideauSalesState: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "upcoming": self = .upcoming
        case "open": self = .open
        case "sold_out": self = .soldOut
        default: self = .unknown
        }
    }
}

struct RideauEvent: Decodable, Identifiable, Equatable {
    let slug: String
    let title: String
    let startsAt: String
    let purchaseUrl: String
    let salesState: RideauSalesState

    let organizerName: String?
    let venue: String?
    let fromPriceOre: Int?
    let toPriceOre: Int?
    /// Skiljer "`to_price_ore` finns och är `null`" (inga biljettyper) från
    /// "fältet saknas helt" (äldre server, fallback-läge) — `decodeIfPresent`
    /// kan inte skilja de två åt på egen hand.
    let toPriceOreKeyPresent: Bool
    let freeTicketNames: [String]
    let posterLandscapeUrl: String?
    let posterPortraitUrl: String?
    let salesOpenAt: String?

    var id: String { slug }

    var posterUrl: String? { posterLandscapeUrl ?? posterPortraitUrl }

    enum CodingKeys: String, CodingKey {
        case slug, title, venue
        case startsAt = "starts_at"
        case purchaseUrl = "purchase_url"
        case salesState = "sales_state"
        case organizerName = "organizer_name"
        case fromPriceOre = "from_price_ore"
        case toPriceOre = "to_price_ore"
        case freeTicketNames = "free_ticket_names"
        case posterLandscapeUrl = "poster_landscape_url"
        case posterPortraitUrl = "poster_portrait_url"
        case salesOpenAt = "sales_open_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        title = try c.decode(String.self, forKey: .title)
        startsAt = try c.decode(String.self, forKey: .startsAt)
        purchaseUrl = try c.decode(String.self, forKey: .purchaseUrl)
        salesState = try c.decode(RideauSalesState.self, forKey: .salesState)
        organizerName = try c.decodeIfPresent(String.self, forKey: .organizerName)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        fromPriceOre = try c.decodeIfPresent(Int.self, forKey: .fromPriceOre)
        toPriceOreKeyPresent = c.contains(.toPriceOre)
        toPriceOre = try c.decodeIfPresent(Int.self, forKey: .toPriceOre)
        freeTicketNames = try c.decodeIfPresent([String].self, forKey: .freeTicketNames) ?? []
        posterLandscapeUrl = try c.decodeIfPresent(String.self, forKey: .posterLandscapeUrl)
        posterPortraitUrl = try c.decodeIfPresent(String.self, forKey: .posterPortraitUrl)
        salesOpenAt = try c.decodeIfPresent(String.self, forKey: .salesOpenAt)
    }

    init(
        slug: String,
        title: String,
        startsAt: String,
        purchaseUrl: String,
        salesState: RideauSalesState,
        organizerName: String? = nil,
        venue: String? = nil,
        fromPriceOre: Int? = nil,
        toPriceOre: Int? = nil,
        toPriceOreKeyPresent: Bool = true,
        freeTicketNames: [String] = [],
        posterLandscapeUrl: String? = nil,
        posterPortraitUrl: String? = nil,
        salesOpenAt: String? = nil
    ) {
        self.slug = slug
        self.title = title
        self.startsAt = startsAt
        self.purchaseUrl = purchaseUrl
        self.salesState = salesState
        self.organizerName = organizerName
        self.venue = venue
        self.fromPriceOre = fromPriceOre
        self.toPriceOre = toPriceOre
        self.toPriceOreKeyPresent = toPriceOreKeyPresent
        self.freeTicketNames = freeTicketNames
        self.posterLandscapeUrl = posterLandscapeUrl
        self.posterPortraitUrl = posterPortraitUrl
        self.salesOpenAt = salesOpenAt
    }
}

struct RideauEventsResponse: Decodable {
    let events: [RideauEvent]
    let serverTime: String

    enum CodingKeys: String, CodingKey {
        case events
        case serverTime = "server_time"
    }
}

nonisolated enum RideauISO8601 {
    static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
