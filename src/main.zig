const std = @import("std");

/// Data structure to hold performance metrics.
pub const PerformanceMetrics = struct {
    avg_waiting_time: f64,
    avg_turnaround_time: f64,
    cpu_utilization: f64,
    throughput: f64,
    avg_response_time: f64,
};

/// A struct representing a single process in the scheduler.
pub const Process = struct {
    id: usize,
    arrival_time: f64,
    burst_time: f64,

    // Filled in later
    start_time: f64,
    completion_time: f64,
    remaining_time: f64,

    pub const Event = struct { id: usize, start: f64, dur: f64 };

    pub var timeline = std.ArrayList(Event).init(std.heap.page_allocator);
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const processes = try generateRandomProcesses(5, 12345678, allocator);
    defer allocator.free(processes);

    sortByArrivalTime(processes);

    // run FCFS
    const FCFSProcs = try runProssesSet(runFCFS, processes, null, "FCFS", allocator);
    defer allocator.free(FCFSProcs);

    const RoundRobinProcs = try runProssesSet(runRoundRobin, processes, 8, "RoundRobin", allocator);
    defer allocator.free(RoundRobinProcs);

    const SJFProcs = try runProssesSet(runSJF, processes, null, "SJF", allocator);
    defer allocator.free(SJFProcs);

    const SRTFProcs = try runProssesSet(runSRTF, processes, null, "SRTF", allocator);
    defer allocator.free(SRTFProcs);
}

fn runProssesSet(comptime function: anytype, processes: []Process, comptime quantum: ?f64, name: []const u8, allocator: std.mem.Allocator) ![]Process {
    const new_processes = try allocator.alloc(Process, processes.len);
    @memcpy(new_processes, processes);

    Process.timeline = std.ArrayList(Process.Event).init(std.heap.page_allocator);

    // run process
    if (quantum) |q| {
        @call(.auto, function, .{ new_processes, q });
    } else {
        @call(.auto, function, .{new_processes});
    }

    // Print details
    std.debug.print("\nData for: {s}", .{name});
    printResultsAsTable(new_processes);

    const outfile = try std.fs.cwd().createFile(try std.fmt.allocPrint(allocator, "timeline_{s}.csv", .{name}), .{});
    defer outfile.close();
    for (Process.timeline.items) |e| try outfile.writer().print("{d},{d},{d}\n", .{ e.id, toInt(e.start), toInt(e.dur) });

    return new_processes;
}

fn generateRandomProcesses(count: usize, rng_seed: u64, allocator: std.mem.Allocator) ![]Process {
    var array = try allocator.alloc(Process, count);

    // Initialize the pseudo-random number generator
    var prng = std.rand.DefaultPrng.init(rng_seed);

    for (0..count) |i| {
        const arrival_int = prng.random().int(u32) % 10; // in [0..9]
        const burst_int = (prng.random().int(u32) % 10) + 1; // in [1..10]

        array[i] = Process{
            .id = i + 1,
            .arrival_time = @floatFromInt(arrival_int),
            .burst_time = @floatFromInt(burst_int),
            .start_time = 0,
            .completion_time = 0,
            .remaining_time = @floatFromInt(burst_int),
        };
    }

    return array;
}

/// Sort the array of processes by arrival_time using selection sort.
fn sortByArrivalTime(procs: []Process) void {
    const count = procs.len;
    for (0..count) |i| {
        var min_index = i;
        var min_arrival = procs[i].arrival_time;

        for (i + 1..count) |j| {
            if (procs[j].arrival_time < min_arrival) {
                min_arrival = procs[j].arrival_time;
                min_index = j;
            }
        }

        if (min_index != i) {
            const temp = procs[i];
            procs[i] = procs[min_index];
            procs[min_index] = temp;
        }
    }
}
/// Perform First-Come, First-Served scheduling on an array of processes (already sorted by arrival_time).
fn runFCFS(procs: []Process) void {
    var current_time: f64 = 0;

    for (procs, 0..) |p, i| {
        // If the CPU is idle until the process arrives:
        if (current_time < p.arrival_time) {
            current_time = p.arrival_time;
        }

        // Process starts as soon as CPU is free
        procs[i].start_time = current_time;

        // Add its burst time
        current_time += procs[i].burst_time;

        // Mark completion
        procs[i].completion_time = current_time;

        Process.timeline.append(.{ .id = p.id, .start = procs[i].start_time, .dur = procs[i].burst_time }) catch unreachable;
    }
}

/// Non-preemptive SJF: pick the next arrived process with the smallest burst time.
fn runSJF(procs: []Process) void {
    var current_time: f64 = 0;
    const n = procs.len;
    var completed_count: usize = 0;

    while (completed_count < n) {
        var chosen_index: ?usize = null;
        var min_burst: f64 = 999999.0; // sentinel large

        for (procs, 0..) |p, i| {
            if (p.completion_time == 0 and p.arrival_time <= current_time) {
                if (p.burst_time < min_burst) {
                    min_burst = p.burst_time;
                    chosen_index = i;
                }
            }
        }

        if (chosen_index == null) {
            var next_arrival: f64 = 999999.0;
            var idx: ?usize = null;
            for (procs, 0..) |p, i| {
                if (p.completion_time == 0 and p.arrival_time < next_arrival) {
                    next_arrival = p.arrival_time;
                    idx = i;
                }
            }
            if (idx != null) {
                current_time = next_arrival;
            }
            continue;
        }

        const i = chosen_index.?;
        Process.timeline.append(.{ .id = procs[i].id, .start = current_time, .dur = procs[i].burst_time }) catch unreachable;
        if (procs[i].start_time == 0 and current_time >= procs[i].arrival_time) {
            procs[i].start_time = current_time;
        }
        current_time += procs[i].burst_time;
        procs[i].completion_time = current_time;
        completed_count += 1;
    }
}

/// Round Robin: each process gets up to `quantum` time in a round-robin cycle.
fn runRoundRobin(procs: []Process, quantum: f64) void {
    var current_time: f64 = 0;
    var completed_count: usize = 0;

    var queue = Queue.init();
    var current_procs: ?*Process = null;
    var current_quantum: f64 = 0;

    while (completed_count < procs.len) : (current_time += 1) {
        for (procs, 0..) |p, i| {
            if (p.arrival_time == current_time) {
                queue.push(&procs[i]);
            }
        }

        if (!queue.isEmpty() and current_procs == null) {
            current_procs = queue.pop().?;
            if (current_procs.?.burst_time == current_procs.?.remaining_time)
                current_procs.?.start_time = current_time;
            current_quantum = quantum;
        }

        if (current_procs) |curr| {
            Process.timeline.append(.{ .id = curr.id, .start = current_time, .dur = 1 }) catch unreachable;
            current_procs.?.remaining_time -= 1;

            if (curr.remaining_time <= 0) {
                completed_count += 1;
                current_procs.?.completion_time = current_time + 1;
                current_procs = null;
            }
            current_quantum -= 1;

            if (current_quantum == 0 and current_procs != null) {
                queue.push(&procs[indexOfProc(procs, current_procs.?.*)]);
                current_procs = null;
            }
        }
    }
}

fn indexOfProc(procs: []Process, proc: Process) usize {
    for (procs, 0..) |p, i| {
        if (p.id == proc.id) {
            return i;
        }
    }
    unreachable;
}

fn findNextArrivalTime(procs: []Process, current_time: f64) f64 {
    var next_arrival: f64 = 999999.0;
    for (procs) |p| {
        if (p.completion_time == 0) {
            if (p.arrival_time > current_time and p.arrival_time < next_arrival) {
                next_arrival = p.arrival_time;
            }
        }
    }
    return next_arrival;
}

/// Preemptive SJF (SRTF): at each time unit, pick the arrived process with smallest remaining_time.
fn runSRTF(procs: []Process) void {
    var current_time: f64 = 0;
    const n = procs.len;
    var completed_count: usize = 0;

    while (completed_count < n) {
        // Pick the arrived process with the smallest remaining time
        var chosen_index: ?usize = null;
        var min_rem: f64 = 999999.0;

        for (procs, 0..) |p, i| {
            if (p.completion_time == 0 and p.arrival_time <= current_time) {
                if (p.remaining_time < min_rem) {
                    min_rem = p.remaining_time;
                    chosen_index = i;
                }
            }
        }

        if (chosen_index == null) {
            const next_arr = findNextArrivalTime(procs, current_time);
            if (next_arr == 999999.0) {
                break;
            }
            current_time = next_arr;
            continue;
        }

        // Found a process to run. If it has never run before, set start_time
        const i = chosen_index.?;
        if (procs[i].start_time == 0 and current_time >= procs[i].arrival_time) {
            // Only set start_time once
            procs[i].start_time = current_time;
        }

        // Run it for 1 unit
        procs[i].remaining_time -= 1.0;
        Process.timeline.append(.{ .id = procs[i].id, .start = current_time, .dur = 1 }) catch unreachable;
        current_time += 1.0;

        // If it finishes, mark completion
        if (procs[i].remaining_time <= 0) {
            procs[i].completion_time = current_time;
            completed_count += 1;
        }
    }
}

/// Print each process's start, completion, waiting, and turnaround times.
fn printProcessInfo(procs: []Process) void {
    for (procs) |p| {
        const waiting_time = p.start_time - p.arrival_time;
        const turnaround_time = p.completion_time - p.arrival_time;
        std.debug.print("Process #{d}:\n" ++
            "  Arrival:    {d}\n" ++
            "  Burst:      {d}\n" ++
            "  Start:      {d}\n" ++
            "  Completion: {d}\n" ++
            "  Waiting:    {d}\n" ++
            "  Turnaround: {d}\n\n", .{
            p.id,
            p.arrival_time,
            p.burst_time,
            p.start_time,
            p.completion_time,
            waiting_time,
            turnaround_time,
        });
    }
}

/// Print a single ASCII table with columns for:
/// ID | Arrival | Burst | Start | Completion | Waiting | Turnaround
fn printResultsAsTable(procs: []Process) void {
    // Print a header
    std.debug.print("\n|\tID\t|\tArrival\t|\tBurst\t|\tStart\t|\tCompl\t|\tWait\t|\tTAT\t|\n", .{});
    std.debug.print("|---------------|---------------|---------------|---------------|---------------|---------------|---------------|\n", .{});

    var total_waiting: f64 = 0;
    var total_turnaround: f64 = 0;
    var total_burst: f64 = 0; // for CPU utilization
    var max_completion_time: f64 = 0; // for CPU utilization & throughput

    const n = procs.len;

    for (procs) |p| {
        const waiting_time = p.start_time - p.arrival_time;
        const turnaround_time = p.completion_time - p.arrival_time;

        // Accumulate for average calculations
        total_waiting += waiting_time;
        total_turnaround += turnaround_time;
        total_burst += p.burst_time;

        if (p.completion_time > max_completion_time) {
            max_completion_time = p.completion_time;
        }

        // Convert floats to integer for printing (truncation)
        const arr_i = toInt(p.arrival_time);
        const burst_i = toInt(p.burst_time);
        const start_i = toInt(p.start_time);
        const compl_i = toInt(p.completion_time);
        const wait_i = toInt(waiting_time);
        const tat_i = toInt(turnaround_time);

        std.debug.print("|\t{d}\t|\t{d}\t|\t{d}\t|\t{d}\t|\t{d}\t|\t{d}\t|\t{d}\t|\n", .{
            p.id,
            arr_i,
            burst_i,
            start_i,
            compl_i,
            wait_i,
            tat_i,
        });
    }

    // Compute and display average waiting & turnaround times
    const avg_wait = total_waiting / @as(f64, @floatFromInt(n));
    const avg_tat = total_turnaround / @as(f64, @floatFromInt(n));

    // Convert them to integer (rounded or truncated).
    const avg_wait_i = roundF64(avg_wait);
    const avg_tat_i = roundF64(avg_tat);

    // Print final row to represent the "average" row
    std.debug.print("|---------------|---------------|---------------|---------------|---------------|---------------|---------------|\n", .{});
    std.debug.print("|\tAvg\t|\t\t|\t\t|\t\t|\t\t|\t{d}\t|\t{d}\t|\n", .{ avg_wait_i, avg_tat_i });

    // CPU Utilization
    var cpu_util: f64 = 0;
    if (max_completion_time != 0) {
        cpu_util = (total_burst / max_completion_time) * 100.0;
    }

    // Throughput
    var throughput: f64 = 0;
    if (max_completion_time != 0) {
        throughput = @as(f64, @floatFromInt(n)) / max_completion_time;
    }
    std.debug.print("CPU Utilization: {d:.3}%\nThroughput: {d:.3} proc/sec\n", .{ cpu_util, throughput });
}

/// Helper fn for casting
fn toInt(value: f64) i64 {
    return @intFromFloat(value);
}

/// Helper to round an f64 to nearest integer.
fn roundF64(value: f64) i64 {
    return toInt(@trunc(value + 0.5));
}

pub const Queue = struct {
    const allocator = std.heap.page_allocator;
    head: ?*Node = null,
    tail: ?*Node = null,

    const Node = struct {
        next: ?*Node = null,
        value: *Process,
    };
    pub fn init() Queue {
        return Queue{};
    }

    pub fn isEmpty(self: *Queue) bool {
        return self.head == null;
    }

    pub fn push(self: *Queue, value: *Process) void {
        if (self.head == null) {
            self.head = allocator.create(Node) catch unreachable;
            self.head.?.value = value;
            self.head.?.next = null;
            self.tail = self.head;
        } else {
            self.tail.?.next = allocator.create(Node) catch unreachable;
            self.tail.?.next.?.value = value;
            self.tail.?.next.?.next = null;
            self.tail = self.tail.?.next.?;
        }
    }

    pub fn pop(self: *Queue) ?*Process {
        if (self.head == null) return null;

        const value = self.head.?.value;

        if (self.head.?.next == null) {
            allocator.destroy(self.tail.?);
            self.tail = null;
            self.head = null;
        } else if (self.head.?.next) |next| {
            allocator.destroy(self.head.?);
            self.head = next;
        }

        return value;
    }

    pub fn printQueue(self: *Queue) void {
        std.debug.print("Queue contents: [", .{});
        var current_ptr = self.head;

        // Walk the list until we hit null
        while (current_ptr != null) {
            const node = current_ptr.?;
            // Print the ID
            std.debug.print(" {d}", .{node.*.value.*.id});
            current_ptr = node.next;
        }

        std.debug.print(" ]\n", .{});
    }
};
