import Foundation

enum RunMode {
    /// A `make shot` snapshot, which can run beside the copy someone is using: it reads
    /// the monitor but never writes to it. Unit tests inject their own fake instead.
    static let isReadOnly = WindowSnapshot.isActive
}
