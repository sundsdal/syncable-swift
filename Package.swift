// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Syncable",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Syncable",
            targets: ["Syncable"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Syncable",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .testTarget(
            name: "SyncableTests",
            dependencies: ["Syncable"]
        )
    ]
)
