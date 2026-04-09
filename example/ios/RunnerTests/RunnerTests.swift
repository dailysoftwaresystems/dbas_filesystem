import Flutter
import UIKit
import XCTest

@testable import dbas_filesystem

class RunnerTests: XCTestCase {
  func testPluginRegisters() {
    let plugin = DbasFilesystemPlugin()
    XCTAssertNotNil(plugin)
  }
}
