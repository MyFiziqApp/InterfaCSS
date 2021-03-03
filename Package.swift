// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyFaCSS",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MyFaCSS",
            targets: ["MyFaCSS"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "MyFaCSS",
            dependencies: [],
            path: "InterfaCSS",
            sources: ["InterfaCSS", "InterfaCSS/InterfaCSS.h", "InterfaCSS/InterfaCSS.m", "Model", "UI", "Util", "Parser"],
            publicHeadersPath: "",
            cSettings: [
                .headerSearchPath("InterfaCSS"), .headerSearchPath("Model"), .headerSearchPath("UI"), .headerSearchPath("Util"), .headerSearchPath("Parser")
            ]
        )
    ]
)
