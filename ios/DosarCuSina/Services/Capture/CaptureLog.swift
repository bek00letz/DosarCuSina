import OSLog

/// Diagnostics for reading documents. Only stage names, timings and error
/// codes are logged, never recognized text, field values or file names.
enum CaptureLog {
    static let engine = Logger(subsystem: "com.ar.dosarcusina.app", category: "capture")
}
