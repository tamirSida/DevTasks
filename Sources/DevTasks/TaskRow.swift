import SwiftUI
import AppKit

enum Feedback {
    /// Loaded once at launch so the first check doesn't wait on disk.
    private static let pop: NSSound? = {
        let s = NSSound(named: "Pop")
        s?.volume = 0.35
        return s
    }()

    static func preload() { _ = pop }

    static func check() {
        if UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true, let s = pop {
            if s.isPlaying { s.stop() }
            s.play()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    let task: TaskItem

    /// Set only while a click's check animation plays; otherwise the stored task is the truth.
    @State private var pending: Bool?
    @State private var expanded = false
    @State private var hover = false
    @State private var showMove = false
    @State private var copied = false
    @State private var newSub = ""
    @StateObject private var subCtl = FieldController()

    init(task: TaskItem) { self.task = task }

    private var checked: Bool { pending ?? task.done }

    private var subDone: Int { task.subtasks.filter(\.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                FAIcon("grip-vertical", size: 10)
                    .foregroundStyle(t.faint)
                    .opacity(hover && !checked ? 1 : 0)
                    .frame(width: 8)
                    .padding(.top, 3)

                CheckBox(checked: checked, baseSize: 18, action: toggle)

                Group {
                    if checked {
                        RichField(text: .constant(task.title), size: 13, color: t.muted, accent: t.accent.opacity(0.75),
                                  readOnly: true, strike: true)
                    } else {
                        RichField(text: store.titleBinding(task.id), size: 13, color: t.text, accent: t.accent, inline: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 1)

                if !task.subtasks.isEmpty {
                    SubtaskChip(done: subDone, total: task.subtasks.count)
                }

                HStack(spacing: 2) {
                    HoverIconButton(icon: copied ? "check" : "copy", hoverColor: t.accent, help: "copy (keeps links for chats)") { copy() }
                    HoverIconButton(icon: "arrow-right-arrow-left", help: "move to list") { showMove = true }
                        .popover(isPresented: $showMove, arrowEdge: .bottom) { MovePopover(task: task, dismiss: { showMove = false }) }
                    HoverIconButton(icon: "trash-can", hoverColor: t.danger, help: "delete") {
                        withAnimation(.spring(response: 0.3)) { store.delete(task.id) }
                    }
                }
                .opacity(hover || showMove || copied ? 1 : 0)
                .padding(.top, -2)

                HoverIconButton(icon: "chevron-down", size: 10, help: "subtasks") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
                    if expanded { subCtl.focus() }
                }
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .opacity(hover || expanded || !task.subtasks.isEmpty ? 1 : 0)
                .padding(.top, -2)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 9)

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.subtasks) { sub in
                        SubtaskRow(taskID: task.id, sub: sub)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        FAIcon("plus", size: 10).foregroundStyle(t.faint).frame(width: 14).padding(.top, 2)
                        RichField(text: $newSub, size: 12, color: t.text, accent: t.accent,
                                  controller: subCtl, endsOnSubmit: false, onSubmit: {
                            withAnimation(.spring(response: 0.3)) { store.addSubtask(task.id, newSub) }
                            newSub = ""
                        })
                        .overlay(alignment: .topLeading) {
                            if newSub.isEmpty {
                                Text("add subtask").font(.mono(12)).foregroundStyle(t.faint).allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.leading, 50)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(t.border).frame(width: 1).padding(.leading, 33).padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(checked ? t.panel.opacity(0.5) : hover ? t.raised : t.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(checked && !task.done ? t.accent.opacity(0.5) : t.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .draggable(task.id.uuidString) {
            HStack(spacing: 8) {
                FAIcon("grip-vertical", size: 10)
                Text(task.title).font(.mono(12)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(t.raised))
            .foregroundStyle(t.text)
        }
        .contextMenu {
            Button(checked ? "Mark Open" : "Complete") { toggle() }
            Button("Copy") { copy() }
            Button("Add Subtask") {
                withAnimation(.spring(response: 0.3)) { expanded = true }
                subCtl.focus()
            }
            Menu("Move To") {
                ForEach(Bucket.allCases.filter { $0 != task.bucket }) { b in
                    Button(b.title) { withAnimation(.spring(response: 0.35)) { store.move(task.id, to: b) } }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                withAnimation(.spring(response: 0.3)) { store.delete(task.id) }
            }
        }
    }

    private func copy() {
        var text = task.title
        if !task.subtasks.isEmpty {
            text += "\n" + task.subtasks.map { "- " + $0.title }.joined(separator: "\n")
        }
        LinkFormat.copy(text)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }

    private func toggle() {
        let new = !checked
        if new { Feedback.check() }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { pending = new }
        // Let the check animation play before the row slides into the done section.
        let id = task.id
        DispatchQueue.main.asyncAfter(deadline: .now() + (new ? 0.42 : 0.05)) {
            guard pending == new else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                store.setDone(id, new)
                pending = nil
            }
        }
    }
}

struct SubtaskChip: View {
    @Environment(\.theme) private var t
    let done: Int
    let total: Int
    var body: some View {
        let complete = done == total
        HStack(spacing: 5) {
            FAIcon(complete ? "check-double" : "list-check", size: 9)
            Text("\(done)/\(total)").font(.mono(10.5, .medium)).contentTransition(.numericText())
        }
        .foregroundStyle(complete ? t.accent : t.muted)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(complete ? t.accent.opacity(0.12) : t.border.opacity(0.5)))
        .animation(.spring(response: 0.3), value: done)
    }
}

struct SubtaskRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    let taskID: UUID
    let sub: Subtask
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CheckBox(checked: sub.done, baseSize: 14) {
                if !sub.done { Feedback.check() }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { store.toggleSubtask(taskID, sub.id) }
            }
            Group {
                if sub.done {
                    RichField(text: .constant(sub.title), size: 12, color: t.muted, accent: t.accent.opacity(0.75),
                              readOnly: true, strike: true)
                } else {
                    RichField(text: store.subtaskBinding(taskID, sub.id), size: 12, color: t.text, accent: t.accent, inline: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HoverIconButton(icon: "xmark", size: 9, hoverColor: t.danger, help: "remove subtask") {
                withAnimation(.spring(response: 0.3)) { store.deleteSubtask(taskID, sub.id) }
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 2)
        .onHover { hover = $0 }
    }
}

struct MovePopover: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    let task: TaskItem
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("move to").padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(Bucket.allCases.filter { $0 != task.bucket }) { b in
                Button {
                    dismiss()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.move(task.id, to: b) }
                } label: {
                    HStack(spacing: 10) {
                        FAIcon(b.icon, size: 11).foregroundStyle(t.tint(b)).frame(width: 16)
                        Text(b.path).font(.mono(12))
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PopoverRowStyle())
            }
        }
        .padding(8)
        .frame(width: 190)
        .background(t.panel)
        .foregroundStyle(t.text)
    }
}

struct PopoverRowStyle: ButtonStyle {
    @Environment(\.theme) private var t
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 6).fill(hover || configuration.isPressed ? t.raised : .clear))
            .onHover { hover = $0 }
            .handCursor()
    }
}

// MARK: - Checkbox with burst

struct CheckBox: View {
    @Environment(\.theme) private var t
    let checked: Bool
    var baseSize: CGFloat = 18
    let action: () -> Void
    @State private var burst = 0
    @State private var hover = false

    private var size: CGFloat { baseSize * UIScale.factor }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.3)
                    .fill(checked ? t.accent : hover ? t.accent.opacity(0.1) : .clear)
                RoundedRectangle(cornerRadius: size * 0.3)
                    .strokeBorder(checked ? t.accent : hover ? t.accent.opacity(0.7) : t.muted.opacity(0.6), lineWidth: 1.5)
                FAIcon("check", size: size * 0.56)
                    .foregroundStyle(t.accentInk)
                    .scaleEffect(checked ? 1 : 0.1)
                    .opacity(checked ? 1 : 0)
                    .rotationEffect(.degrees(checked ? 0 : -45))
            }
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 1.0, trigger: burst) { content, s in
                content.scaleEffect(s)
            } keyframes: { _ in
                CubicKeyframe(0.72, duration: 0.08)
                SpringKeyframe(1.22, duration: 0.16, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
            .background(Burst(trigger: burst, color: t.accent, size: size))
            .shadow(color: checked ? t.accent.opacity(0.45) : .clear, radius: checked ? 6 : 0)
            .contentShape(Rectangle().size(width: size + 8, height: size + 8).offset(x: -4, y: -4))
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
        .onChange(of: checked) { _, new in if new { burst += 1 } }
    }
}

/// A ring plus radiating particles, visible only while its keyframe runs.
struct Burst: View {
    let trigger: Int
    let color: Color
    let size: CGFloat

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, p in
                ZStack {
                    Circle()
                        .stroke(color, lineWidth: max(0.1, 2.5 * (1 - p)))
                        .frame(width: size, height: size)
                        .scaleEffect(0.8 + p * 1.7)
                    ForEach(0..<10, id: \.self) { i in
                        let a = Double(i) / 10 * 2 * .pi
                        let r = size * (0.45 + p * 0.95)
                        Circle()
                            .fill(color)
                            .frame(width: i.isMultiple(of: 2) ? 4 : 3, height: i.isMultiple(of: 2) ? 4 : 3)
                            .offset(x: cos(a) * r, y: sin(a) * r)
                            .scaleEffect(1 - p * 0.5)
                    }
                }
                .opacity(p > 0.001 && p < 0.999 ? 1 - p : 0)
                .allowsHitTesting(false)
            } keyframes: { _ in
                LinearKeyframe(1.0, duration: 0.6, timingCurve: .easeOut)
            }
            .allowsHitTesting(false)
    }
}
