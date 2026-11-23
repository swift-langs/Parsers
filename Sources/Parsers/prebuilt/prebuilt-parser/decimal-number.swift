import Foundation
import Parsing
import Position

extension Prebuilt {
    /// A number as people type it, read without loss into `Decimal`.
    ///
    /// Accepted shapes (each piece optional):
    /// - sign: `-12`, `+12`, `−12` (U+2212), or accounting parentheses `(12)`
    /// - currency: `€ 12`, `12 €`, `EUR 12`, `12 EUR`, `$-12`
    /// - grouping: `2_500`, `1'000`, `1 000` (also NBSP and thin spaces), `1.000.000`, `1,000,000`
    /// - decimal separator: `.` or `,` (see `DecimalSeparatorPolicy`), also a bare `.5` / `,5`
    /// - suffix: `15%`, `2.5k` (thousand), `1.2m` / `1.2mln` (million), `3bn` / `3b` (billion)
    ///
    /// `value` is the number as written with any magnitude applied, so `15%` has value `15`
    /// and unit `.percent`; `fraction` gives `0.15`.
    public struct DecimalNumber: Sendable, Hashable, Codable {
        public enum Unit: Sendable, Hashable, Codable {
            case none
            case percent
            case currency(String)
        }

        public let value: Decimal
        public let unit: Unit

        public init(
            value: Decimal,
            unit: Unit = .none
        ) {
            self.value = value
            self.unit = unit
        }

        /// Percentages as a fraction (`15%` → `0.15`); other units unchanged.
        public var fraction: Decimal {
            unit == .percent ? value / 100 : value
        }

        public var doubleValue: Double {
            NSDecimalNumber(decimal: value).doubleValue
        }
    }

    /// Which of `.` and `,` separates the fraction.
    public enum DecimalSeparatorPolicy: String, Sendable, Hashable, Codable, CaseIterable {
        /// Decide per input:
        /// - both present: the last one is the decimal separator (`1.234,56`, `1,234.56`)
        /// - one kind, repeated: grouping (`1.000.000`)
        /// - one kind, once, followed by exactly three digits after a non-zero lead group of
        ///   at most three digits: grouping (`1.000` = 1000, `12,500` = 12500)
        /// - otherwise: decimal (`12.5`, `0,500`, `1234.567`)
        case infer
        case period
        case comma
    }

    public enum DecimalNumberParserError: Error, LocalizedError, Sendable, Equatable {
        case empty
        case noDigits
        case invalidCharacter(Character, location: Position?)
        case misplacedSign
        case misplacedSeparator(Character)
        case multipleDecimalSeparators
        case unitNotAllowed(String)
        case negativeNotAllowed
        case outOfRange(min: Decimal?, max: Decimal?, actual: Decimal)

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Number cannot be empty"
            case .noDigits:
                return "Number has no digits"
            case .invalidCharacter(let character, let location?):
                return "Invalid number character '\(character)' at \(location.line):\(location.column)"
            case .invalidCharacter(let character, nil):
                return "Invalid number character '\(character)'"
            case .misplacedSign:
                return "Sign must come before the number"
            case .misplacedSeparator(let character):
                return "Separator '\(character)' must sit between digits"
            case .multipleDecimalSeparators:
                return "Number has more than one decimal separator"
            case .unitNotAllowed(let unit):
                return "Unit '\(unit)' is not allowed here"
            case .negativeNotAllowed:
                return "Number cannot be negative"
            case .outOfRange(let min, let max, let actual):
                let lower = min.map { "\($0)" } ?? "-∞"
                let upper = max.map { "\($0)" } ?? "∞"
                return "Number out of range \(lower)...\(upper), got \(actual)"
            }
        }
    }

    public struct DecimalNumberParser: Parser, Sendable {
        public typealias Output = DecimalNumber

        public struct Configuration: Sendable, Hashable {
            public var decimalSeparator: DecimalSeparatorPolicy
            public var allowsNegative: Bool
            public var allowsPercent: Bool
            public var allowsCurrency: Bool
            public var allowsMagnitude: Bool
            public var minimum: Decimal?
            public var maximum: Decimal?

            public init(
                decimalSeparator: DecimalSeparatorPolicy = .infer,
                allowsNegative: Bool = true,
                allowsPercent: Bool = true,
                allowsCurrency: Bool = true,
                allowsMagnitude: Bool = true,
                minimum: Decimal? = nil,
                maximum: Decimal? = nil
            ) {
                self.decimalSeparator = decimalSeparator
                self.allowsNegative = allowsNegative
                self.allowsPercent = allowsPercent
                self.allowsCurrency = allowsCurrency
                self.allowsMagnitude = allowsMagnitude
                self.minimum = minimum
                self.maximum = maximum
            }

            /// Non-negative amounts, currency allowed, no percent.
            public static let amount = Configuration(
                allowsNegative: false,
                allowsPercent: false
            )

            /// Non-negative percentages in 0...100, with or without `%`.
            public static let percentage = Configuration(
                allowsNegative: false,
                allowsCurrency: false,
                allowsMagnitude: false,
                minimum: 0,
                maximum: 100
            )
        }

        public let config: Configuration

        public init(
            config: Configuration = .init()
        ) {
            self.config = config
        }

        /// Consumes one whitespace-free run at the cursor (grouping spaces are
        /// only read by the whole-input `parse(_:config:)`).
        public func parse(_ cursor: Cursor) -> ParseResult<DecimalNumber> {
            var current = cursor
            let start = current.mark()
            current.advance { !$0.isWhitespace && !$0.isNewline }
            let token = current.slice(from: start)
            do {
                return .success(try Self.parse(token, config: config), current)
            } catch {
                return .failure(
                    Diagnostic(
                        error.localizedDescription,
                        range: current.range(from: start)
                    )
                )
            }
        }

        public static func parse(
            _ input: String,
            config: Configuration = .init()
        ) throws -> DecimalNumber {
            var text = Substring(input.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else {
                throw DecimalNumberParserError.empty
            }

            var negative = false
            if text.first == "(", text.last == ")" {
                negative = true
                text = trimmed(text.dropFirst().dropLast())
            }

            negative = try takeSign(&text, negative: negative)

            var currency = takeCurrencyPrefix(&text)
            if currency != nil {
                negative = try takeSign(&text, negative: negative)
            }

            var unit: DecimalNumber.Unit = .none
            var multiplier: Decimal = 1

            if text.last == "%" {
                text = trimmed(text.dropLast())
                unit = .percent
            }

            if currency == nil, unit == .none {
                currency = takeCurrencySuffix(&text)
            }

            if let (suffix, factor) = takeMagnitude(&text) {
                guard config.allowsMagnitude else {
                    throw DecimalNumberParserError.unitNotAllowed(suffix)
                }
                multiplier = factor
            }

            if let currency {
                guard unit == .none else {
                    throw DecimalNumberParserError.unitNotAllowed("%")
                }
                guard config.allowsCurrency else {
                    throw DecimalNumberParserError.unitNotAllowed(currency)
                }
                unit = .currency(currency)
            }

            if unit == .percent, !config.allowsPercent {
                throw DecimalNumberParserError.unitNotAllowed("%")
            }

            let magnitude = try body(text, input: input, policy: config.decimalSeparator)
            var value = magnitude * multiplier
            if negative, value != 0 {
                guard config.allowsNegative else {
                    throw DecimalNumberParserError.negativeNotAllowed
                }
                value = -value
            }

            if let minimum = config.minimum, value < minimum {
                throw DecimalNumberParserError.outOfRange(min: config.minimum, max: config.maximum, actual: value)
            }
            if let maximum = config.maximum, value > maximum {
                throw DecimalNumberParserError.outOfRange(min: config.minimum, max: config.maximum, actual: value)
            }

            return DecimalNumber(
                value: value,
                unit: unit
            )
        }

        // MARK: - affixes

        private static let currencySymbols: Set<Character> = ["€", "$", "£", "¥", "₹", "₣", "₩", "₺", "₽", "₿"]
        private static let groupingOnly: Set<Character> = ["_", "'", "’", " ", "\u{00A0}", "\u{2009}", "\u{202F}"]

        private static func trimmed(_ text: Substring) -> Substring {
            var text = text
            while let first = text.first, first.isWhitespace { text = text.dropFirst() }
            while let last = text.last, last.isWhitespace { text = text.dropLast() }
            return text
        }

        private static func takeSign(
            _ text: inout Substring,
            negative: Bool
        ) throws -> Bool {
            guard let first = text.first, first == "-" || first == "+" || first == "−" else {
                return negative
            }
            guard !negative else {
                throw DecimalNumberParserError.misplacedSign
            }
            text = trimmed(text.dropFirst())
            return first != "+"
        }

        private static func isCurrencyCode(_ text: Substring) -> Bool {
            text.count == 3 && text.allSatisfy { $0.isASCII && $0.isUppercase }
        }

        private static func takeCurrencyPrefix(_ text: inout Substring) -> String? {
            if let first = text.first, currencySymbols.contains(first) {
                text = trimmed(text.dropFirst())
                return String(first)
            }
            let code = text.prefix(3)
            if isCurrencyCode(code) {
                text = trimmed(text.dropFirst(3))
                return String(code)
            }
            return nil
        }

        private static func takeCurrencySuffix(_ text: inout Substring) -> String? {
            if let last = text.last, currencySymbols.contains(last) {
                text = trimmed(text.dropLast())
                return String(last)
            }
            let code = text.suffix(3)
            if isCurrencyCode(code) {
                text = trimmed(text.dropLast(3))
                return String(code)
            }
            return nil
        }

        private static func takeMagnitude(_ text: inout Substring) -> (String, Decimal)? {
            let suffixes: [(String, Decimal)] = [
                ("mln", 1_000_000),
                ("bn", 1_000_000_000),
                ("k", 1_000),
                ("K", 1_000),
                ("m", 1_000_000),
                ("M", 1_000_000),
                ("b", 1_000_000_000),
                ("B", 1_000_000_000),
            ]
            for (suffix, factor) in suffixes where text.hasSuffix(suffix) {
                let rest = text.dropLast(suffix.count)
                guard let last = rest.last, last.isASCII, last.isNumber || last == " " else {
                    continue
                }
                text = trimmed(rest)
                return (suffix, factor)
            }
            return nil
        }

        // MARK: - body

        private static func body(
            _ text: Substring,
            input: String,
            policy: DecimalSeparatorPolicy
        ) throws -> Decimal {
            let characters = Array(text)
            guard !characters.isEmpty else {
                throw DecimalNumberParserError.noDigits
            }

            var periods: [Int] = []
            var commas: [Int] = []
            for (index, character) in characters.enumerated() {
                if isDigit(character) || groupingOnly.contains(character) {
                    continue
                }
                switch character {
                case ".":
                    periods.append(index)
                case ",":
                    commas.append(index)
                case "-", "+", "−":
                    throw DecimalNumberParserError.misplacedSign
                default:
                    let offset = input.firstIndex(of: character).map { input.distance(from: input.startIndex, to: $0) } ?? 0
                    throw DecimalNumberParserError.invalidCharacter(
                        character,
                        location: Prebuilt.loc(in: input, offset: offset)
                    )
                }
            }

            let decimalIndex = try decimalSeparatorIndex(
                characters,
                periods: periods,
                commas: commas,
                policy: policy
            )

            var digits = ""
            digits.reserveCapacity(characters.count + 1)
            var previousWasSeparator = true
            for (index, character) in characters.enumerated() {
                if isDigit(character) {
                    digits.append(character)
                    previousWasSeparator = false
                    continue
                }

                let isDecimal = index == decimalIndex
                let isLeadingDecimal = isDecimal && index == 0
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let followedByDigit = next.map(isDigit) ?? false

                guard (previousWasSeparator == false || isLeadingDecimal), followedByDigit else {
                    throw DecimalNumberParserError.misplacedSeparator(character)
                }
                if let decimalIndex, index > decimalIndex, character == "." || character == "," {
                    throw DecimalNumberParserError.misplacedSeparator(character)
                }

                if isDecimal {
                    if digits.isEmpty { digits.append("0") }
                    digits.append(".")
                }
                previousWasSeparator = true
            }

            guard digits.contains(where: isDigit),
                  let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
            else {
                throw DecimalNumberParserError.noDigits
            }
            return value
        }

        private static func decimalSeparatorIndex(
            _ characters: [Character],
            periods: [Int],
            commas: [Int],
            policy: DecimalSeparatorPolicy
        ) throws -> Int? {
            func single(_ positions: [Int]) throws -> Int? {
                guard positions.count <= 1 else {
                    throw DecimalNumberParserError.multipleDecimalSeparators
                }
                return positions.first
            }

            switch policy {
            case .period:
                return try single(periods)
            case .comma:
                return try single(commas)
            case .infer:
                break
            }

            if !periods.isEmpty, !commas.isEmpty {
                let decimals = periods.last! > commas.last! ? periods : commas
                let grouping = periods.last! > commas.last! ? commas : periods
                guard decimals.count == 1 else {
                    throw DecimalNumberParserError.multipleDecimalSeparators
                }
                guard grouping.allSatisfy({ $0 < decimals[0] }) else {
                    throw DecimalNumberParserError.misplacedSeparator(characters[decimals[0]])
                }
                return decimals[0]
            }

            let positions = periods.isEmpty ? commas : periods
            guard positions.count == 1, let index = positions.first else {
                return nil
            }

            let after = characters[(index + 1)...].prefix(while: isDigit).count
            let fractionEnds = index + 1 + after == characters.count
            let lead = characters[..<index].reversed().prefix(while: isDigit)
            let leadIsGroup = (1...3).contains(lead.count) && lead.contains { $0 != "0" }
            if after == 3, fractionEnds, leadIsGroup {
                return nil
            }
            return index
        }

        @inline(__always)
        private static func isDigit(_ character: Character) -> Bool {
            character.isASCII && character.isNumber
        }
    }
}
