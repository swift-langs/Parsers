import Foundation
import Parsers
import Parsing
import Testing

extension ParserTestSuite {
    static let prebuiltDecimalNumberSuite = TestSuite(
        "prebuilt.decimal-number",
        title: "Prebuilt decimal number parser reads numbers as people type them",
        tags: [
            "parsers",
            "prebuilt",
            "decimal-number",
        ]
    ) {
        Test("plain, grouped and decimal numbers") {
            let cases: [(String, Decimal)] = [
                ("0", 0),
                ("2500", 2500),
                ("2_500", 2500),
                ("1'000'000", 1_000_000),
                ("1 000 000", 1_000_000),
                ("1\u{00A0}000", 1000),
                ("1.000.000", 1_000_000),
                ("1,000,000", 1_000_000),
                ("1.000", 1000),
                ("1,000", 1000),
                ("12,500", 12500),
                ("12.5", Decimal(string: "12.5")!),
                ("12,5", Decimal(string: "12.5")!),
                ("0,500", Decimal(string: "0.5")!),
                ("1234.567", Decimal(string: "1234.567")!),
                ("1.234,56", Decimal(string: "1234.56")!),
                ("1,234.56", Decimal(string: "1234.56")!),
                (".5", Decimal(string: "0.5")!),
                ("  42  ", 42),
            ]
            for (source, expected) in cases {
                let parsed = try Prebuilt.DecimalNumberParser.parse(source)
                try Expect.equal(parsed.value, expected, "decimal-number.value \(source)")
                try Expect.equal(parsed.unit, .none, "decimal-number.unit \(source)")
            }
        }

        Test("signs, currency, percent and magnitude") {
            let euro = try Prebuilt.DecimalNumberParser.parse("€ 1.250,50")
            try Expect.equal(euro.value, Decimal(string: "1250.5")!, "decimal-number.euro.value")
            try Expect.equal(euro.unit, .currency("€"), "decimal-number.euro.unit")

            let code = try Prebuilt.DecimalNumberParser.parse("2500 EUR")
            try Expect.equal(code.unit, .currency("EUR"), "decimal-number.code.unit")

            let negative = try Prebuilt.DecimalNumberParser.parse("-€12")
            try Expect.equal(negative.value, -12, "decimal-number.negative.prefix")
            let afterSymbol = try Prebuilt.DecimalNumberParser.parse("$-12")
            try Expect.equal(afterSymbol.value, -12, "decimal-number.negative.after-symbol")
            let accounting = try Prebuilt.DecimalNumberParser.parse("(1.234,00)")
            try Expect.equal(accounting.value, -1234, "decimal-number.negative.accounting")
            let unicodeMinus = try Prebuilt.DecimalNumberParser.parse("−7")
            try Expect.equal(unicodeMinus.value, -7, "decimal-number.negative.unicode")

            let percent = try Prebuilt.DecimalNumberParser.parse("35,5%")
            try Expect.equal(percent.value, Decimal(string: "35.5")!, "decimal-number.percent.value")
            try Expect.equal(percent.unit, .percent, "decimal-number.percent.unit")
            try Expect.equal(percent.fraction, Decimal(string: "0.355")!, "decimal-number.percent.fraction")

            try Expect.equal(try Prebuilt.DecimalNumberParser.parse("2.5k").value, 2500, "decimal-number.k")
            try Expect.equal(try Prebuilt.DecimalNumberParser.parse("1,2m").value, 1_200_000, "decimal-number.m")
            try Expect.equal(try Prebuilt.DecimalNumberParser.parse("3 mln").value, 3_000_000, "decimal-number.mln")
            try Expect.equal(try Prebuilt.DecimalNumberParser.parse("€2bn").value, 2_000_000_000, "decimal-number.bn")
        }

        Test("explicit separator policy") {
            let period = Prebuilt.DecimalNumberParser.Configuration(decimalSeparator: .period)
            try Expect.equal(
                try Prebuilt.DecimalNumberParser.parse("1.000", config: period).value,
                1,
                "decimal-number.policy.period"
            )
            let comma = Prebuilt.DecimalNumberParser.Configuration(decimalSeparator: .comma)
            try Expect.equal(
                try Prebuilt.DecimalNumberParser.parse("1,000", config: comma).value,
                1,
                "decimal-number.policy.comma"
            )
            try Expect.equal(
                try Prebuilt.DecimalNumberParser.parse("1.234.567,8", config: comma).value,
                Decimal(string: "1234567.8")!,
                "decimal-number.policy.comma.grouped"
            )
        }

        Test("presets and restrictions") {
            try Expect.equal(
                try Prebuilt.DecimalNumberParser.parse("15%", config: .percentage).value,
                15,
                "decimal-number.percentage.with-sign"
            )
            try Expect.equal(
                try Prebuilt.DecimalNumberParser.parse("15", config: .percentage).value,
                15,
                "decimal-number.percentage.bare"
            )
            try Expect.throwsError("decimal-number.percentage.range") {
                _ = try Prebuilt.DecimalNumberParser.parse("101", config: .percentage)
            }
            try Expect.throwsError("decimal-number.amount.negative") {
                _ = try Prebuilt.DecimalNumberParser.parse("-5", config: .amount)
            }
            try Expect.throwsError("decimal-number.amount.percent") {
                _ = try Prebuilt.DecimalNumberParser.parse("5%", config: .amount)
            }
        }

        Test("rejects malformed input") {
            let rejected = [
                "",
                "   ",
                "abc",
                "1..0",
                "1._0",
                "1.",
                "_1",
                "1_",
                "1,2,3.4.5",
                "1.234,5.6",
                "1-2",
                "--1",
                "1x",
                "€",
                "%",
            ]
            for source in rejected {
                try Expect.throwsError("decimal-number.rejects \(source)") {
                    _ = try Prebuilt.DecimalNumberParser.parse(source)
                }
            }
        }

        Test("cursor parser consumes one token") {
            switch Prebuilt.DecimalNumberParser().parse(Cursor("2_500 rest")) {
            case .success(let number, let rest):
                try Expect.equal(number.value, 2500, "decimal-number.cursor.value")
                try Expect.equal(rest.offset, 5, "decimal-number.cursor.offset")
            case .failure(let diagnostic):
                try Expect.true(false, "cursor parse must succeed: \(diagnostic)")
            }
        }
    }
}
