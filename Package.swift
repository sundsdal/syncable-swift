// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Syncable",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "Syncable",
            targets: ["Syncable"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Syncable",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(
            name: "SyncableTests",
            dependencies: ["Syncable"]
        )
    ]
)
