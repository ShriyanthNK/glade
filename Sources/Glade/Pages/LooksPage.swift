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
            PageHeader(title: "Looks", subtitle: "The scene behind your terminal. Add your own photos and Glade turns them into pixel art.")
            HStack(alignment: .top, spacing: 20) {
                LookPreview(look: current, width: 400)
                VStack(alignment: .leading, spacing: 10) {
                    Text("In use").font(Theme.voice(11)).foregroundColor(Theme.peach)
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
        return Button { select(look.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let img = NSImage(contentsOf: store.backdropURL(look)) {
                        Image(nsImage: img).resizable().interpolation(.none).aspectRatio(16.0 / 9.0, contentMode: .fit)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a look").font(Theme.title(22)).foregroundColor(Theme.paper)
            ZStack(alignment: .topLeading) {
                if let r = result {
                    Image(decorative: r.image, scale: 1).resizable().interpolation(.none)
                } else {
                    Rectangle().fill(Theme.ink)
                }
                Rectangle().fill(Theme.ink.opacity(LookPipeline.Options().terminalTint))
                VStack(alignment: .leading, spacing: 4) {
                    Text("~/my-project $ claude").foregroundColor(Theme.paper)
                    Text("Claude's done, your turn.").foregroundColor(Theme.paper)
                    Text("> _").foregroundColor(Theme.sparkle)
                }
                .font(.system(size: 13, design: .monospaced))
                .padding(12)
            }
            .frame(width: 384, height: 216)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 2))
            .accessibilityLabel("Preview of the look behind sample terminal text")

            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Text("Calm").font(.system(size: 13, design: .rounded)).foregroundColor(Theme.paper)
                Slider(value: Binding(get: { calm }, set: { calm = $0; render() }), in: 0...1).tint(Theme.sparkle)
                Text(calm == 0 ? "As is" : "\(Int(calm * 100))%").frame(width: 44, alignment: .trailing)
                    .font(.system(size: 12)).foregroundColor(Theme.secondary)
            }
            if let r = result, r.darkening > 0.01 {
                Text("Darkened \(Int(r.darkening * 100))% so terminal text stays easy to read.")
                    .font(.system(size: 12)).foregroundColor(Theme.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add look") { if let r = result { onAdd(name, r.image) } }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(result == nil)
            }
        }
        .padding(24)
        .frame(width: 432)
        .background(Theme.deep)
        .preferredColorScheme(.dark)
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
