const std = @import("std");
const multitouch = @import("multitouch");
const cl = @import("config.zig");

pub const EventState = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// The event configuration
    config: cl.TouchEvent,
    /// The event criteria is currently being met
    is_active: bool,
    /// The last time the event was triggered
    last_run: ?f64,
    /// Consecutive frames
    consecutive_frames: i32,
    pub fn init(allocator: std.mem.Allocator, config: cl.TouchEvent) EventState {
        return EventState{
            .allocator = allocator,
            .config = config,
            .is_active = false,
            .last_run = null,
            .consecutive_frames = 0,
        };
    }

    pub fn reset(self: *Self) void {
        self.is_active = false;
        self.consecutive_frames = 0;
    }
};

fn handleSwipeGesture(event: *EventState, fingers: []multitouch.Finger) u32 {
    var fingers_meeting_threshold: u32 = 0;
    for (fingers) |finger| {
        const meets_threshold = switch (event.config.gesture) {
            cl.TouchEvent.Gesture.SwipeLeft => finger.normalized.velocity.x < -1.0,
            cl.TouchEvent.Gesture.SwipeRight => finger.normalized.velocity.x > 1.0,
            cl.TouchEvent.Gesture.SwipeUp => finger.normalized.velocity.y > 1.0,
            cl.TouchEvent.Gesture.SwipeDown => finger.normalized.velocity.y < -1.0,
        };

        if (meets_threshold) {
            fingers_meeting_threshold += 1;
        }
    }

    return fingers_meeting_threshold;
}

pub fn touchCallback(events: []EventState, _: *multitouch.MTDevice, fingers: []multitouch.Finger, timestamp: f64, _: i32) void {
    // Check for swipe gestures and run the corresponding command
    for (events) |*event| {
        if (event.last_run) |last_run| {
            // Check if the event can be triggered again, if not, skip evaluation.
            const cooldown = if (event.config.cooldown) |cooldown| cooldown else 0.3;
            if ((timestamp - last_run) < cooldown) {
                continue;
            }
        }

        const fingers_meeting_threshold: u32 = switch (event.config.gesture) {
            cl.TouchEvent.Gesture.SwipeLeft, cl.TouchEvent.Gesture.SwipeRight, cl.TouchEvent.Gesture.SwipeUp, cl.TouchEvent.Gesture.SwipeDown => handleSwipeGesture(event, fingers),
        };

        if (fingers_meeting_threshold >= event.config.num_fingers) {
            event.is_active = true;
            event.consecutive_frames += 1;
        } else {
            event.reset();
        }

        if (event.consecutive_frames > 2) {
            runCommand(event.allocator, event.config.command);
            event.last_run = timestamp;
        }
    }
}

fn runCommand(allocator: std.mem.Allocator, command: []const u8) void {
    var env_map = std.process.getEnvMap(allocator) catch |err| {
        std.debug.panic("Failed to get environment map: {}", .{err});
    };

    defer env_map.deinit();

    const shell = env_map.get("SHELL") orelse "/bin/sh";
    const argv = [_][]const u8{
        shell,
        "-c",
        command,
    };

    var process = std.process.Child.init(&argv, allocator);
    _ = process.spawnAndWait() catch |err| {
        std.debug.panic("Failed to run command: {}", .{err});
    };
}
