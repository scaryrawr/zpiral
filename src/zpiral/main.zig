const std = @import("std");
const multitouch = @import("multitouch");
const cl = @import("config.zig");
const eh = @import("event_handler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed = try cl.loadConfigFile(allocator);
    defer parsed.deinit();

    const device_list = try multitouch.MTDeviceList.init();
    defer device_list.release();

    const config = parsed.value;
    const Callback = multitouch.MTContactFrameCallback([]eh.EventState, eh.touchCallback);
    var event_state = try allocator.alloc(eh.EventState, config.events.len);
    defer allocator.free(event_state);
    for (config.events, 0..) |event, i| {
        event_state[i] = eh.EventState.init(allocator, event);
    }

    var cb_instance: Callback = .{ .context = event_state };

    // Default device on MacBooks with the touch bar is the touch bar,
    // so we need to search for what we hope is the touchpad.
    var largest_device = device_list.at(0);
    var largest_dimensions = largest_device.getDimensions();
    for (0..device_list.count()) |i| {
        const device = device_list.at(i);
        const dimensions = device.getDimensions();
        if (dimensions.width * dimensions.height > largest_dimensions.width * largest_dimensions.height) {
            largest_device = device;
            largest_dimensions = dimensions;
        }
    }

    const device = largest_device;

    if (!device.registerContactFrameCallback(cb_instance.any())) {
        @panic("Failed to register contact callback");
    }

    defer device.unregisterContactFrameCallback(cb_instance.any());
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
