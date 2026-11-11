import SwiftUI

struct MainView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @State private var showDone = true

    var body: some View {
        let bucket = store.selected
        let open = store.open(bucket)
        let done = store.done(bucket)

        VStack(alignment: .leading, spacing: 0) {
            QuickActionsBar()
                .padding(.top, 38)
                .padding(.horizontal, 28)

            Header(bucket: bucket, open: open.count, done: done.count)
                .padding(.horizontal, 28)
                .padding(.top, 22)

            QuickAddBar()
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if open.isEmpty && done.isEmpty {
                        EmptyState(bucket: bucket).padding(.top, 50)
                    } else if open.isEmpty {
                        Text("$ all clear. ship it.")
                            .font(.mono(12)).foregroundStyle(t.accent)
                            .padding(.vertical, 14).padding(.horizontal, 4)
                    }

                    ForEach(open) { task in
                        TaskRow(task: task)
                            .id("open-\(task.id)")
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.97))))
                    }

                    if !done.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { showDone.toggle() }
                            } label: {
                                HStack(spacing: 6) {
                                    FAIcon("chevron-right", size: 9)
                                        .rotationEffect(.degrees(showDone ? 90 : 0))
                                    Text("// done (\(done.count))").font(.mono(11))
                                }
                                .foregroundStyle(t.faint)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button("clear") {
                                withAnimation(.spring(response: 0.35)) { store.clearDone(bucket) }
                            }
                            .buttonStyle(.plain)
                            .font(.mono(11)).foregroundStyle(t.faint)
                        }
                        .padding(.top, 18).padding(.bottom, 4).padding(.horizontal, 4)

                        if showDone {
                            ForEach(done) { task in
                                TaskRow(task: task).id("done-\(task.id)").transition(.opacity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.never)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: bucket)
    }
}

struct Header: View {
    @Environment(\.theme) private var t
    let bucket: Bucket
    let open: Int
    let done: Int

    private var subtitle: String {
        let cal = Calendar.current
        let f = DateFormatter()
        switch bucket {
        case .today:
            f.dateFormat = "EEE, MMM d"
            return f.string(from: Date())
        case .tomorrow:
            f.dateFormat = "EEE, MMM d"
            return f.string(from: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        case .week:
            guard let w = cal.dateInterval(of: .weekOfYear, for: Date()) else { return "" }
            f.dateFormat = "MMM d"
            return "\(f.string(from: w.start)) - \(f.string(from: w.end.addingTimeInterval(-1)))"
        case .backlog:
            return "someday / maybe"
        }
    }

    var body: some View {
        let total = open + done
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(bucket.path)
                    .font(.mono(26, .bold))
                    .foregroundStyle(t.text)
                    .contentTransition(.opacity)
                Text(subtitle).font(.mono(12)).foregroundStyle(t.muted)
                Spacer()
                Text("\(open) open  \u{00B7}  \(done) done")
                    .font(.mono(11.5)).foregroundStyle(t.muted)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.border.opacity(0.7))
                    Capsule().fill(t.tint(bucket))
                        .frame(width: max(0, geo.size.width * progress))
                        .shadow(color: t.tint(bucket).opacity(0.5), radius: 4)
                }
            }
            .frame(height: 3)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        }
    }
}

struct EmptyState: View {
    @Environment(\.theme) private var t
    let bucket: Bucket
    var body: some View {
        VStack(spacing: 12) {
            FAIcon(bucket == .backlog ? "box-open" : "mug-hot", size: 30).foregroundStyle(t.faint)
            Text("$ ls \(bucket.path)").font(.mono(12)).foregroundStyle(t.muted)
            Text("nothing here yet. press \u{2318}N to add a task.").font(.mono(11)).foregroundStyle(t.faint)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick add

struct QuickAddBar: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @State private var text = ""
    @State private var routed: Bucket?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(">").font(.mono(14, .bold)).foregroundStyle(t.accent)
            TextField("", text: $text, prompt: Text("add a task   @tomorrow  @week  @backlog").foregroundStyle(t.faint))
                .textFieldStyle(.plain)
                .font(.mono(13))
                .focused($focused)
                .onSubmit(submit)
            if let routed {
                HStack(spacing: 5) {
                    FAIcon("arrow-right", size: 9)
                    Text(routed.path).font(.mono(11))
                }
                .foregroundStyle(t.tint(routed))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if !text.isEmpty {
                Text("enter").font(.mono(10)).foregroundStyle(t.faint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(t.border))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 9).fill(t.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? t.accent.opacity(0.55) : t.border, lineWidth: 1))
        .shadow(color: focused ? t.accent.opacity(0.12) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear { focused = true }
        .onChange(of: store.focusQuickAdd) { _, _ in focused = true }
    }

    private func submit() {
        var target = store.selected
        var words: [Substring] = []
        for w in text.split(separator: " ") {
            if let b = Bucket.parse(String(w)) { target = b } else { words.append(w) }
        }
        let title = words.joined(separator: " ")
        let added = withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            store.add(title, to: target)
        }
        guard added else { return }
        text = ""
        focused = true
        if target != store.selected {
            withAnimation(.spring(response: 0.3)) { routed = target }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.25)) { routed = nil }
            }
        }
    }
}
