const std = @import("std");
const multitouch = @import("multitouch");
const cl = @import("config.zig");
const eh = @import("event_handler.zig");

/// Custom errors that can occur during application startup
pub const ZpiralError = error{
    NoMultitouchDevicesFound,
    RegisterCallbackFailed,
    StartDeviceFailed,
};

// Create a typed callback for processing touch events
const Callback = multitouch.MTContactFrameCallback([]eh.EventState, eh.touchCallback);

pub fn main() !void {
    const device_list = try multitouch.MTDeviceList.init();
    defer device_list.release();

    // Verify that at least one multitouch device is available
    if (device_list.count() == 0) {
        std.log.err("No multitouch devices found", .{});
        return ZpiralError.NoMultitouchDevicesFound;
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const parsed = try cl.loadConfigFile(allocator);
    defer parsed.deinit();

    const config = parsed.value;

    // Allocate state tracking for each configured event
    var event_state = try allocator.alloc(eh.EventState, config.events.len);

    // Track how many event states we've successfully initialized
    var initialized_count: usize = 0;

    // Use errdefer to clean up partially initialized event_state array if initialization fails
    errdefer {
        for (0..initialized_count) |i| {
            event_state[i].deinit();
        }
        allocator.free(event_state);
    }

    // Initialize each event state with its configuration
    for (config.events, 0..) |event, i| {
        event_state[i] = try eh.EventState.init(allocator, event);
        initialized_count += 1;
    }

    defer {
        for (event_state) |*event| {
            event.deinit();
        }
        allocator.free(event_state);
    }

    // Create the callback instance that will be registered with the multitouch system
    var cb_instance: Callback = .{ .context = event_state };

    // Default device on MacBooks with the touch bar is the touch bar,
    // so we need to search for what we hope is the touchpad (maybe we should register on all devices?)
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

    std.log.info("Selected device with dimensions: {}x{}", .{ largest_dimensions.width, largest_dimensions.height });

    const device = largest_device;

    // Register our callback function to receive touch events
    if (!device.registerContactFrameCallback(cb_instance.any())) {
        std.log.err("Failed to register contact callback", .{});
        return ZpiralError.RegisterCallbackFailed;
    }

    defer device.unregisterContactFrameCallback(cb_instance.any());

    // Start receiving touch events (0 is the default mode)
    if (!device.start(0)) {
        std.log.err("Failed to start the multitouch device", .{});
        return ZpiralError.StartDeviceFailed;
    }

    defer device.stop();

    // Enter the CoreFoundation run loop - this function doesn't return until the program ends
    CFRunLoopRun();
}

/// External function to start the Core Foundation run loop
extern fn CFRunLoopRun() void;

test {
    // Import config.zig to ensure its tests are run
    _ = @import("config.zig");
}
