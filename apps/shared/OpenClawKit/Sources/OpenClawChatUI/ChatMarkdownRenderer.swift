import SwiftUI

#if canImport(Textual)
import Textual
#endif

public enum ChatMarkdownVariant: String, CaseIterable, Sendable {
    case standard
    case compact
}

@MainActor
struct ChatMarkdownRenderer: View {
    enum Context {
        case user
        case assistant
    }

    let text: String
    let context: Context
    let variant: ChatMarkdownVariant
    let font: Font
    let textColor: Color

    var body: some View {
        let processed = ChatMarkdownPreprocessor.preprocess(markdown: self.text)
        VStack(alignment: .leading, spacing: 10) {
            self.markdownBody(for: processed.cleaned)

            if !processed.images.isEmpty {
                InlineImageList(images: processed.images)
            }
        }
    }

    @ViewBuilder
    private func markdownBody(for cleanedText: String) -> some View {
        #if canImport(Textual)
        StructuredText(markdown: cleanedText)
            .modifier(ChatMarkdownStyle(
                variant: self.variant,
                context: self.context,
                font: self.font,
                textColor: self.textColor))
        #else
        Text(cleanedText)
            .font(self.font)
            .foregroundStyle(self.textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if canImport(Textual)
private struct ChatMarkdownStyle: ViewModifier {
    let variant: ChatMarkdownVariant
    let context: ChatMarkdownRenderer.Context
    let font: Font
    let textColor: Color

    func body(content: Content) -> some View {
        Group {
            if self.variant == .compact {
                content.textual.structuredTextStyle(.default)
            } else {
                content.textual.structuredTextStyle(.gitHub)
            }
        }
        .font(self.font)
        .foregroundStyle(self.textColor)
        .textual.inlineStyle(self.inlineStyle)
        .textual.textSelection(self.textSelectionBehavior)
    }

    private var inlineStyle: InlineStyle {
        let linkColor: Color = self.context == .user ? self.textColor : .accentColor
        let codeScale: CGFloat = self.variant == .compact ? 0.85 : 0.9
        return InlineStyle()
            .code(.monospaced, .fontScale(codeScale))
            .link(.foregroundColor(linkColor))
    }

    private var textSelectionBehavior: TextSelection {
        #if os(tvOS)
        .disabled
        #else
        .enabled
        #endif
    }
}
#endif

@MainActor
private struct InlineImageList: View {
    let images: [ChatMarkdownPreprocessor.InlineImage]

    var body: some View {
        ForEach(images, id: \.id) { item in
            if let img = item.image {
                OpenClawPlatformImageFactory.image(img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                Text(item.label.isEmpty ? "Image" : item.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
