import Foundation

struct SidebarItem: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var path: String
    var systemImage: String

    var url: URL { URL(fileURLWithPath: path) }

    init(id: UUID = UUID(), name: String, url: URL, systemImage: String) {
        self.id = id
        self.name = name
        self.path = url.path
        self.systemImage = systemImage
    }

    static var defaults: [SidebarItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        return [
            SidebarItem(name: "Home",        url: home,                                             systemImage: "house"),
            SidebarItem(name: "Desktop",     url: home.appendingPathComponent("Desktop"),           systemImage: "menubar.dock.rectangle"),
            SidebarItem(name: "Documents",   url: home.appendingPathComponent("Documents"),         systemImage: "doc"),
            SidebarItem(name: "Downloads",   url: home.appendingPathComponent("Downloads"),         systemImage: "arrow.down.circle"),
            SidebarItem(name: "Pictures",    url: home.appendingPathComponent("Pictures"),          systemImage: "photo"),
            SidebarItem(name: "Movies",      url: home.appendingPathComponent("Movies"),            systemImage: "film"),
            SidebarItem(name: "Music",       url: home.appendingPathComponent("Music"),             systemImage: "music.note"),
            SidebarItem(name: "Applications", url: URL(fileURLWithPath: "/Applications"),           systemImage: "app.badge"),
        ]
    }
}
