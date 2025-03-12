const std = @import("std");
const multitouch = @import("multitouch");
const cl = @import("config.zig");

/// Tracks the state of a configured touch event across frames
pub const EventState = struct {
    const Self = @This();
    /// Memory allocator for this event state
    allocator: std.mem.Allocator,
    /// Environment variables map for command execution
    env_map: std.process.EnvMap,
    /// The event configuration from the config file
    config: cl.TouchEvent,
    /// The event criteria is currently being met (gesture is in progress)
    is_active: bool,
    /// The last time the event was triggered (for cooldown management)
    last_run: ?f64,
    /// How many consecutive frames have matched this gesture
    consecutive_frames: i32,

    /// Initialize a new event state with the given configuration
    pub fn init(allocator: std.mem.Allocator, config: cl.TouchEvent) !EventState {
        const env_map = try std.process.getEnvMap(allocator);
        return EventState{
            .allocator = allocator,
            .env_map = env_map,
            .config = config,
            .is_active = false,
            .last_run = null,
            .consecutive_frames = 0,
        };
    }

    /// Clean up resources when done
    pub fn deinit(self: *Self) void {
        self.env_map.deinit();
    }

    /// Reset the state for a new gesture detection attempt
    pub fn reset(self: *Self) void {
        self.is_active = false;
        self.consecutive_frames = 0;
    }
};

/// Analyzes finger movements to determine if they constitute a swipe gesture
/// Returns the count of fingers that meet the threshold for the given gesture
fn handleSwipeGesture(event: *EventState, fingers: []multitouch.Finger) u32 {
    var fingers_meeting_threshold: u32 = 0;
    for (fingers) |finger| {
        // Check if the finger's velocity matches the expected direction
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

/// Main callback function that receives touch events from the multitouch system
/// This analyzes the finger data to detect configured gestures
pub fn touchCallback(events: []EventState, _: *multitouch.MTDevice, fingers: []multitouch.Finger, timestamp: f64, _: i32) void {
    // Check each configured event against the current touch data
    for (events) |*event| {
        // Check cooldown period if the event was recently triggered
        if (event.last_run) |last_run| {
            // Check if the event can be triggered again, if not, skip evaluation.
            const cooldown = if (event.config.cooldown) |cooldown| cooldown else 0.3;
            if ((timestamp - last_run) < cooldown) {
                continue;
            }
        }

        // Determine how many fingers match the gesture criteria
        const fingers_meeting_threshold: u32 = switch (event.config.gesture) {
            cl.TouchEvent.Gesture.SwipeLeft, cl.TouchEvent.Gesture.SwipeRight, cl.TouchEvent.Gesture.SwipeUp, cl.TouchEvent.Gesture.SwipeDown => handleSwipeGesture(event, fingers),
        };

        // If enough fingers meet the threshold, mark the event as active
        if (fingers_meeting_threshold >= event.config.num_fingers) {
            event.is_active = true;
            event.consecutive_frames += 1;
        } else {
            event.reset();
        }

        // Only trigger after seeing the gesture for multiple consecutive frames
        // This helps avoid false positives from momentary movements
        if (event.consecutive_frames > 2) {
            triggerEvent(event) catch |err| {
                std.debug.print("Error triggering event: {}\n", .{err});
            };
            event.last_run = timestamp;
        }
    }
}

/// Execute the command associated with a detected gesture
fn triggerEvent(event: *EventState) !void {
    // Get the user's shell or default to /bin/sh
    const shell = event.env_map.get("SHELL") orelse "/bin/sh";

    // Set up the command execution with the shell
    const argv = [_][]const u8{
        shell,
        "-c",
        event.config.command,
    };

    // Create and run the process
    var process = std.process.Child.init(&argv, event.allocator);
    process.env_map = &event.env_map;
    _ = try process.spawnAndWait();
}
