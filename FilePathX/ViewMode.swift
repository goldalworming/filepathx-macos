import Foundation

enum ViewMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case details
    case smallIcons
    case largeIcons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .details: return "Details"
        case .smallIcons: return "Small Icons"
        case .largeIcons: return "Large Icons"
        }
    }

    var systemImage: String {
        switch self {
        case .details: return "list.bullet"
        case .smallIcons: return "square.grid.3x3"
        case .largeIcons: return "square.grid.2x2"
        }
    }
}

enum SortColumn: String, Hashable, Codable {
    case name
    case kind
    case modified
    case size
}
