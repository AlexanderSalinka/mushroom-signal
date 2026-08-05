import Foundation

public enum RegionDatabase {
    public static let all: [Region] = [
        Region(id: "bratislavsky", nameSk: "Bratislavský kraj", latitude: 48.1486, longitude: 17.1077),
        Region(id: "trnavsky", nameSk: "Trnavský kraj", latitude: 48.3709, longitude: 17.5886),
        Region(id: "trenciansky", nameSk: "Trenčiansky kraj", latitude: 48.8945, longitude: 18.0444),
        Region(id: "nitriansky", nameSk: "Nitriansky kraj", latitude: 48.3081, longitude: 18.0873),
        Region(id: "zilinsky", nameSk: "Žilinský kraj", latitude: 49.2231, longitude: 18.7394),
        Region(id: "banskobystricky", nameSk: "Banskobystrický kraj", latitude: 48.7395, longitude: 19.1535),
        Region(id: "presovsky", nameSk: "Prešovský kraj", latitude: 49.0018, longitude: 21.2393),
        Region(id: "kosicky", nameSk: "Košický kraj", latitude: 48.7164, longitude: 21.2611)
    ]

    public static func find(id: String) -> Region? {
        all.first { $0.id == id }
    }
}
