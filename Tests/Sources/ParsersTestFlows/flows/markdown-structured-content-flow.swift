import DSL
import ParsersStructuredContent
import Testing

extension ParserTestSuite {
    static let markdownStructuredContentSuite = TestSuite(
        "structured-content.markdown",
        title: "Markdown parses into StructuredContent",
        tags: [
            "parsers",
            "markdown",
            "structured-content",
        ]
    ) {
        Test("common model markdown maps to semantic content") {
            let source = """
                # Runtime

                Use **typed** `ToolPlan` values.

                - observe
                - mutate
                    - approve

                > Keep *raw* markdown.

                ```swift
                let value = 1
                ```
                """

            let parsed =
                MarkdownStructuredContentParser.parse(
                    source
                )

            let expected: StructuredContent =
                .collection([
                    .heading(
                        level: 1,
                        anchor: nil,
                        content: [
                            .text("Runtime"),
                        ]
                    ),
                    .paragraph([
                        .text("Use "),
                        .strong([
                            .text("typed"),
                        ]),
                        .text(" "),
                        .code("ToolPlan"),
                        .text(" values."),
                    ]),
                    .list(
                        style: .unordered,
                        items: [
                            .paragraph([
                                .text("observe"),
                            ]),
                            .collection([
                                .paragraph([
                                    .text("mutate"),
                                ]),
                                .list(
                                    style: .unordered,
                                    items: [
                                        .paragraph([
                                            .text("approve"),
                                        ]),
                                    ]
                                ),
                            ]),
                        ]
                    ),
                    .quote(
                        .collection([
                            .paragraph([
                                .text("Keep "),
                                .emphasis([
                                    .text("raw"),
                                ]),
                                .text(" markdown."),
                            ]),
                        ])
                    ),
                    .code(
                        language: "swift",
                        source: "let value = 1"
                    ),
                ])

            try Expect.equal(
                parsed,
                expected,
                "markdown.structured-content.common"
            )
        }

        Test("headings are flat blocks in document order") {
            let parsed =
                MarkdownStructuredContentParser.parse(
                    """
                    # Parent

                    Intro.

                    ## Child

                    * * *

                    ### Grandchild
                    """
                )

            let expected: StructuredContent =
                .collection([
                    .heading(level: 1, anchor: nil, content: [.text("Parent")]),
                    .paragraph([.text("Intro.")]),
                    .heading(level: 2, anchor: nil, content: [.text("Child")]),
                    .rule,
                    .heading(level: 3, anchor: nil, content: [.text("Grandchild")]),
                ])

            try Expect.equal(
                parsed,
                expected,
                "markdown.structured-content.headings"
            )
        }

        Test("links and images map to link targets and image blocks") {
            let parsed =
                MarkdownStructuredContentParser.parse(
                    """
                    See [the **guide**](https://example.com/guide "Guide"), [above](#setup), <https://example.com> and ![a dog](dog.png) inline.

                    ![A dog](https://example.com/dog.png)
                    """
                )

            let expected: StructuredContent =
                .collection([
                    .paragraph([
                        .text("See "),
                        .link(
                            target: .external("https://example.com/guide"),
                            content: [.text("the "), .strong([.text("guide")])]
                        ),
                        .text(", "),
                        .link(target: .anchor(.init(rawValue: "setup")), content: [.text("above")]),
                        .text(", "),
                        .link(target: .external("https://example.com"), content: [.text("https://example.com")]),
                        .text(" and "),
                        .link(target: .external("dog.png"), content: [.text("a dog")]),
                        .text(" inline."),
                    ]),
                    .image(source: .external("https://example.com/dog.png"), alt: "A dog"),
                ])

            try Expect.equal(
                parsed,
                expected,
                "markdown.structured-content.links"
            )
        }

        Test("tables parse into rows of cells") {
            let parsed =
                MarkdownStructuredContentParser.parse(
                    """
                    Costs:
                    | Tool | Bytes |
                    |:---|---:|
                    | `a|b` | **12** |
                    | x \\| y |
                    after | the table
                    """
                )

            let expected: StructuredContent =
                .collection([
                    .paragraph([
                        .text("Costs:"),
                    ]),
                    .table(
                        header: [
                            .paragraph([.text("Tool")]),
                            .paragraph([.text("Bytes")]),
                        ],
                        rows: [
                            [
                                .paragraph([.code("a|b")]),
                                .paragraph([.strong([.text("12")])]),
                            ],
                            [
                                .paragraph([.text("x | y")]),
                                .paragraph([]),
                            ],
                            [
                                .paragraph([.text("after")]),
                                .paragraph([.text("the table")]),
                            ],
                        ]
                    ),
                ])

            try Expect.equal(
                parsed,
                expected,
                "markdown.structured-content.table"
            )

            let plain =
                MarkdownStructuredContentParser.parse(
                    "a | b without a delimiter row"
                )

            try Expect.equal(
                plain,
                .collection([
                    .paragraph([
                        .text("a | b without a delimiter row"),
                    ]),
                ]),
                "markdown.structured-content.table.requires-delimiter"
            )
        }

        Test("unsupported or incomplete syntax remains text") {
            let parsed =
                MarkdownStructuredContentParser.parse(
                    "Keep *unfinished and [links](unclosed unchanged."
                )

            let expected: StructuredContent =
                .collection([
                    .paragraph([
                        .text(
                            "Keep *unfinished and [links](unclosed unchanged."
                        ),
                    ]),
                ])

            try Expect.equal(
                parsed,
                expected,
                "markdown.structured-content.fallback"
            )
        }
    }
}
