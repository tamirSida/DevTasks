import Foundation

// One binary, two modes: `devtasks <command>` runs the CLI / MCP server,
// anything else launches the SwiftUI app.
if CLI.handles(CommandLine.arguments) {
    exit(CLI.run(CommandLine.arguments))
} else {
    DevTasksApp.main()
}
