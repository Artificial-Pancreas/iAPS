import Foundation

/// Writes the app's current physical memory footprint into the device log at named
/// checkpoints, so a MetricKit daily peak can be bracketed between known activities
/// without attaching Instruments (which distorts normal behaviour too much to be
/// representative).
///
/// Cost per call is one `task_info` syscall plus one log line — microseconds, safe
/// from any thread, no timers and no state. At the current checkpoints (loop
/// start/end, autotune, statistics build, app phase changes) that is roughly 600
/// log lines a day, a rounding error against normal log volume.
enum FootprintLog {
    static func log(_ tag: String) {
        guard let mb = currentFootprintMB() else { return }
        debug(.apsManager, "MEMORY: footprint \(mb) MB [\(tag)]")
    }

    private static func currentFootprintMB() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }
}
