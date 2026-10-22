import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GladeCore

private let plum = Color(.sRGB, red: 0x2A / 255.0, green: 0x1A / 255.0, blue: 0x26 / 255.0, opacity: 1)
private let paper = Color(.sRGB, red: 1, green: 0xF4 / 255.0, blue: 0xDC / 255.0, opacity: 1)

struct LooksTab: View {
    private let store = LookStore()
    @State private var looks = LookStore().all()
    @State private var config = Config.load()
    @State private var pending: PendingPhoto?
    @State private var message = ""
    @State private var dropping = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 14) {
                    ForEach(looks) { look in card(look) }
                }
                .padding(4)
            }
            .frame(height: 240)
            HStack {
                Button("Add photo…") { choosePhoto() }
                Text(message.isEmpty ? "Or drop a photo here. Photos are turned into pixel art on your Mac and never uploaded."
                                     : message)
                    .font(.callout).foregroundColor(message.isEmpty ? .secondary : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Click a look to choose it. Right-click one of your own looks to delete it.")
                .font(.footnote).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: dropping ? 2 : 0))
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { DispatchQueue.main.async { open(url) } }
            }
            return true
        }
        .sheet(item: $pending) { photo in
            AddLookSheet(photo: photo,
                         onAdd: { name, image in
                             do { let l = try store.add(processed: image, name: name); select(l.id); reload() }
                             catch { message = "Couldn't save that look: \(error.localizedDescription)" }
                             pending = nil
                         },
                         onCancel: { pending = nil })
        }
        .onAppear { reload() }
    }

    private func card(_ look: Look) -> some View {
        let selected = config.lookId == look.id
        return VStack(spacing: 4) {
            Group {
                if let img = NSImage(contentsOf: store.backdropURL(look)) {
                    Image(nsImage: img).resizable().interpolation(.none).aspectRatio(16.0 / 9.0, contentMode: .fit)
                } else {
                    Rectangle().fill(plum).aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
            }
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                                              lineWidth: selected ? 3 : 1))
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
                Text(look.name).lineLimit(1)
            }
            .font(.callout)
        }
        .contentShape(Rectangle())
        .onTapGesture { select(look.id) }
        .contextMenu {
            if !look.builtin { Button("Delete look") { delete(look) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(look.name + (selected ? ", selected" : ""))
        .accessibilityAddTraits(.isButton)
    }

    private func reload() { looks = store.all(); config = Config.load() }

    private func select(_ id: String) {
        config.lookId = id
        config.save()
    }

    private func delete(_ look: Look) {
        do {
            try store.remove(look.id)
            if config.lookId == look.id { select(LookStore.defaultId) }
            reload()
        } catch { message = "Couldn't delete: \(error.localizedDescription)" }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo to use as a backdrop"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    private func open(_ url: URL) {
        message = ""
        guard let image = LookPipeline.load(url) else {
            message = "Couldn't read \(url.lastPathComponent) as an image."
            return
        }
        pending = PendingPhoto(name: url.deletingPathExtension().lastPathComponent, source: image)
    }
}

struct PendingPhoto: Identifiable {
    let id = UUID()
    let name: String
    let source: CGImage
}

/// Shows the result as it will look behind terminal text, and lets the user calm it down before saving.
struct AddLookSheet: View {
    let photo: PendingPhoto
    let onAdd: (String, CGImage) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var calm = 0.0
    @State private var result: LookPipeline.Result?
    @State private var generation = 0

    init(photo: PendingPhoto, onAdd: @escaping (String, CGImage) -> Void, onCancel: @escaping () -> Void) {
        self.photo = photo; self.onAdd = onAdd; self.onCancel = onCancel
        _name = State(initialValue: photo.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a look").font(.headline)
            ZStack(alignment: .topLeading) {
                if let r = result {
                    Image(decorative: r.image, scale: 1).resizable().interpolation(.none)
                } else {
                    Rectangle().fill(plum)
                }
                Rectangle().fill(plum.opacity(LookPipeline.Options().terminalTint))   // the terminal's own tint
                VStack(alignment: .leading, spacing: 4) {
                    Text("~/my-project $ claude").foregroundColor(paper)
                    Text("Claude's done, your turn.").foregroundColor(paper)
                    Text("> _").foregroundColor(Color(.sRGB, red: 1, green: 0.82, blue: 0.25, opacity: 1))
                }
                .font(.system(size: 13, design: .monospaced))
                .padding(12)
            }
            .frame(width: 384, height: 216)
            .cornerRadius(4)
            .accessibilityLabel("Preview of the look behind sample terminal text")

            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Text("Calm")
                Slider(value: Binding(get: { calm }, set: { calm = $0; render() }), in: 0...1)
                Text(calm == 0 ? "As is" : "\(Int(calm * 100))%").frame(width: 44, alignment: .trailing).foregroundColor(.secondary)
            }
            if let r = result, r.darkening > 0.01 {
                Text("Darkened \(Int(r.darkening * 100))% so terminal text stays easy to read.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Add look") { if let r = result { onAdd(name, r.image) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(result == nil)
            }
        }
        .padding(20)
        .frame(width: 424)
        .onAppear { render() }
    }

    private func render() {
        generation += 1
        let mine = generation
        var o = LookPipeline.Options(); o.calm = calm
        let src = photo.source
        DispatchQueue.global(qos: .userInitiated).async {
            let r = LookPipeline.process(src, options: o)
            DispatchQueue.main.async { if mine == generation { result = r } }
        }
    }
}
