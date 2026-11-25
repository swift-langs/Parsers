// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Parsers",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Parsers",
            targets: ["Parsers"]
        ),
        .library(
            name: "ParsersStructuredContent",
            targets: ["ParsersStructuredContent"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-langs/Parsing.git", branch: "master"),
        .package(url: "https://github.com/swift-langs/Grammar.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Methods.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Primitives.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Position.git", branch: "master"),
        .package(url: "https://github.com/swift-dsl/DSL.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Errors.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "Parsers",
            dependencies: [
                .product(name: "Errors", package: "Errors"),
                .product(name: "Parsing", package: "Parsing"),
                .product(name: "GrammarParsing", package: "Parsing"),
                .product(name: "Grammar", package: "Grammar"),
                .product(name: "Methods", package: "Methods"),
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
            ],
        ),
        .target(
            name: "ParsersStructuredContent",
            dependencies: [
                .product(name: "DSL", package: "DSL"),
            ]
        ),
    ]
)
