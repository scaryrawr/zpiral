const std = @import("std");
const toml = @import("toml");

pub const TouchEvent = struct {
    pub const Gesture = enum {
        SwipeUp,
        SwipeDown,
        SwipeLeft,
        SwipeRight,
    };
    /// Number of fingers required in the gesture
    num_fingers: u32,
    /// Gesture to trigger the command.
    gesture: Gesture,
    /// Command to run when the event is triggered.
    command: []const u8,
    /// Threshold size for finger to be considered.
    finger_size_threshold: ?f32,
    /// The cooldown time in seconds for event to trigger again
    cooldown: ?f64,
};

pub const Config = struct {
    events: []const TouchEvent,
};

fn getHomeConfigDir(allocator: std.mem.Allocator, home: ?[]const u8) ![]const u8 {
    if (home) |h| {
        const paths = [_][]const u8{ h, ".config" };
        return try std.fs.path.join(allocator, &paths);
    }

    const paths = [_][]const u8{ "~", ".config" };
    return try std.fs.path.join(allocator, &paths);
}

fn getConfigHome(allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    if (env_map.get("XDG_CONFIG_HOME")) |config_home| {
        return try allocator.dupe(u8, config_home);
    }

    return getHomeConfigDir(allocator, env_map.get("HOME"));
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_home = try getConfigHome(allocator);
    defer allocator.free(config_home);

    const paths = [_][]const u8{ config_home, "zpiral", "zpiral.toml" };
    return try std.fs.path.join(allocator, &paths);
}

fn loadConfig(allocator: std.mem.Allocator, config_str: []const u8) !toml.Parsed(Config) {
    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    return try parser.parseString(config_str);
}

pub fn loadConfigFile(allocator: std.mem.Allocator) !toml.Parsed(Config) {
    const filename = try getConfigPath(allocator);
    defer allocator.free(filename);

    const real_path = try std.fs.realpathAlloc(allocator, filename);
    defer allocator.free(real_path);

    var parser = toml.Parser(Config).init(allocator);
    defer parser.deinit();

    return try parser.parseFile(real_path);
}

test "should be able to get a config path" {
    const allocator = std.testing.allocator;
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    try std.testing.expectStringEndsWith(config_path, "/.config/zpiral/zpiral.toml");
}

test "should parse single event" {
    const config_str =
        \\[[events]]
        \\num_fingers = 2
        \\gesture = 'SwipeUp'
        \\command = 'echo Up'
    ;
    const config = try loadConfig(std.testing.allocator, config_str);
    defer config.deinit();

    const events = config.value;
    try std.testing.expect(events.events.len == 1);
    try std.testing.expect(events.events[0].num_fingers == 2);
    try std.testing.expect(events.events[0].gesture == TouchEvent.Gesture.SwipeUp);
}

test "should parse multiple event" {
    const config_str =
        \\[[events]]
        \\num_fingers = 2
        \\gesture = 'SwipeUp'
        \\command = 'echo Up'
        \\
        \\[[events]]
        \\num_fingers = 3
        \\gesture = 'SwipeLeft'
        \\command = 'echo Left'
    ;

    const config = try loadConfig(std.testing.allocator, config_str);
    defer config.deinit();

    const events = config.value;
    try std.testing.expect(events.events.len == 2);
    try std.testing.expect(events.events[0].num_fingers == 2);
    try std.testing.expect(events.events[0].gesture == TouchEvent.Gesture.SwipeUp);
    try std.testing.expect(events.events[1].num_fingers == 3);
    try std.testing.expect(events.events[1].gesture == TouchEvent.Gesture.SwipeLeft);
}
