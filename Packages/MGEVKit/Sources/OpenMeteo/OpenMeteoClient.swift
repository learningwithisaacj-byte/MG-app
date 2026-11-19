import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Air temperature and sunshine right now at one spot.
public struct Weather: Equatable, Codable, Sendable {
    /// Air temperature 2 m above ground, °C.
    public let tempC: Double
    /// How hot it feels (heat and humidity), °C.
    public let feelsLikeC: Double?
    /// Sunshine on a flat surface, W/m² (about 900 in full midday sun).
    public let sunWm2: Double
    public let isDay: Bool
    public let fetchedAt: Date

    public init(tempC: Double, feelsLikeC: Double?, sunWm2: Double, isDay: Bool, fetchedAt: Date) {
        self.tempC = tempC
        self.feelsLikeC = feelsLikeC
        self.sunWm2 = sunWm2
        self.isDay = isDay
        self.fetchedAt = fetchedAt
    }
}

public enum WeatherError: Error, Equatable {
    case http(Int)
    case unreadable
}

/// Current weather from Open-Meteo (https://open-meteo.com): free for non-commercial use, no API key.
/// The car stops updating its own temperatures once parked, so the outside temperature comes from here.
/// Answers are kept for 15 minutes per square of about 1 km, well inside Open-Meteo's fair-use limit.
/// Weather data by Open-Meteo.com, under CC BY 4.0: the app shows that credit wherever it shows the data.
public actor OpenMeteoClient {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let attribution = "Weather data by Open-Meteo.com"
    public static let cacheSeconds: TimeInterval = 15 * 60

    private let fetch: Fetch
    private let now: @Sendable () -> Date
    private let base: String
    private var cache: [String: Weather] = [:]

    public init(
        base: String = "https://api.open-meteo.com/v1/forecast",
        now: @escaping @Sendable () -> Date = { Date() },
        fetch: Fetch? = nil
    ) {
        self.base = base
        self.now = now
        self.fetch = fetch ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// The weather at `latitude`, `longitude` now, from the cache when a fresh answer for that square exists.
    public func current(latitude: Double, longitude: Double) async throws -> Weather {
        let key = Self.cacheKey(latitude, longitude)
        if let hit = cache[key], now().timeIntervalSince(hit.fetchedAt) < Self.cacheSeconds { return hit }
        var request = URLRequest(url: try url(latitude: latitude, longitude: longitude))
        request.timeoutInterval = 15
        let (data, status) = try await fetch(request)
        guard (200..<300).contains(status) else { throw WeatherError.http(status) }
        let weather = try Self.decode(data, fetchedAt: now())
        cache[key] = weather
        return weather
    }

    func url(latitude: Double, longitude: Double) throws -> URL {
        guard var c = URLComponents(string: base) else { throw WeatherError.unreadable }
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,shortwave_radiation,is_day"),
        ]
        guard let url = c.url else { throw WeatherError.unreadable }
        return url
    }

    /// About 1 km squares: two decimal places of a degree.
    static func cacheKey(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }

    private struct Reply: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double?
            let shortwave_radiation: Double?
            let is_day: Int?
        }
        let current: Current
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> Weather {
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { throw WeatherError.unreadable }
        let c = r.current
        return Weather(
            tempC: c.temperature_2m, feelsLikeC: c.apparent_temperature, sunWm2: c.shortwave_radiation ?? 0,
            isDay: (c.is_day ?? 1) == 1, fetchedAt: fetchedAt
        )
    }
}
