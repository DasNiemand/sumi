import Quickshell
import Quickshell.Io
import QtQuick

// Palette thô do Noctalia xuất ra (template user) tại ~/.config/sumi/colors.json.
// FileView theo dõi file nên màu đổi theo ngay khi đổi wallpaper/theme.
// Thiếu file -> dùng màu mặc định bên dưới (hành vi giống bản gốc).
FileView {
    id: sc
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/sumi/colors.json"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    adapter: JsonAdapter {
        property string primary: "#a9b8f0"
        property string on_primary: "#1c2a5c"
        property string surface: "#14161a"
        property string on_surface: "#e3e1e6"
        property string surface_variant: "#1f2126"
        property string on_surface_variant: "#9a9ba5"
        property string outline: "#5a6070"
    }
}
