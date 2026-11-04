// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Grove", platforms: [.macOS(.v14)], products: [.executable(name: "Grove", targets: ["Grove"])], dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "e213ebb5cc7005e1b9e4629ae97bf921808f683a")], targets: [.executableTarget(name: "Grove", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]), .testTarget(name: "GroveTests", dependencies: ["Grove"])], swiftLanguageModes: [.v5])
