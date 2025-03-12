const std = @import("std");
const testing = std.testing;
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

// Mock multitouch finger data for testing
fn createMockFinger(x_vel: f32, y_vel: f32) multitouch.Finger {
    return multitouch.Finger{
        .normalized = .{
            .point = .{ .x = 0, .y = 0 },
            .velocity = .{ .x = x_vel, .y = y_vel },
        },
        .frame = 0,
        .timestamp = 0.0,
        .identifier = 0,
        .state = 0,
        .finger_number = 0,
        .hand_id = 0,
        .size = 0.0,
        .pressure = 0,
        .angle = 0.0,
        .major_axis = 0.0,
        .minor_axis = 0.0,
        .absolute_vector = .{ .point = .{ .x = 0, .y = 0 }, .velocity = .{ .x = 0, .y = 0 } },
        .unknown = [_]i32{ 0, 0 },
        .z_density = 0.0,
    };
}

// Helper to create a test event state
fn createTestEventState(allocator: std.mem.Allocator, gesture: cl.TouchEvent.Gesture, num_fingers: u32) !EventState {
    const config = cl.TouchEvent{
        .gesture = gesture,
        .num_fingers = num_fingers,
        .command = "echo 'test'",
        .cooldown = 0.1,
        .finger_size_threshold = null,
    };

    return try EventState.init(allocator, config);
}

test "SwipeLeft gesture detection" {
    const allocator = testing.allocator;

    var event_state = try createTestEventState(allocator, .SwipeLeft, 2);
    defer event_state.deinit();

    // Create mock finger data with left swipe
    var fingers: [3]multitouch.Finger = [3]multitouch.Finger{
        createMockFinger(-2.0, 0.0), // Strong left swipe
        createMockFinger(-1.5, 0.1), // Left swipe with slight upward
        createMockFinger(0.5, 0.0), // Right movement (should not count)
    };

    // Test the swipe detection
    const meeting_threshold = handleSwipeGesture(&event_state, &fingers);

    try testing.expectEqual(2, meeting_threshold);
}

test "SwipeRight gesture detection" {
    const allocator = testing.allocator;

    var event_state = try createTestEventState(allocator, .SwipeRight, 2);
    defer event_state.deinit();

    // Create mock finger data with right swipe
    var fingers: [3]multitouch.Finger = [3]multitouch.Finger{
        createMockFinger(1.5, 0.0), // Right swipe
        createMockFinger(2.0, -0.1), // Strong right swipe with slight downward
        createMockFinger(-0.5, 0.0), // Left movement (should not count)
    };

    // Test the swipe detection
    const meeting_threshold = handleSwipeGesture(&event_state, &fingers);

    try testing.expectEqual(2, meeting_threshold);
}

test "SwipeUp gesture detection" {
    const allocator = testing.allocator;

    var event_state = try createTestEventState(allocator, .SwipeUp, 3);
    defer event_state.deinit();

    // Create mock finger data with upward swipe
    var fingers: [4]multitouch.Finger = [4]multitouch.Finger{
        createMockFinger(0.0, 1.5), // Upward swipe
        createMockFinger(0.1, 2.0), // Strong upward swipe with slight rightward
        createMockFinger(-0.1, 1.2), // Upward swipe with slight leftward
        createMockFinger(0.0, 0.5), // Weak upward (should not count)
    };

    // Test the swipe detection
    const meeting_threshold = handleSwipeGesture(&event_state, &fingers);

    try testing.expectEqual(3, meeting_threshold);
}

test "SwipeDown gesture detection" {
    const allocator = testing.allocator;

    var event_state = try createTestEventState(allocator, .SwipeDown, 1);
    defer event_state.deinit();

    // Create mock finger data with downward swipe
    var fingers: [2]multitouch.Finger = [2]multitouch.Finger{
        createMockFinger(0.0, -1.5), // Downward swipe
        createMockFinger(0.0, 0.5), // Upward movement (should not count)
    };

    // Test the swipe detection
    const meeting_threshold = handleSwipeGesture(&event_state, &fingers);

    try testing.expectEqual(1, meeting_threshold);
}

test "Consecutive frames triggering" {
    const allocator = testing.allocator;

    var event_state = try createTestEventState(allocator, .SwipeLeft, 1);
    defer event_state.deinit();

    // Simulate gesture being active for multiple frames
    event_state.is_active = true;
    event_state.consecutive_frames = 2;

    // Verify it's not triggered yet (needs > 2 frames)
    try testing.expect(event_state.consecutive_frames <= 2);

    // Simulate one more frame
    event_state.consecutive_frames += 1;

    // Now it should be ready to trigger
    try testing.expect(event_state.consecutive_frames > 2);
}
