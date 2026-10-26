import SwiftUI
import MurmurCore
import MurmurUI

/// Find and replace in one transcript. Matches design/iphone/FindReplace.dc.html.
struct FindReplaceScreen: View {
    let controller: FindReplaceController
    let speakerNames: [String]
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: Field?
    @State private var toast: String?
    @State private var toastToken = 0

    private enum Field { case find, replace }

    var body: some View {
        ZStack(alignment: .bottom) {
            MurmurTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                panel
                lines
            }
            if let toast {
                Text(toast)
                    .font(MurmurTheme.Fonts.body.weight(.bold))
                    .foregroundStyle(MurmurTheme.Colors.background)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(Capsule().fill(MurmurTheme.Colors.textPrimary))
                    .padding(.bottom, 32)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: toast)
    }

    // MARK: - Header panel

    private var panel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Find & replace")
                    .font(MurmurTheme.Fonts.headline)
                    .foregroundStyle(MurmurTheme.Colors.textPrimary)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done", action: onClose)
                    .font(MurmurTheme.Fonts.body.weight(.semibold))
                    .foregroundStyle(MurmurTheme.Colors.accent)
                    .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
            }
            field("Find", text: Binding(get: { controller.find }, set: { controller.setFind($0) }),
                  trailing: controller.counterText, active: true, which: .find)
            field("Replace", text: Binding(get: { controller.replacement }, set: { controller.replacement = $0 }),
                  trailing: nil, active: false, which: .replace)
            HStack(spacing: 8) {
                squareButton("chevron.up", label: "Previous match") { controller.previous() }
                squareButton("chevron.down", label: "Next match") { controller.next() }
                Button {
                    controller.replaceCurrent()
                } label: {
                    Text("Replace")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: MurmurTheme.Metrics.minTapTarget)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MurmurTheme.Colors.border))
                }
                .buttonStyle(MurmurPressStyle())
                .disabled(!controller.canReplace)
                .opacity(controller.canReplace ? 1 : 0.4)
                Button {
                    let count = controller.replaceAll()
                    if count > 0 { show("\(count) replaced") }
                } label: {
                    Text("Replace all")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MurmurTheme.Colors.onAccent)
                        .frame(maxWidth: .infinity, minHeight: MurmurTheme.Metrics.minTapTarget)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.accent))
                }
                .buttonStyle(MurmurPressStyle())
                .disabled(!controller.canReplace)
                .opacity(controller.canReplace ? 1 : 0.4)
            }
            Toggle(isOn: Binding(get: { controller.addToDictionary }, set: { controller.addToDictionary = $0 })) {
                Text(dictionaryLabel)
                    .font(.footnote)
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            .tint(MurmurTheme.Colors.accent)
            .disabled(!controller.canAddToDictionary)
            .padding(.horizontal, 4)
            .frame(minHeight: MurmurTheme.Metrics.minTapTarget)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(MurmurTheme.Colors.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(MurmurTheme.Colors.border).frame(height: MurmurTheme.Metrics.borderWidth)
        }
    }

    private var dictionaryLabel: String {
        let word = controller.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        return word.isEmpty ? "Also add the new word to custom dictionary" : "Also add “\(word)” to custom dictionary"
    }

    private func field(_ title: String, text: Binding<String>, trailing: String?, active: Bool, which: Field) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                .frame(width: 58, alignment: .leading)
            TextField(title, text: text)
                .font(MurmurTheme.Fonts.body)
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .tint(MurmurTheme.Colors.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(which == .find ? .next : .done)
                .focused($focus, equals: which)
                .onSubmit { focus = which == .find ? .replace : nil }
                .accessibilityLabel(which == .find ? "Find" : "Replace with")
            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MurmurTheme.Colors.background))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(active ? MurmurTheme.Colors.accent : MurmurTheme.Colors.border,
                              lineWidth: active ? MurmurTheme.Metrics.selectedBorderWidth : MurmurTheme.Metrics.borderWidth)
        )
    }

    private func squareButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(MurmurTheme.Colors.textPrimary)
                .frame(width: MurmurTheme.Metrics.minTapTarget, height: MurmurTheme.Metrics.minTapTarget)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MurmurTheme.Colors.background))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(MurmurTheme.Colors.border))
        }
        .buttonStyle(MurmurPressStyle())
        .disabled(!controller.canReplace)
        .opacity(controller.canReplace ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    // MARK: - Transcript lines

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(controller.segments.enumerated()), id: \.element.id) { index, segment in
                        line(index: index, segment: segment)
                            .id(segment.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: controller.current) { _, match in
                guard let match, controller.segments.indices.contains(match.segmentIndex) else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(controller.segments[match.segmentIndex].id, anchor: .center)
                }
            }
        }
    }

    private func line(index: Int, segment: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let speaker = segment.speakerIndex {
                    SpeakerBadge(initial: Speakers.initial(at: speaker, in: speakerNames),
                                 color: MurmurTheme.Colors.folder(speaker))
                        .accessibilityHidden(true)
                    Text(Speakers.name(at: speaker, in: speakerNames))
                        .font(MurmurTheme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(MurmurTheme.Colors.textPrimary)
                }
                Text(Timecode.format(segment.start))
                    .font(MurmurTheme.Fonts.caption.monospacedDigit())
                    .foregroundStyle(MurmurTheme.Colors.textSecondary)
            }
            Text(Highlight.line(segment.text, spans: controller.spans(inSegment: index)))
                .font(.subheadline)
                .lineSpacing(3)
                .foregroundStyle(MurmurTheme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func show(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toastToken == token { toast = nil }
        }
    }
}
