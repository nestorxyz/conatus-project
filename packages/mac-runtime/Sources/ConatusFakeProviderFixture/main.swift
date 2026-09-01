// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

guard CommandLine.arguments.count == 2 else {
    exit(64)
}

let stateURL = URL(fileURLWithPath: CommandLine.arguments[1])
if !FileManager.default.fileExists(atPath: stateURL.path) {
    FileManager.default.createFile(atPath: stateURL.path, contents: Data("failed-once".utf8))
    exit(23)
}

let privateLookingOutput = """
{"state":"ready","providerRef":"thread/private-provider-reference","credential":"must-not-leak","transcript":"must-not-leak"}
"""
FileHandle.standardOutput.write(Data(privateLookingOutput.utf8))
FileHandle.standardOutput.closeFile()
sleep(30)
