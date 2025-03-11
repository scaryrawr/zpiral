const std = @import("std");
const multitouch = @import("multitouch");
const cl = @import("config.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn runCommand(command: []const u8) void {
    var env_map = std.process.getEnvMap(allocator) catch |err| {
        std.debug.panic("Failed to get environment map: {}", .{err});
    };

    defer env_map.deinit();

    const shell = env_map.get("SHELL") orelse "/bin/sh";
    const args = "-c";
    const argv = [_][]const u8{
        shell,
        args,
        command,
    };

    var process = std.process.Child.init(&argv, allocator);
    _ = process.spawnAndWait() catch |err| {
        std.debug.panic("Failed to run command: {}", .{err});
    };
}

fn touchCallback(events: []const cl.TouchEvent, _: *multitouch.MTDevice, fingers: []multitouch.Finger, _: f64, _: i32) void {
    // Check for swipe gestures and run the corresponding command
    for (events) |event| {
        if (fingers.len >= event.num_fingers) {
            // Simplified gesture detection logic
            switch (event.direction) {
                cl.TouchEvent.Direction.Left => if (fingers[0].normalized.velocity.x < -1.0) runCommand(event.command),
                cl.TouchEvent.Direction.Right => if (fingers[0].normalized.velocity.x > 1.0) runCommand(event.command),
                cl.TouchEvent.Direction.Up => if (fingers[0].normalized.velocity.y > 1.0) runCommand(event.command),
                cl.TouchEvent.Direction.Down => if (fingers[0].normalized.velocity.y < -1.0) runCommand(event.command),
            }
        }
    }
}

pub fn main() !void {
    const parsed = try cl.loadConfigFile(allocator);
    defer parsed.deinit();

    const device_list = try multitouch.MTDeviceList.init();
    defer device_list.release();

    const config = parsed.value;
    const Callback = multitouch.MTContactCallback([]const cl.TouchEvent, touchCallback);
    var cb_instance: Callback = .{ .context = config.events };

    var largest_device = device_list.at(0);
    var largest_dimensions = largest_device.getDimensions();

    for (0..device_list.count()) |i| {
        const device = device_list.at(i);
        const dimensions = device.getDimensions();
        std.debug.print("Device dimensions: {} x {}\n", .{ dimensions.width, dimensions.height });
        if (dimensions.width * dimensions.height > largest_dimensions.width * largest_dimensions.height) {
            largest_device = device;
            largest_dimensions = dimensions;
        }
    }

    const device = largest_device;

    if (!device.registerContactCallback(cb_instance.any())) {
        @panic("Failed to register contact callback");
    }

    defer device.unregisterContactCallback(cb_instance.any());
    if (!device.start(0)) {
        @panic("Failed to start the multitouch device");
    }

    defer device.stop();

    CFRunLoopRun();
}

extern fn CFRunLoopRun() void;

test {
    // Import config.zig to ensure its tests are run
    _ = @import("config.zig");
}
