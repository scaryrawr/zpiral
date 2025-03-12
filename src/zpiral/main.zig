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

const EventState = struct {
    /// The event configuration
    config: cl.TouchEvent,
    /// The event criteria is currently being met
    is_active: bool,
    /// The last time the event was triggered
    last_run: ?f64,
    /// Consecutive frames
    consecutive_frames: i32,
    pub fn init(config: cl.TouchEvent) EventState {
        return EventState{
            .config = config,
            .is_active = false,
            .last_run = null,
            .consecutive_frames = 0,
        };
    }

    pub fn reset(self: *EventState) void {
        self.is_active = false;
        self.consecutive_frames = 0;
    }
};

fn touchCallback(events: []EventState, _: *multitouch.MTDevice, fingers: []multitouch.Finger, timestamp: f64, _: i32) void {
    // Check for swipe gestures and run the corresponding command
    for (events) |*event| {
        if (event.last_run) |last_run| {
            // Check if the event can be triggered again, if not, skip evaluation.
            const cooldown = if (event.config.cooldown) |cooldown| cooldown else 0.3;
            if ((timestamp - last_run) < cooldown) {
                continue;
            }
        }

        if (fingers.len == event.config.num_fingers) {
            var avg_velocity_x: f64 = 0;
            var avg_velocity_y: f64 = 0;

            for (fingers) |finger| {
                avg_velocity_x += finger.normalized.velocity.x;
                avg_velocity_y += finger.normalized.velocity.y;
            }

            avg_velocity_x /= @floatFromInt(fingers.len);
            avg_velocity_y /= @floatFromInt(fingers.len);

            // Simplified gesture detection logic
            if (switch (event.config.gesture) {
                cl.TouchEvent.Gesture.SwipeLeft => avg_velocity_x < -1.0,
                cl.TouchEvent.Gesture.SwipeRight => avg_velocity_x > 1.0,
                cl.TouchEvent.Gesture.SwipeUp => avg_velocity_y > 1.0,
                cl.TouchEvent.Gesture.SwipeDown => avg_velocity_y < -1.0,
            }) {
                event.is_active = true;
                event.consecutive_frames += 1;
            } else {
                event.reset();
            }

            if (event.consecutive_frames > 2) {
                runCommand(event.config.command);
                event.last_run = timestamp;
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
    const Callback = multitouch.MTContactFrameCallback([]EventState, touchCallback);
    var event_state = try allocator.alloc(EventState, config.events.len);
    defer allocator.free(event_state);
    for (config.events, 0..) |event, i| {
        event_state[i] = EventState.init(event);
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
