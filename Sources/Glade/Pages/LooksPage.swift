import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GladeCore

struct LooksPage: View {
    private let store = LookStore()
    @State private var looks = LookStore().all()
    @State private var config = Config.load()
    @State private var pending: PendingPhoto?
    @State private var message = ""
    @State private var dropping = false

    var body: some View {
        let current = store.look(id: config.lookId)
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Looks", subtitle: "The scene behind your terminal. Add your own photo, crop it, and turn it into pixel art if you like.")
            HStack(alignment: .top, spacing: 20) {
                LookPreview(look: current, width: 400)
                VStack(alignment: .leading, spacing: 10) {
                    Text("In use").font(Theme.label(13)).foregroundColor(Theme.peach)
                    Text(current.name).font(Theme.title(22)).foregroundColor(Theme.paper)
                    Text(current.builtin ? "Built in to Glade." : "Made from your photo, on this Mac.")
                        .font(.system(size: 13)).foregroundColor(Theme.secondary)
                    Spacer(minLength: 6)
                    HStack {
                        Button("Add photo…") { choosePhoto() }.buttonStyle(PrimaryButtonStyle())
                        if !current.builtin {
                            Button("Delete") { delete(current) }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 225)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(looks) { look in card(look) }
                }
                .padding(.vertical, 4).padding(.trailing, 6)
            }
            Text(message.isEmpty ? "Drop a photo anywhere on this page. It never leaves your Mac." : message)
                .font(.system(size: 12)).foregroundColor(message.isEmpty ? Theme.secondary : Theme.alert)
        }
        .overlay(Rectangle().stroke(Theme.sparkle, lineWidth: dropping ? 3 : 0).padding(-10))
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { DispatchQueue.main.async { open(url) } }
            }
            return true
        }
        .sheet(item: $pending) { photo in
            AddLookSheet(photo: photo,
                         onAdd: { name, image, pixelated in
                             do { let l = try store.add(processed: image, name: name, pixelated: pixelated); select(l.id); reload() }
                             catch { message = "Couldn't save that look: \(error.localizedDescription)" }
                             pending = nil
                         },
                         onCancel: { pending = nil })
        }
        .onAppear { reload() }
    }

    private func card(_ look: Look) -> some View {
        let selected = config.lookId == look.id
        return Button { select(look.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let img = NSImage(contentsOf: store.backdropURL(look)) {
                        Image(nsImage: img).resizable().interpolation(look.pixelated ? .none : .high).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    } else {
                        Rectangle().fill(Theme.ink).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    }
                }
                .overlay(Rectangle().stroke(selected ? Theme.sparkle : Theme.line, lineWidth: selected ? 3 : 2))
                HStack(spacing: 6) {
                    if selected { Rectangle().fill(Theme.sparkle).frame(width: 8, height: 8) }
                    Text(look.name).lineLimit(1)
                }
                .font(.system(size: 12, weight: selected ? .bold : .regular, design: .rounded))
                .foregroundColor(Theme.paper)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { if !look.builtin { Button("Delete look") { delete(look) } } }
        .accessibilityLabel(look.name + (selected ? ", in use" : ""))
    }

    private func reload() { looks = store.all(); config = Config.load() }

    private func select(_ id: String) { config.lookId = id; config.lookChosen = true; config.save() }

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

/// Choose which part of the photo to use, whether to turn it into pixel art, and see the result behind sample
/// terminal text before saving.
struct AddLookSheet: View {
    let photo: PendingPhoto
    let onAdd: (String, CGImage, Bool) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var calm = 0.0
    @State private var pixelate = true
    @State private var crop = CropRegion()
    @State private var result: LookPipeline.Result?
    @State private var generation = 0
    private static let queue = DispatchQueue(label: "glade.look.render", qos: .userInitiated)   // one at a time, newest wins

    init(photo: PendingPhoto, onAdd: @escaping (String, CGImage, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.photo = photo; self.onAdd = onAdd; self.onCancel = onCancel
        _name = State(initialValue: photo.name)
    }

    private var maxZoom: Double { CropRegion.maxZoom(imageWidth: Double(photo.source.width), imageHeight: Double(photo.source.height)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a look").font(Theme.title(22)).foregroundColor(Theme.paper)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    CropEditor(image: photo.source, crop: Binding(get: { crop }, set: { crop = $0; render() }))
                    HStack(spacing: 12) {
                        Text("Zoom").font(Theme.ui(14)).foregroundColor(Theme.paper)
                        Slider(value: Binding(get: { crop.zoom }, set: { setZoom($0) }), in: 1...max(1.01, maxZoom)).tint(Theme.sparkle)
                            .disabled(maxZoom <= 1.01)
                            .accessibilityLabel("Zoom")
                        Button("Reset") { crop = CropRegion(); render() }.buttonStyle(SecondaryButtonStyle())
                            .disabled(crop == CropRegion())
                    }
                    Text("Glade fits your photo to the terminal for you. To pick a different part, drag the box, or drag a corner to resize it.")
                        .font(.system(size: 12)).foregroundColor(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 480)

                VStack(alignment: .leading, spacing: 14) {
                    preview
                    TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                    Toggle("Turn it into pixel art", isOn: Binding(get: { pixelate }, set: { pixelate = $0; render() }))
                        .toggleStyle(PixelToggleStyle())
                    Text(pixelate ? "Chunky pixels and a limited palette, like Hoot." : "Keeps your photo as it is, only fitted and darkened for reading.")
                        .font(.system(size: 12)).foregroundColor(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        .frame(height: 32, alignment: .topLeading)     // two lines either way, so the controls below do not jump
                    HStack {
                        Text("Calm").font(Theme.ui(14)).foregroundColor(Theme.paper)
                        Slider(value: Binding(get: { calm }, set: { calm = $0; render() }), in: 0...1).tint(Theme.sparkle)
                        Text(calm == 0 ? "As is" : "\(Int(calm * 100))%").frame(width: 44, alignment: .trailing)
                            .font(.system(size: 12)).foregroundColor(Theme.secondary)
                    }
                    if let r = result, r.darkening > 0.01 {
                        Text("Darkened \(Int(r.darkening * 100))% so terminal text stays easy to read.")
                            .font(.system(size: 12)).foregroundColor(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 300)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add look") { if let r = result { onAdd(name, r.image, pixelate) } }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(result == nil)
            }
        }
        .padding(24)
        .frame(width: 868)
        .background(Theme.deep)
        .preferredColorScheme(.dark)
        .onAppear { render() }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            if let r = result {
                Image(decorative: r.image, scale: 1).resizable().interpolation(pixelate ? .none : .high)
            } else {
                Rectangle().fill(Theme.ink)
            }
            Rectangle().fill(Theme.ink.opacity(LookPipeline.Options().terminalTint))
            VStack(alignment: .leading, spacing: 3) {
                Text("~/my-project $ claude").foregroundColor(Theme.paper)
                Text("Claude's done, your turn.").foregroundColor(Theme.paper)
                Text("> _").foregroundColor(Theme.sparkle)
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(10)
        }
        .frame(width: 300, height: 169)
        .clipped()
        .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the look behind sample terminal text")
    }

    private func setZoom(_ z: Double) {
        var next = crop; next.zoom = z
        crop = next.clamped(imageWidth: Double(photo.source.width), imageHeight: Double(photo.source.height))
        render()
    }

    private func render() {
        generation += 1
        let mine = generation
        var o = LookPipeline.Options(); o.calm = calm; o.pixelate = pixelate; o.crop = crop
        let src = photo.source
        Self.queue.async {
            // a newer change has already been asked for: skip this one
            if DispatchQueue.main.sync(execute: { mine != generation }) { return }
            let r = LookPipeline.process(src, options: o)
            DispatchQueue.main.async { if mine == generation { result = r } }
        }
    }
}
