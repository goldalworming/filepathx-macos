import SwiftUI

struct BrowserView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var tab: BrowserTab
    var isActive: Bool = true
    var onActivate: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBarView(tab: tab)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab.viewMode {
        case .details:
            DetailsView(tab: tab, isActive: isActive, onActivate: onActivate)
        case .smallIcons:
            IconGridView(tab: tab,
                         iconSize: 36, cellWidth: 88, cellHeight: 86,
                         isActive: isActive, onActivate: onActivate)
        case .largeIcons:
            IconGridView(tab: tab,
                         iconSize: 96, cellWidth: 140, cellHeight: 150,
                         isActive: isActive, onActivate: onActivate)
        }
    }
}
