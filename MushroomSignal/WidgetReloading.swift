import WidgetKit

protocol WidgetReloading: Sendable {
    func reloadAllTimelines() async
}

struct SystemWidgetCenter: WidgetReloading {
    func reloadAllTimelines() async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
