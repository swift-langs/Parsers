import Testing

enum ParserTestSuite {
    static let suite = TestSuite(
        "parsers",
        title: "Parser tests"
    ) {
        prebuiltIPAddressRegressionSuite
        prebuiltDecimalNumberSuite
        markdownStructuredContentSuite
        pklSyntaxSuite
        pklParserSuite
        pklCodingSuite
        grammarISODateSuite
        pklGrammarSuite
    }
}
