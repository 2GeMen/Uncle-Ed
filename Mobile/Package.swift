// swift-tools-version: 5.9
import PackageDescription
let package=Package(name:"UncleEdDomain",platforms:[.macOS(.v13),.iOS(.v17)],products:[.library(name:"UncleEdDomain",targets:["UncleEdDomain"])],dependencies:[.package(url:"https://github.com/weichsel/ZIPFoundation.git",from:"0.9.19")],targets:[.target(name:"UncleEdDomain",dependencies:["ZIPFoundation"],path:"Sources/Domain"),.testTarget(name:"UncleEdDomainTests",dependencies:["UncleEdDomain","ZIPFoundation"],path:"Tests")])
