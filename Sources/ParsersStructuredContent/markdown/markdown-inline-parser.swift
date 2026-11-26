import DSL
import Foundation

enum MarkdownInlineParser {
    static func parse(
        _ source: String
    ) -> [StructuredContent.Inline] {
        let characters = Array(
            source
        )

        var result: [StructuredContent.Inline] = []
        var index = 0

        while index < characters.count {
            if characters[index] == "\\",
               index + 1 < characters.count
            {
                appendText(
                    String(
                        characters[index + 1]
                    ),
                    to: &result
                )
                index += 2
                continue
            }

            if characters[index] == "`",
               let closing = closingIndex(
                    for: ["`"],
                    in: characters,
                    from: index + 1
               )
            {
                result.append(
                    .code(
                        String(
                            characters[
                                (index + 1)..<closing
                            ]
                        )
                    )
                )
                index = closing + 1
                continue
            }

            if characters[index] == "!",
               index + 1 < characters.count,
               characters[index + 1] == "[",
               let link = linkSyntax(in: characters, from: index + 1)
            {
                // Inside running text an image can only be referred to.
                result.append(
                    .link(
                        target: target(link.destination),
                        content: [.text(link.text)]
                    )
                )
                index = link.end
                continue
            }

            if characters[index] == "[",
               let link = linkSyntax(in: characters, from: index)
            {
                result.append(
                    .link(
                        target: target(link.destination),
                        content: parse(link.text)
                    )
                )
                index = link.end
                continue
            }

            if characters[index] == "<",
               let closing = closingIndex(for: [">"], in: characters, from: index + 1)
            {
                let url = String(characters[(index + 1)..<closing])
                if url.contains("://"),
                   !url.contains(" ")
                {
                    result.append(
                        .link(
                            target: .external(url),
                            content: [.text(url)]
                        )
                    )
                    index = closing + 1
                    continue
                }
            }

            if index + 1 < characters.count,
               characters[index] == characters[index + 1],
               characters[index] == "*"
                    || characters[index] == "_"
            {
                let marker = [
                    characters[index],
                    characters[index + 1],
                ]

                if let closing = closingIndex(
                    for: marker,
                    in: characters,
                    from: index + 2
                ) {
                    let content = String(
                        characters[
                            (index + 2)..<closing
                        ]
                    )

                    result.append(
                        .strong(
                            parse(
                                content
                            )
                        )
                    )

                    index = closing + 2
                    continue
                }
            }

            if characters[index] == "*"
                || characters[index] == "_"
            {
                let marker = [
                    characters[index],
                ]

                if let closing = closingIndex(
                    for: marker,
                    in: characters,
                    from: index + 1
                ) {
                    let content = String(
                        characters[
                            (index + 1)..<closing
                        ]
                    )

                    result.append(
                        .emphasis(
                            parse(
                                content
                            )
                        )
                    )

                    index = closing + 1
                    continue
                }
            }

            appendText(
                String(
                    characters[index]
                ),
                to: &result
            )
            index += 1
        }

        return result
    }

    /// A whole-source `![alt](src)`, as an image block.
    static func image(
        _ source: String
    ) -> StructuredContent? {
        let characters = Array(
            source.trimmingCharacters(in: .whitespaces)
        )

        guard characters.count > 1,
              characters[0] == "!",
              let link = linkSyntax(in: characters, from: 1),
              link.end == characters.count
        else {
            return nil
        }

        return .image(
            source: .external(link.destination),
            alt: link.text
        )
    }

    struct LinkSyntax {
        let text: String
        let destination: String
        /// Index just past the closing parenthesis.
        let end: Int
    }

    /// `[text](destination "title")` starting at the `[`; brackets in the
    /// text nest, the title is dropped.
    static func linkSyntax(
        in characters: [Character],
        from start: Int
    ) -> LinkSyntax? {
        guard start < characters.count,
              characters[start] == "["
        else {
            return nil
        }

        var depth = 0
        var index = start
        var textEnd: Int?

        while index < characters.count {
            switch characters[index] {
            case "\\":
                index += 1
            case "[":
                depth += 1
            case "]":
                depth -= 1
                if depth == 0 {
                    textEnd = index
                }
            default:
                break
            }

            if textEnd != nil {
                break
            }

            index += 1
        }

        guard let textEnd,
              textEnd + 1 < characters.count,
              characters[textEnd + 1] == "(",
              let closing = closingIndex(for: [")"], in: characters, from: textEnd + 2)
        else {
            return nil
        }

        var destination = String(characters[(textEnd + 2)..<closing])
            .trimmingCharacters(in: .whitespaces)

        if let space = destination.firstIndex(of: " ") {
            destination = String(destination[..<space])
        }

        if destination.hasPrefix("<"),
           destination.hasSuffix(">")
        {
            destination = String(destination.dropFirst().dropLast())
        }

        guard !destination.isEmpty else {
            return nil
        }

        return .init(
            text: String(characters[(start + 1)..<textEnd]),
            destination: destination,
            end: closing + 1
        )
    }

    static func target(
        _ destination: String
    ) -> StructuredContent.LinkTarget {
        if destination.hasPrefix("#"),
           destination.count > 1
        {
            return .anchor(
                .init(
                    rawValue: String(destination.dropFirst())
                )
            )
        }

        return .external(destination)
    }

    private static func closingIndex(
        for marker: [Character],
        in characters: [Character],
        from start: Int
    ) -> Int? {
        guard !marker.isEmpty,
              start < characters.count
        else {
            return nil
        }

        var index = start

        while index + marker.count <= characters.count {
            var matches = true

            for offset in marker.indices
            where characters[index + offset] != marker[offset]
            {
                matches = false
                break
            }

            if matches {
                return index
            }

            index += 1
        }

        return nil
    }

    private static func appendText(
        _ text: String,
        to result: inout [StructuredContent.Inline]
    ) {
        guard !text.isEmpty else {
            return
        }

        if let last = result.last,
           case .text(let existing) = last
        {
            result[result.count - 1] =
                .text(
                    existing + text
                )
        } else {
            result.append(
                .text(
                    text
                )
            )
        }
    }
}
